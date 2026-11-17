# Online play sidecar (spike)

Spike for [age-of-whatever#44](https://github.com/Casaide/age-of-whatever/issues/44): players find each other with a shared Hyperswarm key, with no lobby and no server of ours.

`sidecar.js` is a small Bare program. It joins a Hyperswarm topic and pipes bytes between the other players and the game's existing lockstep TCP link on localhost, so Creel's `src/net/lockstep.lobster` and Lobster itself are unchanged.

```
bare sidecar.js host [--game-port 47816]   prints "key <z32>"; for every peer that joins,
                                           dials the game's host port and pipes
bare sidecar.js join <key> [--port 47817]  listens on 127.0.0.1:<port>; the game does
                                           net_join("127.0.0.1", <port>)
  --out <file>     status lines go to this file instead of stdout
  --watch <pid>    exit once that process (the game) is gone
  --bootstrap h:p  use a test DHT instead of the public one
```

Status lines: `key <z32>`, `announced`, `listening <port>`, `peer <pubkey>`, `closed <pubkey>`, `error <text>`.

## What the spike showed

Run in a Linux cloud container on 2026-11-17, with Lobster built headless from `Drache93/lobster` `game` (90bd1c1).

- **`test/pipe_check.sh`** (`npm test`): two sidecars find each other by key on a local test DHT, and bytes go both ways. Passes.
- **`test/swarm_check.sh`**: the game's own `net_check.lobster`, a real headless lockstep match, with the host and the joiners only connected through sidecars and the key. 2 players over 2000 ticks and 3 players over 4000 ticks both finish with the same final hash on every side and no desync. The only thing that changes is that each joiner is given `port:<its sidecar's port>`. The 3-player run shows that the host's star (`ls.more`) works through the sidecar too: each peer becomes its own connection to the host's door.
- **Nagle matters.** Without `noDelay` on the sidecar's localhost sockets, the 3-player 4000-tick run took 11.7 s instead of 1.2 s (0.86 s for direct TCP). With `noDelay` the sidecar adds very little.
- **`test/launch_check.lobster`**: Lobster starts the sidecar with the existing `launch_subprocess`, reads the key from the `--out` file within 0.25 s, and the sidecar exits within a second of the game exiting (`--watch $PPID`). Two catches:
  - `launch_subprocess` waits for the process to end, so the sidecar has to be started in the background with `/bin/sh -c '... &'`. A bare `sh` without a path fails (-1).
  - The child keeps the game's stdout and stderr pipes open (subprocess.h doesn't close the parent's pipe ends), so `launch_subprocess` never returns. The command closes fds 3 to 9 first (`exec 3<&- ...`). This works on Linux and macOS. Windows would need something else.
- **Public DHT:** a host sidecar in the container announced on the real DHT, but the first `flushed()` took about 24 s. The key is printed straight away now, and `announced` follows later. A join from inside the same container didn't connect, which is likely the sandbox's networking (even local UDP between non-loopback sockets fails here). **The real test is Mac to Deck.**

## Size

`bare` is about 52 MB per platform (it includes V8). The npm packages bring prebuilds for every platform, so `node_modules` is about 100 MB, but the native addons for one platform are about 3.5 MB (sodium-native 1.9 MB, udx-native 0.4 MB, the rest small). A shipped build would be `bare` plus a `bare-pack` bundle plus one platform's prebuilds, so about 56 MB. The game doesn't load Bare until the player picks online play, so it doesn't affect start-up time.

After `npm install` the `bare` binary in `bare-runtime-<platform>` had lost its exec bit here (`chmod +x` fixed it). Worth checking on the Mac.

## Sidecar or embed libbare in Lobster?

Bare can be embedded: `libbare` is a C library (`bare_setup`, `bare_load`, `bare_run`), and `bare-kit` wraps it for iOS and Android as a worklet with an IPC pipe.

**Embedding** would mean new Lobster natives, roughly `bare.start(bundle) -> resource`, `bare.send(r, bytes)`, `bare.receive(r) -> bytes`, run on their own thread with libuv. Lobster's build would then link V8, libuv and libjs on every platform.

- For: one process with no orphaned sidecars, no localhost port or token, and no shell tricks. **iOS doesn't allow spawning processes**, so mobile has to embed anyway (bare-kit). One native API for every platform would be the clean end state.
- Against: it is a Lobster change, so it needs an `upstream-lobster` issue, and either aardappel takes a V8 dependency upstream or we carry it in the fork. It makes Lobster's build much heavier on every target, including the web build, where Bare can't run. It also does nothing for latency or for getting through NAT, because the bytes and the swarm are the same either way.

**Recommendation:** keep the sidecar for desktop and Deck now. It works with no Lobster change, which the headless runs above show. Keep the game's side a plain byte stream (it already is: `net_join` to localhost) so the transport can change later without touching lockstep. Do the embed when mobile comes, as a Lobster `bare` module behind a build flag (off for web), raised upstream first. If it turns out clean, desktop can move to it too and the sidecar goes away.

## Not done in the spike

- Menu flow in the game: host, show the key, join by key, `waiting for player`.
- Packaging `bare` and the bundle into `make mac` and `make deck`.
- Mac to Deck on the same Wi-Fi, then over a phone hotspot (the real holepunch test).
- A localhost token: the join side listens on 127.0.0.1 only, which is fine for a spike.
- Windows launch (no `sh`).
