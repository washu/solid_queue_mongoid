# frozen_string_literal: true

module SolidQueue
  class Execution < Record
    include JobAttributes
    include Dispatching

    field :dispatched_at, type: Time

    index({ dispatched_at: 1 }, { sparse: true })
  end
end
