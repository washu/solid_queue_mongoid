# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::FailedExecution do
  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default", class_name: "TestJob", arguments: {}
    )
  end

  describe "creation via exception attr" do
    it "stores exception details in the error hash" do
      error = StandardError.new("Test error")
      error.set_backtrace(["line 1", "line 2"])

      execution = described_class.new(job: job, queue_name: job.queue_name, priority: job.priority)
      execution.exception = error
      execution.save!

      expect(execution.exception_class).to eq("StandardError")
      expect(execution.message).to eq("Test error")
      expect(execution.backtrace).to eq(["line 1", "line 2"])
    end
  end

  describe "#retry" do
    it "destroys the failed execution and re-prepares the job" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        error: { "exception_class" => "StandardError", "message" => "boom", "backtrace" => [] }
      )

      execution.retry

      expect(described_class.where(id: execution.id).exists?).to be false
    end
  end

  describe "#discard" do
    it "destroys the failed execution and the job" do
      execution = described_class.create!(
        job: job,
        queue_name: job.queue_name,
        priority: job.priority,
        error: { "exception_class" => "StandardError", "message" => "boom", "backtrace" => [] }
      )
      job_id = job.id

      execution.discard

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(SolidQueue::Job.where(id: job_id).exists?).to be false
    end
  end
end
