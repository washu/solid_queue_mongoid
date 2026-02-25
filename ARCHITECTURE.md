# Architecture

## Overview

`solid_queue_mongoid` provides Mongoid-based models that mirror the structure of SolidQueue's ActiveRecord models. This allows SolidQueue to work with MongoDB instead of PostgreSQL/MySQL/SQLite.

## Design Approach

### Why Not Adapter Pattern?

SolidQueue's models inherit from `ActiveRecord::Base` and use ActiveRecord-specific features throughout (transactions, locking, `insert_all`, etc.). An adapter pattern would be extremely complex and fragile.

### Model Replacement Strategy

Instead, we:

1. **Reimplement models** using Mongoid that match SolidQueue's API surface
2. **Load before SolidQueue** and prevent SolidQueue's AR models from loading
3. **Maintain API compatibility** so business logic works unchanged
4. **Mirror structure** so updates from SolidQueue can be easily ported

## Staying in Sync with SolidQueue

### When SolidQueue Updates

1. Check SolidQueue's CHANGELOG
2. For **business logic changes** in model methods → port to our models
3. For **new fields** → add to our Mongoid field definitions
4. For **new indexes** → add Mongoid index declarations
5. For **new models** → create equivalent Mongoid model

### What We Don't Need to Port

- Database migrations (we use Mongoid schema)
- ActiveRecord-specific code (transactions, locking strategies)
- SQL-specific optimizations

### Testing Compatibility

Run SolidQueue's test suite against our Mongoid models to ensure API compatibility.

## Key Differences from ActiveRecord

### Transactions
MongoDB transactions require replica sets. We fall back to non-transactional operation when not available.

### Locking
- `FOR UPDATE SKIP LOCKED` → Not available in MongoDB
- We use atomic operations (`$inc`, `findAndModify`) instead

### Bulk Operations
- `insert_all` → Individual inserts (MongoDB has `insertMany` but Mongoid doesn't expose it the same way)
- `upsert_all` → Individual find_one_and_replace operations

### IDs
- ActiveRecord uses `bigint` IDs
- Mongoid uses `BSON::ObjectId`
- This affects foreign key relationships

## Module Structure

```
lib/solid_queue_mongoid/
  models/
    record.rb                    # Base model (replaces AR::Base)
    job.rb                       # Job model
    job/
      executable.rb              # Mirrors SolidQueue::Job::Executable
      clearable.rb              # Mirrors SolidQueue::Job::Clearable
      ...
    execution.rb                 # Base execution
    ready_execution.rb           # Ready jobs
    claimed_execution.rb         # In-progress jobs
    ...
```

Each file mirrors its SolidQueue counterpart in `app/models/solid_queue/`.

## Version Compatibility

| SolidQueue Version | solid_queue_mongoid Version | Status |
|--------------------|----------------------------|---------|
| 1.0.x - 1.3.x     | 0.1.0                      | Initial implementation |

## Contributing

When porting changes from SolidQueue:

1. Reference the SolidQueue commit/PR
2. Explain any deviations due to MongoDB differences
3. Update this document if architectural changes are needed
