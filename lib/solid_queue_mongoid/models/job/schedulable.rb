# frozen_string_literal: true

module SolidQueue
  class Job
    module Schedulable
      extend ActiveSupport::Concern

      included do
        field :scheduled_at, type: Time
        field :active_job_id, type: String

        index({ scheduled_at: 1 }, { sparse: true })
        index({ active_job_id: 1 }, { unique: true, sparse: true })

        has_one :scheduled_execution, class_name: "SolidQueue::ScheduledExecution", dependent: :destroy
      end

      def scheduled?
        scheduled_at.present? && scheduled_at > Time.current
      end

      def schedule(scheduled_at:)
        self.scheduled_at = scheduled_at
        save!
        create_scheduled_execution!
      end

      def dispatch_scheduled
        return unless scheduled?
        return if scheduled_at > Time.current

        scheduled_execution&.dispatch
      end

      private

      def create_scheduled_execution!
        ScheduledExecution.create!(
          job: self,
          queue_name: queue_name,
          priority: priority,
          scheduled_at: scheduled_at
        )
      end
    end
  end
end
