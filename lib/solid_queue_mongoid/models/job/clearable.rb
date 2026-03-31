# frozen_string_literal: true

module SolidQueue
  class Job
    module Clearable
      extend ActiveSupport::Concern

      included do
        scope :clearable, ->(finished_before: SolidQueue.clear_finished_jobs_after.ago, class_name: nil) {
          scope = where(:finished_at.ne => nil).where(:finished_at.lte => finished_before)
          scope = scope.where(class_name: class_name) if class_name.present?
          scope
        }
      end

      class_methods do
        def clear_finished_in_batches(batch_size: 500, finished_before: SolidQueue.clear_finished_jobs_after.ago, class_name: nil, sleep_between_batches: 0)
          loop do
            deleted = clearable(finished_before: finished_before, class_name: class_name).limit(batch_size).delete_all
            sleep(sleep_between_batches) if sleep_between_batches > 0
            break if deleted == 0
          end
        end
      end
    end
  end
end
