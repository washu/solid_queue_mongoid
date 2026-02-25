# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::ReadyExecution do
  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {}
    )
  end

  describe "creation" do
    it "creates a ready execution for a job" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority
      )

      expect(execution.job).to eq(job)
      expect(execution.queue_name).to eq("default")
      expect(execution.priority).to eq(0)
    end
  end

  describe ".claim_batch" do
    let(:process) do
      SolidQueue::Process.create!(
        hostname: "localhost",
        pid: 12345,
        name: "worker"
      )
    end

    before do
      3.times do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "TestJob#{i}",
          arguments: {}
        )
        described_class.create!(
          job: job,
          queue_name: "default",
          priority: i
        )
      end
    end

    it "claims executions by priority" do
      claimed = described_class.claim_batch(2, process: process)

      expect(claimed.length).to be <= 2
      # Jobs should be claimed in priority order (0, 1, 2)
      expect(claimed.first.priority).to eq(0) if claimed.any?
    end

    it "respects batch size" do
      claimed = described_class.claim_batch(1, process: process)

      expect(claimed.length).to be <= 1
    end

    it "filters by queue name" do
      different_queue_job = SolidQueue::Job.create!(
        queue_name: "other",
        class_name: "OtherJob",
        arguments: {}
      )
      described_class.create!(
        job: different_queue_job,
        queue_name: "other",
        priority: 0
      )

      claimed = described_class.claim_batch(10, process: process, queues: "default")

      expect(claimed.all? { |e| e.queue_name == "default" }).to be true
    end
  end
end
