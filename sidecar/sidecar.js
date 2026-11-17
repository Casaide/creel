// Creel net sidecar: finds the other players by a shared key over Hyperswarm and pipes bytes
// between them and the game's own lockstep TCP link on localhost. The game's net code is unchanged.
//
//   bare sidecar.js host --game-port 47816          prints "code abcde-fghij", then for every peer
//                                                   that joins, dials the game's host port and pipes.
//   bare sidecar.js join <code> --port 47817         listens on 127.0.0.1:47817 (0: any free port); the
//                                                   game does net_join("127.0.0.1", port), piped to the host.
//
// The join code is 10 z32 characters (50 random bits); the topic is a hash of it, so the code is all
// players share. Plenty for casual matches: it can't be guessed, and the game checks versions on join.
//
// Lines tell the game what happens: "code <code>", "announced", "listening <port>", "peer <pubkey>",
// "closed <pubkey>", "error <text>". They go to stdout, or appended to --out <file>.
// Lobster's launch_subprocess waits for the process to end, so the game starts this in the
// background (sh -c '... &') and reads --out. --watch <pid>: exit once that process (the game) is
// gone. Without --watch it exits when stdin closes.
// --bootstrap host:port,... points at a test DHT instead of the public one.

const Hyperswarm = require('hyperswarm')
const DHT = require('hyperdht')
const crypto = require('hypercore-crypto')
const z32 = require('z32')
const b4a = require('b4a')
const tcp = require('bare-tcp')
const process = require('bare-process')
const os = require('bare-os')
const fs = require('bare-fs')

const args = process.argv.slice(2)
const mode = args[0]
const opt = (name, def) => {
  const i = args.indexOf('--' + name)
  return i === -1 ? def : args[i + 1]
}

const bootstrap = opt('bootstrap', null)
// (a test DHT runs on 127.0.0.1, so bind there too)
const swarm = new Hyperswarm(bootstrap
  ? { dht: new DHT({ bootstrap: bootstrap.split(',').map(parseHost), host: '127.0.0.1' }) }
  : {})

const CODE_CHARS = 'ybndrfg8ejkmcpqxot1uwisza345h769' // (z32: no 0/l/v/2, easy to read out)
const CODE_LEN = 10

function newCode () {
  const bytes = crypto.randomBytes(CODE_LEN)
  let code = ''
  for (const b of bytes) code += CODE_CHARS[b & 31]
  return code
}

// What a player typed: any case, dashes and spaces ignored. Null if it isn't a code.
function readCode (s) {
  const code = String(s).toLowerCase().replace(/[\s-]/g, '')
  if (code.length !== CODE_LEN) return null
  for (const c of code) if (!CODE_CHARS.includes(c)) return null
  return code
}

function showCode (code) { return code.slice(0, 5) + '-' + code.slice(5) }

function topicOf (code) { return crypto.hash(b4a.from('creel/join/1/' + code)) }

function parseHost (s) {
  const [host, port] = s.split(':')
  return { host, port: Number(port) }
}

const out = opt('out', null)
if (out) fs.writeFileSync(out, '')
function say (line) {
  if (out) fs.appendFileSync(out, line + '\n')
  else process.stdout.write(line + '\n')
}

function quit () {
  if (out) try { fs.unlinkSync(out) } catch {}
  swarm.destroy().then(() => process.exit(0))
}

function pipe (a, b) {
  a.pipe(b).on('error', () => {})
  b.pipe(a).on('error', () => {})
  const end = () => { a.destroy(); b.destroy() }
  a.on('close', end)
  b.on('close', end)
}

async function host () {
  const gamePort = Number(opt('game-port', 47816))
  const code = opt('code') ? readCode(opt('code')) : newCode()
  if (!code) throw new Error('not a join code: ' + opt('code'))
  const topic = topicOf(code)
  swarm.on('connection', (peer) => {
    const id = z32.encode(peer.remotePublicKey)
    say('peer ' + id)
    const game = tcp.createConnection(gamePort, '127.0.0.1', { noDelay: true })
    pipe(peer, game)
    peer.on('close', () => say('closed ' + id))
  })
  // The code is known at once, so show it now; the first announce on the public DHT can take
  // 20 s or more, and "announced" says when a joiner can surely find us.
  say('code ' + showCode(code))
  await swarm.join(topic, { server: true, client: false }).flushed()
  say('announced')
}

async function join () {
  const code = readCode(args[1] || '')
  if (!code) throw new Error('not a join code: ' + args[1])
  const topic = topicOf(code)
  const port = Number(opt('port', 47817))
  let peer = null
  let waiting = null
  swarm.on('connection', (p) => {
    if (peer) return p.destroy() // one host per key
    peer = p
    const id = z32.encode(p.remotePublicKey)
    say('peer ' + id)
    p.on('close', () => say('closed ' + id))
    if (waiting) { pipe(waiting, peer); waiting = null }
  })
  const server = tcp.createServer({ noDelay: true }, (game) => {
    if (peer) pipe(game, peer)
    else waiting = game
  })
  server.listen(port, '127.0.0.1', () => say('listening ' + server.address().port))
  swarm.join(topic, { server: false, client: true })
}

const watch = Number(opt('watch', 0))
if (watch) {
  setInterval(() => {
    try { os.kill(watch, 0) } catch { quit() }
  }, 1000)
} else {
  process.stdin.on('end', quit)
  process.stdin.resume()
}

if (mode === 'host') host().catch((e) => say('error ' + e.message))
else if (mode === 'join') join().catch((e) => say('error ' + e.message))
else { say('error usage: host [--game-port n] | join <code> [--port n]'); process.exit(1) }
