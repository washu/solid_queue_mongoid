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
      semaphore = SolidQueue::Semaphore.create!(
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
      semaphore = SolidQueue::Semaphore.create!(
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

  describe ".unblock_all" do
    before do
      semaphore = SolidQueue::Semaphore.create!(
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
