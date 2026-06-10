// MOCKS_VERSION 1.1 — petla-noc characterization-test mocks for Google Apps Script
// In-memory SpreadsheetApp/PropertiesService/GmailApp/UrlFetchApp/... for Node.
// Philosophy: explicit failure beats silent wrong pass — anything not implemented
// throws "[mock] X not implemented" so the test author sees the gap immediately.
//
// KNOWN DIVERGENCES vs real GAS (test authors MUST know these):
// 1. Open-ended ranges ("C2:C") return rows only down to getLastRow(); real GAS
//    returns down to the sheet's max grid rows, padded with "".
// 2. Reads outside the grid return "" instead of throwing out-of-bounds.
// 3. UrlFetchApp.fetch THROWS when no fixtures.http rule matches (real GAS would
//    hit the network) — add {match: /.*/, code: 200, body: ""} as explicit catch-all.
"use strict";

const crypto = require("crypto");

class MockError extends Error {}

function notImplementedService(name, impl) {
  // impl = object with the methods we DO support; any other access throws.
  return new Proxy(impl || {}, {
    get(target, prop) {
      if (prop in target) return target[prop];
      if (typeof prop === "symbol" || prop === "then" || prop === "inspect") return undefined;
      throw new MockError(`[mock] ${name}.${String(prop)} not implemented — add it via fixtures.extend(context, state)`);
    },
  });
}

// ── Spreadsheet model ────────────────────────────────────────────────────────
function colToIndex(letters) {
  let n = 0;
  for (const ch of letters.toUpperCase()) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n; // 1-based
}
function indexToCol(n) {
  let s = "";
  while (n > 0) { const r = (n - 1) % 26; s = String.fromCharCode(65 + r) + s; n = Math.floor((n - 1) / 26); }
  return s;
}

class MockRange {
  constructor(sheet, row, col, numRows, numCols) {
    this._s = sheet; this._r = row; this._c = col; this._nr = numRows; this._nc = numCols;
  }
  _cell(r, c, v) {
    const data = this._s._data;
    while (data.length < r) data.push([]);
    const rowArr = data[r - 1];
    if (v === undefined) return rowArr[c - 1] === undefined ? "" : rowArr[c - 1];
    while (rowArr.length < c) rowArr.push("");
    rowArr[c - 1] = v;
  }
  getValue() { return this._cell(this._r, this._c); }
  setValue(v) { this._cell(this._r, this._c, v); return this; }
  getValues() {
    const out = [];
    for (let r = 0; r < this._nr; r++) {
      const row = [];
      for (let c = 0; c < this._nc; c++) row.push(this._cell(this._r + r, this._c + c));
      out.push(row);
    }
    return out;
  }
  setValues(vals) {
    if (!Array.isArray(vals) || vals.length !== this._nr || (vals[0] || []).length !== this._nc)
      throw new MockError(`[mock] setValues dims ${vals.length}x${(vals[0] || []).length} != range ${this._nr}x${this._nc}`);
    for (let r = 0; r < this._nr; r++) for (let c = 0; c < this._nc; c++) this._cell(this._r + r, this._c + c, vals[r][c]);
    return this;
  }
  clearContent() { for (let r = 0; r < this._nr; r++) for (let c = 0; c < this._nc; c++) this._cell(this._r + r, this._c + c, ""); return this; }
  getNumRows() { return this._nr; }
  getNumColumns() { return this._nc; }
  getRow() { return this._r; }
  getColumn() { return this._c; }
  getA1Notation() { return `${indexToCol(this._c)}${this._r}:${indexToCol(this._c + this._nc - 1)}${this._r + this._nr - 1}`; }
}

class MockSheet {
  constructor(name, data) { this._name = name; this._data = (data || []).map((r) => r.slice()); }
  getName() { return this._name; }
  getLastRow() {
    for (let i = this._data.length - 1; i >= 0; i--)
      if (this._data[i].some((v) => v !== "" && v !== undefined && v !== null)) return i + 1;
    return 0;
  }
  getLastColumn() {
    let m = 0;
    for (const row of this._data) for (let c = row.length - 1; c >= 0; c--)
      if (row[c] !== "" && row[c] !== undefined && row[c] !== null) { m = Math.max(m, c + 1); break; }
    return m;
  }
  getRange(a, b, c, d) {
    if (typeof a === "string") return this._rangeFromA1(a);
    const row = a, col = b, nr = c === undefined ? 1 : c, nc = d === undefined ? 1 : d;
    return new MockRange(this, row, col, nr, nc);
  }
  _rangeFromA1(a1) {
    let m;
    if ((m = a1.match(/^([A-Za-z]+)(\d+)$/)))
      return new MockRange(this, +m[2], colToIndex(m[1]), 1, 1);
    if ((m = a1.match(/^([A-Za-z]+)(\d+):([A-Za-z]+)(\d+)$/))) {
      const c1 = colToIndex(m[1]), r1 = +m[2], c2 = colToIndex(m[3]), r2 = +m[4];
      return new MockRange(this, Math.min(r1, r2), Math.min(c1, c2), Math.abs(r2 - r1) + 1, Math.abs(c2 - c1) + 1);
    }
    if ((m = a1.match(/^([A-Za-z]+)(\d+):([A-Za-z]+)$/))) { // "C2:C" — open rows
      const c1 = colToIndex(m[1]), r1 = +m[2], c2 = colToIndex(m[3]);
      const r2 = Math.max(this.getLastRow(), r1);
      return new MockRange(this, r1, Math.min(c1, c2), r2 - r1 + 1, Math.abs(c2 - c1) + 1);
    }
    if ((m = a1.match(/^([A-Za-z]+):([A-Za-z]+)$/))) { // "A:B" — full columns
      const c1 = colToIndex(m[1]), c2 = colToIndex(m[2]);
      return new MockRange(this, 1, Math.min(c1, c2), Math.max(this.getLastRow(), 1), Math.abs(c2 - c1) + 1);
    }
    throw new MockError(`[mock] unsupported A1 notation: ${a1}`);
  }
  getDataRange() { return new MockRange(this, 1, 1, Math.max(this.getLastRow(), 1), Math.max(this.getLastColumn(), 1)); }
  appendRow(row) {
    const at = this.getLastRow(); // GAS appends after last row with content
    const data = this._data;
    while (data.length < at + 1) data.push([]);
    data[at] = row.slice();
    return this;
  }
  clear() { this._data = []; return this; }
  deleteRow(r) { this._data.splice(r - 1, 1); return this; }
  insertRowBefore(r) { this._data.splice(r - 1, 0, []); return this; }
  hideSheet() { return this; }
  showSheet() { return this; }
  setFrozenRows() { return this; }
  autoResizeColumn() { return this; }
}

class MockSpreadsheet {
  constructor(id, sheetsObj) {
    this._id = id;
    this._sheets = {};
    for (const [name, data] of Object.entries(sheetsObj || {})) this._sheets[name] = new MockSheet(name, data);
  }
  getId() { return this._id; }
  getName() { return `Mock Spreadsheet ${this._id}`; }
  getUrl() { return `https://docs.google.com/spreadsheets/d/${this._id}`; }
  getSheetByName(name) { return this._sheets[name] || null; } // GAS: null, not throw
  getSheets() { return Object.values(this._sheets); }
  getActiveSheet() { const s = Object.values(this._sheets); return s[0] || this.insertSheet("Sheet1"); }
  insertSheet(name) { this._sheets[name] = this._sheets[name] || new MockSheet(name, []); return this._sheets[name]; }
  getRange(a1WithSheet) { // "Dane!A1:B2"
    const m = String(a1WithSheet).match(/^'?([^'!]+)'?!(.+)$/);
    if (!m) throw new MockError(`[mock] Spreadsheet.getRange expects 'Sheet!A1' got: ${a1WithSheet}`);
    const sh = this.getSheetByName(m[1]);
    if (!sh) throw new MockError(`[mock] no sheet ${m[1]}`);
    return sh.getRange(m[2]);
  }
  toast() { return this; }
}

// ── buildMocks ───────────────────────────────────────────────────────────────
// fixtures = {
//   sheets: { "*": { "Dane": [["A",1]] }, "<ssId>": {...} },  // "*" = active spreadsheet
//   properties: { KEY: "value" },                              // ScriptProperties seed
//   http: [{ match: "substring-or-regex", code: 200, body: "..." , headers: {} }],
//   userEmail: "test@example.com",
//   preload: (context, state) => { ... },  // wołany PRZED załadowaniem źródeł (globale dla top-level)
//   extend: (context, state) => { ... }    // wołany PO załadowaniu — last-resort hook
// }
function buildMocks(fixtures) {
  fixtures = fixtures || {};
  const state = {
    log: [], console: [], sentEmails: [], fetches: [], triggers: [],
    // GAS properties are always strings — coerce fixture seeds like setProperty does
    props: Object.fromEntries(Object.entries(fixtures.properties || {}).map(([k, v]) => [k, String(v)])),
    userProps: {}, docProps: {}, cache: {},
    spreadsheets: {},
  };
  for (const [id, sheets] of Object.entries(fixtures.sheets || {}))
    state.spreadsheets[id] = new MockSpreadsheet(id === "*" ? "active-mock-id" : id, sheets);

  const active = state.spreadsheets["*"] || null;

  const propsApi = (store) => ({
    getProperty: (k) => (k in store ? store[k] : null),
    setProperty: (k, v) => { store[k] = String(v); },
    setProperties: (obj, del) => { if (del) for (const k of Object.keys(store)) delete store[k]; for (const [k, v] of Object.entries(obj)) store[k] = String(v); },
    deleteProperty: (k) => { delete store[k]; },
    deleteAllProperties: () => { for (const k of Object.keys(store)) delete store[k]; },
    getProperties: () => Object.assign({}, store),
    getKeys: () => Object.keys(store),
  });

  const triggerBuilder = (fnName) => {
    const rec = { fn: fnName, chain: [] };
    const b = new Proxy({}, {
      get(_, prop) {
        if (prop === "create") return () => { state.triggers.push(rec); return { getUniqueId: () => "mock-trigger" }; };
        return (...args) => { rec.chain.push(`${String(prop)}(${args.map(String).join(",")})`); return b; };
      },
    });
    return b;
  };

  function formatDate(date, _tz, fmt) {
    const p = (n, w) => String(n).padStart(w || 2, "0");
    return String(fmt)
      .replace(/yyyy/g, date.getFullYear())
      .replace(/MM/g, p(date.getMonth() + 1))
      .replace(/dd/g, p(date.getDate()))
      .replace(/HH/g, p(date.getHours()))
      .replace(/mm/g, p(date.getMinutes()))
      .replace(/ss/g, p(date.getSeconds())); // tz ignorowane — testuj na datach lokalnych
  }

  const globals = {
    SpreadsheetApp: notImplementedService("SpreadsheetApp", {
      getActiveSpreadsheet: () => { if (!active) throw new MockError('[mock] no active spreadsheet — add fixtures.sheets["*"]'); return active; },
      getActive: () => { if (!active) throw new MockError('[mock] no active spreadsheet — add fixtures.sheets["*"]'); return active; },
      openById: (id) => { if (!state.spreadsheets[id]) throw new MockError(`[mock] openById(${id}) — add fixtures.sheets["${id}"]`); return state.spreadsheets[id]; },
      openByUrl: (url) => {
        const m = String(url).match(/\/d\/([a-zA-Z0-9_-]+)/);
        const id = m ? m[1] : url;
        if (!state.spreadsheets[id]) throw new MockError(`[mock] openByUrl(${url}) — add fixtures.sheets["${id}"]`);
        return state.spreadsheets[id];
      },
      flush: () => {},
      getUi: () => notImplementedService("Ui", {
        createMenu: (name) => { const menu = { _name: name, _items: [], addItem(t, f) { this._items.push([t, f]); return this; }, addSeparator() { return this; }, addSubMenu() { return this; }, addToUi() { state.triggers.push({ fn: "menu:" + name }); } }; return menu; },
        alert: () => { throw new MockError("[mock] Ui.alert in unattended test"); },
      }),
    }),
    PropertiesService: notImplementedService("PropertiesService", {
      getScriptProperties: () => propsApi(state.props),
      getUserProperties: () => propsApi(state.userProps),
      getDocumentProperties: () => propsApi(state.docProps),
    }),
    CacheService: notImplementedService("CacheService", {
      getScriptCache: () => ({
        get: (k) => (k in state.cache ? state.cache[k] : null),
        put: (k, v) => { state.cache[k] = String(v); },
        remove: (k) => { delete state.cache[k]; },
      }),
    }),
    Logger: { log: (...a) => { state.log.push(a.map(String).join(" ")); } },
    console: { log: (...a) => state.console.push(a.map(String).join(" ")), error: (...a) => state.console.push("E: " + a.map(String).join(" ")), warn: (...a) => state.console.push("W: " + a.map(String).join(" ")) },
    GmailApp: notImplementedService("GmailApp", {
      sendEmail: (...args) => { state.sentEmails.push({ via: "GmailApp", args }); },
    }),
    MailApp: notImplementedService("MailApp", {
      sendEmail: (...args) => { state.sentEmails.push({ via: "MailApp", args }); },
      getRemainingDailyQuota: () => 100,
    }),
    UrlFetchApp: notImplementedService("UrlFetchApp", {
      fetch: (url, params) => {
        state.fetches.push({ url, params });
        const rule = (fixtures.http || []).find((r) =>
          r.match instanceof RegExp ? r.match.test(url) : String(url).includes(r.match));
        if (!rule) throw new MockError(`[mock] UrlFetchApp.fetch unfixtured: ${url} — add fixtures.http rule (or catch-all {match: /.*/})`);
        const code = rule.code === undefined ? 200 : rule.code;
        const body = rule.body === undefined ? "" : rule.body;
        return {
          getResponseCode: () => code,
          getContentText: () => (typeof body === "string" ? body : JSON.stringify(body)),
          getAllHeaders: () => (rule && rule.headers) || {},
          getBlob: () => ({ getBytes: () => Buffer.from(typeof body === "string" ? body : JSON.stringify(body)) }),
        };
      },
    }),
    ScriptApp: notImplementedService("ScriptApp", {
      newTrigger: (fnName) => triggerBuilder(fnName),
      getProjectTriggers: () => [],
      getScriptId: () => "mock-script-id",
    }),
    Session: notImplementedService("Session", {
      getActiveUser: () => ({ getEmail: () => fixtures.userEmail || "test@example.com" }),
      getEffectiveUser: () => ({ getEmail: () => fixtures.userEmail || "test@example.com" }),
      getScriptTimeZone: () => "Europe/Warsaw",
    }),
    Utilities: notImplementedService("Utilities", {
      formatDate,
      sleep: () => {},
      getUuid: () => crypto.randomUUID(),
      base64Encode: (s) => Buffer.from(s).toString("base64"),
      base64Decode: (s) => Array.from(Buffer.from(s, "base64")),
      newBlob: (data, type, name) => ({ getBytes: () => Buffer.from(data), getContentType: () => type, getName: () => name, getDataAsString: () => String(data) }),
    }),
    HtmlService: notImplementedService("HtmlService", {
      createHtmlOutput: (s) => ({ _c: String(s || ""), getContent() { return this._c; }, setTitle() { return this; }, append(x) { this._c += x; return this; }, setWidth() { return this; }, setHeight() { return this; } }),
      createHtmlOutputFromFile: (n) => ({ getContent: () => `<!-- mock file ${n} -->`, setTitle() { return this; } }),
      createTemplateFromFile: (n) => ({ evaluate: () => ({ getContent: () => `<!-- mock template ${n} -->`, setTitle() { return this; } }) }),
    }),
    LockService: notImplementedService("LockService", {
      getScriptLock: () => ({ tryLock: () => true, waitLock: () => {}, releaseLock: () => {}, hasLock: () => true }),
      getUserLock: () => ({ tryLock: () => true, waitLock: () => {}, releaseLock: () => {}, hasLock: () => true }),
    }),
    DriveApp: notImplementedService("DriveApp"),
    CalendarApp: notImplementedService("CalendarApp"),
    ContentService: notImplementedService("ContentService", {
      createTextOutput: (s) => ({ _c: String(s || ""), getContent() { return this._c; }, setMimeType() { return this; } }),
    }),
  };

  return { globals, state, MockError };
}

module.exports = { buildMocks, MockError, MockSheet, MockSpreadsheet };
