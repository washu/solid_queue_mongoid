# frozen_string_literal: true

module SolidQueue
  class Record
    include Mongoid::Document
    include Mongoid::Timestamps

    # Override Mongoid's index_specifications to use per-class instance variables
    # instead of the shared cattr_accessor class variable.
    # This prevents index cross-contamination between models.
    class << self
      def index_specifications
        @_sq_index_specs ||= []
      end

      def index_specifications=(val)
        @_sq_index_specs = val
      end

      # Override Mongoid's index() to use our per-class storage.
      def index(spec, options = nil)
        specification = Mongoid::Indexable::Specification.new(self, spec, options)
        unless index_specifications.include?(specification)
          index_specifications.push(specification)
        end
      end
    end

    # Dynamic collection naming with prefix
    def self.inherited(subclass)
      super

      collection_name = subclass.name.demodulize.tableize
      prefixed_name = "#{SolidQueue.collection_prefix}#{collection_name}"

      subclass.store_in collection: prefixed_name, client: -> { SolidQueue.client.to_s }

      # Each subclass gets its own empty index_specifications array.
      # Indexes must be explicitly defined in each subclass (not inherited from parent)
      # because Mongoid::Indexable::Specification stores a reference to the klass,
      # and copying parent specs would create indexes on the parent's collection.
      subclass.instance_variable_set(:@_sq_index_specs, [])
    end

    class << self
      # MongoDB has no row-level locking; this is a no-op stub so SolidQueue
      # code that chains .non_blocking_lock still works.
      def non_blocking_lock
        all
      end

      # MongoDB supports unique indexes which serve the same purpose.
      def supports_insert_conflict_target?
        true
      end

      # Mongoid 9 supports multi-document transactions via replica sets.
      # We wrap in a MongoDB session transaction when available; fall back to a
      # plain yield for non-replica-set environments (e.g. tests with a standalone).
      def transaction(requires_new: false, &block)
        Mongoid::QueryCache.clear_cache
        Mongoid.default_client.with_session do |session|
          session.start_transaction
          result = yield
          session.commit_transaction
          result
        end
      rescue Mongo::Error::InvalidSession, Mongo::Error::OperationFailure => e
        # Not in a replica set or session not supported — execute without transaction
        raise if e.message.to_s.include?("Transaction numbers are only allowed")
        yield
      rescue StandardError
        yield
      end

      # Mongoid equivalent of ActiveRecord's create_or_find_by!.
      # Tries to create; on duplicate-key error or uniqueness validation error
      # finds the existing record. Falls back to finding by job_id alone when
      # the full attrs lookup would miss the existing record (e.g. queue_name
      # is not in attrs but was set via a before_create callback).
      def create_or_find_by!(attrs, &block)
        record = new(attrs)
        block.call(record) if block_given?
        record.save!
        record
      rescue Mongoid::Errors::Validations => e
        # If the only errors are uniqueness-related, fall back to find the existing record
        if uniqueness_only_error?(e.document)
          find_by_unique_key(attrs) || where(attrs).first || record
        else
          raise
        end
      rescue Mongo::Error::OperationFailure => e
        raise unless duplicate_key_error?(e)
        find_by_unique_key(attrs) || where(attrs).first || raise(e)
      end

      # find_by that raises Mongoid::Errors::DocumentNotFound when missing.
      def find_by!(attrs)
        find_by(attrs) || raise(Mongoid::Errors::DocumentNotFound.new(self, attrs))
      end

      private

      def duplicate_key_error?(err)
        msg = err.respond_to?(:message) ? err.message.to_s : err.to_s
        msg.include?("E11000") || msg.include?("duplicate key")
      end

      # Try to find an existing record using just the unique key field(s).
      # Used as fallback when find_by(full_attrs) misses because some fields
      # (e.g. queue_name) are only set by callbacks, not passed in attrs.
      # Uses where().first to avoid DocumentNotFound exceptions.
      def find_by_unique_key(attrs)
        return where(job_id: attrs[:job_id]).first if attrs[:job_id]
        return where(key: attrs[:key]).first if attrs[:key]
        nil
      end

      def uniqueness_only_error?(document)
        return false unless document.respond_to?(:errors)
        document.errors.all? do |error|
          error.type == :taken || error.message.to_s.include?("already been taken") ||
            (error.attribute.to_s != "base" &&
              document.class.validators
                      .select { |v| v.is_a?(Mongoid::Validatable::UniquenessValidator) }
                      .any? { |v| v.attributes.include?(error.attribute.to_sym) })
        end
      end
    end
  end
end
