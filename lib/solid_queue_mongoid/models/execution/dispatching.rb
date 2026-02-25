# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    module Dispatching
      extend ActiveSupport::Concern

      class_methods do
        def dispatch_next_batch(batch_size, queues: "*", capabilities: {})
          queue_names = resolve_queue_names(queues)

          operations = []
          batch_size.times do
            execution = where(:queue_name.in => queue_names)
              .order_by(priority: :asc, created_at: :asc)
              .find_one_and_update(
                { "$set" => { dispatched_at: Time.current } },
                return_document: :after
              )

            operations << execution if execution
          end

          operations.compact
        end

        private

        def resolve_queue_names(queues)
          return SolidQueue::Queue.all.pluck(:name) if queues == "*"

          Array(queues).flat_map do |queue_pattern|
            if queue_pattern.include?("*")
              regex = /^#{Regexp.escape(queue_pattern).gsub('\*', '.*')}$/
              SolidQueue::Queue.where(name: regex).pluck(:name)
            else
              queue_pattern
            end
          end.uniq
        end
      end
    end
  end
end
