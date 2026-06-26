# VPS Container Consolidation Plan

## TL;DR

> **Quick Summary**: Consolidate 29 containers across 2 stacks (lockin-labs-office, viktor-admin) to ~22 by collapsing 6 burst workers into an ephemeral cron-based worker pool, removing the broken openclaw-dashboard, and triaging the mailserver CPU issue.
>
> **Deliverables**:
> - Ephemeral worker spawner script + cron schedule replacing 6 static burst worker containers
> - Clean docker-compose.yml with dashboard service removed
> - Mailserver CPU diagnosis and fix (if simple)
> - Backups of critical data volumes before migrations
>
> **Estimated Effort**: Medium (2-3 hours)
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Backup → Worker spawner infra → Migrate workers 1-by-1 → Dashboard removal → Mailserver triage → Final verification

---

## Context

### Original Request
Consolidate Ubuntu LTS VPS Docker setup. Current architecture runs 2 stacks (lockin-labs-office and viktor-admin) totaling 27 services and 29 containers. Goal is to collapse static burst workers into an ephemeral on-demand pool and optimize the routing/data layers.

### Interview Summary
**Key Decisions**:
- **Downtime**: Brief (30-60s) per migration step is acceptable
- **Dashboard**: Remove the restart-looping openclaw-dashboard
- **Mailserver**: Triage 99% CPU, fix if simple
- **Worker trigger**: Cron-based spawning
- **Work detection**: Redis queue check
- **Worker type**: Stateless only — safe to kill mid-job
- **Backups**: Critical data only (postgres, mail, hindsight)
- **Agents**: Keep krieger, viktor-prime, capital-mgr separate (no merge)
- **Sidecars**: Keep paperclip-watcher, watchdog-automation, lifecycle-sidecar separate
- **Redis**: Keep local-redis-mesh and openclaw-redis separate

**Metis Review Findings Addressed**:
- All 10 questions surfaced and answered by user
- 8 guardrails incorporated into plan structure
- Edge cases (graceful shutdown, Caddy reload, volume naming, port collision, network dependency) handled per-task

---

## Work Objectives

### Core Objective
Reduce container count from 29 to ~22 by collapsing 6 burst workers into a cron-based ephemeral pool, removing the broken dashboard, and triaging the mailserver CPU issue — preserving all existing infrastructure properties and service functionality.

### Concrete Deliverables
- `/home/viktor-admin/scripts/spawn-worker.sh` — Ephemeral worker spawner script
- Cron entries for periodic worker check-and-spawn
- Updated `/home/viktor-admin/docker-compose.yml` with burst workers replaced by a single `worker-scheduler` service (no dashboard)
- Mailserver CPU triage report + fix (if simple)
- Volume backups of postgres, mail, hindsight data

### Must Have
- All existing HTTP endpoints return 200 after consolidation
- Redis pub/sub messages still flow between all services via local-redis-mesh
- openclaw-gateway, claw3d-studio, fish-speech, hindsight remain operational
- Cloudflare tunnel routes functional
- No data loss on named volumes
- Cron-scheduled workers can process work and self-terminate

### Must NOT Have (Guardrails)
- No DNS changes during migration
- No changes to Postiz stack (openclaw-db, openclaw-redis, openclaw-temporal, openclaw-postiz)
- No changes to fish-speech or tts-sidecar
- No agent/sidecar/Redis merging
- No .env file permission changes (must remain 600)
- No named volume deletions without explicit backup first
- No `args:` or `cmd:` properties in docker-compose — use `command:` only

---

## Verification Strategy

### Pre-Migration Checks (run before each task)
```bash
# Verify current state
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
# Verify critical endpoints
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
# Verify volume list
docker volume ls -q
```

### Post-Migration Checks (run after each task)
```bash
# Verify no restarting containers
docker ps --filter "status=restarting" | grep -c . || echo "0 restarting"
# Verify target service is up
docker ps --filter "name=TARGET" --filter "status=running" --format "{{.Names}}"
# Verify HTTP endpoint
curl -sf -o /dev/null -w "%{http_code}" ENDPOINT
```

### Rollback Procedure (per task)
```bash
# Restore the previous docker-compose.yml from backup
cp docker-compose.yml.bak docker-compose.yml
docker compose up -d
# Verify rollback
docker ps | grep TARGET
```

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Pre-migration safety — all parallel):
├── Task 1: Backup critical volumes [quick]
├── Task 2: Backup docker-compose files [quick]
├── Task 3: Snapshot current container inventory [quick]
└── Task 4: Audit current Redis queue usage [unspecified-low]

Wave 2 (Infrastructure changes — sequential, one-at-a-time):
├── Task 5: Create worker-spawner script + cron [unspecified-high]
├── Task 6: Migrate burst workers (one by one) → cron pool [unspecified-high]
├── Task 7: Remove openclaw-dashboard [quick]
└── Task 8: Triage mailserver CPU [unspecified-high]

Wave 3 (Verification — all parallel):
├── Task F1: Full service health audit [oracle]
├── Task F2: End-to-end worker test [unspecified-high]
├── Task F3: Redis pub/sub integrity check [unspecified-low]
└── Task F4: Idempotency verification [deep]
```

### Dependency Matrix
- **1-4**: None (can start immediately)
- **5**: 1, 2, 3, 4 → 6
- **6**: 4, 5 → F2
- **7**: 1, 2, 3 (can run parallel with 5-6)
- **8**: 1 (can run parallel with 5-7)
- **F1-F4**: All prior tasks → user okay

---

## TODOs

- [ ] 1. Backup critical named volumes

  **What to do**:
  - Back up these Docker volumes before any changes:
    - `lockin-labs-office_postgres-data` (postgres data for Temporal/Postiz)
    - `lockin-labs-office_temporal-server-data` (Temporal workflow state)
    - `lockin-labs-office_caddy_data` (Caddy TLS certificates)
    - `openclaw-db` volume data (Postiz app database)
    - Mailserver mail-data, mail-state volumes
  - Use `docker run --rm -v VOLUME:/source -v /backup:/backup alpine tar czf /backup/VOLUME-$(date +%Y%m%d).tar.gz -C /source .`
  - Store backups in `/root/consolidation-backups/` (create dir if not exists)

  **Must NOT do**:
  - Do NOT change any container state — read-only backup operations only
  - Do NOT use `docker compose down -v` — that destroys volumes

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: N/A (simple backup commands)

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: Tasks 5, 6, 7, 8
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] Backup files exist: `ls /root/consolidation-backups/*.tar.gz` shows all critical volumes
  - [ ] Backup files are non-empty: `du -sh /root/consolidation-backups/`

  **QA Scenarios**:
  ```
  Scenario: Verify backup completeness
    Tool: Bash
    Preconditions: Backup commands have run
    Steps:
      1. Run: ls /root/consolidation-backups/
      2. For each .tar.gz file: tar tzf FILE | head -5 (verify non-corrupt)
    Expected Result: All critical volumes backed up, archives are valid
    Evidence: .omo/evidence/task-1-backup-list.txt

  Scenario: Rollback verification (backup integrity)
    Tool: Bash
    Steps:
      1. Run: for f in /root/consolidation-backups/*.tar.gz; do tar tzf "$f" > /dev/null && echo "OK: $f" || echo "CORRUPT: $f"; done
    Expected Result: All archives pass integrity check
    Evidence: .omo/evidence/task-1-backup-integrity.txt
  ```

  **Evidence to Capture**:
  - [ ] Backup directory listing
  - [ ] Archive integrity test results

  **Commit**: NO (infrastructure task)

---

- [ ] 2. Backup docker-compose and configuration files

  **What to do**:
  - Copy all active docker-compose.yml files to `/root/consolidation-backups/configs/`:
    - `/home/viktor-admin/docker-compose.yml`
    - `/home/viktor-admin/lockin-labs-office/docker-compose.yml`
    - `/home/viktor-admin/lockin-labs-office/docker-compose-postiz-addon.yml`
  - Copy Caddyfile, cloudflared.yml, .env to backup dir
  - Copy agent-supervisor.sh and any cron scripts
  - Set backup files to 600 permissions

  **Must NOT do**:
  - Do NOT modify originals — only copy

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: N/A (file copy operations)

  **Parallelization**:
  - **Can Run In Parallel**: YES (Wave 1)
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] All config files backed up with timestamps
  - [ ] Can diff backup against originals (should match)

  **QA Scenarios**:
  ```
  Scenario: Verify config backup completeness
    Tool: Bash
    Steps:
      1. diff /home/viktor-admin/docker-compose.yml /root/consolidation-backups/configs/docker-compose.yml
      2. diff /home/viktor-admin/Caddyfile /root/consolidation-backups/configs/Caddyfile
    Expected Result: All diffs return no output (files match)
    Evidence: .omo/evidence/task-2-config-diff.txt
  ```

---

- [ ] 3. Snapshot current container inventory

  **What to do**:
  - Capture full `docker ps` output to `/root/consolidation-backups/pre-migration-inventory.txt`
  - Capture `docker stats --no-stream` to same dir
  - Capture `docker network inspect lockin-labs-office_lockin-labs-net`
  - Capture `docker volume ls`
  - Save as reference for post-migration comparison

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: N/A (inventory capture)

  **Parallelization**: YES (Wave 1)

  **Acceptance Criteria**:
  - [ ] Inventory file contains all 29 running containers
  - [ ] Network inspect shows connected services

---

- [ ] 4. Audit current Redis queue usage

  **What to do**:
  - Connect to local-redis-mesh: `docker exec local-redis-mesh redis-cli KEYS '*'`
  - Identify queue/list keys used by burst workers
  - Document the key patterns (e.g., `worker:queue:*`, `task:pending:*`)
  - Check for any TTL-based or blocking operations
  - Save output to `/root/consolidation-backups/redis-keys-before.txt`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: N/A (Redis inspection)

  **Parallelization**: YES (Wave 1)

  **Acceptance Criteria**:
  - [ ] Redis key listing captured
  - [ ] Queue patterns documented for worker-spawner script

---

- [ ] 5. Create worker-spawner script and cron schedule

  **What to do**:
  - Create `/home/viktor-admin/scripts/spawn-worker.sh`:
    - Takes env vars: WORKER_TYPE (sales, ops, QA, lead, content, technical-production), REDIS_KEY_PATTERN
    - Checks Redis queue length: `docker exec local-redis-mesh redis-cli LLEN lockin:queue:{WORKER_TYPE}`
    - Uses Redis key pattern discovered in Task 4 (not hardcoded — read from `redis-keys-before.txt` or accept as env var `REDIS_QUEUE_PATTERN`)
    - If queue length > 0, spawns a worker container:
      ```
      docker run -d --rm \
        --name="worker-{WORKER_TYPE}-$(date +%s)" \
        --network=lockin-labs-office_lockin-labs-net \
        --env-file /home/viktor-admin/.env \
        -e AGENT_NAME={WORKER_TYPE}-manager \
        -e REDIS_URL=redis://local-redis-mesh:6379 \
        openclaw/burst-worker:latest \
        sh -c "python agent_edge_client.py --once"
      ```
    - Worker auto-terminates after processing one job (add `--once` flag logic)
    - Logs to `/var/log/worker-spawner/{WORKER_TYPE}.log`
  - Add cron entries (runs every 2 minutes):
    ```
    * * * * * root /home/viktor-admin/scripts/spawn-worker.sh sales && /home/viktor-admin/scripts/spawn-worker.sh ops && /home/viktor-admin/scripts/spawn-worker.sh lead && /home/viktor-admin/scripts/spawn-worker.sh content && /home/viktor-admin/scripts/spawn-worker.sh technical && /home/viktor-admin/scripts/spawn-worker.sh qa
    ```
    (Spread across 10-second staggered intervals to avoid thundering herd)
  - Make script executable: `chmod +x /home/viktor-admin/scripts/spawn-worker.sh`

  **Must NOT do**:
  - Do NOT remove the original burst worker images (still needed for ephemeral runs)
  - Do NOT change the base Dockerfile structure — only add `--once` support if absent

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: N/A (Bash scripting + Docker + cron)

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential — must complete before worker migration)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 6
  - **Blocked By**: Tasks 1, 2, 3, 4

  **Acceptance Criteria**:
  - [ ] Script exists and is executable: `ls -la /home/viktor-admin/scripts/spawn-worker.sh` (permissions: -rwxr-xr-x)
  - [ ] Script runs without error: `bash -n /home/viktor-admin/scripts/spawn-worker.sh` (syntax check passes)
  - [ ] Cron entries installed: `crontab -l | grep spawn-worker`
  - [ ] Script can connect to Redis: `docker exec local-redis-mesh redis-cli PING` returns PONG

  **QA Scenarios**:
  ```
  Scenario: Script syntax and dry-run
    Tool: Bash
    Preconditions: Script exists
    Steps:
      1. bash -n /home/viktor-admin/scripts/spawn-worker.sh
      2. REDIS_URL=redis://local-redis-mesh:6379 WORKER_TYPE=sales /home/viktor-admin/scripts/spawn-worker.sh --dry-run
    Expected Result: Syntax check passes, dry-run shows what would happen without spawning
    Evidence: .omo/evidence/task-5-script-valid.txt

  Scenario: Cron entry verification
    Tool: Bash
    Steps:
      1. crontab -l | grep spawn-worker
      2. grep -c spawn-worker /etc/crontab || cat /etc/cron.d/worker-spawn 2>/dev/null
    Expected Result: Cron entries reference spawn-worker.sh with stagger timing
    Evidence: .omo/evidence/task-5-cron.txt
  ```

---

- [ ] 6. Migrate burst workers to ephemeral pool

  **What to do**:
  - For each burst worker (sales, ops, QA, lead, content, technical-production):
    1. Check existing `agent_edge_client.py` for any `--once` / single-job support. If absent, add a `--once` flag that processes one queue item then exits. If present, verify it works correctly.
    2. Stop one burst worker at a time: `docker stop {container-name}`
    3. Verify it does not auto-restart (restart: unless-stopped is set, so `docker stop` alone won't suffice — use `docker compose rm -fs` for the specific service)
    4. Push a test message to the appropriate Redis queue
    5. Run spawn-worker.sh manually for that worker type
    6. Verify the ephemeral container starts, processes, and self-terminates
    7. Repeat for all 6 worker types
  - After all 6 are migrated, remove their service definitions from `/home/viktor-admin/docker-compose.yml`
  - Add `worker-scheduler` service (no-op container that holds the cron image, or just rely on host cron)

  **Must NOT do**:
  - Do NOT migrate more than 1 worker at a time
  - Do NOT use `docker compose down -v` — only `docker compose rm -fs SERVICE`
  - Do NOT delete the openclaw/burst-worker:latest image — still needed for ephemeral runs

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: N/A (Docker operations + verification)

  **Parallelization**:
  - **Can Run In Parallel**: NO (one worker at a time — sequential by design)
  - **Parallel Group**: Wave 2
  - **Blocks**: F2 worker end-to-end test
  - **Blocked By**: Tasks 1, 2, 3, 4, 5

  **References**:
  - Current burst worker definitions in `/home/viktor-admin/docker-compose.yml:31-97`
  - Worker Dockerfile: `/home/viktor-admin/Dockerfile`
  - Agent edge client: `/home/viktor-admin/agent_edge_client.py`

  **Acceptance Criteria**:
  - [ ] `docker ps | grep -c manager` = 0 (no persistent manager containers)
  - [ ] Ephemeral workers can be spawned and self-terminate
  - [ ] docker-compose.yml no longer defines any `*-manager` service
  - [ ] `docker compose -f /home/viktor-admin/docker-compose.yml config` succeeds (valid syntax)

  **QA Scenarios**:
  ```
  Scenario: Migrate sales-closing-manager
    Tool: Bash
    Preconditions: Task 5 complete, sales worker still running
    Steps:
      1. docker compose -f /home/viktor-admin/docker-compose.yml rm -fs sales-closing-manager
      2. docker ps | grep sales-closing-manager → empty
      3. docker exec local-redis-mesh redis-cli LPUSH test:queue:sales '{"test": true}'
      4. WORKER_TYPE=sales REDIS_KEY_PATTERN=test:queue:sales /home/viktor-admin/scripts/spawn-worker.sh
      5. sleep 30
      6. docker ps -a | grep worker-sales → Exited (0)
    Expected Result: Old container stopped, new ephemeral container ran and exited 0
    Evidence: .omo/evidence/task-6-migrate-sales.txt

  Scenario: Verify all 6 workers migrated
    Tool: Bash
    Steps:
      1. docker ps | grep -cE 'sales|ops|qa|lead|content|technical' | grep -c manager
    Expected Result: 0 persistent manager containers running
    Evidence: .omo/evidence/task-6-all-migrated.txt
  ```

---

- [ ] 7. Remove openclaw-dashboard service

  **What to do**:
  - Remove the openclaw-dashboard service definition from `/home/viktor-admin/lockin-labs-office/docker-compose.yml` (lines 93-128)
  - Remove any references in cloudflared.yml (line 29-31 referencing dashboard)
  - Stop and remove the container: `docker compose -f /home/viktor-admin/lockin-labs-office/docker-compose.yml rm -fs openclaw-dashboard`
  - Verify no other service depends on it (check `depends_on` in compose files)

  **Must NOT do**:
  - Do NOT change any other service definition
  - Do NOT remove volumes used by other services

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: N/A (simple YAML editing + docker compose)

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6, 8 — independent)
  - **Parallel Group**: Wave 2
  - **Blocks**: F1
  - **Blocked By**: Tasks 1, 2, 3

  **References**:
  - Service definition: `/home/viktor-admin/lockin-labs-office/docker-compose.yml:93-128`
  - Cloudflared route: `/home/viktor-admin/lockin-labs-office/cloudflared.yml:29-31`

  **Acceptance Criteria**:
  - [ ] `docker ps -a | grep openclaw-dashboard` → empty
  - [ ] `grep -c dashboard /home/viktor-admin/lockin-labs-office/docker-compose.yml` → 0
  - [ ] `docker compose -f /home/viktor-admin/lockin-labs-office/docker-compose.yml config` succeeds
  - [ ] Cloudflare tunnel still routes other services correctly

  **QA Scenarios**:
  ```
  Scenario: Dashboard removed, config valid
    Tool: Bash
    Steps:
      1. docker compose -f /home/viktor-admin/lockin-labs-office/docker-compose.yml config
      2. curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
    Expected Result: Compose config succeeds, gateway still responds 200
    Evidence: .omo/evidence/task-7-dashboard-removed.txt

  Scenario: No dependent services broken
    Tool: Bash
    Steps:
      1. docker ps --filter "status=running" --format "{{.Names}}" | sort
    Expected Result: All other services still running (openclaw-gateway, claw3d-studio, etc.)
    Evidence: .omo/evidence/task-7-services-intact.txt
  ```

---

- [ ] 8. Triage mailserver CPU issue

  **What to do**:
  - Diagnose the 99% CPU issue on mailserver container:
    1. Check recent logs: `docker logs --tail 100 mailserver`
    2. Identify the process using CPU: `docker top mailserver` or `docker exec mailserver ps aux --sort=-%cpu | head -10`
    3. Check for common issues:
       - Spam run (excessive inbound traffic on port 25)
       - Misconfigured SPF/DKIM causing repeated delivery attempts
       - Fetchmail polling too frequently (FETCHMAIL_POLL=300 — very aggressive!)
       - Rspamd/Amavis CPU spike
  - Fix if simple (one of the above):
    - If fetchmail: increase FETCHMAIL_POLL to 1800 (30 min) in compose env vars
    - If rspamd: check logs for pattern, consider disabling if not needed
    - If spam run: add rate limiting or block offending IPs via iptables
  - If not simple (code fix, config rewrite): document findings, defer to separate plan

  **Must NOT do**:
  - Do NOT change SSL/TLS config or mail account data
  - Do NOT restart mailserver without verifying config change is safe
  - Do NOT spend more than 30 minutes on diagnosis

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: N/A (Docker diagnostics + mailserver knowledge)

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6, 7)
  - **Parallel Group**: Wave 2
  - **Blocks**: F1
  - **Blocked By**: Task 1

  **Acceptance Criteria**:
  - [ ] CPU usage below 50% after fix (or documented if unfixable)
  - [ ] Mailserver continues to send/receive email
  - [ ] No other mailserver configs changed

  **QA Scenarios**:
  ```
  Scenario: CPU diagnosis
    Tool: Bash
    Steps:
      1. docker stats mailserver --no-stream --format '{{.CPUPerc}}'
      2. docker logs --tail 50 mailserver | grep -iE 'error|warn|spam|fail'
    Expected Result: CPU % captured, any error patterns identified
    Evidence: .omo/evidence/task-8-mailserver-cpu.txt

  Scenario: Post-fix verification (if fix applied)
    Tool: Bash
    Steps:
      1. sleep 60  # Wait for container to stabilize
      2. docker stats mailserver --no-stream --format '{{.CPUPerc}}'
      3. nc -z localhost 25 && echo "SMTP OK"
    Expected Result: CPU < 50%, SMTP port responds
    Evidence: .omo/evidence/task-8-mailserver-fixed.txt
  ```

---

## Final Verification Wave

- [ ] F1. **Full Service Health Audit** — `oracle`
  After all changes, verify: all previously running services are still up, all HTTP endpoints respond 200, no containers in restart loop, no volumes lost. Compare against pre-migration inventory.
  Output: `Services [N/N running] | Endpoints [N/N 200] | Volumes [N/N intact] | VERDICT`

- [ ] F2. **End-to-End Worker Test** — `unspecified-high`
  Trigger the cron worker spawner manually. Verify: (1) a worker container starts, (2) it connects to Redis and checks the queue, (3) it processes a test task, (4) it self-terminates. Capture logs and container lifecycle.
  Output: `Spawn [PASS/FAIL] | Queue check [PASS/FAIL] | Process [PASS/FAIL] | Cleanup [PASS/FAIL] | VERDICT`

- [ ] F3. **Redis Pub/Sub Integrity** — `unspecified-low`
  Publish a test message on local-redis-mesh and verify subscribers (paperclip-watcher, watchdog-automation, lifecycle-sidecar) receive it.
  Output: `Publish [OK] | Subscribe N services [N/N received] | VERDICT`

- [ ] F4. **Idempotency Verification** — `deep`
  Run the consolidation steps a second time (dry-run or re-apply). Verify no errors, no duplicate containers, no configuration drift. Confirm docker-compose.yml can be re-applied safely.
  Output: `Re-apply [PASS/FAIL] | No drift [PASS/FAIL] | VERDICT`

---

## Commit Strategy

- This is infrastructure — no code commits. Changes tracked via:
  - `diff` against config backups
  - Updated docker-compose.yml files
  - New scripts committed via git if repo initialized

---

## Success Criteria

### Verification Commands
```bash
# All critical services running
docker ps --format '{{.Names}}' | grep -E 'openclaw-gateway|claw3d-studio|fish-speech|hindsight|open-bao|openclaw-postiz|cf-tunnel|local-redis-mesh|woodhouse-bot' | wc -l
# Expected: 9

# No restarting containers
docker ps --filter "status=restarting" --format "{{.Names}}" | wc -l
# Expected: 0

# Burst workers count (should be 0 persistent, 1 scheduler)
docker ps --format '{{.Names}}' | grep -cP 'manager|scheduler'
# Expected: 1 (worker-scheduler)

# Critical endpoints
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
# Expected: 200
```

### Final Checklist
- [ ] All "Must Have" endpoints return 200
- [ ] All "Must NOT Have" items verified absent
- [ ] No containers in restart loop
- [ ] Redis pub/sub functional
- [ ] Worker can spawn, process, and self-terminate
- [ ] All critical volumes intact
- [ ] Caddy routes function correctly
- [ ] Cloudflare tunnel routes functional
