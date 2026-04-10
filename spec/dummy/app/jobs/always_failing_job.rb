# frozen_string_literal: true

# A job that always raises, used to verify that exhausted retries produce a FailedExecution.
class AlwaysFailingJob < ApplicationJob
  queue_as :integration_test

  class PermanentError < StandardError; end

  # 2 total attempts (original + 1 retry), no wait so retries are immediately ready.
  retry_on PermanentError, attempts: 2, wait: 0

  def perform(result_key)
    IntegrationTestResults.record(result_key, "attempt_#{executions - 1}")
    raise PermanentError, "Always fails"
  end
end
