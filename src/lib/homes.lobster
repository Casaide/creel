// ------------------------------------------------------------------ homes: workers born in houses (Casaide/creel#73)
// In a stocked economy (#48) with rules economy.homes.born_every set, a building with beds (buildings.json "beds") is a
// home: it keeps the foods its holds have room for topped up (lib/carry's want, like a recipe's inputs), and while it
// has a free bed, food in its larder and room under its owner's cap it counts down; at the end it takes one food and a
// worker is born at its door. A unit born there keeps the home's id in u_house; a bed is free while fewer living units
// say so than it has beds. A home's countdown is its b_make (a home has no recipe).

let HOME_LOOK = 20  // ticks between an idle home's looks at its beds and larder (a second)

def residents(b:int) -> int:
    var n = 0
    for(u_house) h:
        if h == b_id[b]: n++
    return n

def larder_food(b:int) -> int:
    for(r_foods) r:
        if b_hold[b][r] > 0: return r
    return -1

def stock_larder(b:int):
    let k = b_kind[b]
    for(r_foods) r:
        let lack = bt_hold[k][r] - b_hold[b][r] - b_want[b][r] - b_coming[b][r]
        if lack > 0: want(b, r, lack)

def can_be_born(b:int) -> bool:
    let p = b_owner[b]
    let k = worker_type(p)
    return k >= 0 and larder_food(b) >= 0 and pop[p] + t_pop[k] <= pop_cap[p] and residents(b) < bt_beds[b_kind[b]]

def born(b:int):
    let k = worker_type(b_owner[b])
    hold_take(b, larder_food(b), 1)
    let i = trained(b, k)
    u_house[i] = b_id[b]
    pop[b_owner[b]] += t_pop[k]

def homes_tick():
    if not r_stocked or r_born_ticks <= 0: return
    let second = tick % HOME_LOOK == 0
    for(b_id.length) b:
        if b_done[b] != 0 and bt_beds[b_kind[b]] > 0:
            if b_make[b] > 0:
                b_make[b]--
                if b_make[b] == 0 and can_be_born(b): born(b)
            elif second:
                stock_larder(b)
                if can_be_born(b): b_make[b] = r_born_ticks
