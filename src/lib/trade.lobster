// ------------------------------------------------------------------ markets, trade carts, repair (market.gd, trade.gd, repair.gd)
// The market: a lot of goods for gold at prices everyone shares (buying pushes a price up, selling
// down). Trade carts walk between two markets for good, bringing gold home each round trip, more the
// farther apart. Workers mend their side's hurt buildings and engines, paying a twentieth at a time.

let LOT = 100
let PRICE_STEP = 5
let PRICE_LOW = 20
let PRICE_HIGH = 500
let SELL_PCT = 75
let T_TRADE = 5
let T_REPAIR = 7
let TRADE_OUT = 0
let TRADE_HOME = 1
let CHUNKS = 20

var market_price = []::int  // per resource: gold per lot
var r_repair_speed = 0
var r_repair_cost = 0
var r_trade_min = 0
var r_trade_sq_div = 1
var r_trade_lin_pct = 0

def is_market(b:int) -> bool: return b_done[b] == 1 and has_role(b_kind[b], ROLE_TRADE)

// ---- the market

def quote(p:int, r:int, buy:bool) -> int:
    if buy: return market_price[r]
    var fee = 100 - SELL_PCT
    for(bt_roles.length) k:
        if has_role(k, ROLE_TRADE): fee = max(0, fee + bm_trade_fee[p][k])
    return market_price[r] * (100 - fee) / 100

def trade_barred(p:int, b:int, r:int, buy:bool) -> bool:
    if b < 0 or b_owner[b] != p or b_done[b] == 0 or not has_role(b_kind[b], ROLE_TRADE): return true
    if trade_lacked[p]: return true
    let g = resource_index("gold")
    if r < 0 or r == g: return true
    if buy and stock[g][p] < quote(p, r, true): return true
    if not buy and stock[r][p] < LOT: return true
    return false

def cmd_trade(p:int, bid:int, r:int, buy:bool):
    let b = b_index_of(bid)
    if trade_barred(p, b, r, buy): return
    let g = resource_index("gold")
    if buy:
        stock[g][p] -= quote(p, r, true)
        stock[r][p] += LOT
        market_price[r] = min(PRICE_HIGH, market_price[r] + PRICE_STEP)
    else:
        stock[r][p] -= LOT
        stock[g][p] += quote(p, r, false)
        market_price[r] = max(PRICE_LOW, market_price[r] - PRICE_STEP)

// ---- trade carts

def mid_x(b:int) -> int: return b_cx[b] * TILE + b_sx[b] * TILE / 2
def mid_y(b:int) -> int: return b_cy[b] * TILE + b_sy[b] * TILE / 2

def market_tiles(a:int, b:int) -> int: return isqrt(dist2(mid_x(a), mid_y(a), mid_x(b), mid_y(b))) / TILE

def trip_gold(a:int, b:int) -> int:
    let d = market_tiles(a, b)
    return d * d / r_trade_sq_div + d * r_trade_lin_pct / 100

def route_barred(p:int, home:int, far:int) -> bool:
    if not is_market(home) or b_owner[home] != p: return true
    if not is_market(far) or is_enemy(b_owner[far], p): return true
    return home == far or market_tiles(home, far) < r_trade_min

def nearest_market(i:int, except:int) -> int:
    var best = -1
    var best_d = 0
    for(b_id.length) b:
        if b != except and b_owner[b] == u_owner[i] and is_market(b):
            let d = dist2(u_x[i], u_y[i], mid_x(b), mid_y(b))
            if best < 0 or d < best_d:
                best = b
                best_d = d
    return best

def start_route(i:int, home:int, far:int):
    u_task[i] = T_TRADE
    u_route[i] = b_id[home]
    u_target[i] = b_id[far]
    u_work[i] = TRADE_OUT
    approach_building(i, far)

def cmd_route(p:int, ids:[int], bid:int):
    let far = b_index_of(bid)
    if far < 0: return
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and t_trader[u_kind[i]]:
            let home = nearest_market(i, far)
            clear_task(i)
            if home < 0 or route_barred(p, home, far): approach_building(i, far)
            else: start_route(i, home, far)

def trade_step(i:int):
    let home = b_index_of(u_route[i])
    let far = b_index_of(u_target[i])
    if home < 0 or not is_market(home) or b_owner[home] != u_owner[i]:
        clear_task(i)
        u_route[i] = 0
        u_moving[i] = 0
        return
    if far < 0 or not is_market(far) or is_enemy(b_owner[far], u_owner[i]): u_work[i] = TRADE_HOME
    let to = if u_work[i] == TRADE_OUT: far else: home
    let x0, y0, x1, y1 = building_rect(to)
    if in_reach(i, x0, y0, x1, y1):
        u_moving[i] = 0
        u_stuck[i] = 0
        if u_work[i] == TRADE_OUT:
            u_carry_kind[i] = resource_index("gold") + 1
            u_carry[i] = trip_gold(home, far)
            u_work[i] = TRADE_HOME
            approach_building(i, home)
        else:
            if u_carry[i] > 0: stock[u_carry_kind[i] - 1][u_owner[i]] += u_carry[i]
            u_carry[i] = 0
            u_carry_kind[i] = 0
            if far < 0 or route_barred(u_owner[i], home, far):
                clear_task(i)
                u_route[i] = 0
                return
            u_work[i] = TRADE_OUT
            approach_building(i, far)
    elif u_moving[i] == 0:
        approach_building(i, to)

def trade_tick():
    for(u_x.length) i:
        if u_task[i] == T_TRADE: trade_step(i)

// ---- repair

def can_mend(p:int, id:int) -> bool:
    let b = b_index_of(id)
    if b >= 0:
        return b_owner[b] == p and b_done[b] == 1 and b_hp[b] < bm_hp[p][b_kind[b]] and not bm_lacks[p][b_kind[b]]
    let j = index_of(id)
    if j < 0 or u_owner[j] != p: return false
    let k = u_kind[j]
    return t_no_heal[k] and not t_animal[k] and u_hp[j] < t_hp[k]

def mend_approach(i:int, id:int):
    let b = b_index_of(id)
    if b >= 0: approach_building(i, b)
    else:
        let j = index_of(id)
        order_move(i, u_x[j], u_y[j], u_radius[j] + REACH, 0, -1, -1, 0)

def mend_reach(i:int, id:int) -> bool:
    let b = b_index_of(id)
    if b >= 0:
        let x0, y0, x1, y1 = building_rect(b)
        return in_reach(i, x0, y0, x1, y1)
    let j = index_of(id)
    let r = u_radius[i] + u_radius[j] + REACH
    return dist2(u_x[i], u_y[i], u_x[j], u_y[j]) <= r * r

def cmd_repair(p:int, ids:[int], id:int):
    if not can_mend(p, id): return
    for(ids) uid:
        let i = index_of(uid)
        if i >= 0 and u_owner[i] == p and is_worker(i) and u_perch[i] == 0:
            clear_task(i)
            u_task[i] = T_REPAIR
            u_target[i] = id
            u_work[i] = 0
            mend_approach(i, id)

def repair_tick():
    for(u_x.length) i:
        if u_task[i] == T_REPAIR:
            let id = u_target[i]
            let p = u_owner[i]
            if not can_mend(p, id):
                clear_task(i)
                u_moving[i] = 0
            elif not mend_reach(i, id):
                if u_moving[i] == 0:
                    if u_stuck[i] >= GIVE_UP: clear_task(i)
                    else: mend_approach(i, id)
            else:
                u_moving[i] = 0
                let b = b_index_of(id)
                var max_hp = 0
                var ticks = 0
                var cost = []::int
                if b >= 0:
                    max_hp = bm_hp[p][b_kind[b]]
                    ticks = bt_build_ticks[b_kind[b]]
                    cost = bt_cost[b_kind[b]]
                else:
                    let k = u_kind[index_of(id)]
                    max_hp = t_hp[k]
                    ticks = t_train_ticks[k]
                    cost = t_cost[k]
                let step = max(1, max_hp * 1000 * r_repair_speed / 100 / max(1, ticks))
                let chunk = max(1, max_hp * 1000 / CHUNKS)
                var paid = true
                if u_work[i] == 0:
                    let part = map(cost) v: v * r_repair_cost / 100 / CHUNKS
                    if not can_afford(p, part):
                        clear_task(i)
                        paid = false
                    else: pay(p, part)
                if paid:
                    let whole = (u_work[i] + step) / 1000 - u_work[i] / 1000
                    u_work[i] += step
                    if whole > 0:
                        if b >= 0: b_hp[b] = min(max_hp, b_hp[b] + whole)
                        else:
                            let j = index_of(id)
                            u_hp[j] = min(max_hp, u_hp[j] + whole)
                    if u_work[i] >= chunk: u_work[i] = 0
