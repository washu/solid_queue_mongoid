# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::RecurringTask do
  describe "validations" do
    it "requires key" do
      task = described_class.new(schedule: "0 * * * *")
      expect(task).not_to be_valid
    end

    it "requires schedule" do
      task = described_class.new(key: "test_job")
      expect(task).not_to be_valid
    end
  end

  describe ".wrap" do
    it "wraps a [key, config] pair into a RecurringTask" do
      task = described_class.wrap(["cleanup_job", { schedule: "0 2 * * *", class: "CleanupJob", queue: "maintenance" }])
      expect(task).to be_a(described_class)
      expect(task.key).to eq("cleanup_job")
      expect(task.schedule).to eq("0 2 * * *")
      expect(task.class_name).to eq("CleanupJob")
      expect(task.queue_name).to eq("maintenance")
    end

    it "passes through an existing RecurringTask unchanged" do
      task = described_class.new(key: "x", schedule: "0 * * * *")
      expect(described_class.wrap(task)).to be(task)
    end
  end

  describe ".create_or_update_all" do
    it "creates tasks that do not exist" do
      tasks = [described_class.new(key: "new_task", schedule: "0 * * * *",
                                   class_name: "MyJob", queue_name: "default", static: true)]
      described_class.create_or_update_all(tasks)
      expect(described_class.where(key: "new_task").exists?).to be true
    end

    it "updates tasks that already exist" do
      described_class.create!(key: "existing", schedule: "0 * * * *",
                               class_name: "OldJob", queue_name: "default")
      tasks = [described_class.new(key: "existing", schedule: "30 2 * * *",
                                   class_name: "NewJob", queue_name: "default", static: true)]
      described_class.create_or_update_all(tasks)
      expect(described_class.find_by(key: "existing").class_name).to eq("NewJob")
    end
  end

  describe "#delay_from_now and #next_time" do
    let(:task) { described_class.new(key: "t", schedule: "0 * * * *", class_name: "MyJob", queue_name: "default") }

    it "returns a positive delay" do
      expect(task.delay_from_now).to be > 0
    end

    it "returns a future time" do
      expect(task.next_time).to be > Time.current
    end
  end

  describe ".static scope" do
    it "returns only static tasks" do
      described_class.create!(key: "static_t", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: true)
      described_class.create!(key: "dynamic_t", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: false)

      expect(described_class.static.count).to eq(1)
      expect(described_class.static.first.key).to eq("static_t")
    end
  end
end
