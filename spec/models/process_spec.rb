# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Process do
  describe "validations" do
    it "requires hostname" do
      process = described_class.new(pid: 12345, kind: "Worker", name: "w-1")
      expect(process).not_to be_valid
      expect(process.errors[:hostname]).to be_present
    end

    it "requires pid" do
      process = described_class.new(hostname: "localhost", kind: "Worker", name: "w-1")
      expect(process).not_to be_valid
      expect(process.errors[:pid]).to be_present
    end
  end

  describe ".register" do
    it "creates a process with the full runtime keyword set" do
      process = described_class.register(
        kind: "Worker",
        name: "worker-abc",
        pid: ::Process.pid,
        hostname: Socket.gethostname,
        metadata: { queues: "default" }
      )

      expect(process).to be_persisted
      expect(process.kind).to eq("Worker")
      expect(process.name).to eq("worker-abc")
      expect(process.hostname).to eq(Socket.gethostname)
      expect(process.pid).to eq(::Process.pid)
      expect(process.metadata).to eq({ "queues" => "default" })
      expect(process.last_heartbeat_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#heartbeat" do
    it "updates last_heartbeat_at" do
      process = described_class.create!(
        kind: "Worker", hostname: "localhost", pid: 12345,
        name: "worker", last_heartbeat_at: 1.hour.ago
      )

      process.heartbeat

      expect(process.reload.last_heartbeat_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#deregister" do
    it "destroys the process" do
      process = described_class.create!(
        kind: "Worker", hostname: "localhost", pid: 12345, name: "worker"
      )

      process.deregister

      expect(described_class.where(id: process.id).exists?).to be false
    end
  end

  describe ".prune" do
    it "removes processes with stale heartbeats" do
      fresh = described_class.create!(
        kind: "Worker", hostname: "localhost", pid: 11111,
        name: "fresh_worker", last_heartbeat_at: 1.minute.ago
      )
      _stale = described_class.create!(
        kind: "Worker", hostname: "localhost", pid: 22222,
        name: "stale_worker", last_heartbeat_at: 10.minutes.ago
      )

      allow(SolidQueue).to receive(:process_alive_threshold).and_return(5.minutes)
      described_class.prune

      expect(described_class.where(id: fresh.id).exists?).to be true
      expect(described_class.where(name: "stale_worker").exists?).to be false
    end
  end
end
