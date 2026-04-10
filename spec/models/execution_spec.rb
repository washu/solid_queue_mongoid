# frozen_string_literal: true

require "spec_helper"

# Tests targeting SolidQueue::Execution base class methods.
# Uses ReadyExecution as a concrete stand-in since Execution is abstract.
RSpec.describe SolidQueue::Execution do
  def make_job(queue: "default", class_name: "TestJob")
    SolidQueue::Job.create!(queue_name: queue, class_name: class_name, arguments: {})
  end

  describe ".discard_all_in_batches" do
    it "deletes jobs and their executions in batches" do
      3.times { make_job }

      expect(SolidQueue::ReadyExecution.count).to eq(3)

      SolidQueue::ReadyExecution.discard_all_in_batches(batch_size: 2)

      expect(SolidQueue::ReadyExecution.count).to eq(0)
      expect(SolidQueue::Job.count).to eq(0)
    end
  end

  describe ".discard_all_from_jobs" do
    it "deletes specified jobs and their executions" do
      job1 = make_job
      job2 = make_job
      _unrelated = make_job(class_name: "OtherJob")

      SolidQueue::ReadyExecution.discard_all_from_jobs([job1, job2])

      expect(SolidQueue::Job.where(id: job1.id).exists?).to be false
      expect(SolidQueue::Job.where(id: job2.id).exists?).to be false
      expect(SolidQueue::Job.count).to eq(1)
    end
  end

  describe "#discard" do
    it "destroys the execution and its job" do
      job = make_job
      execution = job.ready_execution

      execution.discard

      expect(SolidQueue::ReadyExecution.where(id: execution.id).exists?).to be false
      expect(SolidQueue::Job.where(id: job.id).exists?).to be false
    end
  end

  describe ".type" do
    it "returns the execution type as a symbol" do
      expect(SolidQueue::ReadyExecution.type).to eq(:ready)
      expect(SolidQueue::ClaimedExecution.type).to eq(:claimed)
      expect(SolidQueue::FailedExecution.type).to eq(:failed)
    end
  end

  describe ".ordered scope" do
    it "orders by priority then job_id" do
      SolidQueue::Job.create!(queue_name: "default", class_name: "A", arguments: {}, priority: 10)
      SolidQueue::Job.create!(queue_name: "default", class_name: "B", arguments: {}, priority: 1)

      ordered = SolidQueue::ReadyExecution.ordered.to_a
      priorities = ordered.map(&:priority)
      expect(priorities).to eq(priorities.sort)
    end
  end
end
