# frozen_string_literal: true

# This file pre-declares all the main model classes without their concerns
# This must be loaded BEFORE the concern files to avoid superclass mismatch errors

module SolidQueue
  class Execution < Record; end
  class Job < Record; end
  class ReadyExecution < Execution; end
  class ClaimedExecution < Execution; end
  class BlockedExecution < Execution; end
  class ScheduledExecution < Execution; end
  class FailedExecution < Execution; end
  class RecurringExecution < Record; end
  class Process < Record; end
  class Pause < Record; end
  class Semaphore < Record; end
  class RecurringTask < Record; end
  class Queue < Record; end
end
