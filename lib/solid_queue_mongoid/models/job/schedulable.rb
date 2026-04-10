# frozen_string_literal: true

module SolidQueue
  class Job
    module Schedulable
      extend ActiveSupport::Concern

      included do
        field :scheduled_at, type: Time

        index({ scheduled_at: 1 }, { sparse: true })

        has_one :scheduled_execution, class_name: "SolidQueue::ScheduledExecution", dependent: :destroy

        scope :scheduled, -> { where(finished_at: nil) }
      end

      class_methods do
        def schedule_all(jobs)
          schedule_all_at_once(jobs)
          successfully_scheduled(jobs)
        end

        private

        def schedule_all_at_once(jobs)
          ScheduledExecution.create_all_from_jobs(jobs)
        end

        def successfully_scheduled(jobs)
          job_ids = jobs.map(&:id)
          where(:id.in => ScheduledExecution.where(:job_id.in => job_ids).pluck(:job_id))
        end
      end

      # A job is due if it has no scheduled_at or it's in the past/present.
      def due?
        scheduled_at.nil? || scheduled_at <= Time.current
      end

      # True when a ScheduledExecution document exists.
      def scheduled?
        scheduled_execution.present?
      end

      def schedule
        ScheduledExecution.create_or_find_by!(job_id: id)
      end

      def execution
        super || scheduled_execution
      end
    end
  end
end
