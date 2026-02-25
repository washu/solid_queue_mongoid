# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Pause do
  describe "validations" do
    it "requires queue_name" do
      pause = described_class.new
      expect(pause).not_to be_valid
      expect(pause.errors[:queue_name]).to be_present
    end

    it "requires unique queue_name" do
      described_class.create!(queue_name: "default")
      pause = described_class.new(queue_name: "default")
      expect(pause).not_to be_valid
    end
  end

  describe ".pause_queue" do
    it "creates a pause record for the queue" do
      pause = described_class.pause_queue("default")

      expect(pause).to be_persisted
      expect(pause.queue_name).to eq("default")
    end

    it "returns existing pause if already paused" do
      existing = described_class.create!(queue_name: "default")
      pause = described_class.pause_queue("default")

      expect(pause.id).to eq(existing.id)
    end
  end

  describe ".resume_queue" do
    it "removes pause record for the queue" do
      described_class.create!(queue_name: "default")

      described_class.resume_queue("default")

      expect(described_class.where(queue_name: "default").exists?).to be false
    end

    it "handles non-existent pause gracefully" do
      expect { described_class.resume_queue("non_existent") }.not_to raise_error
    end
  end

  describe ".paused?" do
    it "returns true when queue is paused" do
      described_class.create!(queue_name: "default")

      expect(described_class.paused?("default")).to be true
    end

    it "returns false when queue is not paused" do
      expect(described_class.paused?("default")).to be false
    end
  end
end
