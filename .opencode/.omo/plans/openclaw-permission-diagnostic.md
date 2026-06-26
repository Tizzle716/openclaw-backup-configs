# OpenClaw Permission Diagnostic & Repair

## TL;DR

> **Quick Summary**: Diagnose and resolve "Permission denied" errors in the OpenClaw environment caused by a symlink conflict where `~/.openclaw` points to the root-owned `/root/.openclaw/` directory, blocking read/write access for the `viktor-admin` user.
>
> **Deliverables**:
> - Root cause identification
> - Permission ownership repair
> - Gateway log analysis
> - Post-repair validation
>
> **Estimated Effort**: Quick (5-10 min)
> **Parallel Execution**: NO - sequential diagnostic steps
> **Critical Path**: Diagnosis → Ownership fix → Validation → Report

---

## Context

### Original Request
The user reported persistent "Permission denied" errors in their OpenClaw environment and requested a comprehensive diagnostic audit.

### Metis Gap Analysis
**Metis identified 3 critical gaps requiring user decision:**
1. **Symlink origin**: `~/.openclaw -> /root/.openclaw/` — was this intentional? Three possibilities:
   - Installer bug (npm global install ran as root, creating symlink)
   - Intentional multi-user setup
   - Manual setup mistake
   → This changes whether we keep the symlink or replace it with a proper directory.

2. **Data preservation**: Is there existing config/channel/agent data in `/root/.openclaw/` that must be preserved before any changes?

3. **Gateway service**: systemd user service is not installed. Should it be installed as part of this task, or is manual startup acceptable?

**Metis also flagged 6 assumptions to validate** (added as task prerequisites):
- Immutable bit existence (verify with `lsattr` before `chattr`)
- SELinux/AppArmor status check
- Symlink target actually exists
- No nested symlinks inside target
- npm global install ownership
- Port 18789 availability

### Pre-Diagnosis Findings
**Root cause already identified during research phase:**
- `~/.openclaw` resolves as: `lrwxrwxrwx 1 viktor-admin viktor-admin 16 May 20 16:00 /home/viktor-admin/.openclaw -> /root/.openclaw/`
- The symlink target `/root/.openclaw/` is root-owned and **inaccessible** to the running user (`viktor-admin`)
- OpenClaw CLI is installed (`/usr/bin/openclaw`) and reports: Gateway = unreachable

### OpenClaw Docs Guidance
- The OpenClaw troubleshooting docs explicitly warn against symlinked config directories: *"Verify your sessions directory exists and is directly accessible without symlinks"*
- Multiple GitHub issues (#5434, #74971, #87947) document EACCES permission errors with similar symlink patterns
- The recommended fix is ownership correction of the target directory

---

## Work Objectives

### Core Objective
Resolve OpenClaw permission errors by fixing the symlink/ownership conflict and verifying gateway accessibility.

### Concrete Deliverables
- Ownership of `/root/.openclaw/` corrected to `viktor-admin:viktor-admin`
- Immutable attribute (`-i`) removed from `/root/.openclaw/` if present
- Gateway log reviewed for error signatures
- Write-permissions confirmed via marker file
- Post-repair `openclaw status` and `openclaw doctor` validation

### Definition of Done
- [ ] `touch ~/.openclaw/diagnostics.tmp && rm ~/.openclaw/diagnostics.tmp` succeeds (no Permission denied)
- [ ] `openclaw status` shows Gateway reachability changed or error resolved
- [ ] `ls -la ~/.openclaw/` lists directory contents without errors

### Must Have
- `sudo` access available for `chown` and `chattr` commands
- All actions reversible (no destructive changes beyond ownership fixes)
- Backup plan: if `chown` fails, recommend breaking symlink and creating fresh config directory

### Must NOT Have (Guardrails)
- Do NOT delete `/root/.openclaw/` contents — only fix ownership (unless user explicitly requests symlink replacement with backup)
- Do NOT run `sudo` on the symlink itself — target the real directory at `/root/.openclaw/`
- Do NOT modify OpenClaw configuration files — only file attributes and ownership
- Do NOT restart gateway service without first verifying log state
- Do NOT change ownership of anything outside `~/.openclaw` and `/root/.openclaw/`
- Do NOT install systemd services unless user explicitly requests it
- Do NOT modify npm global packages or their ownership
- Do NOT run openclaw as root to "work around" permission issues
- Do NOT configure channels, agents, or upgrade openclaw — out of scope for this task

### Critical Prerequisites (from Metis analysis)
> These MUST be validated BEFORE any ownership changes are made.

1. **Backup existing data**: `sudo cp -a /root/.openclaw/ /root/.openclaw.bak.$(date +%s)`
2. **Verify symlink target exists**: `test -d /root/.openclaw/` (if broken, fix differs)
3. **Check immutable bit**: `sudo lsattr -d /root/.openclaw/` (confirm `-i` is set before attempting removal)
4. **Check SELinux/AppArmor**: `getenforce` and `sudo aa-status` (MAC policies may block even after chown)
5. **Check port availability**: `ss -tlnp | grep 18789` (ensure port is free if gateway starts)
6. **Check npm global ownership**: `ls -la $(which openclaw)` and `ls -la $(dirname $(which openclaw))/../lib/node_modules/openclaw/ | head -5`

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed.

### Test Decision
- **Infrastructure exists**: N/A (diagnostic task, not a feature)
- **Automated tests**: N/A
- **Agent-Executed QA**: Each step produces observable output captured as evidence

### QA Policy
Every step executes a command and captures the output for analysis. Evidence saved to `.omo/evidence/`.

---

## Execution Strategy

### Sequential Steps (diagnostic flow, cannot parallelize)

```
Step 1 (Pre-diagnosis): Inspect symlink and directory attributes
Step 2 (Ownership fix): chown + chattr on target directory
Step 3 (Log review): Check gateway.log for error history
Step 4 (Write test): Touch marker file to confirm fix
Step 5 (Validation): Run openclaw status + doctor
Step 6 (Report): Compile comprehensive findings
```

### Dependency Chain
- 1 → 2 → 3 → 4 → 5 → 6 (fully sequential, each step depends on previous)

---

## TODOs

- [ ] 1. **Pre-Diagnosis: Inspect symlink and directory attributes**

  **What to do**:
  - Run: `ls -ld ~/.openclaw` to confirm symlink target
  - Run: `lsattr /root/.openclaw/` to check for immutable bit (`-i`)
  - Run: `ls -la /root/.openclaw/` to list directory contents
  - Run: `stat /root/.openclaw/` to get ownership/permissions details
  - Record the exact symlink chain and current ownership

  **Must NOT do**:
  - Do not modify anything in this step — pure observation

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — diagnostic commands, observation only
  - **Skills**: None needed (bash execution only)

  **Parallelization**:
  - **Can Run In Parallel**: NO (blocking first step)
  - **Blocks**: All subsequent steps
  - **Blocked By**: None

  **Evidence to Capture**:
  - [ ] Evidence: `.omo/evidence/task-1-symlink-status.txt`

  **Commit**: NO

- [ ] 2. **Ownership Fix: Correct permissions on target directory**

  **What to do**:
  - Run: `sudo chown -R viktor-admin:viktor-admin /root/.openclaw/`
    - This fixes ownership of ALL files under the target directory
  - Run: `sudo chattr -i -R /root/.openclaw/`
    - This removes any immutable attribute locking the files
  - Verify: `ls -la /root/.openclaw/` now shows `viktor-admin` as owner
  - Verify: `stat /root/.openclaw/` confirms ownership change

  **Must NOT do**:
  - Do NOT run `chown` on the symlink (`~/.openclaw`) — it would only change the symlink owner, not the target
  - Do NOT delete or move the symlink yet — only fix permissions
  - Do NOT use `chmod 777` — use proper ownership, not open permissions

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — sudo commands, needs careful execution
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Steps 3, 4, 5
  - **Blocked By**: Step 1

  **QA Scenarios**:
  ```
  Scenario: Ownership correction succeeds
    Tool: Bash
    Steps:
      1. Run sudo chown -R viktor-admin:viktor-admin /root/.openclaw/
      2. Run stat -c "%U:%G" /root/.openclaw/
    Expected Result: Output contains "viktor-admin:viktor-admin"
    Evidence: .omo/evidence/task-2-ownership-status.txt

  Scenario: Immutable attribute removal
    Tool: Bash
    Steps:
      1. Run sudo chattr -i -R /root/.openclaw/
      2. Run lsattr /root/.openclaw/ | head -5
    Expected Result: No 'i' flag appears in lsattr output (or at least fewer)
    Evidence: .omo/evidence/task-2-attributes.txt
  ```

  **Evidence to Capture**:
  - [ ] `.omo/evidence/task-2-ownership-status.txt`
  - [ ] `.omo/evidence/task-2-attributes.txt`

  **Commit**: NO

- [ ] 3. **Log Reconciliation: Review gateway error history**

  **What to do**:
  - Run: `tail -n 50 /root/.openclaw/gateway.log` (now accessible after chown)
  - Alternatively: check `/tmp/openclaw/` for gateway logs:
    - `ls -la /tmp/openclaw/` and `cat "$(ls -t /tmp/openclaw/openclaw-*.log | head -1)"`
  - Search for: "EACCES", "Permission denied", "symlink-escape", "unreachable", "error"
  - Identify the specific process holding locks or causing errors

  **Must NOT do**:
  - Do not delete or rotate log files — only read them

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — log analysis
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Step 4
  - **Blocked By**: Step 2

  **QA Scenarios**:
  ```
  Scenario: Gateway log is now accessible
    Tool: Bash
    Steps:
      1. head -n 30 /root/.openclaw/gateway.log
    Expected Result: Log content returned (no "Permission denied" error)
    Evidence: .omo/evidence/task-3-gateway-log.txt

  Scenario: /tmp/openclaw/ log check
    Tool: Bash
    Steps:
      1. ls -la /tmp/openclaw/ 2>&1
      2. If files exist: tail -n 50 "$(ls -t /tmp/openclaw/openclaw-*.log | head -1)"
    Expected Result: Log files found and readable
    Evidence: .omo/evidence/task-3-tmp-gateway-log.txt
  ```

  **Evidence to Capture**:
  - [ ] `.omo/evidence/task-3-gateway-log.txt`
  - [ ] `.omo/evidence/task-3-tmp-gateway-log.txt`

  **Commit**: NO

- [ ] 4. **Environment Check: Verify read/write permissions**

  **What to do**:
  - Run: `touch ~/.openclaw/diagnostics.tmp` — test write permission
  - Run: `rm ~/.openclaw/diagnostics.tmp` — test cleanup
  - Run: `ls -la ~/.openclaw/` — verify full directory listing
  - Run: `ls -la ~/.openclaw/sessions/ 2>&1` — verify sessions directory if it exists

  **Must NOT do**:
  - Do not modify any config files — pure write-permission validation

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — permission validation
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Step 5
  - **Blocked By**: Steps 2, 3

  **QA Scenarios**:
  ```
  Scenario: Write permission verified
    Tool: Bash
    Steps:
      1. touch ~/.openclaw/diagnostics.tmp
      2. ls -la ~/.openclaw/diagnostics.tmp
      3. rm ~/.openclaw/diagnostics.tmp
    Expected Result: File created and removed without "Permission denied" errors
    Evidence: .omo/evidence/task-4-write-test.txt

  Scenario: Directory listing accessible
    Tool: Bash
    Steps:
      1. ls -la ~/.openclaw/
    Expected Result: Full directory listing with files and subdirectories shown
    Evidence: .omo/evidence/task-4-directory-listing.txt
  ```

  **Evidence to Capture**:
  - [ ] `.omo/evidence/task-4-write-test.txt`
  - [ ] `.omo/evidence/task-4-directory-listing.txt`

  **Commit**: NO

- [ ] 5. **Post-Repair Validation: Run OpenClaw diagnostics**

  **What to do**:
  - Run: `openclaw status` — compare with pre-fix state
  - Run: `openclaw doctor` — run full diagnostic
  - Run: `openclaw gateway probe` — check gateway reachability
  - Check: if gateway log mentions specific errors

  **Must NOT do**:
  - Do not restart/install gateway service unless doctor recommends it
  - Do not modify any config

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — OpenClaw tool validation
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES (openclaw commands are independent)
  - **Parallel Group**: Wave 2 (within this task only)
  - **Blocks**: Step 6
  - **Blocked By**: Steps 2, 4

  **QA Scenarios**:
  ```
  Scenario: openclaw status reports correct state
    Tool: Bash
    Steps:
      1. openclaw status
      2. Check for "Permission denied", "EACCES" in output
    Expected Result: No permission-related errors in status output
    Evidence: .omo/evidence/task-5-openclaw-status.txt

  Scenario: openclaw doctor completes
    Tool: Bash
    Steps:
      1. openclaw doctor
    Expected Result: Doctor runs without crashing; actionable output
    Evidence: .omo/evidence/task-5-openclaw-doctor.txt

  Scenario: Gateway probe
    Tool: Bash
    Steps:
      1. openclaw gateway probe
    Expected Result: Gateway probe output returned
    Evidence: .omo/evidence/task-5-gateway-probe.txt
  ```

  **Evidence to Capture**:
  - [ ] `.omo/evidence/task-5-openclaw-status.txt`
  - [ ] `.omo/evidence/task-5-openclaw-doctor.txt`
  - [ ] `.omo/evidence/task-5-gateway-probe.txt`

  **Commit**: NO

- [ ] 6. **Final Report: Compile comprehensive findings**

  **What to do**:
  - Synthesize all evidence from steps 1-5 into a structured report
  - Include:
    - Root cause summary
    - What was fixed
    - Current state of the gateway
    - Any remaining issues
    - Recommended next steps (if any)
  - Save report to `.omo/evidence/final-report.md`

  **Must NOT do**:
  - Do not fabricate or assume results — base strictly on evidence files

  **Recommended Agent Profile**:
  - **Category**: `writing` — report compilation
  - **Skills**: None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on all evidence)
  - **Blocks**: None (final step)
  - **Blocked By**: Steps 1-5

  **Evidence to Capture**:
  - [ ] `.omo/evidence/final-report.md`

  **Commit**: NO

---

## Commit Strategy

No commits — this is a diagnostic/repair task, not a code change.

---

## Success Criteria

### Verification
```bash
# Primary check: write permissions restored
touch ~/.openclaw/diagnostics.tmp && rm ~/.openclaw/diagnostics.tmp

# Secondary check: directory accessible
ls -la ~/.openclaw/

# Tertiary check: OpenClaw status clean
openclaw status | grep -i -E "error|denied|eacces"
```

### Final Checklist
- [ ] Ownership of `/root/.openclaw/` corrected to `viktor-admin:viktor-admin`
- [ ] Immutable attributes removed (or confirmed not set)
- [ ] Gateway logs readable and analyzed
- [ ] Write permissions working: `touch ~/.openclaw/.write_test && rm ~/.openclaw/.write_test` → exit code 0
- [ ] OpenClaw CLI can read config: `openclaw config list` → no EACCES
- [ ] OpenClaw CLI can write config: `openclaw config set test.permission_fix verified && openclaw config unset test.permission_fix` → no EACCES
- [ ] Symlink state correct per user decision (preserved or replaced)
- [ ] Gateway probe accessible: `openclaw gateway probe` → succeeds
- [ ] Backup created: `/root/.openclaw.bak.*` exists
- [ ] `openclaw status` no longer reports permission-related errors
- [ ] Comprehensive report saved
