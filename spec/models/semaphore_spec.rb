# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Semaphore do
  describe "validations" do
    it "requires key" do
      semaphore = described_class.new(value: 0, limit: 5)
      expect(semaphore).not_to be_valid
      expect(semaphore.errors[:key]).to be_present
    end

    it "requires unique key" do
      described_class.create!(key: "test_key", value: 0, limit: 5)
      semaphore = described_class.new(key: "test_key", value: 0, limit: 5)
      expect(semaphore).not_to be_valid
    end
  end

  describe "#acquire" do
    it "increments value when below limit" do
      semaphore = described_class.create!(key: "test_key", value: 0, limit: 5)

      result = semaphore.acquire

      expect(result).to be true
      expect(semaphore.reload.value).to eq(1)
    end

    it "does not increment when at limit" do
      semaphore = described_class.create!(key: "test_key", value: 5, limit: 5)

      result = semaphore.acquire

      expect(result).to be false
      expect(semaphore.reload.value).to eq(5)
    end

    it "handles concurrent acquires" do
      semaphore = described_class.create!(key: "test_key", value: 4, limit: 5)

      result1 = semaphore.acquire
      result2 = semaphore.acquire

      # First should succeed, second should fail
      expect(result1).to be true
      expect(result2).to be false
      expect(semaphore.reload.value).to eq(5)
    end
  end

  describe "#release" do
    it "decrements value when above zero" do
      semaphore = described_class.create!(key: "test_key", value: 3, limit: 5)

      semaphore.release

      expect(semaphore.reload.value).to eq(2)
    end

    it "does not decrement below zero" do
      semaphore = described_class.create!(key: "test_key", value: 0, limit: 5)

      semaphore.release

      expect(semaphore.reload.value).to eq(0)
    end
  end

  describe "#available?" do
    it "returns true when below limit" do
      semaphore = described_class.create!(key: "test_key", value: 3, limit: 5)

      expect(semaphore.available?).to be true
    end

    it "returns false when at limit" do
      semaphore = described_class.create!(key: "test_key", value: 5, limit: 5)

      expect(semaphore.available?).to be false
    end
  end
end
