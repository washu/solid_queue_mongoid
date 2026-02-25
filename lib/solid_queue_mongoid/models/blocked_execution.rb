# frozen_string_literal: true

module SolidQueue
  class BlockedExecution < Execution
    def unblock
      semaphore = Semaphore.find_by(key: concurrency_key)
      return unless semaphore&.acquire

      destroy
      job.create_ready_execution!
    end

    def self.unblock_all(concurrency_key)
      where(concurrency_key: concurrency_key).each(&:unblock)
    end
  end
end
