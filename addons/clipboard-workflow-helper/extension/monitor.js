/**
 * REAL-TIME MONITORING SCRIPT
 * Obserwuje folder History i loguje wszystkie zmiany
 */

const fs = require('fs');
const path = require('path');

const HISTORY_FOLDER = 'C:\\Users\\kamil\\AppData\\Roaming\\Code\\User\\History\\-14e7f41c';
const LOG_FILE = path.join(__dirname, '.monitor.log');

function log(msg) {
  const timestamp = new Date().toLocaleString('pl-PL');
  const line = `[${timestamp}] ${msg}`;
  console.log(line);
  try {
    fs.appendFileSync(LOG_FILE, line + '\n', 'utf-8');
  } catch (e) {}
}

function getFilesInFolder() {
  try {
    const files = fs.readdirSync(HISTORY_FOLDER);
    return files.sort();
  } catch (e) {
    return [];
  }
}

function getEntriesJsonIds() {
  try {
    const entriesPath = path.join(HISTORY_FOLDER, 'entries.json');
    if (!fs.existsSync(entriesPath)) {
      return [];
    }
    const content = fs.readFileSync(entriesPath, 'utf-8');
    const data = JSON.parse(content);
    return data.entries.map(e => e.id).sort();
  } catch (e) {
    return [];
  }
}

function compareState(prev, curr) {
  const prevSet = new Set(prev);
  const currSet = new Set(curr);

  const added = curr.filter(f => !prevSet.has(f));
  const removed = prev.filter(f => !currSet.has(f));

  if (added.length > 0 || removed.length > 0) {
    if (added.length > 0) log(`📁 FILES ADDED: [${added.join(', ')}]`);
    if (removed.length > 0) log(`❌ FILES REMOVED: [${removed.join(', ')}]`);
  }

  return curr;
}

function compareEntries(prev, curr) {
  const prevSet = new Set(prev);
  const currSet = new Set(curr);

  const added = curr.filter(id => !prevSet.has(id));
  const removed = prev.filter(id => !currSet.has(id));

  if (added.length > 0 || removed.length > 0) {
    if (added.length > 0) log(`📝 ENTRIES ADDED: [${added.join(', ')}]`);
    if (removed.length > 0) log(`❌ ENTRIES REMOVED: [${removed.join(', ')}]`);
  }

  return curr;
}

log('🚀 MONITOR STARTED');
log(`📂 Watching folder: ${HISTORY_FOLDER}`);
log(`📊 Log file: ${LOG_FILE}`);

let lastFiles = getFilesInFolder();
let lastEntries = getEntriesJsonIds();

log(`\n[INITIAL STATE]`);
log(`Files in folder: [${lastFiles.join(', ')}]`);
log(`IDs in entries.json: [${lastEntries.join(', ')}]`);
log(`\n------- MONITORING (every 1s) -------\n`);

const watcher = setInterval(() => {
  const currFiles = getFilesInFolder();
  const currEntries = getEntriesJsonIds();

  lastFiles = compareState(lastFiles, currFiles);
  lastEntries = compareEntries(lastEntries, currEntries);

  // Co 10 sekund pokaż pełny state
  if (Math.random() < 0.1) {
    log(`\n📊 FULL STATE:`);
    log(`  Files: [${currFiles.join(', ')}]`);
    log(`  Entries: [${currEntries.join(', ')}]`);
    log(`  Mismatch: [${currFiles.filter(f => f !== 'entries.json' && !currEntries.includes(f)).join(', ')}]\n`);
  }
}, 1000);

process.on('SIGINT', () => {
  log('\n🛑 MONITOR STOPPED');
  clearInterval(watcher);
  process.exit(0);
});

log('Ready. Make some changes in VSCode...');
