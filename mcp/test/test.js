// Drives creel-mcp.js over stdio against examples/plain's sim side (examples/plain/src/mcp_server.lobster), as an agent
// would: initialize, list the tools, call them. Run by check.sh: LOBSTER=<lobster> node mcp/test/test.js
'use strict'
const path = require('path')
const { spawn } = require('child_process')

const root = path.resolve(__dirname, '../..')
const proc = spawn(process.execPath, [path.join(root, 'mcp/creel-mcp.js'), path.join(root, 'examples/plain/creel-mcp.json')], { stdio: ['pipe', 'pipe', 'inherit'] })
let buf = ''
const waiting = new Map()
proc.stdout.on('data', d => {
  buf += d
  let n
  while ((n = buf.indexOf('\n')) >= 0) {
    const m = JSON.parse(buf.slice(0, n))
    buf = buf.slice(n + 1)
    const w = waiting.get(m.id)
    if (w) { waiting.delete(m.id); w(m) }
  }
})
let next = 1
function rpc (method, params) {
  const id = next++
  proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n')
  return new Promise(resolve => waiting.set(id, resolve))
}
const tool = async (name, args) => (await rpc('tools/call', { name, arguments: args })).result

let passed = 0
let failed = 0
function check (ok, what) {
  if (ok) passed++
  else { failed++; console.log('FAIL: ' + what) }
}
const body = r => { try { return JSON.parse(r.content[0].text) } catch (e) { return r.content[0].text } }

async function main () {
  const { fill } = require('../creel-mcp.js')
  const f = fill(['{lobster}', 'mods:{start.mods}', 'map:{start.map}', 'shot:{png}'], { lobster: 'L', png: 'p.png' }, { mods: ['a', 'b'] })
  check(JSON.stringify(f) === JSON.stringify(['L', 'mods:a,b', 'shot:p.png']), 'capture commands: start args filled, a missing one left out (' + JSON.stringify(f) + ')')

  const init = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test', version: '0' } })
  check(init.result && init.result.capabilities.tools, 'initialize offers tools')
  proc.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n')
  const list = (await rpc('tools/list', {})).result.tools.map(t => t.name)
  for (const n of ['creel_start', 'creel_step', 'creel_state', 'creel_units', 'creel_buildings', 'creel_order', 'creel_save', 'creel_invariants', 'creel_events', 'creel_pack_tests', 'creel_run_tests']) check(list.includes(n), 'tools/list has ' + n)
  check(!list.includes('creel_capture'), 'no capture tool without a capture command')

  const st = await tool('creel_state', {})
  check(!st.isError && body(st).tick === 0 && body(st).started === false, 'state before a match: tick 0, not started (' + JSON.stringify(st) + ')')
  const names = body(await tool('creel_names', {}))
  check(names.commands[0] === 'move' && names.commands[27] === 'demolish' && names.tile === 1000, 'names: the order names and the tile')
  const early = await tool('creel_step', { ticks: 5 })
  check(early.isError && /start one first/.test(body(early)), 'step before start is refused')
  const pt = await tool('creel_pack_tests', { pack: 'nope' })
  check(pt.isError && /no pack "nope"/.test(body(pt)), 'a pack that isn\'t there has no tests to run')
  const inv = await tool('creel_invariants', {})
  check(inv.isError && /start one first/.test(body(inv)), 'invariants before start is refused')
  const evs = await tool('creel_events', {})
  check(evs.isError && /start one first/.test(body(evs)), 'events before start is refused')
  check(names.events[10] === 'pick' && names.events[19] === 'put', 'names: the event kinds')
  const start = await tool('creel_start', { args: { note: 'x'.repeat(3000) } })
  check(start.isError && /no data/.test(body(start)), 'start reaches the game\'s mcp_start, through a request longer than a line (' + JSON.stringify(start) + ')')
  const bad = await tool('creel_save', { name: '../escape' })
  check(bad.isError && /letters, digits/.test(body(bad)), 'save names can\'t leave the scratch folder')
  const none = await rpc('tools/call', { name: 'creel_run_tests', arguments: { suite: 'rm -rf' } })
  check(none.result.isError, 'only configured suites run')
  const t = await tool('creel_run_tests', { suite: 'edge_scroll' })
  check(!t.isError && body(t).passed && /0 failed/.test(body(t).tail), 'a configured suite runs and passes (' + JSON.stringify(t).slice(0, 300) + ')')
  const badStep = await tool('creel_step', { ticks: 'many' })
  check(badStep.isError && /ticks should be a whole number/.test(body(badStep)), 'a field of the wrong type is an error (' + JSON.stringify(badStep) + ')')
  const after = await tool('creel_state', {})
  check(!after.isError, 'and the sim side goes on (' + JSON.stringify(after) + ')')
  const packs = await tool('creel_pack_tests', { pack: 'only_in_args', args: { mods: ['only_in_args'] } })
  check(packs.isError && /no data/.test(body(packs)), 'pack tests start a match from their args to find a pack they name (' + JSON.stringify(packs) + ')')
  const unknown = await rpc('no/such', {})
  check(unknown.error && unknown.error.code === -32601, 'an unknown method is an error')

  // The runner (#195): examples/plain's start refuses, so the whole run says so; then a stand-in sim for the rest
  const { spawnSync } = require('child_process')
  const os = require('os')
  const fs = require('fs')
  const script = path.join(os.tmpdir(), 'creel-run-test.json')
  fs.writeFileSync(script, JSON.stringify({ steps: [{ step: 10 }] }))
  const ran = spawnSync(process.execPath, [path.join(root, 'mcp/creel-run.js'), path.join(root, 'examples/plain/creel-mcp.json'), script], { encoding: 'utf8' })
  let doc = {}
  try { doc = JSON.parse(ran.stdout) } catch (e) {}
  check(ran.status === 1 && doc.ok === false && /no data/.test(doc.error), 'the runner runs the game\'s sim side and says why a run failed (' + ran.stdout.slice(0, 300) + ')')
  const { runScript } = require('../creel-run.js')
  const fake = (breakAt, eventAt) => {
    let tick = 0
    const asked = []
    return {
      asked,
      request: async (cmd, q) => {
        asked.push(cmd + (q.ticks ? ':' + q.ticks : ''))
        if (cmd === 'step') {
          let ev = null
          let broken = ''
          for (let n = 0; n < q.ticks; n++) {
            tick++
            if (tick === breakAt) { broken = 'solid: units 1 and 2'; break }
            if (q.until && tick === eventAt) { ev = { kind: 'built', tick }; break }
          }
          return { ok: true, result: { tick, hash: tick * 7, broken, event: q.until ? ev : undefined } }
        }
        if (cmd === 'units') return { ok: true, result: { total: 1, units: [{ id: 1 }] } }
        return { ok: true, result: { tick, hash: tick * 7 } }
      }
    }
  }
  const cfg = { scratch: os.tmpdir() }
  let sim = fake()
  let r = await runScript(cfg, sim, { start: {}, steps: [{ step: 75 }, { units: {} }] })
  check(r.ok && r.tick === 75 && JSON.stringify(r.hashes) === '[[0,0],[30,210],[60,420]]' && r.steps[1].total === 1, 'the runner steps, keeps the hash every 30 ticks and asks (' + JSON.stringify(r) + ')')
  check(sim.asked.join(' ') === 'start step:30 step:30 step:15 units state', 'in steps that end on the hash ticks (' + sim.asked.join(' ') + ')')
  r = await runScript(cfg, fake(), { start: {}, steps: [{ step: 20 }, { units: {} }, { step: 20 }] })
  check(r.ok && r.tick === 40 && JSON.stringify(r.hashes) === '[[0,0],[30,210]]', 'a step after a query goes on from the tick the match is at (' + JSON.stringify(r) + ')')
  r = await runScript(cfg, fake(40), { start: {}, steps: [{ step: 100 }, { units: {} }] })
  check(!r.ok && /tick 40: solid/.test(r.error) && r.steps.length === 1, 'it stops on a broken invariant (' + r.error + ')')
  r = await runScript(cfg, fake(0, 50), { start: {}, steps: [{ step: 100, until: { kinds: ['built'] } }, { step: 5 }] })
  check(r.ok && r.steps[0].tick === 50 && r.tick === 55, 'a step with until stops on its event (' + JSON.stringify(r.steps) + ')')
  r = await runScript(cfg, fake(), { start: {}, steps: [{ step: 10, until: { kinds: ['built'] } }] })
  check(!r.ok && /no event like/.test(r.error), 'and fails if it never comes')
  r = await runScript(cfg, fake(), { start: {}, steps: [{ fly: 1 }] })
  check(!r.ok && /no "fly"/.test(r.error) && r.failed_step === 0, 'a step it doesn\'t know is an error')
  r = await runScript(cfg, fake(), { start: {}, steps: [{ save: '../x' }] })
  check(!r.ok && /letters, digits/.test(r.error), 'save names stay in the scratch folder')

  proc.stdin.end()
  console.log('test_mcp: ' + passed + ' passed, ' + failed + ' failed')
  process.exit(failed ? 1 : 0)
}
main().catch(e => { console.log('test_mcp: ' + e.stack); process.exit(1) })
