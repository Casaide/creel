// ------------------------------------------------------------------ finding a match on the home network (src/net/lan.gd)
// Godot's host broadcasts a UDP beacon; this Lobster build has TCP only, so a joiner asks instead: it
// tries every address of its own /24 (and this machine) on the game's port at once, and each host that
// answers says who it is ('?' -> 'I': its name, version, map). A host keeps listening through that; only
// a 'J' (join, with the joiner's version) becomes its match, and builds that would part ways refuse to
// play (the version: the protocol and every data file the sim reads, hashed).

let NET_PROTOCOL = 1

class LanHost:
    ip:string
    name:string
    version:string
    map:string

var net_version_cache = ""

def lan_files(dir:string) -> [string]:
    let names, sizes = scan_folder(dir, true)
    if not names or not sizes: return []
    let out = []::string
    for(names) n, k:
        if sizes[k] >= 0 and ends_with(n, ".json"): out.push(n)
    return sorted_strs(out)

// Data files only the looks and sounds read: two builds that differ in them still play together.
let net_look_only = [ "atmosphere.json", "audio.json", "tips.json", "ui.json" ]

// This build's network version: the protocol and every data file the sim reads (sorted), hashed. A file's
// name goes in relative to the data folder, so where the game is installed doesn't matter.
def net_version() -> string:
    if net_version_cache != "": return net_version_cache
    var all = "aow-net-{NET_PROTOCOL}"
    for([ "", "rules/", "maps/" ]) sub:
        let dir = lib_root + "/" + sub
        for(lan_files(dir)) f:
            if sub != "" or not has_s(net_look_only, f):
                all += sub + f
                all += read_file(dir + f) or ""
    net_version_cache = substring(sha256_text(all), 0, 12)
    return net_version_cache

// A system tool's command line, run through sh: launch_subprocess doesn't search PATH (a bare "ip" never ran),
// and an app started from the Finder or Steam may lack the sbin folders (macOS's ipconfig is in /usr/sbin).
def tool_command(line:string) -> [string]:
    return [ "/bin/sh", "-c", "PATH=\"$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\"; " + line + " 2>/dev/null" ]

// The first IPv4 address in a tool's output that isn't this machine's loopback ("192.168.0.3", "inet 10.0.0.7/24 ..."), or "".
def ipv4_in(out:string) -> string:
    for(tokenize(out, " \n\t", "")) t:
        let a = if find_string(t, "/") >= 0: substring(t, 0, find_string(t, "/")) else: t  // (ip's 192.168.0.5/24)
        let parts = tokenize(a, ".", "")
        if parts.length == 4 and not starts_with(a, "127."):
            var ok = true
            for(parts) p:
                if not p.length or p.length > 3 or string_to_int(p) > 255: ok = false
                for(p) c: if c < '0' or c > '9': ok = false
            if ok: return a
    return ""

// This machine's address on the home network (macOS, then Linux / the Deck), or "" if none. (SteamOS's
// hostname has no -I, so the Deck asks ip; hostname -I stays for other Linuxes without ip.)
def my_ipv4() -> string:
    for([ "ipconfig getifaddr en0", "ipconfig getifaddr en1", "ip -4 -o addr show scope global", "hostname -I" ]) cmd:
        let code, out = launch_subprocess(tool_command(cmd))
        if code == 0 and out:
            let a = ipv4_in(out)
            if a != "": return a
    return ""

// Ask every address nearby; the hosts that answered within `seconds`. (Blocks: a lobby button.)
def lan_scan(seconds:float) -> [LanHost]:
    let me = my_ipv4()
    let ips = [ "127.0.0.1" ]
    if me != "":
        let parts = tokenize(me, ".", "")
        for(254) n:
            let ip = "{parts[0]}.{parts[1]}.{parts[2]}.{n + 1}"
            if ip != me: ips.push(ip)
    // In batches (each socket is a file; a whole /24 at once runs a Mac out of them), each its share of the time.
    let found = []::LanHost
    let batch = 48
    let per = seconds / float((ips.length + batch - 1) / batch)
    var at = 0
    while at < ips.length:
        let these = ips.slice(at, min(batch, ips.length - at))
        var links = map(these) ip: net_join(ip, NET_PORT)
        let asked = map(these): false
        let t0 = seconds_elapsed()
        while seconds_elapsed() - t0 < per:
            for(links) l, k:
                if l.error == "" and not l.closed:
                    if net_ready(l) and not asked[k]:
                        net_send(l, '?', "")
                        asked[k] = true
                    for(net_poll(l)) f:
                        if f[0] == "I":
                            let p = tokenize(f[1], "|", "")
                            if p.length >= 3: found.push(LanHost { these[k], p[0], p[1], p[2] })
                            l.closed = true
            tcp.wait(nil, nil, false, 0.01)
        for(links) l: l.sock = nil  // (closed now, not when they're collected)
        links = []
        at += batch
    return found

// The packs in use, as a hello carries them, and what's wrong if a joiner's differ from ours.
def net_packs() -> string: return concat_string(lib_mods, ",")

def packs_differ(theirs:string) -> string:
    let them = if theirs == "": []::string else: tokenize(theirs, ",", "")
    for(lib_mods) sig:
        if not has_s(them, sig): return "this host plays with the mod {sig_id(sig)} ({sig}), and you don\'t"
    for(them) sig:
        if not has_s(lib_mods, sig): return "you\'re playing with the mod {sig_id(sig)} ({sig}), and this host isn\'t"
    return ""

// The host's door: accept whoever knocks; answer a '?' and let it go; a 'J' with our version becomes the
// match's link (true once there is one). A 'J' from another version gets an 'X' with why.
class HostDoor:
    listener:resource<tcplistener>? = nil
    knocking = []::Link
    name = ""
    map = ""
    error = ""

def door_open(port:int, name:string, map_id:string) -> HostDoor:
    let l, err = tcp.listen("0.0.0.0", port)
    let d = HostDoor {}
    d.listener = l
    d.name = name
    d.map = map_id
    if err: d.error = err
    return d

def door_tick(d:HostDoor) -> Link?:
    let l = d.listener
    if not l: return nil
    while true:
        let s, err = tcp.accept(l)
        if err: d.error = err
        if not s: break
        let k = Link {}
        k.sock = s
        k.connected = true
        d.knocking.push(k)
    var joined:Link? = nil
    for(d.knocking) k:
        if not k.closed:
            for(net_poll(k)) f:
                if f[0] == "?":
                    net_send(k, 'I', "{d.name}|{net_version()}|{d.map}")
                    k.closed = true
                elif f[0] == "J":
                    let hello = tokenize(f[1], "|", "")
                    let why = if hello[0] != net_version(): "this host plays another build of the game ({net_version()}, yours {hello[0]})" else: packs_differ(if hello.length > 1: hello[1] else: "")
                    if why == "": joined = k
                    else:
                        net_send(k, 'X', why)
                        k.closed = true
    d.knocking = filter(d.knocking) k: not k.closed and (not joined or k != joined)
    return joined

// The joiner's side: once connected, say who's joining (with our version).
def join_hello(link:Link): net_send(link, 'J', net_version() + "|" + net_packs())
