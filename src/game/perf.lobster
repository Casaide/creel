// ------------------------------------------------------------------ perf:<seconds>: the drawing's cost, in the real window
// A watched match in the window, vsync on and the frame cap as the player has them, measured for that many seconds of
// play after a warm-up: each frame's work (from gl.frame's return to the next call: everything but the swap's wait and
// the cap's sleep), the frames a second, and the GPU buffers each frame made. Above a budget it fails (exit code 1).
// novsync measures with the screen locked (vsync lets no frame through then; the frame cap still paces it). Where the
// work goes is printed too, phase by phase (perf_lap), and the text's share (oldtext: text drawn as before
// game/text_cache.lobster, to measure it against).
// The laptop ran hot (2026-10-31): every gl.text made and deleted a buffer, macOS waited on each delete, and the game
// drew 120 frames a second on a ProMotion display. Headless runs never saw it.

let PERF_WARM = 4.0  // seconds of play first (the armies bake, the first frames build their buffers)
// Measured 2026-10-31 on the MacBook (ProMotion, 3024x1834): 3.3 ms median, 4.6 ms 95th, 0 buffers, 60 a second.
// Before the UI's meshes were drawn from the pool: 13.7 ms, 18.4 ms and 1500 buffers a frame (81% of the main thread).
// 2026-11-03, the sprites on atlas pages and the HUD's fills batched: 1.2 to 2.6 ms median, 1.6 to 6 ms 95th, the main
// thread busy 8 to 16% (the same build twice as slow on some runs: which cores macOS gives it). Budgets above the slow end.
let PERF_WORK_MEDIAN = 0.004  // seconds of work a frame, the median
let PERF_WORK_P95 = 0.008     // and the 95th percentile
let PERF_BUSY_MAX = 0.22      // the main thread's share of the wall clock spent working (not in the swap or the cap's sleep)
let PERF_FPS_MAX = 66.0       // frames a second (the cap is 60: a 120 Hz display uncapped draws twice as often)
let PERF_BUFFERS_P95 = 0      // GPU buffers made a frame, the 95th percentile (pooled: none once the pool is full)
let PERF_TEXT_MAX = 0.0001    // seconds of text a frame (game/text_cache.lobster: labels from atlas pages)
// A big battle (army:) has budgets of its own: 2026-11-06 on the MacBook, 2,000 units in formation on open_field, 7.3 ms median, 11.6 ms 95th, 47% busy, 58.4 fps.
let PERF_BIG_MEDIAN = 0.010
let PERF_BIG_P95 = 0.0166
let PERF_BIG_BUSY = 0.65
let PERF_BIG_BUFFERS = 8  // (a batch past the pool's biggest buffer)
// A building finished (#335): the frame that re-plans and repaints the paths to it. 2026-11-10 on the MacBook, 35 to 48 ms
// (the whole map's path mask rastered, blurred and made into textures again): three frames dropped as the camera moved.
// Painting only the new paths, patched into the textures on the GPU, in a frame that rebuilds neither the ground nor the
// masks: 3.2 ms (the median frame 2.6); in the big battle (160 tiles) 14.5 ms against a median of 9.1 and a 95th of 12.7.
let PERF_BUILT_MAX = 0.008  // seconds of work in that frame, at worst: no worse than the 95th percentile may be
let PERF_BIG_BUILT_MAX = 0.0166

var perf_for = 0.0          // perf:<seconds> (0: off)
var perf_live = false       // perflive: the bakes run as they do in play, nothing baked ahead (what a player sees with a new race)
var perf_units_max = 0      // the most units alive in a frame
var perf_unseen_max = 0     // the most units in view of the fog with no frame to draw (a health bar over nothing)
var perf_unseen = 0         // this frame's
var perf_built_now = false  // this frame re-planned the paths to a building just finished (#335)
var perf_masks_now = false  // and this one rebuilt the terrain masks (left out of it: their own cost)
let perf_built = []::float  // the work of each such frame
var perf_house_put = false
let perf_work = []::float
let perf_made = []::int
var perf_t = -1.0  // the frame's start (after gl.frame)
var perf_b = 0
var perf_wall0 = -1.0  // the measure's start
var perf_text0 = 0.0   // text_time then
// Where a frame's work goes: seconds in each phase over the measure (perf_lap(k) at the end of phase k).
let PERF_PHASES = [ "input and sim", "ground", "collect", "sort", "sprites", "over the world", "panel", "hud", "groups", "rest" ]
let perf_phase = map(PERF_PHASES): 0.0
var perf_last = 0.0

let perf_think = []::float  // each tick: the bots, the sim (seconds)
let perf_step = []::float

def perf_tick(think:float, step:float):
    if perf_for <= 0.0 or perf_wall0 < 0.0: return
    perf_think.push(think)
    perf_step.push(step)

def perf_sorted_at(xs, q:float):
    let s = copy(xs)
    qsort_in_place(s) a, b: a < b
    return s[min(s.length - 1, int(float(s.length) * q))]

// At the top of a frame: its start.
def perf_begin():
    perf_built_now = false
    perf_masks_now = false
    perf_t = seconds_elapsed()
    perf_last = perf_t
    perf_b = gl.buffers_made()

// The end of phase k of a frame's work.
def perf_lap(k:int):
    if perf_for <= 0.0 or perf_wall0 < 0.0: return
    let t = seconds_elapsed()
    perf_phase[k] += t - perf_last
    perf_last = t

// At the end of a frame (clock: seconds of play): its work kept; true once the measure is done (then quit).
def perf_end(clock:float, big:bool) -> bool:
    if clock < PERF_WARM or perf_t < 0.0: return false
    if perf_wall0 < 0.0:
        perf_wall0 = perf_t
        perf_text0 = text_time
    perf_work.push(seconds_elapsed() - perf_t)
    perf_units_max = max(perf_units_max, u_x.length)
    perf_unseen_max = max(perf_unseen_max, perf_unseen)
    perf_made.push(gl.buffers_made() - perf_b)
    if perf_built_now and not perf_masks_now: perf_built.push(perf_work[perf_work.length - 1])
    if clock < PERF_WARM + perf_for: return false
    let wall = seconds_elapsed() - perf_wall0
    let fps = float(perf_work.length) / wall
    let med = perf_sorted_at(perf_work, 0.5)
    let p95 = perf_sorted_at(perf_work, 0.95)
    let bmed = perf_sorted_at(perf_made, 0.5)
    let b95 = perf_sorted_at(perf_made, 0.95)
    let busy = sum(perf_work) / wall
    let text = (text_time - perf_text0) / float(perf_work.length)
    def tenths(x:float): return float(int(x * 10.0 + 0.5)) / 10.0
    let stats = "{tenths(fps)} fps, work {tenths(med * 1000.0)} ms median, {tenths(p95 * 1000.0)} ms 95th, buffers {bmed} / {b95}, busy {int(busy * 100.0)}%, text {tenths(text * 10000.0) / 10.0} ms; {perf_work.length} frames, {sum(perf_made)} buffers in all"
    let bad = []::string
    let budget_med = if big: PERF_BIG_MEDIAN else: PERF_WORK_MEDIAN
    let budget_p95 = if big: PERF_BIG_P95 else: PERF_WORK_P95
    let budget_busy = if big: PERF_BIG_BUSY else: PERF_BUSY_MAX
    let budget_buffers = if big: PERF_BIG_BUFFERS else: PERF_BUFFERS_P95
    if med > budget_med: bad.push("work median over {budget_med * 1000.0} ms")
    if p95 > budget_p95: bad.push("work 95th over {budget_p95 * 1000.0} ms")
    if busy > budget_busy: bad.push("the main thread busy {int(busy * 100.0)}%, over {int(budget_busy * 100.0)}%")
    if fps > PERF_FPS_MAX: bad.push("{fps} frames a second, over {PERF_FPS_MAX} (the frame cap?)")
    if text > PERF_TEXT_MAX: bad.push("text {text * 1000.0} ms a frame, over {PERF_TEXT_MAX * 1000.0} ms")
    if perf_unseen_max > 0: bad.push("{perf_unseen_max} units with nothing to draw (#170)")
    if b95 > budget_buffers: bad.push("{b95} GPU buffers a frame (95th), over {budget_buffers}")
    let built_worst = if perf_built.length: perf_sorted_at(perf_built, 1.0) else: 0.0
    if not big and not perf_built.length: bad.push("no building finished in the measure (#335)")
    let budget_built = if big: PERF_BIG_BUILT_MAX else: PERF_BUILT_MAX
    if built_worst > budget_built: bad.push("a building finished: a frame of {tenths(built_worst * 1000.0)} ms, over {budget_built * 1000.0} ms (#335)")
    if bad.length:
        print "perf FAIL: {concat_string(bad, "; ")}"
        set_exit_code(1)
    print "perf: {stats}"
    print "perf built: {perf_built.length} frames re-planned the paths to a finished building, the worst {tenths(built_worst * 1000.0)} ms"
    print "perf units: {perf_units_max} at most, {perf_unseen_max} with nothing to draw at most"
    if perf_step.length: print "perf ticks: {tenths(float(perf_step.length) / wall)} a second (20 keeps time), sim {tenths(perf_sorted_at(perf_step, 0.5) * 1000.0)} ms median, {tenths(perf_sorted_at(perf_step, 0.95) * 1000.0)} ms 95th, bots {tenths(perf_sorted_at(perf_think, 0.5) * 1000.0)} ms median, {tenths(perf_sorted_at(perf_think, 0.95) * 1000.0)} ms 95th"
    print "perf phases (ms a frame): {concat_string(map(PERF_PHASES) n, k: "{n} {tenths(perf_phase[k] * 1000.0 / float(perf_work.length) * 10.0) / 10.0}", ", ")}"
    return true

// A house of yours finished a second into the measure, by the Town Center (#335): a building finishing is measured on
// every run, not only when the bots happen to finish one in time.
def perf_finish_house(clock:float, me:int):
    if perf_for <= 0.0 or perf_house_put or clock < PERF_WARM + 1.0: return
    perf_house_put = true
    let tc = town_center(me)
    let k = btype_index("house")
    if tc < 0 or k < 0: return
    var done = false
    for(12) r:
        for(2 * r + 1) j:
            for([ -r, r ]) dy:
                let x = b_cx[tc] + j - r
                let y = b_cy[tc] + dy
                if not done and r >= 4 and can_place(me, k, x, y):
                    fort_put(me, k, x, y, 0)
                    update_pop()
                    print "perf: a house finished at {x},{y}, {clock} s"
                    done = true
