// ------------------------------------------------------------------ the plainest frame loop
// A match's frames with nothing of a game's on top: no menus, no panels, no sound. A world must be set up first
// (gen/setup, gen/start) and a window open. Start a game's own loop from this and add to it; the steps and their
// order are game/match_loop.lobster's.

def plain_loop():
    var paused = false
    var speed = 1.0
    sim_reset()
    while gl.frame() and gl.button("escape") != 1:
        ui_click_tick()
        window_tick()
        drop_lost_selection()
        if gl.button("space") == 1 and not net_on: paused = not paused
        if gl.button("=") == 1 and not net_on: speed = min(8.0, speed * 2.0)
        if gl.button("-") == 1 and not net_on: speed = max(0.25, speed / 2.0)
        let dt = gl.delta_time()
        frame_dt = dt
        fx_tick(dt)
        vx_tick(0.006, true)  // (the voxel units' later bakes, a little each frame)
        // the sim: this frame's time, then the ticks it pays for
        if not paused and winner < 0: sim_owe(dt * speed)
        if net_on: ls_receive(lockstep)
        sim_run(false): nil
        // the player
        scroll()
        keys()
        mouse()
        // the picture
        if drawing():  // (minimised: the sim plays on, nothing is drawn)
            gl.clear(float4 { 0.05, 0.05, 0.05, 1.0 })
            gl.blend(1)
            draw_world_lit()
            draw_hud(paused, speed)
        if rec_dir != "" and clock_s >= rec_from:  // (record:<dir>: a take of the match, a PNG a frame)
            if rec_n == 0: record_begin()
            if record_frame(): return
