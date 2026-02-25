# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Concurrency and Performance" do
  let(:process1) { SolidQueue::Process.create!(hostname: "worker1", pid: 1001) }
  let(:process2) { SolidQueue::Process.create!(hostname: "worker2", pid: 1002) }
  let(:process3) { SolidQueue::Process.create!(hostname: "worker3", pid: 1003) }

  describe "concurrent job claiming" do
    it "prevents multiple processes from claiming the same job" do
      # Create 10 jobs in the ready queue
      jobs = 10.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "TestJob",
          arguments: { id: i },
          priority: 0
        )
        job.dispatch
        job
      end

      # Simulate 3 processes trying to claim jobs simultaneously
      threads = [process1, process2, process3].map do |process|
        Thread.new do
          SolidQueue::ReadyExecution.claim_batch(5, process: process, queues: "default")
        end
      end

      claimed_executions = threads.map(&:value).flatten.compact

      # Each job should be claimed exactly once
      expect(claimed_executions.size).to eq(10)

      # No duplicate jobs should be claimed
      job_ids = claimed_executions.map(&:job_id)
      expect(job_ids.uniq.size).to eq(job_ids.size)

      # Verify all claimed executions are in database
      expect(SolidQueue::ClaimedExecution.count).to eq(10)
      expect(SolidQueue::ReadyExecution.count).to eq(0)
    end

    it "respects queue priorities under concurrent load" do
      # Create jobs with different priorities
      high_priority_jobs = 3.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "HighPriorityJob",
          arguments: { id: i },
          priority: 10
        )
        job.dispatch
        job
      end

      low_priority_jobs = 3.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "LowPriorityJob",
          arguments: { id: i },
          priority: 1
        )
        job.dispatch
        job
      end

      # Claim first 3 jobs
      claimed = SolidQueue::ReadyExecution.claim_batch(3, process: process1, queues: "default")

      # Should claim all high priority jobs first
      claimed_priorities = claimed.map(&:priority).sort.reverse
      expect(claimed_priorities).to eq([10, 10, 10])
    end
  end

  describe "semaphore concurrency control" do
    it "prevents more than the limit of concurrent acquisitions" do
      semaphore = SolidQueue::Semaphore.create!(
        key: "test_resource",
        limit: 3,
        value: 0
      )

      # Try to acquire 5 times concurrently
      threads = 5.times.map do |i|
        Thread.new do
          semaphore.reload
          acquired = semaphore.acquire
          { thread: i, acquired: acquired }
        end
      end

      results = threads.map(&:value)
      successful_acquisitions = results.count { |r| r[:acquired] }

      # Only 3 should succeed (the limit)
      expect(successful_acquisitions).to eq(3)

      # Verify semaphore value
      semaphore.reload
      expect(semaphore.value).to eq(3)
    end

    it "handles release and re-acquisition correctly" do
      semaphore = SolidQueue::Semaphore.create!(
        key: "test_resource",
        limit: 2,
        value: 0
      )

      # Acquire twice (at limit)
      expect(semaphore.acquire).to be true
      semaphore.reload
      expect(semaphore.acquire).to be true
      semaphore.reload

      # Should be at limit now
      expect(semaphore.available?).to be false

      # Release one
      semaphore.release

      # Should be able to acquire again
      semaphore.reload
      expect(semaphore.acquire).to be true
    end
  end

  describe "blocked execution handling with concurrency" do
    it "unblocks multiple executions when semaphore becomes available" do
      semaphore = SolidQueue::Semaphore.create!(
        key: "limited_resource",
        limit: 1,
        value: 1 # Already at limit
      )

      # Create multiple blocked executions
      blocked_jobs = 3.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "ResourceJob",
          arguments: { id: i },
          concurrency_key: "limited_resource"
        )

        SolidQueue::BlockedExecution.create!(
          job: job,
          queue_name: job.queue_name,
          priority: job.priority,
          concurrency_key: "limited_resource"
        )
      end

      # Release the semaphore
      semaphore.release

      # Unblock one execution
      unblocked_count = SolidQueue::BlockedExecution.unblock_all("limited_resource", 1)

      expect(unblocked_count).to eq(1)
      expect(SolidQueue::ReadyExecution.count).to eq(1)
      expect(SolidQueue::BlockedExecution.count).to eq(2)
    end
  end

  describe "performance under load" do
    it "handles bulk job creation efficiently" do
      start_time = Time.now

      # Create 100 jobs
      jobs = 100.times.map do |i|
        SolidQueue::Job.create!(
          queue_name: "bulk_queue",
          class_name: "BulkJob",
          arguments: { index: i },
          priority: rand(1..10)
        )
      end

      creation_time = Time.now - start_time

      # Should create 100 jobs in reasonable time (< 5 seconds)
      expect(creation_time).to be < 5

      # Dispatch all jobs
      dispatch_start = Time.now
      jobs.each(&:dispatch)
      dispatch_time = Time.now - dispatch_start

      # Should dispatch 100 jobs in reasonable time (< 10 seconds)
      expect(dispatch_time).to be < 10

      # Verify all jobs were dispatched
      expect(SolidQueue::ReadyExecution.count).to eq(100)
    end

    it "handles concurrent claims efficiently" do
      # Create 50 jobs
      50.times do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "ConcurrentJob",
          arguments: { id: i },
          priority: 0
        )
        job.dispatch
      end

      start_time = Time.now

      # Simulate 5 workers claiming jobs concurrently
      threads = 5.times.map do |worker_id|
        process = SolidQueue::Process.create!(
          hostname: "worker_#{worker_id}",
          pid: 2000 + worker_id
        )

        Thread.new do
          SolidQueue::ReadyExecution.claim_batch(10, process: process, queues: "default")
        end
      end

      all_claimed = threads.map(&:value).flatten.compact
      claim_time = Time.now - start_time

      # Should claim all 50 jobs
      expect(all_claimed.size).to eq(50)

      # Should complete in reasonable time (< 5 seconds)
      expect(claim_time).to be < 5

      # No jobs should be double-claimed
      job_ids = all_claimed.map(&:job_id)
      expect(job_ids.uniq.size).to eq(50)
    end
  end

  describe "scheduled execution dispatching" do
    it "dispatches only due jobs under concurrent load" do
      # Create mix of due and future jobs
      due_jobs = 5.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "ScheduledJob",
          arguments: { id: i },
          scheduled_at: 1.minute.ago
        )
        job.dispatch
        job
      end

      future_jobs = 5.times.map do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "FutureJob",
          arguments: { id: i },
          scheduled_at: 1.hour.from_now
        )
        job.dispatch
        job
      end

      # Try to dispatch from multiple threads
      threads = 3.times.map do
        Thread.new do
          SolidQueue::ScheduledExecution.dispatch_due_batch(10)
        end
      end

      threads.each(&:join)

      # Only due jobs should be dispatched
      expect(SolidQueue::ReadyExecution.count).to eq(5)
      expect(SolidQueue::ScheduledExecution.count).to eq(5)
    end
  end

  describe "process cleanup and recovery" do
    it "releases jobs when process is deregistered" do
      process = SolidQueue::Process.create!(hostname: "worker1", pid: 5001)

      # Create and claim jobs
      5.times do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "TestJob",
          arguments: { id: i }
        )
        job.dispatch
      end

      SolidQueue::ReadyExecution.claim_batch(5, process: process, queues: "default")

      expect(SolidQueue::ClaimedExecution.count).to eq(5)
      expect(SolidQueue::ReadyExecution.count).to eq(0)

      # Deregister process
      process.deregister

      # All jobs should be released back to ready queue
      expect(SolidQueue::ClaimedExecution.count).to eq(0)
      expect(SolidQueue::ReadyExecution.count).to eq(5)
    end

    it "handles stale process cleanup" do
      # Create stale processes (old heartbeat)
      stale_process = SolidQueue::Process.create!(
        hostname: "stale_worker",
        pid: 6001,
        last_heartbeat_at: 2.hours.ago
      )

      # Create fresh process
      fresh_process = SolidQueue::Process.create!(
        hostname: "fresh_worker",
        pid: 6002,
        last_heartbeat_at: 1.minute.ago
      )

      # Prune stale processes
      SolidQueue::Process.prune_stale_processes(timeout: 1.hour)

      # Only fresh process should remain
      expect(SolidQueue::Process.count).to eq(1)
      expect(SolidQueue::Process.first.pid).to eq(6002)
    end
  end

  describe "race condition handling" do
    it "handles concurrent job finish operations" do
      job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )
      job.dispatch

      claimed = SolidQueue::ReadyExecution.claim_batch(1, process: process1, queues: "default").first

      # Try to finish the job from multiple threads
      threads = 3.times.map do
        Thread.new do
          begin
            job.reload
            job.finish unless job.finished?
            true
          rescue => e
            e
          end
        end
      end

      results = threads.map(&:value)

      # Job should be marked as finished
      job.reload
      expect(job.finished?).to be true

      # No claimed execution should remain
      expect(SolidQueue::ClaimedExecution.where(job_id: job.id).count).to eq(0)
    end
  end
end
