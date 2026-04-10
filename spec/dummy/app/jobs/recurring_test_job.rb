# frozen_string_literal: true

# Used by cron integration tests to verify RecurringTask enqueue + execution.
class RecurringTestJob < ApplicationJob
  queue_as :integration_test

  def perform(result_key)
    IntegrationTestResults.record(result_key, :executed)
  end
end
