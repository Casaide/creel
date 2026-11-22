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
  for (const n of ['creel_start', 'creel_step', 'creel_state', 'creel_units', 'creel_buildings', 'creel_order', 'creel_save', 'creel_invariants', 'creel_run_tests']) check(list.includes(n), 'tools/list has ' + n)
  check(!list.includes('creel_capture'), 'no capture tool without a capture command')

  const st = await tool('creel_state', {})
  check(!st.isError && body(st).tick === 0 && body(st).started === false, 'state before a match: tick 0, not started (' + JSON.stringify(st) + ')')
  const names = body(await tool('creel_names', {}))
  check(names.commands[0] === 'move' && names.commands[27] === 'demolish' && names.tile === 1000, 'names: the order names and the tile')
  const early = await tool('creel_step', { ticks: 5 })
  check(early.isError && /start one first/.test(body(early)), 'step before start is refused')
  const inv = await tool('creel_invariants', {})
  check(inv.isError && /start one first/.test(body(inv)), 'invariants before start is refused')
  const start = await tool('creel_start', { args: { note: 'x'.repeat(3000) } })
  check(start.isError && /no data/.test(body(start)), 'start reaches the game\'s mcp_start, through a request longer than a line (' + JSON.stringify(start) + ')')
  const bad = await tool('creel_save', { name: '../escape' })
  check(bad.isError && /letters, digits/.test(body(bad)), 'save names can\'t leave the scratch folder')
  const none = await rpc('tools/call', { name: 'creel_run_tests', arguments: { suite: 'rm -rf' } })
  check(none.result.isError, 'only configured suites run')
  const t = await tool('creel_run_tests', { suite: 'edge_scroll' })
  check(!t.isError && body(t).passed && /0 failed/.test(body(t).tail), 'a configured suite runs and passes (' + JSON.stringify(t).slice(0, 300) + ')')
  const unknown = await rpc('no/such', {})
  check(unknown.error && unknown.error.code === -32601, 'an unknown method is an error')

  proc.stdin.end()
  console.log('test_mcp: ' + passed + ' passed, ' + failed + ' failed')
  process.exit(failed ? 1 : 0)
}
main().catch(e => { console.log('test_mcp: ' + e.stack); process.exit(1) })
