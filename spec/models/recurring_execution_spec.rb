# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::RecurringExecution do
  describe "validations" do
    it "requires key" do
      execution = described_class.new(
        schedule: "0 * * * *",
        class_name: "TestJob",
        queue_name: "default"
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:key]).to be_present
    end

    it "requires schedule" do
      execution = described_class.new(
        key: "test_job",
        class_name: "TestJob",
        queue_name: "default"
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:schedule]).to be_present
    end

    it "requires class_name" do
      execution = described_class.new(
        key: "test_job",
        schedule: "0 * * * *",
        queue_name: "default"
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:class_name]).to be_present
    end

    it "requires queue_name" do
      execution = described_class.new(
        key: "test_job",
        schedule: "0 * * * *",
        class_name: "TestJob"
      )
      expect(execution).not_to be_valid
      expect(execution.errors[:queue_name]).to be_present
    end
  end

  describe "#dispatch" do
    it "creates a job and updates timestamps" do
      execution = described_class.create!(
        key: "test_job",
        schedule: "0 * * * *",
        class_name: "TestJob",
        queue_name: "default",
        arguments: { foo: "bar" },
        priority: 5
      )

      execution.dispatch

      job = SolidQueue::Job.where(recurring_execution: execution).first
      expect(job).to be_present
      expect(job.class_name).to eq("TestJob")
      expect(job.queue_name).to eq("default")
      expect(job.arguments).to eq({ "foo" => "bar" })
      expect(job.priority).to eq(5)

      execution.reload
      expect(execution.last_run_at).to be_within(1.second).of(Time.current)
      expect(execution.next_run_at).to be > Time.current
    end
  end

  describe ".dispatch_due_tasks" do
    before do
      # Create due task
      described_class.create!(
        key: "due_job",
        schedule: "0 * * * *",
        class_name: "DueJob",
        queue_name: "default",
        next_run_at: 1.hour.ago
      )

      # Create future task
      described_class.create!(
        key: "future_job",
        schedule: "0 * * * *",
        class_name: "FutureJob",
        queue_name: "default",
        next_run_at: 1.hour.from_now
      )
    end

    it "dispatches only due tasks" do
      described_class.dispatch_due_tasks

      expect(SolidQueue::Job.where(class_name: "DueJob").count).to eq(1)
      expect(SolidQueue::Job.where(class_name: "FutureJob").count).to eq(0)
    end
  end
end
