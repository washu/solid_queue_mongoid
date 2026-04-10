# frozen_string_literal: true

# A job that fails on the first two attempts and succeeds on the third.
# Used by integration tests to verify retry behaviour.
class RetryingJob < ApplicationJob
  queue_as :integration_test

  class TransientError < StandardError; end

  # 3 total attempts (original + 2 retries), no wait so retries are immediately ready.
  retry_on TransientError, attempts: 3, wait: 0

  def perform(result_key)
    attempt = executions - 1
    IntegrationTestResults.record(result_key, "attempt_#{attempt}")
    raise TransientError, "Transient failure on attempt #{attempt}" if attempt < 2
  end
end
