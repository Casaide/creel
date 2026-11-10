// ------------------------------------------------------------------ the bot and walls (walls_ai.gd)
// man: with walkway walls of its own, the bot keeps up to man_pct of its shooters at home up on the
// wall nearest the nearest enemy it sees. storm: attacking, a docked siege tower of its own takes the
// foot soldiers near it up onto the enemy's wall, then on at the target (a queued attack-move); an
// undocked tower is pushed to the enemy walkway cell nearest it. besiege: a side with no town (the
// Siege mode's attackers) keeps its whole army on the attack.

// Finished walkway cells of the player's (mine) or of its enemies' it can see, ascending.
def walkway_cells(p:int, mine:bool) -> [int]:
    let out = []::int
    for(b_id.length) b:
        if b_done[b] != 0 and bt_walkway[b_kind[b]] > 0:
            let own = b_owner[b] == p
            if own == mine and (mine or is_enemy(p, b_owner[b])) and (mine or fog_sees_area(p, b)):
                for(footprint(b)) c: out.push(c)
    sort_ints(out)
    return out

// Where trouble is: the nearest enemy (not an animal) we see near home, else the nearest enemy start.
def wall_threat(bot:Bot, hx:int, hy:int) -> int, int:
    let r = cfg("military.defend_tiles") * 3000
    var bx = -1
    var by = -1
    var best_d = r * r
    for(u_x.length) i:
        if is_foe(bot.player, u_owner[i]) and t_animal[u_kind[i]] == 0 and fog_visible(bot.player, u_x[i], u_y[i]):
            let d = dist2(hx, hy, u_x[i], u_y[i])
            if d < best_d:
                best_d = d
                bx = u_x[i]
                by = u_y[i]
    if bx >= 0: return bx, by
    best_d = 1 << 62
    for(num_players) q:
        if q < start_x.length and is_enemy(bot.player, q):
            let d = dist2(hx, hy, start_x[q], start_y[q])
            if d < best_d:
                best_d = d
                bx = start_x[q]
                by = start_y[q]
    return bx, by

def man_walls(bot:Bot, army:[int], hx:int, hy:int):
    if not has_cfg("military.walls.every") or tick % (cfg("military.walls.every") * 20) != bot_phase(bot) or bot.assault: return
    let ours = walkway_cells(bot.player, true)
    if not ours.length: return
    let shooters = []::int
    var up = 0
    let r = cfg("military.defend_tiles") * 2000
    for(army) i:
        let k = u_kind[i]
        if t_ranged[k] and t_splash[k] == 0 and t_pass_len[k] == 0 and can_climb(i):
            if u_perch[i] != 0 or u_task[i] == T_CLIMB: up++
            elif u_foe[i] == 0 and u_moving[i] == 0 and u_task[i] == T_NONE and dist2(hx, hy, u_x[i], u_y[i]) < r * r: shooters.push(i)
    let want = (up + shooters.length) * cfg("military.walls.man_pct") / 100 - up
    if want <= 0 or not shooters.length: return
    let tx, ty = wall_threat(bot, hx, hy)
    var best = -1
    var best_d = 1 << 62
    for(ours) cell:
        let d = dist2((cell % W) * 1000 + 500, (cell / W) * 1000 + 500, tx, ty)
        if d < best_d:
            best_d = d
            best = cell
    let ids = map(slice(shooters, 0, min(want, shooters.length))) i: u_id[i]
    issue_cmd(bot.player, CMD_MOVE, ids, (best % W) * 1000 + 500, (best / W) * 1000 + 500, 0, 0)

def storm_walls(bot:Bot, army:[int], tx:int, ty:int):
    if not has_cfg("military.walls.every") or not bot.assault or tx < 0 or tick % (cfg("military.walls.every") * 20) != bot_phase(bot): return
    let theirs = walkway_cells(bot.player, false)
    if not theirs.length: return
    let near = cfg("military.walls.climb_tiles") * 1000
    for(army) j:
        if t_docks[u_kind[j]]:
            let top = docked_at(j)
            if top < 0:
                if u_moving[j] == 0:
                    var best = -1
                    var best_d = 1 << 62
                    for(theirs) cell:
                        let d = dist2(u_x[j], u_y[j], (cell % W) * 1000 + 500, (cell / W) * 1000 + 500)
                        if d < best_d:
                            best_d = d
                            best = cell
                    if best >= 0: issue_cmd(bot.player, CMD_MOVE, [ u_id[j] ], (best % W) * 1000 + 500, (best / W) * 1000 + 500, 0, 0)
            else:
                let ids = []::int
                for(army) i:
                    let k = u_kind[i]
                    if not t_ranged[k] and can_climb(i) and u_perch[i] == 0 and u_task[i] != T_CLIMB:
                        let ln = lane(i)
                        if area_at(bot.eco.reach, ln, u_x[i], u_y[i]) != area_at(bot.eco.reach, ln, tx, ty) and
                            dist2(u_x[i], u_y[i], u_x[j], u_y[j]) <= near * near: ids.push(u_id[i])
                if ids.length:
                    issue_cmd(bot.player, CMD_MOVE, ids, (top % W) * 1000 + 500, (top / W) * 1000 + 500, 0, 0)
                    issue_cmd(bot.player, CMD_ATTACK_MOVE, ids, tx, ty, 0, 0, 1)  // once up: down their stairs and on

def besiege(bot:Bot):
    if not has_cfg("military.walls.every") or tick % (cfg("military.walls.every") * 20) != bot_phase(bot): return
    let army = []::int
    for(u_x.length) i:
        if u_owner[i] == bot.player and not t_worker[u_kind[i]] and t_animal[u_kind[i]] == 0: army.push(i)
    if not army.length: return
    let hx = start_x[bot.player]
    let hy = start_y[bot.player]
    bot.aln = lane(army[0])
    bot.harea = area_at(bot.eco.reach, bot.aln, hx, hy)
    bot.assault = true
    let tx, ty = enemy_target(bot, hx, hy)
    if tx < 0: return
    bot_siege(bot, army, hx, hy)
    storm_walls(bot, army, tx, ty)
    let go = []::int
    for(army) i:
        let k = u_kind[i]
        if not t_buildings_only[k] and not t_docks[k] and u_perch[i] == 0 and u_task[i] == T_NONE and u_foe[i] == 0 and u_moving[i] == 0 and not u_orders[i].length:
            go.push(u_id[i])
    if go.length:
        let rx, ry = reachable(bot, tx, ty)
        issue_cmd(bot.player, CMD_ATTACK_MOVE, go, rx, ry, 0, 0)
