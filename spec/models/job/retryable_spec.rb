# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Job::Retryable do
  def make_job(**attrs)
    SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob",
                            arguments: { "executions" => 1, "exception_executions" => {} },
                            **attrs)
  end

  describe "#failed_with" do
    it "creates a FailedExecution with exception details" do
      job = make_job
      error = StandardError.new("something broke")
      error.set_backtrace(%w[line1 line2])

      job.failed_with(error)

      fe = SolidQueue::FailedExecution.find_by(job_id: job.id)
      expect(fe).to be_present
      expect(fe.exception_class).to eq("StandardError")
      expect(fe.message).to eq("something broke")
    end
  end

  describe "#can_retry?" do
    it "returns true when retry_count < max_retries" do
      job = make_job(max_retries: 3, retry_count: 1)
      expect(job.can_retry?).to be true
    end

    it "returns false when retry_count == max_retries" do
      job = make_job(max_retries: 2, retry_count: 2)
      expect(job.can_retry?).to be false
    end

    it "returns false when max_retries is 0 (default)" do
      job = make_job
      expect(job.can_retry?).to be false
    end
  end

  describe "#reset_execution_counters" do
    it "resets executions and exception_executions in arguments" do
      job = make_job
      job.arguments["executions"] = 5
      job.arguments["exception_executions"] = { "RuntimeError" => 2 }
      job.save!

      job.reset_execution_counters

      expect(job.reload.arguments["executions"]).to eq(0)
      expect(job.reload.arguments["exception_executions"]).to eq({})
    end
  end

  describe "#retry (via FailedExecution)" do
    it "re-dispatches a failed job and removes the failed execution" do
      job = make_job
      error = RuntimeError.new("oops")
      job.failed_with(error)

      expect(SolidQueue::FailedExecution.where(job_id: job.id).exists?).to be true

      job.retry

      expect(SolidQueue::FailedExecution.where(job_id: job.id).exists?).to be false
      expect(job.reload.ready_execution).to be_present
    end
  end
end
