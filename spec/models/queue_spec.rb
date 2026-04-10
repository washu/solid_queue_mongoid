# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Queue do
  describe ".all" do
    it "returns queues derived from existing jobs" do
      SolidQueue::Job.create!(queue_name: "default",  class_name: "TestJob", arguments: {})
      SolidQueue::Job.create!(queue_name: "critical", class_name: "TestJob", arguments: {})

      names = described_class.all.map(&:name)
      expect(names).to include("default", "critical")
    end

    it "returns an empty array when there are no jobs" do
      expect(described_class.all).to be_empty
    end
  end

  describe ".find_by_name" do
    it "returns a Queue with the given name without hitting the DB" do
      queue = described_class.find_by_name("some_queue")
      expect(queue).to be_a(described_class)
      expect(queue.name).to eq("some_queue")
    end
  end

  describe "#paused?" do
    it "returns true when a Pause record exists for the queue" do
      SolidQueue::Pause.create!(queue_name: "test_queue")
      queue = described_class.new("test_queue")
      expect(queue.paused?).to be true
    end

    it "returns false when no Pause record exists" do
      queue = described_class.new("test_queue")
      expect(queue.paused?).to be false
    end
  end

  describe "#pause" do
    it "creates a Pause record for the queue" do
      queue = described_class.new("test_queue")
      queue.pause
      expect(SolidQueue::Pause.where(queue_name: "test_queue").exists?).to be true
    end
  end

  describe "#resume" do
    it "removes the Pause record for the queue" do
      SolidQueue::Pause.create!(queue_name: "test_queue")
      queue = described_class.new("test_queue")
      queue.resume
      expect(SolidQueue::Pause.where(queue_name: "test_queue").exists?).to be false
    end
  end

  describe "#size" do
    it "returns the number of ready executions in the queue" do
      # Job auto-dispatches a ReadyExecution on creation
      SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob", arguments: {})

      queue = described_class.new("default")
      expect(queue.size).to eq(1)
    end
  end

  describe "#==" do
    it "compares by name" do
      expect(described_class.new("a")).to eq(described_class.new("a"))
      expect(described_class.new("a")).not_to eq(described_class.new("b"))
    end
  end
end
