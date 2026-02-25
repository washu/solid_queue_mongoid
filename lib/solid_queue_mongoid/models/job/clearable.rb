# frozen_string_literal: true

module SolidQueue
  class Job
    module Clearable
      extend ActiveSupport::Concern

      class_methods do
        def clear_finished_in_batches(batch_size: 500, finished_before: nil)
          finished_before ||= SolidQueue.clear_finished_jobs_after.ago
          scope = finished.where(:finished_at.lte => finished_before)

          loop do
            deleted = scope.limit(batch_size).delete_all
            break if deleted < batch_size
          end
        end
      end

      def finished?
        finished_at.present?
      end

      def clear_if_finished
        destroy if finished?
      end
    end
  end
end
