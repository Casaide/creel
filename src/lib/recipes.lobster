// ------------------------------------------------------------------ recipes: buildings turn goods into goods (Casaide/creel#50)
// In a stocked economy (#48) a building with a recipe (buildings.json "makes": {"in": {...}, "out": {...}, "time": s})
// keeps its in slots topped up by asking for them (lib/carry's want), and when they are all there and its out slots
// have room it takes the inputs and, after the recipe's time, puts the outputs out. What sits in out slots (and in
// "offers") is offered to carriers: to whoever asks, else to the nearest store.

def has_recipe(k:int) -> bool: return bt_make_ticks[k] > 0

// Ask for what its in slots lack, beyond what is already asked for or on its way.
def top_up(b:int):
    let k = b_kind[b]
    for(bt_in[k]) need, r:
        if need > 0:
            let lack = bt_hold[k][r] - b_hold[b][r] - b_want[b][r] - b_coming[b][r]
            if lack > 0: want(b, r, lack)

def can_start(b:int) -> bool:
    let k = b_kind[b]
    for(bt_in[k]) need, r:
        if b_hold[b][r] < need: return false
    for(bt_out[k]) n, r:
        if n > 0 and hold_room(b, r) < n: return false
    return true

def recipes_tick():
    if not r_stocked: return
    for(b_id.length) b:
        let k = b_kind[b]
        if b_done[b] != 0 and has_recipe(k):
            if b_make[b] > 0:
                b_make[b]--
                if b_make[b] == 0:
                    for(bt_out[k]) n, r:
                        if n > 0:
                            hold_put(b, r, n)
                            ev_goods(EV_MADE, 0, b, r, n)
                            produced[r][b_owner[b]] += n
                    mark_carry(b_owner[b])
            if b_make[b] == 0 and can_start(b) and hook_can_make(b):  // (a pack may hold it back: its worker away, #98)
                for(bt_in[k]) need, r:
                    if need > 0:
                        b_hold[b][r] -= need
                        ev_goods(EV_USED, 0, b, r, need)
                b_make[b] = bt_make_ticks[k]
            top_up(b)
