# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Process do
  describe "validations" do
    it "requires hostname" do
      process = described_class.new(pid: 12345)
      expect(process).not_to be_valid
      expect(process.errors[:hostname]).to be_present
    end

    it "requires pid" do
      process = described_class.new(hostname: "localhost")
      expect(process).not_to be_valid
      expect(process.errors[:pid]).to be_present
    end
  end

  describe ".register" do
    it "creates a new process with current hostname and pid" do
      process = described_class.register(name: "test_worker", metadata: { version: "1.0" })

      expect(process.hostname).to eq(Socket.gethostname)
      expect(process.pid).to eq(::Process.pid)
      expect(process.name).to eq("test_worker")
      expect(process.metadata).to eq({ "version" => "1.0" })
      expect(process.last_heartbeat_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#heartbeat" do
    it "updates last_heartbeat_at" do
      process = described_class.create!(
        hostname: "localhost",
        pid: 12345,
        name: "worker",
        last_heartbeat_at: 1.hour.ago
      )

      process.heartbeat

      expect(process.reload.last_heartbeat_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#deregister" do
    it "releases claimed executions and destroys process" do
      process = described_class.create!(
        hostname: "localhost",
        pid: 12345,
        name: "worker"
      )

      job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {}
      )

      claimed = SolidQueue::ClaimedExecution.create!(
        job: job,
        process: process,
        queue_name: "default",
        priority: 0
      )

      process.deregister

      expect(described_class.where(id: process.id).exists?).to be false
      expect(SolidQueue::ClaimedExecution.where(id: claimed.id).exists?).to be false
    end
  end

  describe ".prune_stale_processes" do
    before do
      # Create fresh process
      described_class.create!(
        hostname: "localhost",
        pid: 11111,
        name: "fresh_worker",
        last_heartbeat_at: 1.minute.ago
      )

      # Create stale process
      described_class.create!(
        hostname: "localhost",
        pid: 22222,
        name: "stale_worker",
        last_heartbeat_at: 10.minutes.ago
      )
    end

    it "removes stale processes" do
      described_class.prune_stale_processes(timeout: 5.minutes)

      expect(described_class.where(name: "fresh_worker").exists?).to be true
      expect(described_class.where(name: "stale_worker").exists?).to be false
    end
  end
end
