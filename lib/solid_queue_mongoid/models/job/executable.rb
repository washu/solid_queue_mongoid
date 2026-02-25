# frozen_string_literal: true

module SolidQueue
  class Job
    module Executable
      extend ActiveSupport::Concern

      included do
        field :finished_at, type: Time

        has_one :ready_execution, class_name: "SolidQueue::ReadyExecution", dependent: :destroy
        has_one :claimed_execution, class_name: "SolidQueue::ClaimedExecution", dependent: :destroy

        scope :finished, -> { where(:finished_at.ne => nil) }
        scope :pending, -> { where(finished_at: nil) }
      end

      def ready_to_execute?
        ready_execution.present?
      end

      def claimed?
        claimed_execution.present?
      end

      def dispatch
        return if finished?
        return unless acquire_concurrency_lock

        if scheduled? && scheduled_at > Time.current
          schedule(scheduled_at: scheduled_at)
        else
          create_ready_execution!
        end
      end

      def claim(process:)
        return unless ready_execution

        transaction do
          ready_execution.destroy
          create_claimed_execution!(process: process)
        end
      end

      def finish
        update(finished_at: Time.current)
        release_concurrency_lock
        claimed_execution&.destroy
      end

      def fail_with_error(error)
        FailedExecution.create_from_job!(self, error)
        release_concurrency_lock
        claimed_execution&.destroy
      end

      private

      def create_ready_execution!
        ReadyExecution.create!(
          job: self,
          queue_name: queue_name,
          priority: priority,
          concurrency_key: concurrency_key
        )
      end

      def create_claimed_execution!(process:)
        ClaimedExecution.create!(
          job: self,
          process: process,
          queue_name: queue_name,
          priority: priority
        )
      end
    end
  end
end
