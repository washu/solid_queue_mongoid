# frozen_string_literal: true

# This file pre-declares all the main model classes without their concerns.
# Must be loaded BEFORE concern files to avoid superclass mismatch errors.

module SolidQueue
  class Execution < Record; end

  class Job < Record; end

  class ReadyExecution < Execution; end
  class ClaimedExecution < Execution; end
  class BlockedExecution < Execution; end
  class ScheduledExecution < Execution; end
  class FailedExecution < Execution; end

  class RecurringExecution < Record; end

  class Process < Record
    module Executor; end
    module Prunable; end
  end

  class Pause < Record; end
  class Queue < Record; end
  class Semaphore < Record; end

  class RecurringTask < Record
    module Arguments; end
  end

  # Queue is a plain Ruby class (not Mongoid-backed) — no stub needed here.
end
