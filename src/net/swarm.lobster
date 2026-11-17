// ------------------------------------------------------------------ online play: a join code, through the sidecar
// Players far apart find each other by a short join code over Hyperswarm (creel/sidecar). A small Bare
// program, the sidecar, does that and pipes bytes to this game's own lockstep link on localhost, so
// lockstep.lobster doesn't change: the host's sidecar dials the host's door for every player that
// comes, and a joiner net_joins 127.0.0.1 at its sidecar's port.
// launch_subprocess waits for what it starts to end, so the sidecar goes into the background through
// sh; it writes its status lines to a file this reads ("code ...", "announced", "listening <port>",
// "peer ...", "closed ...", "error ..."), and quits by itself once this game is gone (--watch).

class Swarm:
    pid = ""
    out = ""   // the sidecar's status file
    code = ""  // the host's join code, "abcde-fghij"
    port = 0   // a joiner's sidecar port, once it listens
    announced = false
    peers = 0  // players connected through it now
    error = ""
    seen = 0  // status lines read so far

class SwarmSetup:
    dir = "../creel/sidecar"  // where sidecar.js is (and its node_modules, after npm install)
    bare = ""                 // the bare binary; "": the sidecar's own copy, else bare on the PATH
    extra = ""                // more for the sidecar's command line (tests: "--bootstrap <a local test DHT>")

let swarm_setup = SwarmSetup {}

let JOIN_CODE_CHARS = "ybndrfg8ejkmcpqxot1uwisza345h769"  // (z32, as in sidecar.js)
let JOIN_CODE_LEN = 10

// What a player typed, as a join code ("abcdefghij"): any case, dashes and spaces left out. "" if it isn't one
// (an address, say).
def join_code_in(typed:string) -> string:
    var code = ""
    for(typed.lowercase()) c:
        if c != '-' and c != ' ':
            if find_string(JOIN_CODE_CHARS, unicode_to_string([ c ])) < 0: return ""
            code += unicode_to_string([ c ])
    return if code.length == JOIN_CODE_LEN: code else: ""

def chomp_nl(s:string) -> string: return if s.length and s[s.length - 1] == '\n': substring(s, 0, s.length - 1) else: s

def swarm_start(what:string) -> Swarm:
    let s = Swarm {}
    let bare = if swarm_setup.bare != "": "B=\"{swarm_setup.bare}\"; " else:
        "B=$(ls \"{swarm_setup.dir}\"/node_modules/bare-runtime-*/bin/bare 2>/dev/null | head -n 1); " +
            "[ -n \"$B\" ] && [ ! -x \"$B\" ] && chmod +x \"$B\"; [ -n \"$B\" ] || B=$(command -v bare); "
    // (every fd past 2 is closed first: some are launch_subprocess's pipes back to us, and left open in the
    // sidecar the call never returns; in a game they can be any number, so bash, which takes fds past 9)
    let line = "for f in /dev/fd/*; do n=$\{f##*/\}; [ \"$n\" -gt 2 ] && eval \"exec $n>&-\"; done 2>/dev/null; " + bare +
        "[ -n \"$B\" ] || \{ echo \'error no bare runtime: run npm install in {swarm_setup.dir}\'; exit 1; \}; " +
        "[ -f \"{swarm_setup.dir}/sidecar.js\" ] || \{ echo \'error no sidecar at {swarm_setup.dir}\'; exit 1; \}; " +
        "out=\"$\{TMPDIR:-/tmp\}/creel-swarm-$PPID-$$.txt\"; : > \"$out\"; " +
        "\"$B\" \"{swarm_setup.dir}/sidecar.js\" {what} {swarm_setup.extra} --watch $PPID --out \"$out\" < /dev/null > /dev/null 2>&1 & " +
        "echo \"ok $! $out\""
    let code, said = launch_subprocess([ "/bin/bash", "-c", "PATH=\"$PATH:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin\"; " + line ])
    let words = tokenize(said, " \n", " \n")
    if code != 0 or words.length < 3 or words[0] != "ok":
        s.error = if starts_with(said, "error "): substring(said, 6, said.length - 6).chomp_nl() else: "could not start the sidecar ({code})"
        return s
    s.pid = words[1]
    s.out = words[2]
    return s

// Host: a new join code; every player who comes with it reaches this game's door at game_port.
def swarm_host(game_port:int) -> Swarm: return swarm_start("host --game-port {game_port}")

// Join with a code: the sidecar listens on 127.0.0.1 (port 0: any free one); net_join there once swarm_poll has a port.
def swarm_join(code:string, port:int) -> Swarm: return swarm_start("join {code} --port {port}")

// Take in the sidecar's new status lines.
def swarm_poll(s:Swarm):
    if s.out == "": return
    let all = read_file(s.out)
    if not all: return
    let whole = find_string_reverse(all, "\n")  // (a line still being written waits for the next poll)
    if whole < 0: return
    let got = tokenize(substring(all, 0, whole), "\n", "")
    while s.seen < got.length:
        let l = got[s.seen]
        s.seen++
        if starts_with(l, "code "): s.code = substring(l, 5, l.length - 5)
        elif l == "announced": s.announced = true
        elif starts_with(l, "listening "): s.port = string_to_int(substring(l, 10, l.length - 10))
        elif starts_with(l, "peer "): s.peers++
        elif starts_with(l, "closed "): s.peers = max(0, s.peers - 1)
        elif starts_with(l, "error "): s.error = substring(l, 6, l.length - 6)

def swarm_stop(s:Swarm):
    if s.pid != "": launch_subprocess(tool_command("kill {s.pid}; rm -f \"{s.out}\""))
    s.pid = ""
