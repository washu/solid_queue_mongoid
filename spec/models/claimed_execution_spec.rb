# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::ClaimedExecution do
  let(:process) do
    SolidQueue::Process.create!(
      hostname: "localhost",
      pid: 12345,
      name: "worker"
    )
  end

  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {}
    )
  end

  describe "creation" do
    it "creates a claimed execution" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      expect(execution.job).to eq(job)
      expect(execution.process).to eq(process)
      expect(execution.process_id).to eq(process.id)
    end
  end

  describe "#release" do
    it "destroys claimed execution and creates ready execution" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      execution.release

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(job.reload.ready_execution).to be_present
    end
  end

  describe ".release_all_for_process" do
    it "releases all executions for a process" do
      3.times do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "TestJob",
          arguments: {}
        )
        described_class.create!(
          job: job,
          process: process,
          queue_name: "default",
          priority: 0
        )
      end

      expect(described_class.where(process: process).count).to eq(3)

      described_class.release_all_for_process(process)

      expect(described_class.where(process: process).count).to eq(0)
    end
  end
end
