#!/bin/sh
# Two sidecars on a local test DHT find each other by key; a stand-in host game echoes what the
# joiner's game sends. Needs node (for the test DHT) and `npm install` in sidecar/.
set -e
cd "$(dirname "$0")/.."
BARE="${BARE:-$(node -p "require('bare-runtime')()")}"
logs=$(mktemp -d)
cleanup() { kill $TN $FG $SH $SJ 2>/dev/null; rm -rf "$logs"; }
trap cleanup EXIT
node test/testnet.js > $logs/bs & TN=$!
node -e "require('net').createServer(s => s.on('data', d => s.write('host:' + d))).listen(47816, '127.0.0.1')" & FG=$!
while [ ! -s $logs/bs ]; do sleep 0.1; done
BS=$(cat $logs/bs)
"$BARE" sidecar.js host --game-port 47816 --bootstrap $BS --watch $$ --out $logs/host & SH=$!
while ! grep -q '^code' $logs/host 2>/dev/null; do sleep 0.1; done
CODE=$(awk '/^code/{print $2}' $logs/host)
"$BARE" sidecar.js join $CODE --port 47817 --bootstrap $BS --watch $$ --out $logs/join & SJ=$!
while ! grep -q '^listening' $logs/join 2>/dev/null; do sleep 0.1; done
node -e "
const s = require('net').connect(47817, '127.0.0.1', () => s.write('hello'))
s.on('data', d => { if (String(d) !== 'host:hello') { console.log('FAILED: got', String(d)); process.exit(1) } console.log('pipe_check: ok'); process.exit(0) })
setTimeout(() => { console.log('FAILED: no answer'); process.exit(1) }, 10000)"
