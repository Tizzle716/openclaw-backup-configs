# Draft: OpenClaw Permission Diagnostic

## Requirements (confirmed)
- Diagnose "Permission denied" errors in OpenClaw environment
- Fix symlink-based permission conflict
- Verify gateway registry accessibility
- Report comprehensive findings

## Discovered Facts
- `~/.openclaw` is a symlink: `lrwxrwxrwx 1 viktor-admin viktor-admin 16 May 20 16:00 /home/viktor-admin/.openclaw -> /root/.openclaw/`
- Target `/root/.openclaw/` is root-owned, inaccessible to `viktor-admin`
- OpenClaw CLI is installed at `/usr/bin/openclaw` and operational
- Gateway shows: "unreachable" - likely due to permission issues
- Systemd user service: not installed
- No channels configured, 0 active sessions

## OpenClaw Docs Findings
- Symlinked `~/.openclaw/` is a known anti-pattern — docs explicitly say: "Verify sessions directory exists and is directly accessible without symlinks"
- EACCES with symlinked config dir is a well-documented issue across multiple GitHub issues
- Fix approach confirmed by docs: ownership correction of the target directory

## Technical Decisions
- Root cause: symlink to `/root/.openclaw/` creates permission boundary violation
- Fix: Either (a) fix ownership of target dir, or (b) break symlink and create proper user-owned dir
- Preferred approach: Fix ownership of target + run `openclaw doctor` for post-fix validation

## Scope Boundaries
- IN: Permission diagnosis, ownership fix, gateway log review, environment validation
- OUT: Docker-based deployments, channel configuration, session recovery
