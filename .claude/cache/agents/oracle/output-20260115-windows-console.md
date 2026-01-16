# Research Report: Windows Console Window with Node.js spawn + uv

Generated: 2026-01-15

## Summary

The console window appearing when spawning `uv run python` via Node.js is a **known limitation** caused by two factors: (1) `uv.exe` is a console subsystem application that always creates a console window, and (2) Node.js `windowsHide: true` has known bugs with certain configurations. There are several workarounds available, including the new `uvw.exe` wrapper.

## Questions Answered

### Q1: Why does `windowsHide: true` not work with uv?
**Answer:** Two separate issues:
1. **uv.exe itself** is compiled as a Windows console application (console subsystem), so it ALWAYS creates a console window regardless of how you spawn it
2. **Node.js `windowsHide`** has known bugs - it doesn't work properly with `detached: true`, and has inconsistent behavior with `stdio: 'inherit'`

**Source:** [Node.js Issue #21825](https://github.com/nodejs/node/issues/21825), [uv Issue #6801](https://github.com/astral-sh/uv/issues/6801)
**Confidence:** High

### Q2: Is there a uv solution?
**Answer:** Yes! `uvw.exe` was added in early 2025. It's a wrapper that runs `uv` without creating a console window (uses Windows GUI subsystem instead of console subsystem).

**Source:** [uv PR #11786](https://github.com/astral-sh/uv/pull/11786)
**Confidence:** High

### Q3: What about pythonw.exe?
**Answer:** Using `.pyw` extension or `pythonw.exe` only hides the Python interpreter's window - it doesn't help because the problem is `uv.exe` creating the window BEFORE Python even starts.

**Source:** [Python Windows Documentation](https://docs.python.org/3/using/windows.html)
**Confidence:** High

### Q4: Can Node.js pass CREATE_NO_WINDOW?
**Answer:** No. Node.js doesn't expose Windows `creationflags` like Python's `subprocess.Popen(creationflags=subprocess.CREATE_NO_WINDOW)`. The `windowsHide: true` option is the closest equivalent but it's implemented differently and has bugs.

**Source:** [Node.js Child Process Documentation](https://nodejs.org/api/child_process.html)
**Confidence:** High

## Solutions (Ranked by Practicality)

### Solution 1: Use `uvw.exe` instead of `uv.exe` (BEST)
**Source:** [uv PR #11786](https://github.com/astral-sh/uv/pull/11786)

Replace `uv` with `uvw` in your spawn command:

```javascript
// Before (shows console)
spawnSync('uv', ['run', 'script.py'], { windowsHide: true });

// After (no console)
spawnSync('uvw', ['run', 'script.py'], { windowsHide: true });
```

**Pros:**
- Built-in solution from astral-sh
- No wrapper scripts needed
- Works with all uv commands

**Cons:**
- Only available in recent uv versions (2025+)
- Windows Defender may flag it as false positive if manually extracted (use official installer)

### Solution 2: VBScript Wrapper
**Source:** [Jose Espitia Blog](https://www.joseespitia.com/2018/05/24/silently-launch-scripts-or-applications-with-hidden-vbs/)

Create a `hidden.vbs`:
```vbs
CreateObject("Wscript.Shell").Run """" & WScript.Arguments(0) & """", 0, False
```

Then spawn:
```javascript
spawnSync('wscript', ['hidden.vbs', 'uv run script.py'], { windowsHide: true });
```

**Pros:**
- Works with any console application
- No external dependencies

**Cons:**
- Additional file to manage
- Slightly more complex

### Solution 3: PowerShell Hidden Window
**Source:** [IDERA Blog](https://blog.idera.com/database-tools/launching-powershell-scripts-invisibly)

```javascript
spawnSync('powershell', [
  '-WindowStyle', 'Hidden',
  '-Command', 'uv run script.py'
], { windowsHide: true });
```

**Pros:**
- No additional files needed

**Cons:**
- PowerShell startup overhead
- May still flash briefly

### Solution 4: Bypass uv for simple scripts
**Source:** [Python Windows Documentation](https://docs.python.org/3/using/windows.html)

If you don't need uv's dependency management for a specific call:
```javascript
// Use pythonw.exe directly (no console)
spawnSync('pythonw', ['path/to/script.py'], { windowsHide: true });
```

**Pros:**
- Simplest if you don't need uv features

**Cons:**
- Loses uv's virtual environment management
- Only works for simple scripts

## Node.js windowsHide Known Issues

| Issue | Description | Workaround |
|-------|-------------|------------|
| [#21825](https://github.com/nodejs/node/issues/21825) | Doesn't work with `detached: true` | Don't use `detached` |
| [#17824](https://github.com/nodejs/node/issues/17824) | Inconsistent with `stdio: 'inherit'` | Use `stdio: 'pipe'` |
| [#29837](https://github.com/nodejs/node/issues/29837) | Prevents SIGINT on child | Accept the limitation |

## Recommendations

### For This Use Case (Node.js + uv hooks)

1. **Check if `uvw` is available:**
   ```javascript
   const uvCommand = process.platform === 'win32' ? 'uvw' : 'uv';
   ```

2. **Fallback to VBScript wrapper if uvw not available**

3. **Ensure stdio is NOT 'inherit':**
   ```javascript
   spawnSync(uvCommand, args, {
     windowsHide: true,
     stdio: 'pipe',  // NOT 'inherit'
     // detached: false  // DON'T use detached
   });
   ```

### Implementation Example

```javascript
function spawnUvHidden(args) {
  const isWin = process.platform === 'win32';
  
  if (isWin) {
    // Try uvw first (no console window)
    try {
      return spawnSync('uvw', args, {
        windowsHide: true,
        stdio: 'pipe',
        encoding: 'utf-8'
      });
    } catch (e) {
      // Fall back to uv (may show console briefly)
      return spawnSync('uv', args, {
        windowsHide: true,
        stdio: 'pipe',
        encoding: 'utf-8'
      });
    }
  }
  
  // Non-Windows: just use uv
  return spawnSync('uv', args, { stdio: 'pipe', encoding: 'utf-8' });
}
```

## Sources

1. [uv Issue #6801 - Console window on Windows](https://github.com/astral-sh/uv/issues/6801) - Original issue requesting no-console option
2. [uv PR #11786 - Add uvw](https://github.com/astral-sh/uv/pull/11786) - Implementation of uvw wrapper
3. [Node.js Issue #21825 - windowsHide + detached](https://github.com/nodejs/node/issues/21825) - Known bug
4. [Node.js Issue #17824 - windowsHide + stdio](https://github.com/nodejs/node/issues/17824) - Known inconsistency
5. [Python Windows Documentation](https://docs.python.org/3/using/windows.html) - pythonw.exe explanation
6. [subprocess CREATE_NO_WINDOW](https://runebook.dev/en/docs/python/library/subprocess/subprocess.CREATE_NO_WINDOW) - Python solution (not available in Node.js)
7. [VBScript Hidden.vbs](https://www.joseespitia.com/2018/05/24/silently-launch-scripts-or-applications-with-hidden-vbs/) - VBS wrapper approach

## Open Questions

- Will Node.js ever expose Windows `creationflags` for finer control?
- Is there a way to compile a custom launcher that wraps uv with GUI subsystem?
