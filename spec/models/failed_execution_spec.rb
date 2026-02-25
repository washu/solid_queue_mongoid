# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::FailedExecution do
  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {}
    )
  end

  describe ".create_from_job!" do
    it "creates a failed execution from a job and error" do
      error = StandardError.new("Test error")
      error.set_backtrace(["line 1", "line 2"])

      execution = described_class.create_from_job!(job, error)

      expect(execution.job).to eq(job)
      expect(execution.error_class).to eq("StandardError")
      expect(execution.error_message).to eq("Test error")
      expect(execution.backtrace).to eq(["line 1", "line 2"])
      expect(execution.failed_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#retry" do
    it "destroys failed execution and creates ready execution" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        error_class: "StandardError",
        error_message: "Test error",
        backtrace: [],
        failed_at: Time.current
      )

      execution.retry

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(job.reload.ready_execution).to be_present
    end
  end

  describe "#discard" do
    it "destroys failed execution and marks job as finished" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        error_class: "StandardError",
        error_message: "Test error",
        backtrace: [],
        failed_at: Time.current
      )

      execution.discard

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(job.reload.finished_at).to be_present
    end
  end
end
