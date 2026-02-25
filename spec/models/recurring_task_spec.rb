# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::RecurringTask do
  describe "validations" do
    it "requires key" do
      task = described_class.new(
        schedule: "0 * * * *",
        class_name: "TestJob",
        queue_name: "default"
      )
      expect(task).not_to be_valid
      expect(task.errors[:key]).to be_present
    end

    it "requires schedule" do
      task = described_class.new(
        key: "test_job",
        class_name: "TestJob",
        queue_name: "default"
      )
      expect(task).not_to be_valid
      expect(task.errors[:schedule]).to be_present
    end

    it "requires class_name" do
      task = described_class.new(
        key: "test_job",
        schedule: "0 * * * *",
        queue_name: "default"
      )
      expect(task).not_to be_valid
      expect(task.errors[:class_name]).to be_present
    end

    it "requires queue_name" do
      task = described_class.new(
        key: "test_job",
        schedule: "0 * * * *",
        class_name: "TestJob"
      )
      expect(task).not_to be_valid
      expect(task.errors[:queue_name]).to be_present
    end
  end

  describe ".load_tasks" do
    it "creates tasks from configuration" do
      config = {
        "cleanup_job" => {
          schedule: "0 2 * * *",
          class: "CleanupJob",
          queue: "maintenance",
          args: { days: 30 },
          priority: 10
        }
      }

      described_class.load_tasks(config)

      task = described_class.find_by(key: "cleanup_job")
      expect(task).to be_present
      expect(task.schedule).to eq("0 2 * * *")
      expect(task.class_name).to eq("CleanupJob")
      expect(task.queue_name).to eq("maintenance")
      expect(task.arguments).to eq({ "days" => 30 })
      expect(task.priority).to eq(10)
    end

    it "updates existing tasks" do
      existing = described_class.create!(
        key: "test_job",
        schedule: "0 * * * *",
        class_name: "OldJob",
        queue_name: "default"
      )

      config = {
        "test_job" => {
          schedule: "0 2 * * *",
          class: "NewJob",
          queue: "priority"
        }
      }

      described_class.load_tasks(config)

      task = described_class.find_by(key: "test_job")
      expect(task.id).to eq(existing.id)
      expect(task.schedule).to eq("0 2 * * *")
      expect(task.class_name).to eq("NewJob")
      expect(task.queue_name).to eq("priority")
    end
  end

  describe "#to_recurring_execution" do
    it "creates or updates a recurring execution" do
      task = described_class.create!(
        key: "test_job",
        schedule: "0 * * * *",
        class_name: "TestJob",
        queue_name: "default",
        arguments: { foo: "bar" },
        priority: 5
      )

      execution = task.to_recurring_execution

      expect(execution.key).to eq("test_job")
      expect(execution.schedule).to eq("0 * * * *")
      expect(execution.class_name).to eq("TestJob")
      expect(execution.queue_name).to eq("default")
      expect(execution.arguments).to eq({ "foo" => "bar" })
      expect(execution.priority).to eq(5)
    end
  end
end
