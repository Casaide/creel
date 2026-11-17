#!/bin/sh
# The game's net_check (a real lockstep match, headless) over Hyperswarm: the host and the joiners
# only reach each other through sidecars and a shared key, on a local test DHT. Neither the game
# nor Creel nor Lobster is changed: the joiners just net_join 127.0.0.1:<their sidecar's port>.
#   GAME=<age-of-whatever checkout> LOBSTER=<lobster binary> sh test/swarm_check.sh [ticks] [people]
set -e
SC=$(cd "$(dirname "$0")/.." && pwd)
B="${BARE:-$(cd $SC && node -p "require('bare-runtime')()")}"
GAME=${GAME:-$HOME/Dev/age-of-whatever}
ticks=${1:-2000}
people=${2:-2}
logs=$(mktemp -d)
cleanup() { kill $TN 2>/dev/null; pkill -f "$SC/sidecar.js" 2>/dev/null; rm -rf "$logs"; }
trap cleanup EXIT
node $SC/test/testnet.js > $logs/bs & TN=$!
while [ ! -s $logs/bs ]; do sleep 0.1; done
BS=$(cat $logs/bs)
cd $GAME/src
"$LOBSTER" net_check.lobster -- host $ticks port:47816 players:$people > $logs/host 2>&1 & H=$!
(sleep 120 | $B $SC/sidecar.js host --game-port 47816 --bootstrap $BS > $logs/sc_host) &
while ! grep -q '^key' $logs/sc_host 2>/dev/null; do sleep 0.1; done
KEY=$(awk '/^key/{print $2}' $logs/sc_host)
echo "key: $KEY"
n=1
while [ $n -lt $people ]; do
	p=$((47816 + n))
	(sleep 120 | $B $SC/sidecar.js join $KEY --port $p --bootstrap $BS > $logs/sc_join$n) &
	while ! grep -q '^listening' $logs/sc_join$n 2>/dev/null; do sleep 0.1; done
	n=$((n + 1))
done
start=$(date +%s.%N)
n=1
while [ $n -lt $((people - 1)) ]; do
	"$LOBSTER" net_check.lobster -- join $ticks noscan port:$((47816 + n)) players:$people > $logs/join$n 2>&1 &
	J="$J $!"; sleep 1; n=$((n + 1))
done
"$LOBSTER" net_check.lobster -- join $ticks noscan port:$((47816 + n)) players:$people > $logs/join 2>&1 || echo "join FAILED"
for j in $J; do wait $j || echo "a joiner FAILED"; done
wait $H || echo "host FAILED"
end=$(date +%s.%N)
grep -v warning $logs/*
echo "match time: $(echo "$end - $start" | bc) s"
