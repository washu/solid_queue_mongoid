# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::BlockedExecution do
  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {},
      concurrency_key: "test_key",
      concurrency_limit: 1
    )
  end

  describe "creation" do
    it "creates a blocked execution" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        concurrency_key: job.concurrency_key
      )

      expect(execution.job).to eq(job)
      expect(execution.concurrency_key).to eq("test_key")
    end
  end

  describe "#unblock" do
    it "unblocks when semaphore is available" do
      SolidQueue::Semaphore.create!(
        key: "test_key",
        value: 0,
        limit: 2
      )

      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        concurrency_key: "test_key"
      )

      execution.unblock

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(job.reload.ready_execution).to be_present
    end

    it "does not unblock when semaphore is at limit" do
      SolidQueue::Semaphore.create!(
        key: "test_key",
        value: 1,
        limit: 1
      )

      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        concurrency_key: "test_key"
      )

      execution.unblock

      expect(described_class.where(id: execution.id).exists?).to be true
    end
  end

  describe "INDEX_HINTS" do
    it "maps the release index to the correct MongoDB fields" do
      spec = described_class::INDEX_HINTS[:index_solid_queue_blocked_executions_for_release]
      expect(spec).to eq({ concurrency_key: 1, priority: 1, job_id: 1 })
    end

    it "maps the maintenance index to the correct MongoDB fields" do
      spec = described_class::INDEX_HINTS[:index_solid_queue_blocked_executions_for_maintenance]
      expect(spec).to eq({ expires_at: 1, concurrency_key: 1 })
    end
  end

  describe ".release_one" do
    it "promotes the blocked execution to ready when semaphore is available" do
      SolidQueue::Semaphore.create!(key: "test_key", value: 0, limit: 2)
      execution = described_class.create!(
        job: job, queue_name: job.queue_name, priority: job.priority,
        concurrency_key: job.concurrency_key
      )

      described_class.release_one("test_key")
      expect(described_class.where(id: execution.id).exists?).to be false
      expect(SolidQueue::ReadyExecution.where(job_id: job.id).exists?).to be true
    end

    it "leaves the execution when semaphore is at limit" do
      SolidQueue::Semaphore.create!(key: "test_key", value: 1, limit: 1)
      execution = described_class.create!(
        job: job, queue_name: job.queue_name, priority: job.priority,
        concurrency_key: job.concurrency_key
      )

      described_class.release_one("test_key")
      expect(described_class.where(id: execution.id).exists?).to be true
    end

    it "returns false when no blocked execution exists for the key" do
      result = described_class.release_one("nonexistent_key")
      expect(result).to be_falsy
    end

    it "uses the release index hint without raising" do
      expect do
        described_class.use_index(:index_solid_queue_blocked_executions_for_release)
                       .where(concurrency_key: "any").count
      end.not_to raise_error
    end
  end

  describe ".unblock_all" do
    before do
      SolidQueue::Semaphore.create!(
        key: "test_key",
        value: 0,
        limit: 5
      )

      3.times do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "TestJob#{i}",
          arguments: {},
          concurrency_key: "test_key"
        )
        described_class.create!(
          job: job,
          queue_name: "default",
          priority: 0,
          concurrency_key: "test_key"
        )
      end
    end

    it "unblocks multiple executions" do
      expect(described_class.where(concurrency_key: "test_key").count).to eq(3)

      described_class.unblock_all("test_key")

      # At least some should be unblocked
      expect(described_class.where(concurrency_key: "test_key").count).to be < 3
    end
  end
end
