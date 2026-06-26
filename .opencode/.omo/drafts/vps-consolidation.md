# Draft: VPS Consolidation Plan

## Core Objective
Consolidate 29 containers across 2 stacks (lockin-labs-office, viktor-admin) to ~22 by collapsing 6 burst workers into an ephemeral cron-based worker pool, removing the broken openclaw-dashboard, and triaging the mailserver CPU issue.

### Consolidation Targets
1. **6 burst workers → ephemeral cron pool**: Replace sales, ops, QA, lead, content, technical-production managers with cron-triggered containers that check Redis queues, process work, and self-terminate
2. **Remove openclaw-dashboard**: Container is in restart loop; remove service definition
3. **Triage mailserver CPU**: ~99% CPU + 1GB RAM usage - diagnose and fix if simple
4. **Everything else stays unchanged**: agents, sidecars, Redis instances all keep separate

## User Decisions
- Downtime tolerance: Brief downtime OK
- Dashboard: Remove it
- Mailserver: Triage & fix if simple
- Worker trigger: Cron schedule
- Volume backup: Critical data only (postgres, mail, hindsight)
- Work detection: Redis queue check
- Worker statefulness: Stateless only (safe to kill mid-job)
- Agent merge: Keep separate (krieger, viktor-prime, capital-mgr)
- Sidecar merge: Keep separate (paperclip, watchdog, lifecycle)
- Redis merge: Keep separate (local-redis-mesh, openclaw-redis)

## Scope
- IN: Burst worker collapse, dashboard removal, mailserver triage
- OUT: Mailserver reconfig, Postiz stack, fish-speech, agent/sidecar merging, Redis merging

## Guardrails (from Metis)
1. No data loss - backup volumes before container removal
2. Each consolidation step independently reversible
3. No DNS changes during migration
4. Test each change in isolation
5. Preserve all .env vars and file permissions (600)

## Metis Edge Cases to Address in Plan
- Graceful shutdown of burst workers (SIGTERM handling)
- Caddy hot-reload vs restart
- Volume naming during container replacement
- Port collision avoidance during migration
- Docker network dependency (shared lockin-labs-net)
