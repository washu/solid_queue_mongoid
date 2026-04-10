# frozen_string_literal: true

# A trivial job used by integration tests to verify end-to-end execution.
class SimpleJob < ApplicationJob
  queue_as :integration_test

  def perform(result_key)
    IntegrationTestResults.record(result_key, :success)
  end
end
