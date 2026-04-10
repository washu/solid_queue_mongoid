# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidQueue::Job::Clearable do
  def make_job(finished_at: nil)
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "TestJob",
      arguments:  {},
      finished_at: finished_at
    )
  end

  describe ".clearable scope" do
    it "includes finished jobs older than the threshold" do
      old_job = make_job(finished_at: 2.days.ago)
      make_job(finished_at: nil)           # not finished — excluded
      make_job(finished_at: 1.minute.ago)  # finished but recent — excluded by default threshold

      clearable = SolidQueue::Job.clearable(finished_before: 1.day.ago)
      expect(clearable.to_a).to include(old_job)
      expect(clearable.count).to eq(1)
    end

    it "filters by class_name when provided" do
      make_job(finished_at: 2.days.ago)
      SolidQueue::Job.create!(queue_name: "default", class_name: "OtherJob",
                               arguments: {}, finished_at: 2.days.ago)

      clearable = SolidQueue::Job.clearable(finished_before: 1.day.ago, class_name: "TestJob")
      expect(clearable.pluck(:class_name).uniq).to eq(["TestJob"])
    end
  end

  describe ".clear_finished_in_batches" do
    it "deletes all finished jobs older than the threshold" do
      3.times { make_job(finished_at: 2.days.ago) }
      make_job(finished_at: nil)

      SolidQueue::Job.clear_finished_in_batches(finished_before: 1.day.ago)

      expect(SolidQueue::Job.where(:finished_at.ne => nil).count).to eq(0)
      expect(SolidQueue::Job.where(finished_at: nil).count).to eq(1)
    end

    it "respects batch_size and loops until done" do
      5.times { make_job(finished_at: 2.days.ago) }

      SolidQueue::Job.clear_finished_in_batches(batch_size: 2, finished_before: 1.day.ago)

      expect(SolidQueue::Job.where(:finished_at.ne => nil).count).to eq(0)
    end
  end
end
