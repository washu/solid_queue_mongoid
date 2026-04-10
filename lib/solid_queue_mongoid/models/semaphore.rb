# frozen_string_literal: true

module SolidQueue
  # Semaphore for concurrency control.
  #
  # Convention (matches spec expectations):
  #   value = number of USED (acquired) slots   (0 = none in use)
  #   limit = maximum concurrent slots
  #
  #   wait:   acquire a slot — succeeds when value < limit (increments value)
  #   signal: release a slot — increments value (marks another slot returned)
  #
  # NOTE: This intentionally differs from the ActiveRecord original which uses
  # value = remaining available slots.  The specs and BlockedExecution logic here
  # both expect the "used slots" convention.
  class Semaphore < Record
    field :key, type: String
    field :value, type: Integer, default: 0 # number of currently USED slots
    field :limit, type: Integer, default: 1
    field :expires_at, type: Time

    index({ key: 1 }, { unique: true })
    index({ expires_at: 1 })

    validates :key, presence: true, uniqueness: true

    # available: value < limit (at least one slot still free to acquire)
    scope :available, -> { where("$expr" => { "$lt" => ["$value", "$limit"] }) }
    scope :expired, -> { where(:expires_at.lt => Time.current) }

    class << self
      def wait(job)
        Proxy.new(job).wait
      end

      def signal(job)
        Proxy.new(job).signal
      end

      def signal_all(jobs)
        Proxy.signal_all(jobs)
      end

      # Requires a unique index on key.
      # Returns true if created/inserted; false on duplicate.
      def create_unique_by(attributes)
        create!(attributes)
        true
      rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure => e
        raise unless duplicate_key_error?(e)

        false
      end

      private

      def duplicate_key_error?(err)
        err.message.to_s.include?("E11000") || err.message.to_s.include?("duplicate key")
      end
    end

    # ── Instance methods ──────────────────────────────────────────────────────

    # Atomically acquire one slot (increment value if value < limit).
    # Returns true on success, false when at limit.
    def acquire
      result = self.class.collection.find_one_and_update(
        { _id: id, "value" => { "$lt" => limit } },
        { "$inc" => { "value" => 1 } },
        return_document: :after
      )
      result.present?
    end

    # Release one slot (decrement value). No-op if already at 0.
    def release
      self.class.collection.find_one_and_update(
        { _id: id, "value" => { "$gt" => 0 } },
        { "$inc" => { "value" => -1 } },
        return_document: :after
      )
      true
    end

    # True when there is still room to acquire (value < limit).
    def available?
      reload
      value < limit
    end

    # ── Proxy inner class ─────────────────────────────────────────────────────
    class Proxy
      # Decrement value for every job's semaphore key (signal = release a used slot).
      def self.signal_all(jobs)
        keys = jobs.map(&:concurrency_key)
        return if keys.empty?

        Semaphore.in(key: keys).each do |sem|
          Semaphore.collection.find_one_and_update(
            { _id: sem.id, "value" => { "$gt" => 0 } },
            { "$inc" => { "value" => -1 } }
          )
        end
      end

      def initialize(job)
        @job = job
      end

      # Acquire a slot: succeeds when value < limit.
      # Creates the semaphore document on first use.
      def wait
        semaphore = Semaphore.where(key: key).first

        if semaphore
          # Atomically increment if value < limit
          attempt_acquire(semaphore.id, semaphore.limit)
        else
          attempt_creation
        end
      end

      # Release a slot: decrement value (marks one used slot as freed).
      def signal
        attempt_release_slot
      end

      private

      attr_reader :job

      # Try to create the semaphore with value=1 (one slot in use).
      def attempt_creation
        lim = limit
        if Semaphore.create_unique_by(key: key, value: 1, limit: lim, expires_at: expires_at)
          true
        else
          # Race: someone else created it first — try to acquire from existing
          sem = Semaphore.where(key: key).first
          return false unless sem

          attempt_acquire(sem.id, sem.limit)
        end
      end

      # Atomically increment value if currently < limit.
      def attempt_acquire(semaphore_id, lim)
        result = Semaphore.collection.find_one_and_update(
          { _id: semaphore_id, "value" => { "$lt" => lim } },
          { "$inc" => { "value" => 1 }, "$set" => { "expires_at" => expires_at } },
          return_document: :after
        )
        result.present?
      end

      # Atomically decrement value if currently > 0 (release one used slot).
      def attempt_release_slot
        result = Semaphore.collection.find_one_and_update(
          { "key" => key, "value" => { "$gt" => 0 } },
          { "$inc" => { "value" => -1 }, "$set" => { "expires_at" => expires_at } },
          return_document: :after
        )
        result.present?
      end

      def key
        job.concurrency_key
      end

      def expires_at
        job.respond_to?(:concurrency_duration) ? job.concurrency_duration.from_now : 5.minutes.from_now
      end

      def limit
        (job.respond_to?(:concurrency_limit) ? job.concurrency_limit : nil) || 1
      end
    end
  end
end
