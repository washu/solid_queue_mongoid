# frozen_string_literal: true

module SolidQueue
  class Process
    module Executor
      extend ActiveSupport::Concern

      included do
        has_many :claimed_executions, class_name: "SolidQueue::ClaimedExecution",
                 foreign_key: :process_id

        after_destroy :release_all_claimed_executions
      end

      def fail_all_claimed_executions_with(error)
        claimed_executions.fail_all_with(error) if claims_executions?
      end

      def release_all_claimed_executions
        claimed_executions.release_all if claims_executions?
      end

      private

        def claims_executions?
          kind.nil? || kind == "Worker"
        end
    end
  end
end

