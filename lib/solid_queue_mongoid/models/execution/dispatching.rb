# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    module Dispatching
      extend ActiveSupport::Concern

      class_methods do
        # Called by ScheduledExecution.dispatch_next_batch and FailedExecution.retry_all.
        # Dispatches jobs by id: promotes them to ready/blocked, then removes the
        # source execution records.
        def dispatch_jobs(job_ids)
          jobs = Job.where(:id.in => job_ids)

          Job.dispatch_all(jobs).map(&:id).then do |dispatched_job_ids|
            where(:job_id.in => dispatched_job_ids).delete_all
            dispatched_job_ids.size
          end
        end
      end
    end
  end
end
