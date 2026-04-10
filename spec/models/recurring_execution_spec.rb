# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::RecurringExecution do
  describe "AlreadyRecorded exception" do
    it "is defined" do
      expect(defined?(SolidQueue::RecurringExecution::AlreadyRecorded)).to eq("constant")
    end
  end

  describe ".record" do
    it "calls the block and returns the result" do
      dummy_job = double("active_job", successfully_enqueued?: false)
      result = described_class.record("task_key", Time.current) { dummy_job }
      expect(result).to eq(dummy_job)
    end

    it "creates a RecurringExecution document when the job is successfully enqueued" do
      dummy_job = double("active_job",
                         successfully_enqueued?: true,
                         provider_job_id: BSON::ObjectId.new.to_s)

      run_at = 1.hour.ago
      described_class.record("my_task", run_at) { dummy_job }

      doc = described_class.find_by(task_key: "my_task")
      expect(doc).to be_present
      expect(doc.run_at).to be_within(1.second).of(run_at)
    end

    it "does not create a document when the job fails to enqueue" do
      dummy_job = double("active_job", successfully_enqueued?: false)
      described_class.record("my_task_fail", Time.current) { dummy_job }
      expect(described_class.where(task_key: "my_task_fail").exists?).to be false
    end
  end

  describe ".create_or_insert!" do
    it "raises AlreadyRecorded on duplicate task_key + run_at" do
      run_at = Time.current
      described_class.create_or_insert!(task_key: "dup", run_at: run_at)

      expect do
        described_class.create_or_insert!(task_key: "dup", run_at: run_at)
      end.to raise_error(SolidQueue::RecurringExecution::AlreadyRecorded)
    end
  end
end
