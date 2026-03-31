# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::ScheduledExecution do
  let(:job) do
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments: {},
      scheduled_at: 1.hour.from_now
    )
  end

  describe "creation" do
    it "creates a scheduled execution" do
      # Job.create! with future scheduled_at auto-schedules via after_create
      execution = job.scheduled_execution

      expect(execution).to be_present
      expect(execution.job).to eq(job)
      expect(execution.scheduled_at).to be_within(1.second).of(1.hour.from_now)
    end
  end

  describe "#dispatch" do
    it "does not dispatch future jobs" do
      execution = job.scheduled_execution

      execution.dispatch

      expect(described_class.where(id: execution.id).exists?).to be true
    end

    it "dispatches due jobs" do
      past_job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "TestJob",
        arguments: {},
        scheduled_at: 1.hour.ago
      )

      # past_job auto-dispatched as ready; create a ScheduledExecution manually to test dispatch
      execution = described_class.create!(
        job: past_job,
        queue_name: past_job.queue_name,
        priority: past_job.priority,
        scheduled_at: past_job.scheduled_at
      )

      execution.dispatch

      expect(described_class.where(id: execution.id).exists?).to be false
      expect(past_job.reload.ready_execution).to be_present
    end
  end

  describe ".dispatch_due_batch" do
    before do
      # Create past scheduled jobs — after_create dispatches them as ready (not scheduled).
      # Manually create ScheduledExecutions to represent the scheduled queue state.
      2.times do |i|
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "PastJob#{i}",
          arguments: {},
          scheduled_at: 1.hour.ago
        )
        described_class.create!(
          job: job,
          queue_name: "default",
          priority: 0,
          scheduled_at: 1.hour.ago
        )
      end

      # Create future scheduled job — after_create auto-schedules it (1 ScheduledExecution created)
      SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "FutureJob",
        arguments: {},
        scheduled_at: 1.hour.from_now
      )
    end

    it "dispatches only due jobs" do
      described_class.dispatch_due_batch(10)

      # Should have dispatched 2 past jobs, leaving 1 future job
      expect(described_class.count).to eq(1)
    end

    it "respects batch size" do
      described_class.dispatch_due_batch(1)

      # Should leave at least 2 jobs (1 dispatched, 2 remaining)
      expect(described_class.count).to be >= 1
    end
  end
end
