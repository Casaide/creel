// The game side of starting the sidecar: launch it in the background, wait for its key line.
//   lobster test/launch_check.lobster -- <sidecar dir> <bare binary> <test DHT bootstrap>
// Then the sidecar must be gone within a second or two of this ending (--watch).
import std
let args = command_line_arguments()
let dir = args[0]
let bare = args[1]
let bs = args[2]
let out = dir + "/sidecar.out"
write_file(out, "")  // (not a key left from before)
// (subprocess.h leaves the pipes back to the game open in the child: close them, or the
// sidecar keeps them and launch_subprocess never returns)
let cmd = "exec 3<&- 4<&- 5<&- 6<&- 7<&- 8<&- 9<&-; \"{bare}\" \"{dir}/sidecar.js\" host --game-port 47816 --watch $PPID --out \"{out}\" --bootstrap {bs} > /dev/null 2>&1 &"
let t0 = seconds_elapsed()
let code, text = launch_subprocess([ "/bin/sh", "-c", cmd ], nil)
print "launch returned {code} after {seconds_elapsed() - t0} s"
var key = ""
while key == "" and seconds_elapsed() - t0 < 10.0:
    let got = read_file(out)
    if got:
        for(tokenize(got, "\n", " ")) l:
            if l.length > 4 and l.substring(0, 4) == "key ": key = l.substring(4, l.length - 4)
print "key {key} after {seconds_elapsed() - t0} s"
