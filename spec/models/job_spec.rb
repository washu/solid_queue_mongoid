# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Job do
  describe "validations" do
    it "requires queue_name" do
      job = described_class.new(class_name: "TestJob", arguments: {})
      expect(job).not_to be_valid
      expect(job.errors[:queue_name]).to be_present
    end

    it "requires class_name" do
      job = described_class.new(queue_name: "default", arguments: {})
      expect(job).not_to be_valid
      expect(job.errors[:class_name]).to be_present
    end
  end

  describe "fields" do
    it "has required fields" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: { foo: "bar" },
        priority: 5
      )

      expect(job.queue_name).to eq("default")
      expect(job.class_name).to eq("TestJob")
      expect(job.arguments).to eq({ "foo" => "bar" })
      expect(job.priority).to eq(5)
    end

    it "defaults priority to 0" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      expect(job.priority).to eq(0)
    end
  end

  describe "#scheduled?" do
    it "returns true when scheduled in future" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        scheduled_at: 1.hour.from_now
      )

      expect(job.scheduled?).to be true
    end

    it "returns false when scheduled in past" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        scheduled_at: 1.hour.ago
      )

      expect(job.scheduled?).to be false
    end

    it "returns false when not scheduled" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      expect(job.scheduled?).to be false
    end
  end

  describe "#finished?" do
    it "returns true when finished_at is set" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        finished_at: Time.current
      )

      expect(job.finished?).to be true
    end

    it "returns false when finished_at is not set" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      expect(job.finished?).to be false
    end
  end

  describe "#dispatch" do
    it "creates a ready execution for immediate jobs" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      job.dispatch

      expect(job.ready_execution).to be_present
      expect(job.ready_execution.queue_name).to eq("default")
    end

    it "creates a scheduled execution for future jobs" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        scheduled_at: 1.hour.from_now
      )

      job.dispatch

      expect(job.scheduled_execution).to be_present
      expect(job.scheduled_execution.scheduled_at).to be_within(1.second).of(1.hour.from_now)
    end
  end

  describe "#finish" do
    it "sets finished_at timestamp" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      job.finish

      expect(job.finished_at).to be_present
      expect(job.finished_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "retry functionality" do
    it "tracks retry count" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        max_retries: 3
      )

      expect(job.retry_count).to eq(0)
      expect(job.can_retry?).to be true
    end

    it "respects max_retries limit" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        max_retries: 2,
        retry_count: 2
      )

      expect(job.can_retry?).to be false
    end
  end

  describe "concurrency controls" do
    it "supports concurrency_key" do
      job = described_class.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        concurrency_key: "test_key",
        concurrency_limit: 5
      )

      expect(job.concurrency_key).to eq("test_key")
      expect(job.concurrency_limit).to eq(5)
    end
  end

  describe "scopes" do
    before do
      described_class.create!(
        queue_name: "default",
        class_name: "TestJob1",
        arguments: {},
        finished_at: Time.current
      )
      described_class.create!(
        queue_name: "default",
        class_name: "TestJob2",
        arguments: {}
      )
    end

    it "filters finished jobs" do
      expect(described_class.finished.count).to eq(1)
    end

    it "filters pending jobs" do
      expect(described_class.pending.count).to eq(1)
    end
  end
end
