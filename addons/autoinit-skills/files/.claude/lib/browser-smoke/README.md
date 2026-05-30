# browser-smoke

Universal puppeteer-core wrapper for `/petla smoke` mode (E2E browser smoke tests on Termux Android).

## Quick Start

```bash
# Install (first time)
cd ~/.claude/lib/browser-smoke && npm ci

# Verify install
node smoke-launcher.js --self-test    # exits 0 if 5/5 tests pass
```

## Architecture

| File | Purpose |
|------|---------|
| `smoke-launcher.js` | Universal puppeteer wrapper. Runs single test, JSON Lines + END marker output, exit codes 0-4. |
| `adapters/gas-server.py` | Python HTTP server with `google.script.run` shim — serves GAS HTML projects locally + proxies API calls to deployed GAS Web App. |
| `examples/wycena-helpers-example.js` | Reference template for project-specific helpers (port to `thoughts/shared/petla/smoke-helpers/<project>-helpers.js`). |

## Configuration

Per-project: `.smoke-config.yaml` in **project root** (NOT in thoughts/):

```yaml
project_type: gas-web
chromium_version_expected: "143"
dev_server:
  type: gas-server
  port: 0            # 0 = auto-discover
  gas_url: https://script.google.com/...
init_wait_for_function: "() => typeof appReady !== 'undefined' && appReady"
schema_version: "3.1"
enabled: true
```

## Test Author API

Test files (`module.exports = async function(page, helpers) { ... }`) get these helpers:

- `snapshot(label, data)` → push to `evidence.state_snapshots[]`
- `assertDom(selector, expectation)` → push to `evidence.dom_assertions[]`
- `recordCustom(key, value)` → set `evidence.custom_fields[key]`
- `recordBonusBug({description, severity, file, line, hint})` → push to `bonus_bugs[]`
- `baseUrl` → http://localhost:${allocated_port}

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | PASS |
| 1 | FAIL |
| 2 | INCONCLUSIVE (END marker present z status=INCONCLUSIVE OR truncation/corruption) |
| 3 | SETUP_ERROR (chromium not found, port retry exhausted, dev server failed) |
| 4 | CRASH/TIMEOUT (process died, missing END marker) |

## Output Protocol (JSON Lines + END marker)

Each event = one JSON line on stdout. Final line MUST be:

```json
{"_marker":"END","test_id":"<id>","status":"PASS|FAIL|INCONCLUSIVE","checksum":"<sha1>"}
```

If END marker missing → orchestrator treats as INCONCLUSIVE (truncated_output), NEVER silent PASS.

## Troubleshooting

- **chromium not found:** `pkg install chromium`
- **port retry exhausted:** another smoke run in progress; check `pgrep -f 'chromium-browser.*smoke-chromium-'`
- **broken pipe on proxy_to_gas:** known empirical issue — fresh launch per test mitigates
- **INCONCLUSIVE truncated_output:** launcher crashed mid-test; check chromium logs in $TMPDIR
- **Android low-memory killer:** SIGKILL bypasses trap → reboot or `pkill chromium` then retry

## API for Other Skills

```javascript
const { runTest, findFreePortWithRetry, checkChromiumVersion, makeHelpers }
  = require('~/.claude/lib/browser-smoke/smoke-launcher.js');

// runTest options: testFile, baseUrl?, chromiumPath?, chromiumArgs?, timeout?,
//                  initWaitForFunction?, consoleFilterRegex?, port?
// Returns: { exit: 0|1|2|3|4 }; emits TestResult to stdout via JSON Lines
```

## Related

- Plan: `thoughts/shared/petla-smoke-extension-plan-2026-05-01.md` (rev 4)
- Skill: `~/.claude/skills/petla/SKILL.md` (`## TRYB: smoke` section, v3.1+)
- Empirical context: Terminator-Umowy session 2026-05-01
