# frozen_string_literal: true

module SolidQueue
  class Job
    module Recurrable
      extend ActiveSupport::Concern

      included do
        field :recurring_execution_id, type: BSON::ObjectId

        belongs_to :recurring_execution, class_name: "SolidQueue::RecurringExecution", optional: true
      end

      def recurring?
        recurring_execution_id.present?
      end
    end
  end
end
