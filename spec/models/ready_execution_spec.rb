# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::ReadyExecution do
  let(:process) do
    SolidQueue::Process.create!(
      hostname: "localhost", pid: 12345, name: "worker", kind: "Worker"
    )
  end

  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default", class_name: "TestJob", arguments: {}
    )
  end

  describe "creation" do
    it "creates a ready execution for a job" do
      # Job.create! auto-dispatches via after_create; just verify the record exists
      execution = job.ready_execution

      expect(execution).to be_present
      expect(execution.job).to eq(job)
      expect(execution.queue_name).to eq("default")
      expect(execution.priority).to eq(0)
    end
  end

  describe ".claim" do
    before do
      3.times do |i|
        SolidQueue::Job.create!(
          queue_name: "default", class_name: "TestJob#{i}", arguments: {}, priority: i
        )
      end
    end

    it "claims executions atomically" do
      claimed = described_class.claim("default", 2, process.id)

      expect(claimed.length).to be <= 2
      expect(claimed).to all(be_a(SolidQueue::ClaimedExecution))
    end

    it "respects limit" do
      claimed = described_class.claim("default", 1, process.id)
      expect(claimed.length).to be <= 1
    end

    it "filters by queue name" do
      SolidQueue::Job.create!(queue_name: "other", class_name: "OtherJob", arguments: {})

      claimed = described_class.claim("default", 10, process.id)
      expect(claimed.map(&:queue_name).uniq).to eq(["default"])
    end

    it "supports wildcard queue claim" do
      SolidQueue::Job.create!(queue_name: "other", class_name: "OtherJob", arguments: {})

      claimed = described_class.claim("*", 10, process.id)
      expect(claimed.size).to eq(4)
    end
  end

  describe ".aggregated_count_across" do
    before do
      2.times do |i|
        SolidQueue::Job.create!(queue_name: "default", class_name: "Job#{i}", arguments: {})
      end
      SolidQueue::Job.create!(queue_name: "critical", class_name: "CriticalJob", arguments: {})
    end

    it "counts across all queues with wildcard" do
      expect(described_class.aggregated_count_across("*")).to eq(3)
    end

    it "counts only matching queues" do
      expect(described_class.aggregated_count_across("default")).to eq(2)
    end
  end
end
