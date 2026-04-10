## [Unreleased]

## [0.3.0] - 2026-04-10

### Changed
- `fixed CI.yml`
- `fixed Rubocop settings and results.`

## [0.2.0] - 2026-04-10

### Added
- `RecurringTask.create_dynamic_task(key, **options)` — create recurring tasks at runtime without restarting the scheduler (solid_queue 1.4.0 parity)
- `RecurringTask.delete_dynamic_task(key)` — remove a dynamic recurring task at runtime
- `RecurringTask.dynamic` scope — query tasks created dynamically (`static: false`)
- `RecurringTask` validates that `class_name` resolves to an existing class (`ensure_existing_job_class`)
- `Record.use_index(*indexes)` — translates solid_queue MySQL index hints to MongoDB `.hint()` calls via a per-model `INDEX_HINTS` mapping; no-op for unknown index names

### Changed
- `RecurringTask.from_configuration` now accepts `static:` option (defaults `true`); previously hardcoded
- `BlockedExecution` indexes updated to match solid_queue 1.4.0 schema: `(concurrency_key, priority, job_id)` for release queries and `(expires_at, concurrency_key)` for maintenance
- `BlockedExecution::INDEX_HINTS` maps solid_queue MySQL index names to their MongoDB equivalents so `use_index` hints are applied correctly
- `BlockedExecution.release_one` no longer wraps in an outer `Mongoid.transaction` (MongoDB does not support nested sessions; `#release` already manages its own transaction)
- Minimum `solid_queue` version tightened from `~> 1.0` to `>= 1.4.0, < 2.0`

## [0.1.0] - 2026-02-23

- Initial release
