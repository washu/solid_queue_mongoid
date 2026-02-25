# frozen_string_literal: true

module SolidQueue
  class ReadyExecution < Execution
    def self.claim_batch(batch_size, process:, queues: "*")
      queue_names = resolve_queue_names(queues)

      claimed = []
      batch_size.times do
        execution = where(:queue_name.in => queue_names)
          .order_by(priority: :asc, created_at: :asc)
          .first

        break unless execution

        if execution.job.claim(process: process)
          claimed << execution
        end
      end

      claimed
    end
  end
end
