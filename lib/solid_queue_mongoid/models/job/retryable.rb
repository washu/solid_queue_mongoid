# frozen_string_literal: true

module SolidQueue
  class Job
    module Retryable
      extend ActiveSupport::Concern

      included do
        has_one :failed_execution, class_name: "SolidQueue::FailedExecution", dependent: :destroy
      end

      def retry
        failed_execution&.retry
      end

      def can_retry?
        max = read_attribute(:max_retries) || 0
        count = read_attribute(:retry_count) || 0
        count < max
      end

      def failed_with(exception)
        FailedExecution.create!(job_id: id, exception: exception)
      rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure => e
        raise unless duplicate_key_error?(e)

        existing = FailedExecution.find_by(job_id: id)
        if existing
          existing.exception = exception
          existing.save!
        else
          retry
        end
      end

      def reset_execution_counters
        return unless arguments.is_a?(Hash)

        arguments["executions"] = 0
        arguments["exception_executions"] = {}
        save!
      end

      private

      def duplicate_key_error?(err)
        err.message.to_s.include?("E11000") || err.message.to_s.include?("duplicate key")
      end
    end
  end
end
