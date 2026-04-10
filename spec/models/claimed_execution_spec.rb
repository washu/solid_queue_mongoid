# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::ClaimedExecution do
  let(:process) do
    SolidQueue::Process.create!(
      hostname: "localhost",
      pid: 12345,
      name: "worker-test",
      kind: "Worker"
    )
  end

  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {}
    )
  end

  describe "creation" do
    it "creates a claimed execution" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      expect(execution.job).to eq(job)
      expect(execution.process).to eq(process)
      expect(execution.process_id).to eq(process.id)
    end
  end

  describe "#release" do
    it "destroys claimed execution and re-dispatches the job" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      execution.release

      expect(described_class.where(id: execution.id).exists?).to be false
      # Job should be re-dispatched (ready or scheduled)
      job.reload
      expect(job.ready? || job.scheduled?).to be true
    end
  end

  describe ".release_all" do
    it "releases all executions" do
      3.times do
        j = SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob", arguments: {})
        described_class.create!(job: j, process: process, queue_name: "default", priority: 0)
      end

      expect(described_class.where(process: process).count).to eq(3)

      described_class.where(process_id: process.id).release_all

      expect(described_class.where(process_id: process.id).count).to eq(0)
    end
  end

  describe ".claiming" do
    it "bulk-inserts claimed executions and yields them" do
      j2 = SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob2", arguments: {})

      yielded = nil
      described_class.claiming([job.id, j2.id], process.id) { |claimed| yielded = claimed }

      expect(yielded.size).to eq(2)
      expect(yielded.map(&:process_id).uniq).to eq([process.id])
    end
  end

  describe ".fail_all_with" do
    it "marks all executions as failed and removes them" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      error = RuntimeError.new("process died")
      described_class.where(process_id: process.id).fail_all_with(error)

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(SolidQueue::FailedExecution.where(job_id: job.id).exists?).to be true
    end
  end

  describe "#failed_with" do
    it "creates a failed execution and destroys the claimed execution" do
      execution = described_class.create!(
        job: job,
        process: process,
        queue_name: job.queue_name,
        priority: job.priority
      )

      error = RuntimeError.new("worker crashed")
      execution.failed_with(error)

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(SolidQueue::FailedExecution.where(job_id: job.id).exists?).to be true
    end
  end

  describe ".discard_all_in_batches / .discard_all_from_jobs" do
    it "raises UndiscardableError" do
      expect { described_class.discard_all_in_batches }.to raise_error(SolidQueue::Execution::UndiscardableError)
      expect { described_class.discard_all_from_jobs([]) }.to raise_error(SolidQueue::Execution::UndiscardableError)
    end
  end

  describe "#discard" do
    it "raises UndiscardableError" do
      execution = described_class.create!(
        job: job, process: process,
        queue_name: job.queue_name, priority: job.priority
      )
      expect { execution.discard }.to raise_error(SolidQueue::Execution::UndiscardableError)
    end
  end

  describe ".orphaned scope" do
    it "returns executions whose process no longer exists (simulating crash)" do
      execution = described_class.create!(
        job: job, process: process,
        queue_name: job.queue_name, priority: job.priority
      )

      # Simulate a process crash by deleting the process document directly,
      # bypassing the after_destroy callback that would normally release executions.
      SolidQueue::Process.collection.find(_id: process.id).delete_one

      orphaned_ids = described_class.orphaned.pluck(:id)
      expect(orphaned_ids).to include(execution.id)
    end

    it "does not include executions whose process still exists" do
      execution = described_class.create!(
        job: job, process: process,
        queue_name: job.queue_name, priority: job.priority
      )

      expect(described_class.orphaned.pluck(:id)).not_to include(execution.id)
    end
  end
end
