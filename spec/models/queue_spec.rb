# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Queue do
  describe "validations" do
    it "requires name" do
      queue = described_class.new
      expect(queue).not_to be_valid
      expect(queue.errors[:name]).to be_present
    end

    it "requires unique name" do
      described_class.create!(name: "default")
      queue = described_class.new(name: "default")
      expect(queue).not_to be_valid
    end
  end

  describe ".find_or_create_by_name" do
    it "creates a new queue if it doesn't exist" do
      queue = described_class.find_or_create_by_name("new_queue")

      expect(queue).to be_persisted
      expect(queue.name).to eq("new_queue")
    end

    it "returns existing queue if it exists" do
      existing = described_class.create!(name: "existing_queue")
      queue = described_class.find_or_create_by_name("existing_queue")

      expect(queue.id).to eq(existing.id)
    end
  end

  describe "#pause" do
    it "sets paused to true" do
      queue = described_class.create!(name: "test_queue")
      queue.pause

      expect(queue.reload.paused).to be true
    end
  end

  describe "#resume" do
    it "sets paused to false" do
      queue = described_class.create!(name: "test_queue", paused: true)
      queue.resume

      expect(queue.reload.paused).to be false
    end
  end

  describe "#paused?" do
    it "returns true when paused" do
      queue = described_class.create!(name: "test_queue", paused: true)
      expect(queue.paused?).to be true
    end

    it "returns false when not paused" do
      queue = described_class.create!(name: "test_queue", paused: false)
      expect(queue.paused?).to be false
    end
  end
end
