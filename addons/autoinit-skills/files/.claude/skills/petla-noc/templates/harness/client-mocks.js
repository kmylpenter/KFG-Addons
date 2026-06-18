// CLIENT_MOCKS_VERSION 1.0 — DOM + google.script.run shim for petla-noc client tests.
// Hand-written (NOT jsdom): dependency-free, PRoot-safe, same philosophy as mocks.js —
// "explicit failure beats silent wrong pass": anything not implemented throws so the
// test author sees the gap. Covers CLIENT LOGIC (parse/compute/branch/which-server-call),
// NOT rendering/layout — that is the SMOKE layer's job.
//
// fixtures = {
//   dom: { "#id": {value,text,html,checked,...}, ".cls": {...}, "tag": {...} },  // seed elements
//   server: { fnName: value | (args)=>value },   // google.script.run.<fn> success payloads
//   url: "https://script.google.com/...",          // window.location.href seed
//   preload: (ctx, state) => {},  extend: (ctx, state) => {}
// }
"use strict";

class ClientMockError extends Error {}
function notImpl(name, impl) {
  return new Proxy(impl || {}, {
    get(t, p) {
      if (p in t) return t[p];
      if (typeof p === "symbol" || p === "then" || p === "inspect" || p === "toJSON") return undefined;
      throw new ClientMockError(`[client-mock] ${name}.${String(p)} not implemented — add it via fixtures.extend(ctx, state)`);
    },
  });
}

// ── one DOM element ────────────────────────────────────────────────────────────
function makeEl(state, seed, tag) {
  seed = seed || {};
  const listeners = {};
  const el = {
    tagName: (tag || seed.tag || "div").toUpperCase(),
    id: seed.id || "",
    value: seed.value !== undefined ? seed.value : "",
    textContent: seed.text !== undefined ? seed.text : "",
    innerHTML: seed.html !== undefined ? seed.html : "",
    innerText: seed.text !== undefined ? seed.text : "",
    checked: seed.checked !== undefined ? !!seed.checked : false,
    disabled: seed.disabled !== undefined ? !!seed.disabled : false,
    className: seed.className || "",
    href: seed.href || "",
    _attrs: Object.assign({}, seed.attrs),
    _children: [],
    style: new Proxy(Object.assign({}, seed.style), { set(t, k, v) { t[k] = v; state.styleSets.push({ k, v }); return true; } }),
    dataset: Object.assign({}, seed.dataset),
    setAttribute(k, v) { this._attrs[k] = String(v); if (k === "value") this.value = v; },
    getAttribute(k) { return k in this._attrs ? this._attrs[k] : null; },
    removeAttribute(k) { delete this._attrs[k]; },
    hasAttribute(k) { return k in this._attrs; },
    appendChild(c) { this._children.push(c); return c; },
    removeChild(c) { this._children = this._children.filter((x) => x !== c); return c; },
    querySelector() { return null; },           // nested queries: extend via fixtures if needed
    querySelectorAll() { return []; },
    addEventListener(ev, fn) { (listeners[ev] = listeners[ev] || []).push(fn); state.listeners.push({ id: el.id, ev }); },
    removeEventListener(ev, fn) { if (listeners[ev]) listeners[ev] = listeners[ev].filter((f) => f !== fn); },
    dispatchEvent(ev) { const fs = listeners[(ev && ev.type) || ev] || []; for (const f of fs) f.call(el, typeof ev === "object" ? ev : { type: ev, target: el }); return true; },
    click() { this.dispatchEvent({ type: "click", target: this }); },
    focus() {}, blur() {}, remove() {},
    classList: {
      add: (...c) => { const s = new Set(el.className.split(/\s+/).filter(Boolean)); c.forEach((x) => s.add(x)); el.className = [...s].join(" "); },
      remove: (...c) => { const s = new Set(el.className.split(/\s+/).filter(Boolean)); c.forEach((x) => s.delete(x)); el.className = [...s].join(" "); },
      toggle: (c) => { const s = new Set(el.className.split(/\s+/).filter(Boolean)); s.has(c) ? s.delete(c) : s.add(c); el.className = [...s].join(" "); return s.has(c); },
      contains: (c) => el.className.split(/\s+/).includes(c),
    },
  };
  return el;
}

// ── google.script.run chainable mock ───────────────────────────────────────────
// Usage in client code: google.script.run.withSuccessHandler(cb).withFailureHandler(eb).serverFn(args)
// We record the call; if fixtures.server[fn] is set we invoke the success handler with it
// synchronously (so logic that depends on the response is exercised); else the test can
// drive it via state.serverCalls[i].succeed(value) / .fail(err).
function makeGoogleRun(state, fixtures) {
  function builder(ctx) {
    return new Proxy(function () {}, {
      get(_, prop) {
        const p = String(prop);
        if (p === "withSuccessHandler") return (fn) => builder(Object.assign({}, ctx, { success: fn }));
        if (p === "withFailureHandler") return (fn) => builder(Object.assign({}, ctx, { failure: fn }));
        if (p === "withUserObject") return (o) => builder(Object.assign({}, ctx, { userObject: o }));
        // any other property = the server function name; calling it triggers the call
        return (...args) => {
          const rec = {
            fn: p, args, success: ctx.success || null, failure: ctx.failure || null, userObject: ctx.userObject,
            succeed(v) { if (this.success) this.success(v, this.userObject); },
            fail(e) { if (this.failure) this.failure(e, this.userObject); },
          };
          state.serverCalls.push(rec);
          const seed = (fixtures.server || {})[p];
          if (seed !== undefined) rec.succeed(typeof seed === "function" ? seed(...args) : seed);
        };
      },
    });
  }
  return { script: { run: builder({}), host: notImpl("google.script.host", { close: () => {}, setHeight: () => {}, setWidth: () => {} }), url: notImpl("google.script.url", { getLocation: (cb) => cb({ parameter: {}, hash: "" }) }) } };
}

// ── buildClientMocks ────────────────────────────────────────────────────────────
function buildClientMocks(fixtures) {
  fixtures = fixtures || {};
  const state = { serverCalls: [], log: [], alerts: [], confirms: [], styleSets: [], listeners: [], timeouts: [], byId: {}, elements: [] };

  const registry = {}; // selector -> element
  for (const [sel, seed] of Object.entries(fixtures.dom || {})) {
    const el = makeEl(state, seed, seed && seed.tag);
    if (sel.startsWith("#")) { el.id = el.id || sel.slice(1); state.byId[el.id] = el; }
    registry[sel] = el;
    state.elements.push(el);
  }
  const getById = (id) => state.byId[id] || (registry["#" + id]) || null;

  const document = notImpl("document", {
    getElementById: (id) => getById(id),
    querySelector: (sel) => registry[sel] || (sel[0] === "#" ? getById(sel.slice(1)) : null),
    querySelectorAll: (sel) => (registry[sel] ? [registry[sel]] : []),
    getElementsByClassName: (c) => Object.entries(registry).filter(([s]) => s === "." + c).map(([, e]) => e),
    getElementsByTagName: (t) => Object.entries(registry).filter(([s]) => s.toLowerCase() === t.toLowerCase()).map(([, e]) => e),
    createElement: (tag) => makeEl(state, {}, tag),
    createTextNode: (t) => ({ textContent: String(t), nodeType: 3 }),
    addEventListener: (ev, fn) => { state.listeners.push({ id: "document", ev }); if (ev === "DOMContentLoaded") state._domReady = fn; },
    body: makeEl(state, { id: "body" }, "body"),
    head: makeEl(state, { id: "head" }, "head"),
    cookie: "",
  });

  const window = notImpl("window", {
    document,
    alert: (m) => { state.alerts.push(String(m)); },
    confirm: (m) => { state.confirms.push(String(m)); return fixtures.confirm !== undefined ? !!fixtures.confirm : true; },
    prompt: (m, d) => (fixtures.prompt !== undefined ? fixtures.prompt : d || ""),
    setTimeout: (fn, ms) => { state.timeouts.push(ms); if (typeof fn === "function") fn(); return 0; }, // run immediately (deterministic)
    clearTimeout: () => {},
    setInterval: () => 0, clearInterval: () => {},
    location: { href: fixtures.url || "https://script.google.com/macros/s/mock/exec", reload: () => {}, assign: () => {}, search: "", hash: "" },
    localStorage: (() => { const s = {}; return { getItem: (k) => (k in s ? s[k] : null), setItem: (k, v) => { s[k] = String(v); }, removeItem: (k) => { delete s[k]; }, clear: () => { for (const k of Object.keys(s)) delete s[k]; } }; })(),
    navigator: { userAgent: "petla-noc-client-mock" },
    scrollTo: () => {}, addEventListener: (ev, fn) => { state.listeners.push({ id: "window", ev }); },
  });

  const globals = {
    window, document,
    google: makeGoogleRun(state, fixtures),
    console: { log: (...a) => state.log.push(a.map(String).join(" ")), error: (...a) => state.log.push("E: " + a.map(String).join(" ")), warn: (...a) => state.log.push("W: " + a.map(String).join(" ")), info: (...a) => state.log.push(a.map(String).join(" ")) },
    alert: window.alert, confirm: window.confirm, prompt: window.prompt,
    setTimeout: window.setTimeout, clearTimeout: window.clearTimeout, setInterval: window.setInterval, clearInterval: window.clearInterval,
    location: window.location, localStorage: window.localStorage, navigator: window.navigator,
    JSON, Math, Date, parseInt, parseFloat, isNaN, isFinite, encodeURIComponent, decodeURIComponent, Array, Object, String, Number, Boolean, RegExp, Error,
  };

  return { globals, state, ClientMockError };
}

module.exports = { buildClientMocks, ClientMockError, makeEl };
