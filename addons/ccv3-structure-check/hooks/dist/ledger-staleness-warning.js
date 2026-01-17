import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
// Thresholds for warnings (percentage of context window)
const CTX_THRESHOLD_WARN = 50; // 50% - gentle reminder
const CTX_THRESHOLD_URGENT = 80; // 80% - urgent warning
async function main() {
    const input = JSON.parse(await readStdin());
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    // Read ctx% from statusline cache file
    const tempDir = os.tmpdir();
    const ctxCacheFile = path.join(tempDir, `claude-context-pct-${input.session_id}.txt`);
    let ctxPercent = 0;
    if (fs.existsSync(ctxCacheFile)) {
        try {
            const content = fs.readFileSync(ctxCacheFile, 'utf-8').trim();
            ctxPercent = parseInt(content, 10) || 0;
        }
        catch {
            // Ignore read errors
        }
    }
    // Skip if below threshold
    if (ctxPercent < CTX_THRESHOLD_WARN) {
        console.log(JSON.stringify({ result: 'continue' }));
        return;
    }
    // Check if ledger exists and get its mtime
    const ledgerDir = path.join(projectDir, 'thoughts', 'ledgers');
    let ledgerExists = false;
    let ledgerAge = 0; // in minutes
    if (fs.existsSync(ledgerDir)) {
        const ledgerFiles = fs.readdirSync(ledgerDir)
            .filter(f => f.startsWith('CONTINUITY_') && f.endsWith('.md'));
        if (ledgerFiles.length > 0) {
            ledgerExists = true;
            // Get most recent ledger mtime
            const mostRecentMtime = ledgerFiles
                .map(f => fs.statSync(path.join(ledgerDir, f)).mtime.getTime())
                .reduce((max, t) => Math.max(max, t), 0);
            ledgerAge = Math.floor((Date.now() - mostRecentMtime) / 60000);
        }
    }
    // Check handoffs too
    const handoffsDir = path.join(projectDir, 'thoughts', 'shared', 'handoffs');
    let handoffExists = false;
    if (fs.existsSync(handoffsDir)) {
        const sessionDirs = fs.readdirSync(handoffsDir);
        handoffExists = sessionDirs.length > 0;
    }
    // Build warning message based on conditions
    let warning = '';
    if (ctxPercent >= CTX_THRESHOLD_URGENT) {
        // Urgent warning at 80%+
        if (!ledgerExists && !handoffExists) {
            warning = `⚠️ CONTEXT ${ctxPercent}% - No ledger or handoff exists! Run /continuity_ledger or /create_handoff NOW before compact.`;
        }
        else if (ledgerExists && ledgerAge > 30) {
            warning = `⚠️ CONTEXT ${ctxPercent}% - Ledger last updated ${ledgerAge}min ago. Consider /continuity_ledger update.`;
        }
        else if (!handoffExists) {
            warning = `⚠️ CONTEXT ${ctxPercent}% - No handoff exists. Run /create_handoff before ending session.`;
        }
    }
    else if (ctxPercent >= CTX_THRESHOLD_WARN) {
        // Gentle reminder at 50%+
        if (!ledgerExists && !handoffExists) {
            warning = `📋 Context at ${ctxPercent}% - Consider running /continuity_ledger to track session state.`;
        }
        else if (ledgerExists && ledgerAge > 60) {
            warning = `📋 Context at ${ctxPercent}% - Ledger not updated for ${ledgerAge}min.`;
        }
    }
    if (warning) {
        const output = {
            result: 'continue',
            additionalContext: `[CCv3 Ledger Check] ${warning}`
        };
        console.log(JSON.stringify(output));
    }
    else {
        console.log(JSON.stringify({ result: 'continue' }));
    }
}
async function readStdin() {
    return new Promise((resolve) => {
        let data = '';
        process.stdin.on('data', chunk => data += chunk);
        process.stdin.on('end', () => resolve(data));
    });
}
main().catch(err => {
    console.error('Ledger staleness check error:', err);
    console.log(JSON.stringify({ result: 'continue' }));
});
