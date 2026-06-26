#!/usr/bin/env node
/**
 * openclaw-github-sync-wrapper.js
 * Node.js wrapper for OpenClaw post-execution hook integration.
 *
 * Usage:
 *   node openclaw-github-sync-wrapper.js [--dry-run]
 *
 * Environment:
 *   GITHUB_TOKEN            - GitHub Personal Access Token
 *   GIT_REMOTE_URL          - e.g. git@github.com:user/repo.git
 *   SYNC_COOLDOWN_MINUTES   - Minimum minutes between syncs (default: 30)
 *   SYNC_SCRIPT_PATH        - Path to bash script
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const SYNC_SCRIPT = process.env.SYNC_SCRIPT_PATH || path.join(HOME, 'scripts', 'openclaw-github-sync.sh');
const COOLDOWN_MINUTES = parseInt(process.env.SYNC_COOLDOWN_MINUTES || '30', 10);
const LOCK_FILE = '/tmp/openclaw-github-sync-wrapper.lock';
const DRY_RUN = process.argv.includes('--dry-run');

function log(level, message) {
    const ts = new Date().toISOString();
    process.stderr.write(`[${ts}] ${level}: ${message}\n`);
}

function shouldSkip() {
    if (!fs.existsSync(LOCK_FILE)) return false;
    try {
        const lastRun = parseInt(fs.readFileSync(LOCK_FILE, 'utf8').trim(), 10);
        const now = Math.floor(Date.now() / 1000);
        const elapsed = (now - lastRun) / 60;
        if (elapsed < COOLDOWN_MINUTES) {
            log('INFO', `Skipping: last sync was ${elapsed.toFixed(1)} min ago (cooldown: ${COOLDOWN_MINUTES} min)`);
            return true;
        }
    } catch {
        // Corrupt lock file — proceed
    }
    return false;
}

function touchLock() {
    fs.writeFileSync(LOCK_FILE, String(Math.floor(Date.now() / 1000)), 'utf8');
}

function validateEnvironment() {
    const issues = [];

    if (!fs.existsSync(SYNC_SCRIPT)) {
        issues.push(`Sync script not found: ${SYNC_SCRIPT}`);
    }

    const hasToken = !!process.env.GITHUB_TOKEN || !!process.env.GH_TOKEN;
    const hasSshKey = fs.existsSync(path.join(HOME, '.ssh', 'id_ed25519'))
        || fs.existsSync(path.join(HOME, '.ssh', 'id_rsa'));

    if (!hasToken && !hasSshKey) {
        issues.push('No GITHUB_TOKEN, GH_TOKEN, or SSH key found');
    }

    if (!process.env.GIT_REMOTE_URL) {
        issues.push('GIT_REMOTE_URL is not set');
    }

    return issues;
}

function main() {
    log('INFO', 'openclaw-github-sync-wrapper starting');

    if (shouldSkip() && !DRY_RUN) {
        process.exit(0);
    }

    const issues = validateEnvironment();
    if (issues.length > 0) {
        log('ERROR', 'Pre-flight validation failed:');
        issues.forEach(i => log('ERROR', `  - ${i}`));
        process.exit(1);
    }

    const env = { ...process.env };
    if (DRY_RUN) {
        env.DRY_RUN = 'true';
    }

    try {
        log('INFO', `Executing: bash ${SYNC_SCRIPT}`);
        const result = execFileSync('bash', [SYNC_SCRIPT], {
            env,
            cwd: HOME,
            timeout: 300_000,
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'pipe'],
        });

        if (result.stdout) process.stdout.write(result.stdout);
        if (result.stderr) process.stderr.write(result.stderr);

        touchLock();
        log('INFO', 'Sync completed successfully');
        process.exit(0);
    } catch (err) {
        if (err.stderr) process.stderr.write(err.stderr);
        if (err.stdout) process.stdout.write(err.stdout);

        log('ERROR', `Sync failed (exit code: ${err.status || 'unknown'}): ${err.message}`);
        process.exit(err.status || 1);
    }
}

main();
