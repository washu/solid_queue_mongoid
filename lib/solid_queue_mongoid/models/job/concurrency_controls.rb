# frozen_string_literal: true

module SolidQueue
  class Job
    module ConcurrencyControls
      extend ActiveSupport::Concern

      included do
        field :concurrency_key, type: String
        field :concurrency_limit, type: Integer

        index({ concurrency_key: 1 }, { sparse: true })

        has_one :blocked_execution, class_name: "SolidQueue::BlockedExecution", dependent: :destroy
      end

      def blocked?
        blocked_execution.present?
      end

      def acquire_concurrency_lock
        return true unless concurrency_key.present?

        semaphore = Semaphore.find_or_create_by(key: concurrency_key) do |s|
          s.value = 0
          s.limit = concurrency_limit
        end

        if semaphore.acquire
          true
        else
          create_blocked_execution!
          false
        end
      end

      def release_concurrency_lock
        return unless concurrency_key.present?

        semaphore = Semaphore.find_by(key: concurrency_key)
        semaphore&.release

        # Unblock waiting jobs
        BlockedExecution.where(concurrency_key: concurrency_key).first&.unblock
      end

      private

      def create_blocked_execution!
        BlockedExecution.create!(
          job: self,
          queue_name: queue_name,
          priority: priority,
          concurrency_key: concurrency_key
        )
      end
    end
  end
end
