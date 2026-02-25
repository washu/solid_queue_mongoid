# frozen_string_literal: true

module SolidQueue
  class Job
    module Retryable
      extend ActiveSupport::Concern

      included do
        field :retry_count, type: Integer, default: 0
        field :max_retries, type: Integer

        has_many :failed_executions, class_name: "SolidQueue::FailedExecution", dependent: :destroy
      end

      def retry!
        return unless can_retry?

        increment(retry_count: 1)
        failed_executions.last&.retry
      end

      def can_retry?
        max_retries.nil? || retry_count < max_retries
      end

      def retried?
        retry_count > 0
      end
    end
  end
end
