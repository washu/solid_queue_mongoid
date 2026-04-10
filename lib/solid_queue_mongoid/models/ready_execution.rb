# frozen_string_literal: true

module SolidQueue
  class ReadyExecution < Execution
    assumes_attributes_from_job # inherits queue_name and priority

    scope :queued_as, ->(queue_name) { where(queue_name: queue_name) }

    index({ queue_name: 1, priority: 1, created_at: 1 })

    class << self
      # Primary entry point called by SolidQueue::Worker.
      # Atomically claims up to +limit+ executions from +queue_list+ for +process_id+.
      def claim(queue_list, limit, process_id)
        QueueSelector.new(queue_list, self).scoped_relations.flat_map do |queue_relation|
          select_and_lock(queue_relation, process_id, limit).tap do |locked|
            limit -= locked.size
          end
        end
      end

      # Integration spec compatible wrapper:
      #   claim_batch(limit, process:, queues:)
      def claim_batch(limit, process:, queues: "*")
        claim(queues, limit, process.id)
      end

      # Called by Worker#all_work_completed?.
      def aggregated_count_across(queue_list)
        QueueSelector.new(queue_list, self).scoped_relations.sum(&:count)
      end

      private

      # Atomically remove a ReadyExecution and create a ClaimedExecution.
      # Uses findOneAndDelete for each slot to guarantee no double-claim.
      def select_and_lock(queue_relation, process_id, limit)
        return [] if limit <= 0

        claimed = []
        ClaimedExecution.claiming(
          select_candidates(queue_relation, limit),
          process_id
        ) do |claimed_set|
          claimed = claimed_set
        end
        claimed
      end

      def select_candidates(queue_relation, limit)
        job_ids = []
        limit.times do
          raw = queue_relation.collection.find_one_and_delete(
            queue_relation.selector,
            sort: { "priority" => -1, "created_at" => 1 }
          )
          break unless raw

          job_ids << raw["job_id"]
        end
        job_ids
      end

      def discard_jobs(job_ids)
        Job.release_all_concurrency_locks(Job.where(:id.in => job_ids).to_a)
        Job.where(:id.in => job_ids).delete_all
      end
    end
  end
end
