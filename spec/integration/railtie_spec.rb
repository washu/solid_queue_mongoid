# frozen_string_literal: true

# Railtie integration spec — boots a minimal Rails app (spec/dummy) and verifies
# that solid_queue_mongoid correctly shims in before SolidQueue's AR models load.
#
# This spec is intentionally separate from the main suite's spec_helper so that
# it can load Rails in isolation without conflicting with the non-Rails specs.

ENV["RAILS_ENV"] = "test"

require "rails"
require "mongoid"

DUMMY_APP_PATH = File.expand_path("../dummy", __dir__)

require File.join(DUMMY_APP_PATH, "config", "application")

require "rspec/rails"

# ---------------------------------------------------------------------------
# Shared result store used by integration test jobs
# ---------------------------------------------------------------------------
module IntegrationTestResults
  @results = {}
  @mutex   = Mutex.new

  class << self
    def record(key, value)
      @mutex.synchronize { (@results[key] ||= []) << value }
    end

    def for(key)
      @mutex.synchronize { Array(@results[key]).dup }
    end

    def reset!
      @mutex.synchronize { @results.clear }
    end
  end
end

# ---------------------------------------------------------------------------
# Helper: claim and execute all ready (and due-scheduled) jobs in-process.
#
# SolidQueue normally runs a Worker in a separate process. For integration
# tests we replicate the same sequence inline:
#   1. Dispatch any ScheduledExecutions whose scheduled_at has passed.
#   2. Claim a batch of ReadyExecutions for a throw-away Process record.
#   3. Call #perform on each ClaimedExecution (which runs ActiveJob#execute).
#   4. Repeat until nothing is left or max_iterations is reached.
# ---------------------------------------------------------------------------
def run_pending_jobs(queues: "*", batch_size: 10, max_iterations: 20)
  process = SolidQueue::Process.create!(
    kind: "Worker",
    name: "integration-test-worker",
    pid:  Process.pid,
    hostname: "localhost",
    last_heartbeat_at: Time.current
  )

  max_iterations.times do
    # Move any retry-scheduled executions that are now due.
    SolidQueue::ScheduledExecution.dispatch_next_batch(batch_size)

    claimed = SolidQueue::ReadyExecution.claim(queues, batch_size, process.id)
    break if claimed.empty?

    claimed.each do |ce|
      ce.perform
    rescue StandardError
      # Failure is intentional in some tests; ClaimedExecution#perform already
      # called failed_with and created a FailedExecution.
    end
  end
ensure
  process&.destroy! rescue nil
end

# ---------------------------------------------------------------------------
# Specs
# ---------------------------------------------------------------------------

RSpec.describe "SolidQueueMongoid Railtie" do
  before(:all) do
    Dummy::Application.initialize! unless Rails.application.initialized?

    Mongoid.load!(File.join(DUMMY_APP_PATH, "config", "mongoid.yml"), :test)
    Mongoid.purge!
    SolidQueueMongoid.create_indexes

    # Wire ActiveJob to use SolidQueue adapter
    ActiveJob::Base.queue_adapter = :solid_queue
  end

  after(:all) do
    Mongoid.purge! rescue nil
  end

  # ── Infrastructure checks ────────────────────────────────────────────────

  it "loads solid_queue_mongoid before SolidQueue AR models" do
    expect(SolidQueue::Job.ancestors).to include(Mongoid::Document)
    expect(SolidQueue::Job.ancestors).not_to include(ActiveRecord::Base) if defined?(ActiveRecord::Base)
  end

  it "SolidQueue::Job persists to MongoDB" do
    job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments:  {}
    )
    expect(job).to be_persisted
    expect(SolidQueue::Job.where(id: job.id).exists?).to be true
  end

  it "SolidQueue namespace helpers are delegated to SolidQueueMongoid" do
    expect(SolidQueue.collection_prefix).to eq(SolidQueueMongoid.collection_prefix)
    expect(SolidQueue.clear_finished_jobs_after).to be_present
    expect(SolidQueue.process_alive_threshold).to be_present
  end

  it "SolidQueue::Engine app/models path is excluded from eager_load_paths" do
    sq_app_path = SolidQueue::Engine.root.join("app").to_s

    eager_paths = Rails.application.config.eager_load_paths
    matching = eager_paths.select { |p| p.start_with?(sq_app_path) }
    expect(matching).to be_empty,
      "Expected SolidQueue app/ to be removed from eager_load_paths, but found: #{matching.inspect}"
  end

  it "SolidQueue AR model files are marked as ignored by Zeitwerk" do
    sq_job_file = SolidQueue::Engine.root.join("app", "models", "solid_queue", "job.rb").to_s

    Rails.autoloaders.each do |loader|
      next unless loader.respond_to?(:ignored?)
      expect(loader.ignored?(sq_job_file)).to be(true),
        "Expected #{sq_job_file} to be ignored by Zeitwerk"
    end
  end

  it "all_models returns Mongoid-backed classes" do
    SolidQueueMongoid.all_models.each do |model|
      expect(model.ancestors).to include(Mongoid::Document),
        "Expected #{model} to include Mongoid::Document"
    end
  end

  it "create_indexes runs without error" do
    expect { SolidQueueMongoid.create_indexes }.not_to raise_error
  end

  # ── Cron / RecurringTask ─────────────────────────────────────────────────

  describe "cron scheduling" do
    before(:each) do
      Mongoid.purge!
      SolidQueueMongoid.create_indexes
      IntegrationTestResults.reset!
    end

    # Simulate what SolidQueue::Scheduler::RecurringSchedule does:
    # persists a RecurringTask then calls #enqueue with a past run_at so the
    # job is immediately due.
    def enqueue_recurring(key:, class_name:, run_at: 1.minute.ago, schedule: "* * * * *")
      task = SolidQueue::RecurringTask.create_or_update_all([
        SolidQueue::RecurringTask.new(
          key:        key,
          class_name: class_name,
          schedule:   schedule,
          queue_name: "integration_test",
          static:     true
        )
      ])
      SolidQueue::RecurringTask.find_by(key: key).enqueue(at: run_at)
    end

    it "enqueues a job for a recurring task" do
      enqueue_recurring(key: "cron_simple", class_name: "RecurringTestJob")

      expect(SolidQueue::Job.where(class_name: "RecurringTestJob").count).to eq(1)
      expect(SolidQueue::ReadyExecution.count).to eq(1)
      expect(SolidQueue::RecurringExecution.where(task_key: "cron_simple").count).to eq(1)
    end

    it "records a RecurringExecution with the correct run_at" do
      run_at = 5.minutes.ago
      enqueue_recurring(key: "cron_run_at", class_name: "RecurringTestJob", run_at: run_at)

      rec = SolidQueue::RecurringExecution.find_by(task_key: "cron_run_at")
      expect(rec).to be_present
      expect(rec.run_at).to be_within(1.second).of(run_at)
    end

    it "executes the job end-to-end after enqueuing" do
      task = SolidQueue::RecurringTask.create!(
        key: "cron_exec_task", class_name: "SimpleJob",
        schedule: "* * * * *", queue_name: "integration_test", static: true,
        arguments: ["cron_exec_result"]
      )
      task.enqueue(at: 1.minute.ago)

      run_pending_jobs

      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(IntegrationTestResults.for("cron_exec_result")).to eq([:success])
    end

    it "does not enqueue a duplicate for the same task_key + run_at" do
      run_at = 10.minutes.ago
      task = SolidQueue::RecurringTask.create!(
        key: "cron_dedup", class_name: "RecurringTestJob",
        schedule: "* * * * *", queue_name: "integration_test", static: true
      )

      task.enqueue(at: run_at)
      task.enqueue(at: run_at)  # second call — same run_at, should be silently skipped

      expect(SolidQueue::RecurringExecution.where(task_key: "cron_dedup").count).to eq(1)
      expect(SolidQueue::Job.where(class_name: "RecurringTestJob").count).to eq(1)
    end

    it "allows a second enqueue for a different run_at" do
      task = SolidQueue::RecurringTask.create!(
        key: "cron_multi_run", class_name: "RecurringTestJob",
        schedule: "* * * * *", queue_name: "integration_test", static: true
      )

      task.enqueue(at: 20.minutes.ago)
      task.enqueue(at: 10.minutes.ago)

      expect(SolidQueue::RecurringExecution.where(task_key: "cron_multi_run").count).to eq(2)
      expect(SolidQueue::Job.where(class_name: "RecurringTestJob").count).to eq(2)
    end

    it "create_or_update_all updates an existing task's configuration" do
      SolidQueue::RecurringTask.create!(
        key: "cron_update", class_name: "RecurringTestJob",
        schedule: "0 * * * *", queue_name: "default", static: true
      )

      SolidQueue::RecurringTask.create_or_update_all([
        SolidQueue::RecurringTask.new(
          key: "cron_update", class_name: "RecurringTestJob",
          schedule: "30 * * * *", queue_name: "integration_test", static: true
        )
      ])

      task = SolidQueue::RecurringTask.find_by(key: "cron_update")
      expect(task.schedule).to eq("30 * * * *")
      expect(task.queue_name).to eq("integration_test")
      expect(SolidQueue::RecurringTask.where(key: "cron_update").count).to eq(1)
    end

    it "last_enqueued_time reflects the most recent run_at" do
      task = SolidQueue::RecurringTask.create!(
        key: "cron_last_enq", class_name: "RecurringTestJob",
        schedule: "* * * * *", queue_name: "integration_test", static: true
      )

      older = 30.minutes.ago
      newer = 5.minutes.ago
      task.enqueue(at: older)
      task.enqueue(at: newer)

      expect(task.last_enqueued_time).to be_within(1.second).of(newer)
    end
  end

  # ── End-to-end job execution ─────────────────────────────────────────────

  describe "job execution" do
    before(:each) do
      Mongoid.purge!
      SolidQueueMongoid.create_indexes
      IntegrationTestResults.reset!
    end

    it "executes a simple job end-to-end" do
      SimpleJob.perform_later("simple_test")

      expect(SolidQueue::ReadyExecution.count).to eq(1)

      run_pending_jobs

      expect(SolidQueue::ReadyExecution.count).to eq(0)
      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(IntegrationTestResults.for("simple_test")).to eq([:success])
    end

    it "enqueues multiple jobs and runs them all" do
      3.times { |i| SimpleJob.perform_later("multi_#{i}") }

      expect(SolidQueue::ReadyExecution.count).to eq(3)

      run_pending_jobs

      expect(SolidQueue::ReadyExecution.count).to eq(0)
      expect(SolidQueue::FailedExecution.count).to eq(0)
      (0..2).each do |i|
        expect(IntegrationTestResults.for("multi_#{i}")).to eq([:success])
      end
    end

    it "retries a transiently-failing job and eventually succeeds" do
      # RetryingJob fails on attempts 0 and 1, succeeds on attempt 2.
      # retry_on with wait: 0 re-enqueues immediately (ScheduledExecution at Time.now).
      RetryingJob.perform_later("retry_test")

      run_pending_jobs(max_iterations: 10)

      attempts = IntegrationTestResults.for("retry_test")
      # Should have recorded: attempt_0, attempt_1, attempt_2 (success)
      expect(attempts).to eq(["attempt_0", "attempt_1", "attempt_2"])

      # No failed executions — job ultimately succeeded
      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::ReadyExecution.count).to eq(0)
    end

    it "creates a FailedExecution after max retries are exhausted" do
      # AlwaysFailingJob has attempts: 2 (original + 1 retry) and always raises.
      AlwaysFailingJob.perform_later("fail_test")

      run_pending_jobs(max_iterations: 10)

      attempts = IntegrationTestResults.for("fail_test")
      # Two attempts recorded: attempt_0 and attempt_1
      expect(attempts).to eq(["attempt_0", "attempt_1"])

      # After exhausting retries, SolidQueue creates a FailedExecution
      expect(SolidQueue::FailedExecution.count).to eq(1)
      failed = SolidQueue::FailedExecution.first
      expect(failed.job.class_name).to eq("AlwaysFailingJob")
      expect(failed.exception_class).to include("PermanentError")
    end
  end
end
