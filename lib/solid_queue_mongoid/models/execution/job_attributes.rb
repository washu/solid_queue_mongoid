# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    module JobAttributes
      extend ActiveSupport::Concern

      included do
        field :job_id, type: BSON::ObjectId
        field :queue_name, type: String
        field :priority, type: Integer, default: 0
        field :concurrency_key, type: String

        index({ job_id: 1 }, { unique: true })
        index({ queue_name: 1, priority: 1 })
        index({ concurrency_key: 1 }, { sparse: true })

        belongs_to :job, class_name: "SolidQueue::Job", optional: false
      end

      def arguments
        job.arguments
      end

      def class_name
        job.class_name
      end

      def finished!
        destroy
      end
    end
  end
end
