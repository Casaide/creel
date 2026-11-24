#!/usr/bin/env node
// Creel's MCP server (#196): lets an agent run a game on Creel headless while it works on it. It speaks MCP (JSON-RPC
// over stdio) to the agent and drives one headless sim, the game's own Lobster program built on src/mcp/serve.lobster,
// one request at a time. No dependencies: plain Node 18 or newer.
//
//   node creel-mcp.js <path to the game's creel-mcp.json>
//
// The config says how to run the game's sim side, and which test suites and capture command the agent may run. The agent
// can't run anything else: saves and pictures go in one scratch folder, by name only. See README.md.

'use strict'
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn } = require('child_process')

const PREFIX = '@mcp '
const LINE_MAX = 900 // get_line reads at most 999 characters a line, so longer requests go in pieces
const NAME_RE = /^[A-Za-z0-9_-]{1,64}$/

function home (p) { return p.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p }

function loadConfig (file) {
  const cfg = JSON.parse(fs.readFileSync(file, 'utf8'))
  const root = path.dirname(path.resolve(file))
  cfg.root = root
  cfg.lobster = home(process.env.LOBSTER || cfg.lobster || 'lobster')
  cfg.cwd = path.resolve(root, cfg.cwd || '.')
  cfg.scratch = path.resolve(root, home(cfg.scratch || path.join(os.tmpdir(), 'creel-mcp')))
  cfg.tests = cfg.tests || {}
  cfg.timeout_s = cfg.timeout_s || 600
  if (!cfg.server) throw new Error(file + ': no "server" (the game\'s Lobster program built on src/mcp/serve.lobster)')
  fs.mkdirSync(cfg.scratch, { recursive: true })
  return cfg
}

// {lobster}, {save}, {png}, {scratch} in a configured command, and {start.<key>}: that arg of the last creel_start (a list
// joined by commas). An argument whose {start.<key>} is missing or empty is left out ("mods:{start.mods}" with no mods).
function fill (args, vars, start) {
  const out = []
  for (const a of args) {
    let empty = false
    const v = a.replace(/\{([\w.]+)\}/g, (m, k) => {
      if (k.startsWith('start.')) {
        const x = (start || {})[k.slice(6)]
        const s = x === undefined || x === null ? '' : Array.isArray(x) ? x.join(',') : String(x)
        if (!s) empty = true
        return s
      }
      return k in vars ? vars[k] : m
    })
    if (!empty) out.push(v)
  }
  return out
}

// ---------------------------------------------------------------- the sim side: one Lobster process

class Sim {
  constructor (cfg, log) {
    this.cfg = cfg
    this.log = log
    this.proc = null
    this.waiting = new Map()
    this.nextId = 1
    this.ready = null
    this.startArgs = {}  // the last creel_start's args, for {start.<key>} in the capture command
  }

  start () {
    if (this.proc) return this.ready
    const proc = spawn(this.cfg.lobster, [this.cfg.server], { cwd: this.cfg.cwd, stdio: ['pipe', 'pipe', 'pipe'] })
    this.proc = proc
    let buf = ''
    let readyOk, readyFail
    this.ready = new Promise((resolve, reject) => { readyOk = resolve; readyFail = reject })
    const early = []
    proc.stdout.on('data', d => {
      buf += d.toString()
      let n
      while ((n = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, n).replace(/\r$/, '')
        buf = buf.slice(n + 1)
        if (!line.startsWith(PREFIX)) { early.push(line); this.log(line); continue }
        const msg = JSON.parse(line.slice(PREFIX.length))
        if (msg.ready) { readyOk(); continue }
        const w = this.waiting.get(msg.id)
        if (w) { this.waiting.delete(msg.id); w(msg) }
      }
    })
    proc.stderr.on('data', d => { early.push(d.toString()); this.log(d.toString()) })
    proc.on('exit', code => {
      const why = 'the sim stopped (exit ' + code + '): ' + early.slice(-20).join('\n')
      readyFail(new Error(why))
      for (const w of this.waiting.values()) w({ ok: false, error: why })
      this.waiting.clear()
      if (this.proc === proc) this.proc = null
    })
    proc.on('error', e => readyFail(e))
    return this.ready
  }

  async request (cmd, fields) {
    await this.start()
    const id = this.nextId++
    const text = JSON.stringify(Object.assign({}, fields, { id, cmd }))
    const reply = new Promise(resolve => this.waiting.set(id, resolve))
    const lines = []
    for (let i = 0; i < text.length; i += LINE_MAX) lines.push(text.slice(i, i + LINE_MAX))
    const out = lines.map((l, i) => (i < lines.length - 1 ? '+' : '') + l).join('\n') + '\n'
    this.proc.stdin.write(out)
    return reply
  }

  stop () {
    if (!this.proc) return
    try { this.proc.stdin.end() } catch (e) {}
    const p = this.proc
    setTimeout(() => { try { p.kill() } catch (e) {} }, 2000)
    this.proc = null
  }
}

// ---------------------------------------------------------------- the tools

const ids = { type: 'array', items: { type: 'integer' } }
const filters = {
  ids,
  owner: ids,
  kind: ids,
  rect: { type: 'array', items: { type: 'integer' }, minItems: 4, maxItems: 4, description: 'x0, y0, x1, y1 in sim units (a tile is "tile" units, see creel_names)' },
  limit: { type: 'integer', description: 'at most this many (200 by default); "total" says how many matched' }
}

function tools (cfg) {
  const t = [
    { name: 'creel_start', description: 'Start a fresh match in the headless sim. ' + (cfg.start_help || 'The args are the game\'s own.'), inputSchema: { type: 'object', properties: { args: { type: 'object' } } } },
    { name: 'creel_state', description: 'The tick, the state hash and whether a match is running.', inputSchema: { type: 'object', properties: {} } },
    { name: 'creel_step', description: 'Run the sim for this many ticks (20 a second), then give the tick and the hash. With until, it stops early on the first matching event. With invariants, every tick is checked (see creel_invariants) and the run stops on the tick one breaks: broken says which, and where.', inputSchema: { type: 'object', properties: { ticks: { type: 'integer', minimum: 1, maximum: 72000 }, invariants: { type: 'boolean' }, until: { type: 'object', description: 'stop after the tick an event like this happens: kinds, a, b, c as in creel_events; the result\'s event is it, or null' }, stuck_limit: { type: 'integer', minimum: 0, description: 'ticks a walker may be held up before "stuck" breaks (0: not checked)' } }, required: ['ticks'] } },
    { name: 'creel_events', description: 'What happened since the match started (the newest 20,000 kept): goods picked up, dropped, gathered, made, used and lost; built, trained, hits, deaths; packs\' own (pack:<code>). a is the unit, b the building (or cell), c the resource, n how many. Filter by kinds (names from creel_names or codes), a, b, c, since (a tick).', inputSchema: { type: 'object', properties: { kinds: { type: 'array', items: { type: ['string', 'integer'] } }, a: { type: 'integer' }, b: { type: 'integer' }, c: { type: 'integer' }, since: { type: 'integer' }, limit: { type: 'integer' } } } },
    { name: 'creel_invariants', description: 'Check the invariants now: the engine\'s (columns, ids, on_map, carry, stock, holds, jobs, solid, stuck) and the packs\' own (a Lua invariants() hook). broken is "" while all hold.', inputSchema: { type: 'object', properties: {} } },
    { name: 'creel_pack_tests', description: 'Run a pack\'s own tests (its data/tests/*.lua: docs/lua.md), each in a fresh match from args (as creel_start\'s), with every invariant checked each tick. tests is a line a test, "ok <name>" or "FAIL <name>: why"; failed counts them. The last test\'s match is left running.', inputSchema: { type: 'object', properties: { pack: { type: 'string' }, args: { type: 'object' } }, required: ['pack'] } },
    { name: 'creel_names', description: 'Unit types, building types, resources and order names by index, the tile size and the map size. Kinds and resources elsewhere are these indexes.', inputSchema: { type: 'object', properties: {} } },
    { name: 'creel_units', description: 'Units with their state (position, task, target, carry, hp, ...), filtered.', inputSchema: { type: 'object', properties: filters } },
    { name: 'creel_buildings', description: 'Buildings and sites with their state (cell, done, progress, what they hold, want and have coming), filtered.', inputSchema: { type: 'object', properties: filters } },
    { name: 'creel_players', description: 'Each player\'s population and stock.', inputSchema: { type: 'object', properties: {} } },
    { name: 'creel_cell', description: 'One map cell: road, the building on it, its resource and amount.', inputSchema: { type: 'object', properties: { cx: { type: 'integer' }, cy: { type: 'integer' } }, required: ['cx', 'cy'] } },
    { name: 'creel_order', description: 'Give a player\'s order, as a player would. It runs at the start of the turn after next, like every order. a, b, c, d are the order\'s own values (a point in sim units, a building type, a target id, ...).', inputSchema: { type: 'object', properties: { player: { type: 'integer' }, command: { type: ['string', 'integer'], description: 'an order name from creel_names, or a code' }, ids, a: { type: 'integer' }, b: { type: 'integer' }, c: { type: 'integer' }, d: { type: 'integer' }, queue: { type: 'integer' } }, required: ['player', 'command'] } },
    { name: 'creel_save', description: 'Save the match under a name (letters, digits, - and _), in the server\'s scratch folder.', inputSchema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } },
    { name: 'creel_load', description: 'Load a match saved with creel_save.', inputSchema: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] } },
    { name: 'creel_restart', description: 'Stop the sim process; the next call starts a fresh one (after a code or data change).', inputSchema: { type: 'object', properties: {} } }
  ]
  if (cfg.capture) t.push({ name: 'creel_capture', description: 'A picture of the match as it is now, drawn by the game. ' + (cfg.capture_help || ''), inputSchema: { type: 'object', properties: { args: { type: 'object', description: 'the capture\'s own options' } } } })
  const suites = Object.keys(cfg.tests)
  if (suites.length) t.push({ name: 'creel_run_tests', description: 'Run one of the game\'s test suites and give its result and the end of its output. Suites: ' + suites.join(', ') + '.', inputSchema: { type: 'object', properties: { suite: { type: 'string', enum: suites } }, required: ['suite'] } })
  return t
}

function run (args, cwd, timeoutS) {
  return new Promise(resolve => {
    const p = spawn(args[0], args.slice(1), { cwd, stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''
    p.stdout.on('data', d => { out += d })
    p.stderr.on('data', d => { out += d })
    const timer = setTimeout(() => { p.kill(); out += '\n(stopped after ' + timeoutS + ' s)' }, timeoutS * 1000)
    p.on('error', e => { clearTimeout(timer); resolve({ code: -1, out: String(e) }) })
    p.on('exit', code => { clearTimeout(timer); resolve({ code, out }) })
  })
}

function text (v, isError) { return { content: [{ type: 'text', text: typeof v === 'string' ? v : JSON.stringify(v) }], isError: !!isError } }

async function call (cfg, sim, name, a) {
  a = a || {}
  const simCall = async (cmd, fields) => {
    const r = await sim.request(cmd, fields)
    return r.ok ? text(r.result) : text(r.error, true)
  }
  const savePath = n => {
    if (!NAME_RE.test(n || '')) throw new Error('a save name is letters, digits, - and _ only')
    return path.join(cfg.scratch, n + '.save')
  }
  switch (name) {
    case 'creel_start': {
      const r = await simCall('start', { args: a.args || {} })
      if (!r.isError) sim.startArgs = a.args || {}
      return r
    }
    case 'creel_pack_tests': {
      const r = await simCall('pack_tests', { pack: a.pack, args: a.args || {} })
      if (!r.isError) sim.startArgs = a.args || {}
      return r
    }
    case 'creel_state': return simCall('state', {})
    case 'creel_step': {
      const q = { ticks: a.ticks, invariants: !!a.invariants, stuck_limit: a.stuck_limit || 0 }
      if (a.until) q.until = a.until
      return simCall('step', q)
    }
    case 'creel_events': return simCall('events', a)
    case 'creel_invariants': return simCall('invariants', {})
    case 'creel_names': return simCall('names', {})
    case 'creel_units': return simCall('units', a)
    case 'creel_buildings': return simCall('buildings', a)
    case 'creel_players': return simCall('players', {})
    case 'creel_cell': return simCall('cell', a)
    case 'creel_order': return simCall('order', a)
    case 'creel_save': return simCall('save', { path: savePath(a.name) })
    case 'creel_load': return simCall('load', { path: savePath(a.name) })
    case 'creel_restart': sim.stop(); return text('stopped; the next call starts a fresh sim')
    case 'creel_capture': {
      if (!cfg.capture) break
      const save = path.join(cfg.scratch, '_capture.save')
      const png = path.join(cfg.scratch, '_capture.png')
      try { fs.unlinkSync(png) } catch (e) {}
      const r = await sim.request('save', { path: save })
      if (!r.ok) return text(r.error, true)
      const extra = Object.entries(a.args || {}).map(([k, v]) => String(k) + ':' + String(v)).filter(s => /^[\w.,:-]+$/.test(s))
      const res = await run(fill(cfg.capture, { lobster: cfg.lobster, save, png, scratch: cfg.scratch }, sim.startArgs).concat(extra), cfg.cwd, cfg.timeout_s)
      if (!fs.existsSync(png)) return text('no picture (exit ' + res.code + '): ' + res.out.slice(-2000), true)
      return { content: [{ type: 'image', data: fs.readFileSync(png).toString('base64'), mimeType: 'image/png' }] }
    }
    case 'creel_run_tests': {
      const suite = cfg.tests[a.suite]
      if (!suite) return text('no suite "' + a.suite + '"', true)
      const res = await run(fill(suite, { lobster: cfg.lobster, scratch: cfg.scratch }), cfg.cwd, cfg.timeout_s)
      return text({ suite: a.suite, exit: res.code, passed: res.code === 0, tail: res.out.split('\n').filter(l => !/warning/.test(l)).slice(-40).join('\n') }, res.code !== 0)
    }
  }
  return text('no tool "' + name + '"', true)
}

// ---------------------------------------------------------------- MCP over stdio

function main () {
  const file = process.argv[2] || 'creel-mcp.json'
  const cfg = loadConfig(file)
  const log = s => process.stderr.write(String(s).replace(/\n?$/, '\n'))
  const sim = new Sim(cfg, log)
  const send = m => process.stdout.write(JSON.stringify(m) + '\n')
  let buf = ''
  let queue = Promise.resolve()
  process.stdin.on('data', d => {
    buf += d.toString()
    let n
    while ((n = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, n).trim()
      buf = buf.slice(n + 1)
      if (!line) continue
      let msg
      try { msg = JSON.parse(line) } catch (e) { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }); continue }
      // One at a time, in order: the sim is one process and its state moves on with each call.
      queue = queue.then(() => handle(msg)).catch(e => log(e.stack || e))
    }
  })
  process.stdin.on('end', () => { queue.then(() => { sim.stop(); process.exit(0) }) })

  async function handle (msg) {
    const reply = result => { if (msg.id !== undefined) send({ jsonrpc: '2.0', id: msg.id, result }) }
    const fail = (code, message) => { if (msg.id !== undefined) send({ jsonrpc: '2.0', id: msg.id, error: { code, message } }) }
    switch (msg.method) {
      case 'initialize':
        return reply({
          protocolVersion: (msg.params && msg.params.protocolVersion) || '2025-06-18',
          capabilities: { tools: {} },
          serverInfo: { name: 'creel' + (cfg.name ? '-' + cfg.name : ''), version: '0.1.0' },
          instructions: cfg.instructions || 'A headless match of a game on Creel. creel_start, then creel_step and the queries; creel_names maps kinds and resources to names.'
        })
      case 'ping': return reply({})
      case 'tools/list': return reply({ tools: tools(cfg) })
      case 'tools/call': {
        const p = msg.params || {}
        try { return reply(await call(cfg, sim, p.name, p.arguments)) } catch (e) { return reply(text(String(e.message || e), true)) }
      }
      default:
        if (msg.id === undefined) return // a notification
        return fail(-32601, 'no method ' + msg.method)
    }
  }
}

if (require.main === module) main()
module.exports = { loadConfig, tools, fill, Sim }
