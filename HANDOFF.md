# HANDOFF: SolidQueueMongoid Compatibility Recovery Plan

## Objective

Make `solid_queue_mongoid` a true drop-in persistence replacement for SolidQueue using Mongoid (no ActiveRecord storage models), with compatibility targeting latest SolidQueue behavior (current lockfile shows `1.3.2`).

---

## Current State Snapshot

- Lockfile currently resolves `solid_queue (1.3.2)`.
- Adapter models exist under `lib/solid_queue_mongoid/models/`.
- Runtime compatibility with SolidQueue worker/dispatcher/scheduler is incomplete.
- Existing tests are model-focused; runtime/process compatibility coverage is missing.

---

## Critical Gaps To Fix First (P0)

1. **Missing runtime API methods used by SolidQueue processes**
   - Missing/renamed symbols break worker/dispatcher/scheduler paths.
   - Required methods include:
     - `SolidQueue::ReadyExecution.claim`
     - `SolidQueue::ReadyExecution.aggregated_count_across`
     - `SolidQueue::ScheduledExecution.dispatch_next_batch`
     - `SolidQueue::RecurringTask.wrap`
     - `SolidQueue::RecurringTask.create_or_update_all`
     - `SolidQueue::RecurringExecution.record`

2. **Process registration signature mismatch**
   - `SolidQueue::Process.register` in adapter accepts too few keywords.
   - Runtime expects `kind:, name:, pid:, hostname:, supervisor:, metadata:`.

3. **Shim/autoload conflict risk**
   - Need deterministic boot strategy so ActiveRecord SolidQueue storage models do not override Mongoid model replacements.

4. **Private method visibility bug**
   - `Job#create_ready_execution!` is private but called with explicit receiver from other models.

---

## Missing Files / Modules (P0)

Create and wire these files:

- `lib/solid_queue_mongoid/models/queue_selector.rb`
- `lib/solid_queue_mongoid/models/process/executor.rb`
- `lib/solid_queue_mongoid/models/process/prunable.rb`
- `lib/solid_queue_mongoid/models/recurring_task/arguments.rb`

Also update `lib/solid_queue_mongoid.rb` requires to include these paths.

---

## Required Symbol Matrix (P0 -> P1)

### ReadyExecution
- Add `self.claim(queue_list, limit, process_id)`
- Add `self.aggregated_count_across(queue_list)`
- Preserve wildcard queue support via Mongo query strategy.

### ScheduledExecution
- Add `self.dispatch_next_batch(batch_size)` (or alias with equivalent behavior).

### ClaimedExecution
- Add instance `perform` (required by pool thread executor).
- Add class methods:
  - `self.claiming(job_ids, process_id)`
  - `self.release_all`
  - `self.fail_all_with(error)`
- Add `orphaned` scope equivalent.

### Process
- Expand `self.register` keyword signature to runtime contract.
- Add `self.prune(excluding: nil)` behavior for maintenance flow.
- Align deregistration to release/fail claimed executions as needed.

### RecurringTask / RecurringExecution
- Add:
  - `RecurringTask.wrap`
  - `RecurringTask.create_or_update_all`
  - static task handling (`static` scope/field)
  - `RecurringExecution.record(task_key, run_at)`
- Add argument serializer helper behavior via `recurring_task/arguments.rb`.

---

## Wildcard Queue Design (Requested Direction)

Implement wildcard resolution with Mongo semantics:

- `"*"` => all distinct queue names from executable relation.
- `prefix*` => anchored regex prefix query.
- Exact names remain exact matches.
- Exclude paused queues before claim.
- Preserve raw queue-list ordering where practical.

Indexing expectations:

- `queue_name`
- `priority`
- `created_at`
- compound index for claim ordering path if needed by profiler.

---

## Shim / Boot Plan (P0)

1. Ensure adapter model classes load before SolidQueue runtime paths use storage models.
2. Prevent AR model class redefinition/superclass mismatch (`SolidQueue::Record`).
3. Keep compatibility with Rails loading/eager loading via `Railtie` initializer.

Implementation note: do not rely on best-effort require order alone; add explicit initializer/load guard.

---

## Test Plan

### P0 tests (must pass before moving on)

Add integration specs for:

- Worker claiming loop (`ReadyExecution.claim`, `aggregated_count_across`)
- Dispatcher scheduling loop (`ScheduledExecution.dispatch_next_batch`)
- Scheduler recurring loop (`RecurringTask.wrap/create_or_update_all`, `RecurringExecution.record`)
- Process maintenance (`Process.prune`) and registration signature compatibility

### Contract tests

Add API contract spec that asserts required methods/symbols exist for targeted SolidQueue version.

---

## Suggested Execution Sequence

1. Add missing files + require wiring.
2. Implement missing runtime symbols with parity-first behavior.
3. Fix process register/prune compatibility.
4. Fix private method visibility and claim ordering mismatch.
5. Implement/verify wildcard queue selector behavior.
6. Implement shim initializer safeguards.
7. Add integration and contract specs.
8. Run full test suite and iterate.

---

## Acceptance Criteria

- SolidQueue worker boots and claims jobs using Mongoid models only.
- Dispatcher dispatches due scheduled jobs through adapter API.
- Scheduler persists and enqueues recurring tasks/executions without missing method errors.
- No superclass mismatch from AR vs Mongoid storage models.
- All contract + integration specs pass.
- Wildcard queues function via Mongo queries and paused queues are respected.

---

## Risks / Watchouts

- Upstream SolidQueue API drift between minor versions.
- Behavioral differences around priority ordering and lock semantics.
- Mongo transactional semantics differ from SQL; keep operations atomic at document level where possible.

Mitigation:

- Maintain a parity checklist per SolidQueue release.
- Keep contract tests version-gated and required in CI.

