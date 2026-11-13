// ------------------------------------------------------------------ the steps of a match's frame
// What a game's own frame loop calls each frame, in this order: sim_owe (the play time this frame adds), sim_run (the
// ticks that time pays for: lockstep's turns, the bots, the step), cam_follow_fight (captures), draw_world_lit (the
// world under its atmosphere), and for a take record_begin and record_frame. The loop itself is the game's: its menus,
// its panels, what pauses play and what ends it. examples/plain/src/loop.lobster is the plainest one.

// Who plays whom, and the network match if there is one.
var bots = []::Bot
var link = Link {}
var net_on = false
var lockstep = Lockstep { Link {}, 0, [ 0 ], [] }

var sim_acc = 0.0        // play time owed to the sim, seconds (under one tick after sim_run, unless lockstep is waiting)
var sim_steps = 0        // ticks stepped this match
var sim_step_time = 0.0  // and the wall time they took, bots included

def sim_reset():
    sim_acc = 0.0
    sim_steps = 0
    sim_step_time = 0.0

// This frame's play time (its length times the speed; nothing while play is held). Never more than half a second owed:
// a long frame doesn't become a burst of ticks.
def sim_owe(t:float): sim_acc = min(sim_acc + t, 0.5)

// The ticks the owed time pays for. Each: the view's last positions kept (drawing blends from them), the bots think
// (not yours unless watch, not a network player's, none when bots_idle), the sim steps, lockstep hashes its turn, and
// stepped() runs before the next. In a network match a turn whose orders aren't all here yet stops it for this frame.
def sim_run(bots_idle:bool, stepped):
    while sim_acc >= 0.05:
        if net_on and tick % TICKS_PER_TURN == 0 and not may_run(lockstep, tick / TICKS_PER_TURN):
            sim_acc = min(sim_acc, 0.05)  // (waiting on the other player: don't save up time to rush through after)
            break
        p_id = copy(u_id)
        p_x = copy(u_x)
        p_y = copy(u_y)
        let t0 = seconds_elapsed()
        for(bots) bot, p:
            if not bots_idle and (p != ME or watch) and not (net_on and p != ME and contains(lockstep.players, p)):
                ai_level_for(p)
                full_bot_think(bot)  // (watch: your own bot plays your side)
        let t1 = seconds_elapsed()
        step()
        if net_on: ls_after_step(lockstep)
        stepped()
        sim_step_time += seconds_elapsed() - t0
        perf_tick(t1 - t0, seconds_elapsed() - t1)
        sim_steps++
        clock_s += 0.05
        after_step()
        sim_acc -= 0.05

// How far the view is between the last tick and the next (0 to 1), for draw_world.
def sim_blend() -> float: return sim_acc / 0.05

// The camera eases toward the fighting; with none yet, toward the armies (captures and filming).
def cam_follow_fight(ease:float):
    var fx = 0
    var fy = 0
    var nf = 0
    for(u_x.length) i:
        if u_foe[i] != 0:
            fx += u_x[i]
            fy += u_y[i]
            nf++
    if nf == 0:  // (no fighting yet: the armies)
        for(u_x.length) i:
            if t_worker[u_kind[i]] == 0 and t_animal[u_kind[i]] == 0:
                fx += u_x[i]
                fy += u_y[i]
                nf++
    if nf > 0: cam = cam + (iso(float(fx / nf), float(fy / nf)) - cam) * ease

// The world as the player sees it: shaken by what just hit, drawn, then graded by the map's mood with the game's glows
// (collect_glows, a hook) when the atmosphere pass is on.
def draw_world_lit():
    let shake = fx_shake_off()
    cam += shake
    draw_world(sim_blend())
    if atmo_on:
        collect_glows()
        atmo_end(float2 { floor(cam.x * zoom), floor(cam.y * zoom) } / zoom, zoom, 1.5)
    cam -= shake

// A take starts: frames are rec_fps apart in play time from here, however long each takes to draw.
def record_begin(): gl.set_fixed_delta_time(1.0 / rec_fps, 0.0)

// One frame of the take written to rec_dir, and the camera's move over the take a frame further (the push in and the
// drift; iso: tiles are 1000 art units). True when that was the take's last frame.
def record_frame() -> bool:
    gl.screenshot("{rec_dir}/{100000 + rec_n}.png")
    rec_n++
    let take_frames = rec_for * rec_fps
    if float(rec_n) >= take_frames: return true
    zoom *= pow(rec_push, 1.0 / take_frames)
    cam += (iso(rec_pan.x * 1000.0, rec_pan.y * 1000.0) - iso(0.0, 0.0)) / take_frames
    return false
