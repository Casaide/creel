#!/usr/bin/env node
// Creel's headless runner (#195): the MCP's sim side (src/mcp/serve.lobster) driven by a script instead of an agent, for
// scripts and CI. It runs a game's match from its start args (or a save), steps it, gives orders, asks what's there, and
// prints one JSON document: every step's result, the hash every `hash_every` ticks, and whether it all held.
//
//   node creel/mcp/creel-run.js <creel-mcp.json> <script.json> [out.json]
//
// The script (mcp/README.md, "The runner"):
//   { "start": { <the game's start args> }, "load": "<a save's name, to resume it: optional>",
//     "hash_every": 30, "invariants": true, "stuck_limit": 0,
//     "steps": [ { "step": 600, "until": { "kinds": ["built"] } }, { "order": { ... } }, { "units": { "owner": 0 } },
//                { "buildings": {} }, { "players": {} }, { "cell": { "cx": 3, "cy": 4 } }, { "events": { "kinds": ["drop"] } },
//                { "invariants": {} }, { "state": {} }, { "names": {} }, { "save": "<name>" }, { "load": "<name>" } ] }
// It stops at the first step that fails, the first invariant that breaks (with "invariants") or an `until` that never
// came; the exit code is 0 only when every step held.
'use strict'
const fs = require('fs')
const path = require('path')
const { loadConfig, Sim } = require('./creel-mcp.js')

const NAME_RE = /^[A-Za-z0-9_-]{1,64}$/
const STEP_MAX = 72000 // serve.lobster's MCP_MAX_STEP: an hour of ticks a request
const QUERIES = ['units', 'buildings', 'players', 'cell', 'events', 'invariants', 'state', 'names', 'order']

async function runScript (cfg, sim, script) {
  const out = { ok: true, start: null, steps: [], hashes: [] }
  const hashEvery = script.hash_every === undefined ? 30 : script.hash_every
  const checked = script.invariants === undefined ? true : !!script.invariants
  const savePath = n => {
    if (!NAME_RE.test(n || '')) throw new Error('a save name is letters, digits, - and _ only')
    return path.join(cfg.scratch, n + '.save')
  }
  const fail = (why, at) => { out.ok = false; out.error = why; if (at !== undefined) out.failed_step = at; return out }
  const ask = async (cmd, fields) => {
    const r = await sim.request(cmd, fields)
    if (!r.ok) throw new Error(cmd + ': ' + r.error)
    return r.result
  }
  const noteHash = s => {
    if (hashEvery > 0 && s.tick % hashEvery === 0 && !out.hashes.some(h => h[0] === s.tick)) out.hashes.push([s.tick, s.hash])
  }

  try {
    out.start = await ask('start', { args: script.start || {} })
    if (script.load) out.start = await ask('load', { path: savePath(script.load) })  // (a match from the same args first: the sim side loads into one)
  } catch (e) { return fail(e.message) }
  noteHash(out.start)

  for (let j = 0; j < (script.steps || []).length; j++) {
    const st = script.steps[j]
    const what = Object.keys(st).filter(k => k !== 'until')
    if (what.length !== 1) return fail('step ' + j + ' must name one thing to do: ' + JSON.stringify(st), j)
    const op = what[0]
    try {
      if (op === 'step') {
        let left = st.step
        if (!Number.isInteger(left) || left < 1) return fail('step ' + j + ': a whole number of ticks, 1 or more', j)
        let s = null
        while (left > 0) {
          const tick = s ? s.tick : (out.steps.length ? out.steps[out.steps.length - 1].tick : out.start.tick)
          let n = Math.min(left, STEP_MAX)
          if (hashEvery > 0) n = Math.min(n, hashEvery - (tick % hashEvery))
          const q = { ticks: n, invariants: checked, stuck_limit: script.stuck_limit || 0 }
          if (st.until) q.until = st.until
          s = await ask('step', q)
          left -= n
          noteHash(s)
          if ((checked && s.broken) || (st.until && s.event)) break
        }
        const r = Object.assign({ step: op }, s)
        out.steps.push(r)
        if (checked && s.broken) return fail('an invariant broke at tick ' + s.tick + ': ' + s.broken, j)
        if (st.until && !s.event) return fail('no event like ' + JSON.stringify(st.until) + ' by tick ' + s.tick, j)
      } else if (op === 'save' || op === 'load') {
        const s = await ask(op, { path: savePath(st[op]) })
        noteHash(s)
        out.steps.push(Object.assign({ step: op }, s))
      } else if (QUERIES.includes(op)) {
        const r = await ask(op, st[op] || {})
        out.steps.push(Object.assign({ step: op }, r))
        if (op === 'invariants' && r.broken) return fail('an invariant is broken: ' + r.broken, j)
      } else {
        return fail('step ' + j + ': no "' + op + '" (step, order, ' + QUERIES.filter(q => q !== 'order').join(', ') + ', save, load)', j)
      }
    } catch (e) { return fail(e.message, j) }
  }
  const last = await ask('state', {})
  out.tick = last.tick
  out.hash = last.hash
  return out
}

async function main () {
  const [cfgFile, scriptFile, outFile] = process.argv.slice(2)
  if (!cfgFile || !scriptFile) {
    process.stderr.write('usage: node creel-run.js <creel-mcp.json> <script.json> [out.json]\n')
    process.exit(2)
  }
  const cfg = loadConfig(cfgFile)
  const script = JSON.parse(fs.readFileSync(scriptFile, 'utf8'))
  const sim = new Sim(cfg, s => process.stderr.write(String(s).replace(/\n?$/, '\n')))
  let out
  try { out = await runScript(cfg, sim, script) } catch (e) { out = { ok: false, error: String(e.message || e) } }
  sim.stop()
  const text = JSON.stringify(out, null, 1) + '\n'
  if (outFile) fs.writeFileSync(outFile, text)
  else process.stdout.write(text)
  process.exit(out.ok ? 0 : 1)
}

if (require.main === module) main()
module.exports = { runScript }
