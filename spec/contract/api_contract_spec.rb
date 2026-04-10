# frozen_string_literal: true

require "spec_helper"

# This spec is a version-gated contract test.
# It asserts that all symbols required by SolidQueue 1.3.x runtime are present
# on our Mongoid adapter. Fail here = guaranteed runtime breakage.
RSpec.describe "SolidQueue 1.3.x API contract" do
  describe "SolidQueue::ReadyExecution" do
    subject { SolidQueue::ReadyExecution }

    it { is_expected.to respond_to(:claim) }
    it { is_expected.to respond_to(:aggregated_count_across) }
    it { is_expected.to respond_to(:queued_as) }
  end

  describe "SolidQueue::ScheduledExecution" do
    subject { SolidQueue::ScheduledExecution }

    it { is_expected.to respond_to(:dispatch_next_batch) }
    it { is_expected.to respond_to(:due) }
    it { is_expected.to respond_to(:ordered) }
    it { is_expected.to respond_to(:next_batch) }
  end

  describe "SolidQueue::ClaimedExecution" do
    subject { SolidQueue::ClaimedExecution }

    it { is_expected.to respond_to(:claiming) }
    it { is_expected.to respond_to(:release_all) }
    it { is_expected.to respond_to(:fail_all_with) }
    it { is_expected.to respond_to(:orphaned) }

    it "instances respond to perform" do
      expect(SolidQueue::ClaimedExecution.instance_methods).to include(:perform)
    end

    it "instances respond to release" do
      expect(SolidQueue::ClaimedExecution.instance_methods).to include(:release)
    end

    it "instances respond to failed_with" do
      expect(SolidQueue::ClaimedExecution.instance_methods).to include(:failed_with)
    end

    it "instances respond to unblock_next_job" do
      expect(SolidQueue::ClaimedExecution.instance_methods).to include(:unblock_next_job)
    end
  end

  describe "SolidQueue::BlockedExecution" do
    subject { SolidQueue::BlockedExecution }

    it { is_expected.to respond_to(:release_one) }
    it { is_expected.to respond_to(:release_many) }
  end

  describe "SolidQueue::Process" do
    subject { SolidQueue::Process }

    it { is_expected.to respond_to(:register) }
    it { is_expected.to respond_to(:prune) }

    it "register accepts the runtime keyword set" do
      expect(SolidQueue::Process.method(:register).parameters).to include(
        %i[keyreq kind], %i[keyreq name], %i[keyreq pid], %i[keyreq hostname]
      )
    end

    it "instances respond to heartbeat" do
      expect(SolidQueue::Process.instance_methods).to include(:heartbeat)
    end

    it "instances respond to deregister" do
      expect(SolidQueue::Process.instance_methods).to include(:deregister)
    end
  end

  describe "SolidQueue::RecurringTask" do
    subject { SolidQueue::RecurringTask }

    it { is_expected.to respond_to(:wrap) }
    it { is_expected.to respond_to(:create_or_update_all) }
    it { is_expected.to respond_to(:static) }

    it "instances respond to enqueue" do
      expect(SolidQueue::RecurringTask.instance_methods).to include(:enqueue)
    end

    it "instances respond to delay_from_now" do
      expect(SolidQueue::RecurringTask.instance_methods).to include(:delay_from_now)
    end

    it "instances respond to next_time" do
      expect(SolidQueue::RecurringTask.instance_methods).to include(:next_time)
    end
  end

  describe "SolidQueue::RecurringExecution" do
    subject { SolidQueue::RecurringExecution }

    it { is_expected.to respond_to(:record) }
    it { is_expected.to respond_to(:clear_in_batches) }

    it "defines AlreadyRecorded exception" do
      expect(defined?(SolidQueue::RecurringExecution::AlreadyRecorded)).to eq("constant")
    end
  end

  describe "SolidQueue::Job" do
    subject { SolidQueue::Job }

    it { is_expected.to respond_to(:enqueue) }
    it { is_expected.to respond_to(:enqueue_all) }
    it { is_expected.to respond_to(:dispatch_all) }
    it { is_expected.to respond_to(:prepare_all_for_execution) }

    it "instances respond to dispatch" do
      expect(SolidQueue::Job.instance_methods).to include(:dispatch)
    end

    it "instances respond to dispatch_bypassing_concurrency_limits" do
      expect(SolidQueue::Job.instance_methods).to include(:dispatch_bypassing_concurrency_limits)
    end

    it "instances respond to finished!" do
      expect(SolidQueue::Job.instance_methods).to include(:finished!)
    end

    it "instances respond to failed_with" do
      expect(SolidQueue::Job.instance_methods).to include(:failed_with)
    end

    it "instances respond to due?" do
      expect(SolidQueue::Job.instance_methods).to include(:due?)
    end
  end

  describe "SolidQueue::Semaphore" do
    subject { SolidQueue::Semaphore }

    it { is_expected.to respond_to(:wait) }
    it { is_expected.to respond_to(:signal) }
    it { is_expected.to respond_to(:signal_all) }
  end
end
