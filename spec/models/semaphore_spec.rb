# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Semaphore do
  describe "validations" do
    it "requires key" do
      sem = described_class.new(value: 0)
      expect(sem).not_to be_valid
      expect(sem.errors[:key]).to be_present
    end

    it "requires unique key" do
      described_class.create!(key: "test_key", value: 0)
      sem = described_class.new(key: "test_key", value: 0)
      expect(sem).not_to be_valid
    end
  end

  describe ".wait / .signal via Proxy" do
    let(:job) do
      double("job",
             concurrency_key: "resource_key",
             concurrency_limit: 2,
             concurrency_duration: 5.minutes)
    end

    it "allows acquisition when below limit" do
      result = described_class.wait(job)
      expect(result).to be true

      sem = described_class.find_by(key: "resource_key")
      # Started at limit-1=1, decremented to 0 after wait — or created at limit-1
      expect(sem).to be_present
    end

    it "blocks when at limit" do
      # Fill up the semaphore
      2.times { described_class.wait(job) }

      # Try one more — should fail
      result = described_class.wait(job)
      expect(result).to be false
    end

    it "signal decrements value (releases a used slot)" do
      described_class.wait(job)
      before = described_class.find_by(key: "resource_key").value

      described_class.signal(job)
      after = described_class.find_by(key: "resource_key").value

      expect(after).to eq(before - 1)
    end
  end

  describe ".signal_all" do
    let(:job1) { double("j1", concurrency_key: "k1", concurrency_limit: 3, concurrency_duration: 5.minutes) }
    let(:job2) { double("j2", concurrency_key: "k2", concurrency_limit: 3, concurrency_duration: 5.minutes) }

    before do
      described_class.create!(key: "k1", value: 1)
      described_class.create!(key: "k2", value: 2)
    end

    it "decrements value for each job's concurrency key (releases used slots)" do
      described_class.signal_all([job1, job2])

      expect(described_class.find_by(key: "k1").value).to eq(0)
      expect(described_class.find_by(key: "k2").value).to eq(1)
    end
  end
end
