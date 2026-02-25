# frozen_string_literal: true

module SolidQueue
  class BlockedExecution < Execution
    def unblock
      semaphore = Semaphore.where(key: concurrency_key).first
      return false unless semaphore&.acquire

      destroy
      job.create_ready_execution!
      true
    end

    def self.unblock_all(concurrency_key, limit = nil)
      executions = where(concurrency_key: concurrency_key)
      executions = executions.limit(limit) if limit

      count = 0
      executions.each do |execution|
        if execution.unblock
          count += 1
        end
      end
      count
    end
  end
end
