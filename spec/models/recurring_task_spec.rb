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
      stub_const("NewJob", Class.new)
      described_class.create!(key: "existing", schedule: "0 * * * *",
                               class_name: "MyJob", queue_name: "default")
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

  describe ".dynamic scope" do
    it "returns only dynamic tasks" do
      described_class.create!(key: "static_t2", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: true)
      described_class.create!(key: "dynamic_t2", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: false)

      expect(described_class.dynamic.count).to eq(1)
      expect(described_class.dynamic.first.key).to eq("dynamic_t2")
    end
  end

  describe ".from_configuration" do
    it "defaults to static: true" do
      task = described_class.from_configuration("my_task", schedule: "0 * * * *", class: "MyJob")
      expect(task.static).to be true
    end

    it "accepts static: false for dynamic tasks" do
      task = described_class.from_configuration("my_task", schedule: "0 * * * *", class: "MyJob", static: false)
      expect(task.static).to be false
    end
  end

  describe ".create_dynamic_task" do
    it "creates a persisted task with static: false" do
      described_class.create_dynamic_task("dyn_task", schedule: "0 * * * *", class: "MyJob", queue: "default")

      task = described_class.find_by(key: "dyn_task")
      expect(task).to be_present
      expect(task.static).to be false
    end

    it "raises on invalid options" do
      expect {
        described_class.create_dynamic_task("bad_dyn", schedule: "not-cron", class: "MyJob")
      }.to raise_error(Mongoid::Errors::Validations)
    end
  end

  describe ".delete_dynamic_task" do
    it "destroys a dynamic task by key" do
      described_class.create!(key: "to_delete", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: false)
      described_class.delete_dynamic_task("to_delete")
      expect(described_class.where(key: "to_delete").exists?).to be false
    end

    it "raises when the key does not exist" do
      expect {
        described_class.delete_dynamic_task("nonexistent")
      }.to raise_error(Mongoid::Errors::DocumentNotFound)
    end

    it "raises when the key belongs to a static task" do
      described_class.create!(key: "static_only", schedule: "0 * * * *", class_name: "MyJob",
                               queue_name: "default", static: true)
      expect {
        described_class.delete_dynamic_task("static_only")
      }.to raise_error(Mongoid::Errors::DocumentNotFound)
    end
  end

  describe "#previous_time" do
    let(:task) { described_class.new(key: "t", schedule: "0 * * * *", class_name: "MyJob", queue_name: "default") }

    it "returns a past time" do
      expect(task.previous_time).to be < Time.current
    end
  end

  describe "#to_s" do
    it "includes class name and schedule" do
      task = described_class.new(key: "t", schedule: "0 * * * *",
                                  class_name: "MyJob", arguments: [], queue_name: "default")
      expect(task.to_s).to include("MyJob")
      expect(task.to_s).to include("0 * * * *")
    end
  end

  describe "#attributes_for_upsert" do
    it "excludes _id, id, and key" do
      task = described_class.create!(key: "upsert_t", schedule: "0 * * * *",
                                      class_name: "MyJob", queue_name: "default")
      attrs = task.attributes_for_upsert
      expect(attrs.keys).not_to include("_id", "id", "key")
      expect(attrs["class_name"]).to eq("MyJob")
    end
  end

  describe "validations" do
    it "rejects an unsupported schedule format" do
      task = described_class.new(key: "bad", schedule: "not-a-cron", class_name: "MyJob")
      expect(task).not_to be_valid
      expect(task.errors[:schedule]).to be_present
    end

    it "requires either command or class_name" do
      task = described_class.new(key: "no-class-or-cmd", schedule: "0 * * * *")
      expect(task).not_to be_valid
      expect(task.errors[:base]).to be_present
    end

    it "is valid with a command instead of class_name" do
      task = described_class.new(key: "cmd_task", schedule: "0 * * * *", command: "ls -la")
      expect(task).to be_valid
    end

    it "rejects a class_name that does not resolve to an existing class" do
      task = described_class.new(key: "bad_class", schedule: "0 * * * *", class_name: "NonExistentJob123")
      expect(task).not_to be_valid
      expect(task.errors[:class_name]).to be_present
    end

    it "is valid when class_name resolves to an existing class" do
      stub_const("RealJob", Class.new)
      task = described_class.new(key: "real_class", schedule: "0 * * * *", class_name: "RealJob")
      expect(task).to be_valid
    end
  end

  describe "#last_enqueued_time" do
    let(:task) do
      described_class.create!(key: "last_enq", schedule: "0 * * * *",
                               class_name: "MyJob", queue_name: "default")
    end

    it "returns nil when no recurring executions exist" do
      expect(task.last_enqueued_time).to be_nil
    end

    it "returns the maximum run_at from recurring executions" do
      t1 = 2.hours.ago
      t2 = 1.hour.ago
      SolidQueue::RecurringExecution.create!(task_key: task.key, run_at: t1)
      SolidQueue::RecurringExecution.create!(task_key: task.key, run_at: t2)

      expect(task.last_enqueued_time).to be_within(1.second).of(t2)
    end

    it "returns the latest run_at when multiple recurring executions exist" do
      # Mongoid has_many proxy does not support .loaded?, so always queries the DB.
      t1 = 2.hours.ago
      t2 = 30.minutes.ago
      t3 = 1.hour.ago
      SolidQueue::RecurringExecution.create!(task_key: task.key, run_at: t1)
      SolidQueue::RecurringExecution.create!(task_key: task.key, run_at: t2)
      SolidQueue::RecurringExecution.create!(task_key: task.key, run_at: t3)

      expect(task.last_enqueued_time).to be_within(1.second).of(t2)
    end
  end

  describe "#enqueue" do
    let(:run_at) { Time.current }

    context "when using a non-solid_queue adapter" do
      let(:task) do
        described_class.new(key: "enq_task", schedule: "0 * * * *",
                             class_name: "MyJob", queue_name: "default")
      end

      it "records enqueue_error in payload when job fails to enqueue" do
        fake_job = double("active_job",
          successfully_enqueued?: false,
          enqueue_error:          double(message: "queue full"),
          job_id:                 nil
        )
        fake_class = double("MyJob",
          queue_adapter_name: "test",
          new:                fake_job
        )
        allow(fake_job).to receive(:enqueue).and_return(fake_job)
        allow(task).to receive(:job_class).and_return(fake_class)
        allow(task).to receive(:using_solid_queue_adapter?).and_return(false)

        # When enqueue fails, the job object is still returned (not false);
        # the error is surfaced in the instrument payload.
        result = task.enqueue(at: run_at)
        expect(result).to eq(fake_job)
      end
    end

    context "when AlreadyRecorded is raised" do
      let(:task) do
        described_class.new(key: "dup_task", schedule: "0 * * * *",
                             class_name: "MyJob", queue_name: "default")
      end

      it "returns false and skips silently" do
        allow(task).to receive(:using_solid_queue_adapter?).and_return(true)
        allow(task).to receive(:enqueue_and_record)
          .and_raise(SolidQueue::RecurringExecution::AlreadyRecorded)

        result = task.enqueue(at: run_at)
        expect(result).to be false
      end
    end
  end
end
