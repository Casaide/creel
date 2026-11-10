// ------------------------------------------------------------------ the command panel (src/view/command_panel.gd, unit_card.gd)
// At the foot of the screen, from the left, sized to what it holds (command_panel.gd, laid out as Godot lays
// it, in UI px times hud_s()): a frame in the look with the culture's crest on its top edge, in three parts
// split by carved grooves:
// - who's selected: a portrait (a bust cut from the unit's own figure, its role glyph in the corner; a
//   building's picture), the name, a slim health bar with "hp / max", and what it's doing or its card's
//   first lines; for a group, a tray of small portraits with counts;
// - what it can do: square buttons with a picture, a hotkey and the cost (a number and the resource's icon,
//   red when you can't pay), in captioned groups (Train, Heroes, Research, Age up, Orders, Stance, Build);
//   workers' buildings on two pages (civilian, military) as Godot's; hovering shows a card;
// - for a building, its queue sunk in a well: what's under way in the first slot with a progress bar, the
//   rest in small slots after it; a click on one cancels it.
// Imported by game.lobster after its controls and the tech tree page; the look's boxes, the icons and the
// text with its fonts are game/topbar.lobster's (hud_box, hud_button, tb_icon, tb_text).

let P_PORTRAIT = 96.0
let P_BUTTON = 80.0
let P_QFIRST = 60.0
let P_QSLOT = 28.0
let P_QCOLS = 7
let P_GROUP_COLS = 4
let PANEL_GOLD = float4 { 0.95, 0.79, 0.3, 1.0 }    // #f2c94c
let PANEL_SHORT = float4 { 0.88, 0.44, 0.38, 1.0 }  // #e07060: a cost you can\'t pay
let HP_GOOD = float4 { 0.36, 0.72, 0.29, 1.0 }      // #5cb84a
let HP_HURT = float4 { 0.88, 0.66, 0.23, 1.0 }      // #e0a83a
let HP_LOW = float4 { 0.85, 0.31, 0.24, 1.0 }       // #d8503c
let STANCE_NAMES = [ "Aggressive", "Defensive", "Stand ground", "No attack" ]
let STANCE_ICONS = [ "stance_aggressive", "stance_defensive", "stance_stand", "stance_passive" ]
let STANCE_TIPS = [ "Go for any foe in sight and keep chasing it.", "Fight foes that come near, chase them a short way, then walk back.",
                    "Never move to fight: hit only what is already in reach.", "Never fight on their own, not even back." ]
let TASK_NAMES = [ "Idle", "Gathering", "Carrying back", "Building", "Going inside", "Trading", "Climbing", "Repairing" ]

var panel_rect = float4_0  // where the panel is (x, y, w, h): clicks there aren't the world's
var build_page = -1        // workers' build page: -1 the two page buttons, 0 civilian, 1 military
var hud_culture = "?"
var hud_crest = "sun"

def in_panel(m:float2) -> bool: return m.x >= panel_rect.x and m.y >= panel_rect.y and m.x <= panel_rect.x + panel_rect.z and m.y <= panel_rect.y + panel_rect.w

def cost_words(c:[int]) -> string:
    let parts = []::string
    for(c) v, n:
        if v > 0: parts.push("{v} {resource_names[n]}")
    return concat_string(parts, ", ")

def age_name(age:int) -> string:
    for(su_ages) a:
        if gint(a, "age", 0) == age: return gstr(a, "name", "Age {age}")
    return "Age {age}"

// A research's picture: its icon (data/tech.json's `icon`, else its id; the generic scroll when there's no
// such icon), or for a line upgrade the unit it gives, in a gold frame (sim_debug's _upgrade_icon).
def research_look(b:Btn, r:int):
    let item = su_research[r]
    let line = gstr(item, "line", "")
    if line != "":
        let k = type_of_slot(ME, line)
        if k >= 0:
            let age = gint(item, "line_age", 0)
            for(glist(su_units[k], "line")) l:
                if as_int(at(l, "age")) == age:
                    b.line_recipe = at(l, "look")
                    b.line_key = 100000 + k * 16 + age
            if b.line_key < 0: b.unit = k
            b.accent = true
            return
    b.icon = gstr(item, "icon", research[r].id)

// What's in a queue entry: a unit type (its portrait), or the age-up or a research (its picture).
def queue_look(e:int) -> Btn:
    let t = tech_of(e)
    if t == -1:
        let b = Btn { unit_name(e), "", 0, 0 }
        b.unit = e
        return b
    if t == AGE_UP_ENTRY:
        let b = Btn { "Age up to the " + age_name(ages[ME] + 1), "", 2, 0 }
        b.icon = "age_up"
        return b
    let b = Btn { research_name(t), "", 1, t }
    research_look(b, t)
    return b

// The building pages (data/buildings.json's menu): each page's buildings this race can put up now.
var build_menu_ids = []::[string]
def page_buildings(page:int) -> [int]:
    if not build_menu_ids.length:
        let menu = gobj(lib_data("buildings.json"), "menu")
        build_menu_ids = [ gstrs(menu, "civilian"), gstrs(menu, "military") ]
    let can = buildable()
    let out = []::int
    for(build_menu_ids[page]) id:
        for(can) k:
            if bt_name[k] == id: out.push(k)
    return out

// ---- what a hover card says (sim_debug.gd's _unit_tip, _building_tip, _age_tip, _research_tip): what it is and
// does, what makes it better, and in red just what stops you now (resources short, or a building or age missing).
def names_list(names:[string], most:int) -> string:
    let shown = concat_string(names.slice(0, min(most, names.length)), ", ")
    return if names.length > most: shown + " +{names.length - most} more" else: shown

def short_of(cost:[int]) -> string:
    let parts = []::string
    for(cost) c, r:
        if stock[r][ME] < c: parts.push("{c - stock[r][ME]} {resource_names[r]}")
    return if parts.length: "!Not enough resources: short {concat_string(parts, ", ")}" else: ""

// Why the building bi can't research r (or age up, r -1) now: "" when it can.
def why_barred(bi:int, r:int) -> string:
    if bi < 0: return ""
    if b_done[bi] == 0: return "!The building isn\'t finished yet."
    if r < 0:
        let a = next_age(ME)
        if a < 0: return "~The last age."
        if tech_queued(ME, AGE_UP_ENTRY): return "~Already ageing up."
        let need = filter(ages_list[a].needs[ME]) k: not has_building(ME, k)
        if need.length: return "!Needs a building first: " + concat_string(map(need) k: bname(k), ", ")
        if b_queue[bi].length >= r_queue_max: return "!The queue is full."
        return short_of(ages_list[a].cost)
    let item = research[r]
    if researched[ME][r] == 1: return "~Done."
    if tech_queued(ME, r): return "~Being researched."
    if ages[ME] < item.age: return "!Needs the {age_name(item.age)} first."
    if item.after >= 0 and researched[ME][item.after] == 0: return "!Needs {research_name(item.after)} first."
    if item.before[ME] >= 0 and researched[ME][item.before[ME]] == 0: return "!Needs {research_name(item.before[ME])} first."
    if b_queue[bi].length >= r_queue_max: return "!The queue is full."
    return short_of(research_cost(ME, r))

def any_bonus(bonus:[int], tags:[int]) -> bool:
    for(tags) tag:
        if tag >= 0 and tag < bonus.length and bonus[tag] > 0: return true
    return false

def betters_unit(item:Research, tags:[int]) -> bool:  // a unit stat effect (attack, hp, armour, bonus...) that reaches it
    for(item.effects) fx:
        if fx.kind <= 4 and reaches(fx, tags): return true
    return false

def unit_tip(k:int, room:bool) -> string:
    let rows = []::string
    if t_worker[k]: rows.push("Gathers food, wood, stone and gold, and builds.")
    else:
        for(card_lines(k)) l: rows.push(l)
        let bonus = []::string
        for(t_bonus[k]) v, c:
            if v > 0 and c < su_classes.length: bonus.push("+{v} vs {su_classes[c]}")
        if bonus.length: rows.push("Bonus " + concat_string(bonus, ", "))
        let strong = []::string
        let weak = []::string
        for(t_player) owner, f:
            if is_foe(ME, owner) and t_animal[f] == 0:
                let fname = unit_name(f)
                if any_bonus(t_bonus[k], t_tags[f]) and not contains_str(strong, fname): strong.push(fname)
                if any_bonus(t_bonus[f], t_tags[k]) and not contains_str(weak, fname): weak.push(fname)
        if strong.length: rows.push("+Strong vs: " + names_list(strong, 3))
        if weak.length: rows.push("Weak vs: " + names_list(weak, 3))
    let ups = []::string
    for(research) item, r:
        if researched[ME][r] == 0 and item.open[ME] != 0 and betters_unit(item, t_tags[k]):
            ups.push("{research_name(r)} ({bname(item.building)})")
    if ups.length: rows.push("~Upgrades: " + names_list(ups, 4))
    for(glist(su_units[k], "line")) l, n:
        let age = as_int(at(l, "age"))
        if n > 0 and age > ages[ME]: rows.push("~{age_name(age)}: becomes {gstr(at(l, "look"), "name", unit_name(k))}")
    if not room: rows.push("!The queue is full.")
    else:
        let short = short_of(t_cost[k])
        if short != "": rows.push(short)
    return concat_string(rows, "\n")

def building_tip(k:int) -> string:
    let rows = []::string
    let desc = if k < su_btypes.length: gstr(su_btypes[k], "desc", "") else: ""
    if desc != "": rows.push(desc)
    let trains = map(bm_trains[ME][k]) u: unit_name(u)
    if trains.length: rows.push("Trains: " + names_list(trains, 5))
    let res = []::string
    for(research) item, r:
        if item.building == k and item.open[ME] != 0 and item.line_has[ME] and researched[ME][r] == 0: res.push(research_name(r))
    if res.length: rows.push("Research: " + names_list(res, 5))
    if bt_pop[k] > 0: rows.push("Houses {bt_pop[k]}")
    let takes = []::string
    for(bt_drop[k]) d, r:
        if d == 1: takes.push(resource_names[r].lowercase())
    if takes.length: rows.push("Takes in: " + concat_string(takes, ", "))
    for(ages_list) a:
        if a.age > ages[ME] and contains(a.needs[ME], k): rows.push("+Needed to reach the {age_name(a.age)}")
    let short = short_of(bm_cost[ME][k])
    if short != "": rows.push(short)
    return concat_string(rows, "\n")

def age_tip(bi:int) -> string:
    let a = next_age(ME)
    if a < 0: return ""
    let ag = ages_list[a]
    let rows = [ "~Takes {ag.ticks / 20} s at the {bname(ag.building)}" ]
    let unlocks = []::string
    for(bt_age) age, k:
        if age == ag.age and not bt_special[k]: unlocks.push(bname(k))
    if unlocks.length: rows.push("+Unlocks: " + names_list(unlocks, 6))
    let why = why_barred(bi, -1)
    if why != "": rows.push(why)
    return concat_string(rows, "\n")

def research_tip(bi:int, r:int) -> string:
    let rows = []::string
    let desc = gstr(su_research[r], "desc", "")
    if desc != "": rows.push(desc)
    let why = why_barred(bi, r)
    if why != "": rows.push(why)
    elif not rows.length: rows.push("Click to research it.")
    return concat_string(rows, "\n")

def build_btn(k:int) -> Btn:
    let can = buildable()
    var n = -1
    for(can) c, i:
        if c == k: n = i
    let b = Btn { bname(k), if build_menu and n >= 0 and n < 9: string(n + 1) else: "", 3, k }
    b.building = k
    b.costv = bm_cost[ME][k]
    b.cost = cost_words(b.costv)
    b.enabled = can_afford(ME, b.costv)
    b.glyph = bt_name[k]
    b.tip = building_tip(k)
    return b

def panel_buttons() -> [Btn]:
    let out = []::Btn
    let ids = selected_units()
    let bi = b_index_of(sel_building)
    if bi >= 0 and b_owner[bi] == ME and not ids.length:
        let room = b_queue[bi].length < r_queue_max
        for(trainable(bi)) k, n:
            let b = Btn { unit_name(k), if n < 9: string(n + 1) else: "", 0, n }
            b.unit = k
            b.costv = t_cost[k]
            b.cost = cost_words(b.costv)
            b.enabled = b_done[bi] != 0 and room and can_afford(ME, b.costv) and ages[ME] >= t_age[k]
            b.group = if t_hero[k] != 0: "Heroes" else: "Train"
            b.tip = unit_tip(k, room) + (if b_done[bi] == 0: "\n!The building isn\'t finished yet." else: "")
            if ages[ME] < t_age[k]: b.tip += "\n!Needs the {age_name(t_age[k])} first."
            elif pop[ME] + t_pop[k] > pop_cap[ME]: b.tip += "\n!Population full: build a house."
            out.push(b)
        for(offered(bi)) r, n:
            let b = Btn { research_name(r), if n < RESEARCH_KEYS.length: RESEARCH_KEYS[n].uppercase() else: "", 1, r }
            b.costv = research_cost(ME, r)
            b.cost = cost_words(b.costv)
            b.enabled = not tech_barred(ME, bi, r)
            b.group = "Research"
            b.tip = research_tip(bi, r)
            research_look(b, r)
            out.push(b)
        if next_age(ME) >= 0 and ages_list[next_age(ME)].building == b_kind[bi]:
            let b = Btn { "Age up: the " + age_name(ages_list[next_age(ME)].age), "U", 2, 0 }
            b.costv = ages_list[next_age(ME)].cost
            b.cost = cost_words(b.costv)
            b.icon = "age_up"
            b.accent = true
            b.enabled = not tech_barred(ME, bi, -1)
            b.group = "Age up"
            b.tip = age_tip(bi)
            out.push(b)
        if capacity(bi) > 0:  // a building that holds a garrison: everyone out
            let inside = b_inside[bi].length / REC_SIZE
            let b = Btn { "Ungarrison", "", 12, 0 }
            b.icon = "ungarrison"
            b.enabled = inside > 0
            b.group = "Orders"
            b.note = "{inside}/{capacity(bi)}"
            b.tip = "Everyone inside comes out (to the rally point, if it has one)."
            out.push(b)
        let anchor_cell = b_cy[bi] * W + b_cx[bi]
        if b_done[bi] != 0 and pool[anchor_cell] >= 0:  // a farm: Reseed when it's worked out, and Auto-reseed for all farms
            let fk = btype_named("farm")
            let reseed = if fk >= 0: bt_reseed[fk] else: []::int
            if left_at(anchor_cell) <= 0:
                let b = Btn { "Reseed", "", 13, 0 }
                b.icon = "fallow_fields"
                b.costv = reseed
                b.cost = cost_words(reseed)
                b.enabled = can_afford(ME, reseed)
                b.group = "Farm"
                b.tip = "Crops again for {b.cost}; its farmer starts the harvest."
                out.push(b)
            let on = auto_reseed[ME] == 1
            let b = Btn { "Auto-reseed", "", 14, 0 }
            b.icon = "fallow_fields"
            b.accent = on
            b.note = if on: "ON" else: "OFF"
            b.group = "Farm"
            b.tip = "A farm worked out is sown again at once for {cost_words(reseed)}, and its farmer farms on. For all your farms."
            out.push(b)
        if b_done[bi] != 0 and is_pen(bi):
            let n = min(pen_animals(bi, true).length, bt_pen_animals[b_kind[bi]])
            let b = Btn { "Release", "", 15, 0 }
            b.icon = "release"
            b.enabled = n > 0
            b.group = "Orders"
            b.tip = "The animals walk out and stand in front of the pen."
            out.push(b)
        if is_market(bi):  // buy and sell a lot of each resource for gold
            let g = resource_index("gold")
            for([ true, false ]) buy:
                for(resource_names) rn, r:
                    if r != g:
                        let price = quote(ME, r, buy)
                        let verb = if buy: "Buy" else: "Sell"
                        let b = Btn { "{verb} {LOT} {rn}", if buy: "+" else: "-", 16, r * 2 + (if buy: 1 else: 0) }
                        b.icon = "res_" + rn
                        b.note = "{price} gold"
                        b.enabled = not trade_barred(ME, bi, r, buy)
                        b.group = verb
                        b.tip = "{if buy: "Costs" else: "Pays"} {price} gold. Each trade moves the price: buying pushes it up, selling down."
                        out.push(b)
        if has_role(b_kind[bi], ROLE_HUB) and b_done[bi] != 0:  // one bell, rung and unrung
            let rung = (filter(b_id.length) b: b_owner[b] == ME and (filter(b_inside[b].length / REC_SIZE) k: t_worker[b_inside[b][k * REC_SIZE + REC_KIND]] != 0).length > 0).length > 0
            let b = Btn { if rung: "Back to work" else: "Call to arms", "", if rung: 9 else: 8, 0 }
            b.icon = if rung: "back_to_work" else: "call_to_arms"
            b.accent = rung
            b.group = "Orders"
            b.tip = if rung: "The sheltering workers come out and go back to work." else: "Workers near it run into the nearest buildings."
            out.push(b)
        return out
    if not ids.length: return out
    let workers = selected_workers()
    let soldiers = filter(ids) id: t_worker[u_kind[index_of(id)]] == 0 and t_animal[u_kind[index_of(id)]] == 0
    let herd = filter(ids) id: t_animal[u_kind[index_of(id)]] != 0
    if herd.length and workers.length:  // workers and our sheep: the workers slaughter them
        let b = Btn { "Slaughter", "", 17, 0 }
        b.icon = "slaughter"
        b.group = "Orders"
        b.tip = "The selected workers slaughter the selected animals, one at a time, and gather the meat."
        out.push(b)
    if soldiers.length:
        let am = Btn { "Attack-move", "R", 10, 0 }
        am.icon = "attack_move"
        am.group = "Orders"
        am.accent = arming_attack
        am.tip = "Then click where: they walk there and fight whatever they meet on the way."
        out.push(am)
        let ab = my_ability()
        let users = ability_users()
        if ab and users.length:  // the race's ability: ready on the first that's ready, else its wait
            var wait = 1000000
            for(users) id: wait = min(wait, ability_wait(index_of(id)))
            let b = Btn { gstr(ab, "name", "Ability"), gstr(ab, "hotkey", ""), 11, 0 }
            b.icon = "creature_research"
            b.enabled = wait == 0
            b.note = if wait == 0: "" else: "{(wait + 19) / 20}s"
            b.accent = arming_ability
            b.group = "Orders"
            b.tip = "{gstr(ab, "desc", "")} Then click where (within {gint(ab, "range", 0) / 1000} tiles)."
            out.push(b)
        let st = Btn { "Stop", "X", 4, 0 }
        st.icon = "stop"
        st.group = "Orders"
        st.tip = "Drop every order: they stand where they are."
        out.push(st)
        let now = u_posture[index_of(soldiers[0])]
        for(STANCE_NAMES) name, k:
            let b = Btn { name, "", 7, k }
            b.icon = STANCE_ICONS[k]
            b.group = "Stance"
            b.accent = now == k
            b.note = if now == k: "ON" else: ""
            b.tip = STANCE_TIPS[k]
            out.push(b)
    if workers.length:
        if build_menu:  // (B: every building, on the number keys)
            for(buildable()) k:
                let b = build_btn(k)
                b.group = "Build"
                out.push(b)
        elif build_page < 0:
            for([ "Civilian", "Military" ]) name, page:
                let b = Btn { "Build: " + name, "", 6, page }
                b.building = btype_with(if page == 0: ROLE_HOUSING else: ROLE_BARRACKS)
                b.glyph = if page == 0: "house" else: "barracks"
                b.note = name
                b.group = "Build"
                b.tip = if page == 0: "Houses, farms, camps, the market, the armoury and Town Centers." else: "Barracks, ranges, stables, towers, walls and gates."
                out.push(b)
        else:
            for(page_buildings(build_page)) k:
                let b = build_btn(k)
                b.group = if build_page == 0: "Civilian" else: "Military"
                out.push(b)
            let back = Btn { "Back", "Esc", 6, -1 }
            back.icon = "back"
            back.group = " "
            back.tip = "To the civilian and military pages."
            out.push(back)
    return out

def press(b:Btn):
    switch b.act:
        case 0: train_slot(b.arg)
        case 1: issue_cmd(ME, CMD_RESEARCH, []::int, sel_building, b.arg, 0, 0)
        case 2: issue_cmd(ME, CMD_AGE_UP, []::int, sel_building, 0, 0, 0)
        case 3:
            placing = b.arg
            build_menu = false
            build_page = -1
        case 4: issue_cmd(ME, CMD_STOP, selected_units(), 0, 0, 0, 0)
        case 6: build_page = b.arg
        case 7: issue_cmd(ME, CMD_STANCE, selected_units(), b.arg, 0, 0, 0)
        case 8:
            issue_cmd(ME, CMD_CALL_TO_ARMS, []::int, sel_building, 0, 0, 0)
            play_sound("town_bell", -2.0)
        case 9:
            issue_cmd(ME, CMD_BACK_TO_WORK, []::int, 0, 0, 0, 0)
            play_sound("town_bell_clear", -4.0)
        case 10: arming_attack = true
        case 11: arming_ability = true
        case 12: issue_cmd(ME, CMD_UNGARRISON, []::int, sel_building, 0, 0, 0)
        case 13: issue_cmd(ME, CMD_RESEED, []::int, sel_building, 0, 0, 0)
        case 14: issue_cmd(ME, CMD_AUTO_RESEED, []::int, if auto_reseed[ME] == 1: 0 else: 1, 0, 0, 0)
        case 15: issue_cmd(ME, CMD_RELEASE, []::int, sel_building, 0, 0, 0)
        case 16: issue_cmd(ME, CMD_TRADE, []::int, sel_building, b.arg / 2, b.arg % 2, 0)
        case 17:  // the workers go for the first of the selected animals (sim_debug.slaughter_selected)
            let herd = filter(selected_units()) id: t_animal[u_kind[index_of(id)]] != 0
            if herd.length: issue_cmd(ME, CMD_ATTACK, selected_workers(), herd[0], 0, 0, 0)
        default:
            let bi = b_index_of(sel_building)
            if bi >= 0 and b_queue[bi].length: issue_cmd(ME, CMD_CANCEL, []::int, sel_building, b_queue[bi].length - 1, 0, 0)

// A click on the panel or the top bar: true if it took it (the world doesn't get it; their buttons act as they're drawn).
def panel_click(m:float2) -> bool: return in_panel(m) or in_topbar(m)

// ---- figures and portraits

def draw_figure(key:int, recipe:JV, owner:int, at:float2, z:float):
    let f = vx_figure(recipe)
    if f < 0: return
    let fr = frames[f]
    let s = min(floor(z * 0.6 + 0.5), floor(at.y / float(fr.oy) * 2.0) / 2.0)
    let tc = team_col(owner)
    sprite_xf(f, [ s, 0.0, 0.0, s, at.x - float(fr.ox) * s, at.y - float(fr.oy) * s ], float4 { tc.x, tc.y, tc.z, 1.0 })

// A portrait (art_kit.gd's bust_icon): the figure drawn once into a texture, then a square cut on its body
// (thin rows, a pole or a tail, trimmed off; the top ICON_BUST of it, centred on its weight), and the role
// glyph in the corner. A crewed engine is framed whole.
class Portrait:
    tex:resource<texture>
    uv0:float2
    uv1:float2
    glyph:string

let PT_CELL = 240
let busts = dictionary<int, Portrait>(64)

// A unit's role glyph (art_kit.gd's role_glyph): by its weapon's tags; a rider with a lance or a blade, the horse.
def role_glyph(recipe:JV) -> string:
    if gstr(recipe, "role", "") == "worker": return ""
    let id = gstr(gobj(recipe, "parts"), "hand_r", "")
    let tags = if id != "": gstrs(part(id), "tags") else: []::string
    let rides = has(recipe, "mount") and not gbool(gobj(recipe, "mount"), "fused", false)
    if has_s(tags, "heal") or has_s(tags, "staff"): return "staff"
    if has_s(tags, "bow"): return "bow"
    if has_s(tags, "ranged"): return "sling"
    if rides and (has_s(tags, "lance") or not has_s(tags, "spear")): return "horse"
    if has_s(tags, "spear") or has_s(tags, "reach"): return "spear"
    if has_s(tags, "melee"): return "sword"
    return ""

def bust(key:int, recipe:JV, owner:int) -> Portrait?:
    let have = busts.get(key)
    if have: return have
    if vx_figure(recipe) < 0: return nil  // (asked for: baked in play)
    flush_sprites()
    let tex = gl.create_blank_texture(int3 { PT_CELL, PT_CELL, 0 }, texture_format_nomipmap | texture_format_nearest_mag | texture_format_nearest_min | texture_format_clamp)
    gl.switch_to_framebuffer(tex)
    gl.ortho()
    gl.clear(float4 { 0.0, 0.0, 0.0, 0.0 })
    b_sheet = -1
    draw_figure(key, recipe, owner, float2 { 0.5, 0.8 } * float(PT_CELL), 3.2)
    flush_sprites()
    gl.switch_to_framebuffer(nil)
    gl.ortho()
    let px = gl.read_texture(tex) or ""
    let n = PT_CELL
    def alpha(x:int, y:int) -> bool: return px.length >= n * n * 4 and px[((n - 1 - y) * n + x) * 4 + 3] > 25  // (rows come bottom up)
    let rows = map(n): 0
    var x0 = n
    var x1 = -1
    for(n) y:
        for(n) x:
            if alpha(x, y):
                rows[y]++
                x0 = min(x0, x)
                x1 = max(x1, x)
    var y0 = 0
    while y0 < n - 1 and rows[y0] < 5: y0++
    var y1 = n - 1
    while y1 > y0 and rows[y1] < 5: y1--
    let engine = has(recipe, "crew")
    var side = max(int(float(y1 - y0 + 1) * (if engine: 1.15 else: 0.62 * 1.1)), 54)
    var sum = 0
    var mass = 0
    for(min(y0 + side, n) - y0) dy:
        for(n) x:
            if alpha(x, y0 + dy):
                sum += x
                mass++
    var cx = if mass > 0: sum / mass else: n / 2
    var top = y0 - int(float(side) * 0.06)
    if engine:
        side = max(x1 - x0 + 1, y1 - y0 + 1) + 8
        cx = (x0 + x1) / 2
        top = (y0 + y1) / 2 - side / 2
    let left = cx - side / 2
    let p = Portrait { tex, float2 { float(left), float(top) } / float(n), float2 { float(left + side), float(top + side) } / float(n), if engine: "" else: role_glyph(recipe) }
    busts.set(key, p)
    return p

// A unit type's portrait in a square (its line step's when key/recipe say so).
def draw_bust(key:int, recipe:JV, owner:int, at:float2, side:float):
    let p = bust(key, recipe, owner)
    if not p: return
    let w = float4_1
    ui_batch_flush()
    gl.set_shader("textured_color")
    gl.set_primitive_texture(0, p.tex)
    gl.color(float4_1):
        gl.draw_mesh("PCT", [ float3 { at.x, at.y, 0.0 }, float3 { at.x + side, at.y, 0.0 }, float3 { at.x + side, at.y + side, 0.0 }, float3 { at.x, at.y + side, 0.0 } ],
                     [ w, w, w, w ], []::float3,
                     [ float2 { p.uv0.x, 1.0 - p.uv0.y }, float2 { p.uv1.x, 1.0 - p.uv0.y }, float2 { p.uv1.x, 1.0 - p.uv1.y }, float2 { p.uv0.x, 1.0 - p.uv1.y } ],
                     []::float2, [ 0, 2, 1, 0, 3, 2 ])
    gl.set_shader("color")
    if p.glyph != "":
        let g = side * 0.375
        tb_icon("glyph/role_" + p.glyph, at + float2_1 * (side - g - max(1.0, side / 40.0)), g, 1.0)

def draw_type_bust(k:int, at:float2, side:float): draw_bust(k, gobj(su_units[k], "look"), t_player[k], at, side)

// A building's picture scaled into a box (its look's body bake; sprite_xf places the frame's corner).
def draw_building_icon(k:int, owner:int, at:float2, size:float):
    let lk = looks.get(building_key(arch_of[owner], bt_name[k], ages[owner], 0))
    if not lk: return
    let f = frame_index(lk.body)
    if f < 0: return
    let fr = frames[f]
    let s = size / float(max(fr.w, fr.h))
    let tc = team_col(owner)
    sprite_xf(f, [ s, 0.0, 0.0, s, at.x + size / 2.0 - float(fr.w) / 2.0 * s, at.y + size / 2.0 - float(fr.h) / 2.0 * s ], float4 { tc.x, tc.y, tc.z, 1.0 })

// ---- pieces of the look

// A well (theme.gd's well_box: a thin frame round a dark sunk face), as the top bar's plaques.
def hud_well(at:float2, size:float2): tb_plaque(at, size)

// A carved groove down the panel (command_panel.gd's Groove): a dark cut with a light lip; a major one runs
// the height with a bronze diamond at its middle, a minor one starts under the captions and is fainter.
def groove(x:float, top:float, bottom:float, major:bool):
    let s = hud_s()
    let a = if major: 1.0 else: 0.55
    let y0 = top + (if major: 2.0 else: 22.0) * s
    let y1 = bottom - 2.0 * s
    let gx = floor(x + 5.0 * s)
    ui_fill(float2 { gx, y0 }, float2 { max(1.0, s), y1 - y0 }, float4 { 0.0, 0.0, 0.0, 0.6 * a })
    ui_fill(float2 { gx + max(1.0, s), y0 }, float2 { max(1.0, s), y1 - y0 }, float4 { 0.54, 0.45, 0.31, 0.5 * a })
    if major:
        let m = float2 { gx + 0.5 * s, floor((y0 + y1) * 0.5) }
        let d = 4.0 * s
        ui_batch_flush()
        gl.set_shader("color_attr")
        let c = float4 { 0.63, 0.53, 0.35, 1.0 }
        gl.draw_mesh("PC", [ float3 { m.x, m.y - d, 0.0 }, float3 { m.x + d, m.y, 0.0 }, float3 { m.x, m.y + d, 0.0 }, float3 { m.x - d, m.y, 0.0 } ],
                     [ c, c, c, c ], []::float3, []::float2, []::float2, [ 0, 1, 2, 0, 2, 3 ])
        gl.set_shader("color")

// A slim bar (theme.gd's bar_back and bar_fill): a dark sunk track, the fill raised.
def hud_bar(at:float2, size:float2, frac:float, col:float4):
    ui_fill(at, size, float4 { 0.0, 0.0, 0.0, 0.6 })
    ui_outline(at, size, 1.0, float4 { 0.0, 0.0, 0.0, 0.7 })
    let w = size.x * clamp(frac, 0.0, 1.0)
    if w > 0.0:
        ui_fill(at, float2 { w, size.y }, col)
        ui_fill(at, float2 { w, max(1.0, size.y * 0.3) }, float4 { 1.0, 1.0, 1.0, 0.3 })
        ui_fill(at + float2 { 0.0, size.y - max(1.0, size.y * 0.25) }, float2 { w, max(1.0, size.y * 0.25) }, float4 { 0.0, 0.0, 0.0, 0.3 })

// Text with a dark edge (queued).
def edged_text(at:float2, s:string, size:int, col:float4, font:int): tb_text_edged(at, s, size, col, font)

// Lines of text no wider than w (word wrap, by the text's estimated width).
def wrap(s:string, size:int, font:int, w:float) -> [string]:
    let out = []::string
    for(tokenize(s, "\n", "")) para:
        var line = ""
        for(tokenize(para, " ", "")) word:
            let next = if line == "": word else: line + " " + word
            if line != "" and tb_text_w(next, size, font) > w:
                out.push(line)
                line = word
            else: line = next
        out.push(line)
    return out

// The card's first lines (unit_card.gd short): attack, damage, range and hp; armour and speed.
def card_lines(k:int) -> [string]:
    let e = su_units[k]
    let C = su_classes.length
    if t_heal[k] > 0:
        let cb = gobj(su_rules, "combat")
        let every = gint(cb, "heal_reload", 0) * 10 / 20
        let reach = gint(cb, "heal_range", 0) / 100
        def tenths(n:int) -> string: return if n % 10 == 0: string(n / 10) else: "{n / 10}.{n % 10}"
        let heals = if gint(cb, "heal_amount", 0) > 0: "Heals {gint(cb, "heal_amount", 0) * t_heal[k]} hp every {tenths(every)} s, range {tenths(reach)}" else: "Heals wounded friends"
        return [ heals + "    HP {t_hp[k]}", "Never fights" ]
    let range = gint(e, "range", 1)
    let attack = if t_eval_attack[k] > 0: t_eval_attack[k] else: gint(e, "attack", 0)
    let arm = t_arm[k]
    return [ "Attack {attack} {gstr(e, "damage", "melee")}" + (if range > 1: ", range {range}" else: "") + "    HP {t_hp[k]}",
             "Armour {if C > 0: arm[0] else: 0} melee / {if C > 1: arm[1] else: 0} pierce    Speed {t_speed[k] / SPEED_SCALE}" ]

// The culture's look on the HUD (sim_debug: the HUD wears the culture of the side you command) and its crest.
def hud_look():
    let fam = rstr(su_races[ME], "family")
    if fam == hud_culture: return
    hud_culture = fam
    ui_setup(fam)
    let d = lib_data("ui.json")
    hud_crest = gstr(gobj(family(fam), "ui"), "ornament", gstr(at(at(d, "directions"), gstr(d, "direction", "timber")), "ornament", "sun"))

// ---- the panel

class PItem:  // a button's place this frame
    b:Btn
    at:float2
    side:float

// A button's picture: a unit's bust (a line upgrade's step), an icon, the gold rim of an upgrade.
def btn_picture(it:PItem, inset:float, foot:float):
    let b = it.b
    let side = it.side - inset * 2.0
    let pic_side = side - foot
    let pat = it.at + float2 { inset + foot * 0.5, inset }
    let r = b.line_recipe
    if b.line_key >= 0 and r: draw_bust(b.line_key, r, ME, pat, pic_side)
    elif b.unit >= 0: draw_type_bust(b.unit, pat, pic_side)
    if b.icon != "": tb_icon(b.icon, pat, pic_side, if b.enabled: 1.0 else: 0.35)
    if b.line_key >= 0 or (b.unit >= 0 and b.accent): ui_outline(pat, float2_1 * pic_side, max(1.5, pic_side / 20.0), float4 { 0.91, 0.72, 0.29, 1.0 })

def draw_panel():
    hud_look()
    let s = hud_s()
    let ws = float(gl.window_size())
    let mpos = mouse_px()
    ui_frame(false)
    let ids = selected_units()
    let bi = b_index_of(sel_building)
    let fi = index_of(sel_foreign)
    // (on a pad the orders live on the wheel, so the panel keeps who and the queue: command_panel.gd's compact)
    let btns = if pad_on or (build_menu and not selected_workers().length): []::Btn else: panel_buttons()
    // What's shown: title, hp, info lines, portrait, tray, queue.
    var title = rstr(su_races[ME], "name")
    var hp_now = -1
    var hp_max = 1
    var info = []::string
    var portrait = -1  // a unit type
    var b_pic = -1     // or a building type
    let tray_k = []::int
    let tray_n = []::int
    var has_queue = false
    if bi >= 0:
        let k = b_kind[bi]
        let owner = b_owner[bi]
        title = bname(k)
        if owner != ME: info.push(rstr(su_races[owner], "name"))
        hp_now = b_hp[bi]
        hp_max = bm_hp[owner][k]
        b_pic = k
        if b_done[bi] == 0: info.push("Being built: {100 * b_progress[bi] / max(1, bt_build_ticks[k])}%")
        elif teams[owner] == teams[ME]:  // (an enemy's garrison and training don't show from outside)
            if bt_garrison[k] > 0:
                let inside = b_inside[bi].length / REC_SIZE
                let arrows = bt_arrows[k] + inside
                info.push("{inside} / {bt_garrison[k]} inside" + (if bt_attacks[k] != 0: (if arrows > 0: ", {arrows} arrow{if arrows == 1: "" else: "s"} a volley" else: ", no arrows till manned") else: ""))
            has_queue = owner == ME and (trainable(bi).length > 0 or (filter(research) r: r.building == k).length > 0)
            let q = b_queue[bi]
            if q.length:
                let t = head_tech(bi)
                if t == AGE_UP_ENTRY: info.push("Ageing up to the " + age_name(ages[owner] + 1))
                elif t != -1: info.push("Researching " + research_name(t))
                else: info.push("Training " + unit_name(q[0]) + (if b_train[bi] == 0 and pop[owner] + t_pop[q[0]] > pop_cap[owner]: " (needs a house)" else: ""))
    elif ids.length:
        let i = index_of(ids[0])
        let k = u_kind[i]
        portrait = k
        if ids.length == 1:
            title = unit_name(k)
            hp_now = u_hp[i]
            hp_max = t_hp[k]
            if t_worker[k] != 0:
                var line = TASK_NAMES[clamp(u_task[i], 0, TASK_NAMES.length - 1)]
                if u_carry[i] > 0 and u_carry_kind[i] > 0: line += " ({u_carry[i]} {resource_names[u_carry_kind[i] - 1]})"
                info.push(line)
            elif t_animal[k] == 0: info = card_lines(k)
        else:
            title = "{ids.length} selected"
            for(ids) id:
                let kk = u_kind[index_of(id)]
                var at = -1
                for(tray_k) t, n:
                    if t == kk: at = n
                if at < 0:
                    tray_k.push(kk)
                    tray_n.push(1)
                else: tray_n[at]++
            insertion_sort(tray_k) a, b: a < b
            for(tray_k) kk, n: tray_n[n] = (filter(ids) id: u_kind[index_of(id)] == kk).length
    elif fi >= 0:
        let k = u_kind[fi]
        let owner = u_owner[fi]
        title = unit_name(k)
        if owner != gaia: info.push(rstr(su_races[owner], "name"))
        hp_now = u_hp[fi]
        hp_max = t_hp[k]
        portrait = k
        if t_animal[k] == 0: info = append(info, card_lines(k))
    else:
        info.push("Select units or a building.")
    panel_hp = hp_now
    if placing >= 0: info = [ "Placing {bname(placing)}: left-click to build, shift keeps placing, right-click/Esc cancels" ]
    // Lay it out (UI px times s): the who column, the button groups, the queue.
    let pad_l = 16.0 * s
    let pad_t = 16.0 * s
    let pad_b = 12.0 * s
    let sep = 12.0 * s
    let x0 = 12.0 * s
    let who_w = 300.0 * s
    let info_lines = []::string
    for(info) l: for(wrap(l, int(15.0 * s), 0, who_w)) w: info_lines.push(w)
    let title_h = 30.0 * s
    let hp_h = if hp_now >= 0: 20.0 * s else: 0.0
    let tray_rows = (tray_k.length + 6) / 7
    let line_n = info_lines.length + (if has_queue and not b_queue[bi].length: 1 else: 0)  // (room for "Training ..." before it starts)
    let who_h = title_h + 5.0 * s + hp_h + (if hp_now >= 0: 5.0 * s else: 0.0) + float(line_n) * 20.0 * s + (if tray_k.length: 5.0 * s + float(tray_rows) * 43.0 * s else: 0.0)
    let show_pic = portrait >= 0 or b_pic >= 0
    // Button grps, in the order their captions first appear.
    let grps = []::string
    for(btns) b:
        if not has_s(grps, b.group): grps.push(b.group)
    let group_w = map(grps) g:
        let n = (filter(btns) b: b.group == g).length
        let cols = min(n, P_GROUP_COLS)
        float(cols) * P_BUTTON * s + float(cols - 1) * 6.0 * s
    let group_rows = map(grps) g: ((filter(btns) b: b.group == g).length + P_GROUP_COLS - 1) / P_GROUP_COLS
    var acts_h = 0.0
    for(group_rows) r: acts_h = max(acts_h, 21.0 * s + float(r) * P_BUTTON * s + float(r - 1) * 6.0 * s)
    var acts_w = 0.0
    for(group_w) w, n: acts_w += w + (if n > 0: 10.0 * s + 10.0 * s + 10.0 * s else: 0.0)
    let queue = if has_queue: b_queue[bi] else: []::int
    let q_rest = max(0, r_queue_max - 1)  // (the well sized for a full queue, so training doesn't grow the panel)
    let q_rows = (q_rest + P_QCOLS - 1) / P_QCOLS
    let q_inner_w = P_QFIRST * s + (if q_rest > 0: 6.0 * s + float(min(q_rest, P_QCOLS)) * (P_QSLOT + 3.0) * s - 3.0 * s else: 0.0)
    let q_w = 20.0 * s + max(q_inner_w, 70.0 * s)
    let q_h = 16.0 * s + 16.0 * s + 5.0 * s + max(P_QFIRST * s, float(q_rows) * (P_QSLOT + 3.0) * s) + 5.0 * s + 4.0 * s
    let acts = grps.length > 0
    var content_w = (if show_pic: P_PORTRAIT * s + sep else: 0.0) + who_w
    if acts or has_queue: content_w += sep + 10.0 * s
    if acts: content_w += sep + acts_w
    if acts and has_queue: content_w += sep + 10.0 * s
    if has_queue: content_w += sep + q_w
    let content_h = max(max(if show_pic: P_PORTRAIT * s else: 0.0, who_h), max(acts_h, if has_queue: q_h else: 0.0))
    let pw = pad_l * 2.0 + content_w
    let ph = pad_t + content_h + pad_b
    let py = ws.y - 12.0 * s - ph
    panel_rect = float4 { x0, py, pw, ph }
    hud_box(float2 { x0, py }, float2 { pw, ph }, 8.0, ui_look.face, true, 12.0)
    // The crest on the top edge, cast in the look's metal.
    let crest_h = 36.0 * s
    let cy = py  // (ui_box.gd: centred on the top edge)
    // Who.
    var x = x0 + pad_l
    let y = py + pad_t
    let items = []::PItem
    if show_pic:
        hud_well(float2 { x, y }, float2_1 * P_PORTRAIT * s)
        x += P_PORTRAIT * s + sep
    let who_x = x
    var wy = y + title_h + 5.0 * s
    if hp_now >= 0:
        let f = float(hp_now) / float(max(1, hp_max))
        hud_bar(float2 { who_x, wy + 6.0 * s }, float2 { who_w - 84.0 * s, 7.0 * s }, f, if f > 0.5: HP_GOOD elif f > 0.25: HP_HURT else: HP_LOW)
        wy += hp_h + 5.0 * s
    let info_y = wy
    let tray_y = info_y + float(info_lines.length) * 20.0 * s + 5.0 * s
    for(tray_k.length) n: hud_well(float2 { who_x + float(n % 7) * 43.0 * s, tray_y + float(n / 7) * 43.0 * s }, float2_1 * 40.0 * s)
    x += who_w
    let bottom = py + ph - pad_b
    if acts or has_queue:
        groove(x + sep - 5.0 * s, py + pad_t, bottom, true)
        x += sep + 10.0 * s
    // The button grps.
    var pressed = -1
    var hover = -1
    if acts:
        x += sep
        for(grps) g, gn:
            if gn > 0:
                groove(x, py + pad_t, bottom, false)
                x += 20.0 * s + 10.0 * s
            let mine = filter(btns) b: b.group == g
            for(mine) b, n:
                let at = float2 { x + float(n % P_GROUP_COLS) * (P_BUTTON + 6.0) * s, y + 21.0 * s + float(n / P_GROUP_COLS) * (P_BUTTON + 6.0) * s }
                items.push(PItem { b, at, P_BUTTON * s })
            x += group_w[gn]
    for(items) it, n:
        if hud_button(it.at, float2_1 * it.side, it.b.accent, it.b.enabled): pressed = n
        if mpos.x >= it.at.x and mpos.y >= it.at.y and mpos.x <= it.at.x + it.side and mpos.y <= it.at.y + it.side: hover = n
    if pressed >= 0: press(items[pressed].b)
    // The queue well.
    let qlook = map(queue) e: queue_look(e)
    let q_items = []::PItem
    var frac = 0.0
    var qx = 0.0
    if has_queue:
        if acts:
            groove(x + sep - 5.0 * s, py + pad_t, bottom, true)
            x += sep + 10.0 * s
        qx = x + sep
        hud_well(float2 { qx, y }, float2 { q_w, q_h })
        let fx = qx + 10.0 * s
        let fy = y + 8.0 * s + 16.0 * s + 5.0 * s
        if queue.length: q_items.push(PItem { qlook[0], float2 { fx, fy }, P_QFIRST * s })
        else: hud_well(float2 { fx, fy }, float2_1 * P_QFIRST * s)
        for(max(0, queue.length - 1)) n: q_items.push(PItem { qlook[n + 1], float2 { fx + (P_QFIRST + 6.0) * s + float(n % P_QCOLS) * (P_QSLOT + 3.0) * s, fy + float(n / P_QCOLS) * (P_QSLOT + 3.0) * s }, P_QSLOT * s })
        var cancel = -1
        for(q_items) it, n:
            if hud_button(it.at, float2_1 * it.side, n == 0, true): cancel = n
        if cancel >= 0: issue_cmd(ME, CMD_CANCEL, []::int, sel_building, cancel, 0, 0)
        if queue.length:
            let t = head_tech(bi)
            let ticks = if t != -1: head_ticks(bi) else: t_train_ticks[queue[0]]
            frac = float(b_train[bi]) / float(max(1, ticks))
        let bar = float2 { fx, fy + P_QFIRST * s + 5.0 * s }
        hud_bar(bar, float2 { P_QFIRST * s, 4.0 * s }, frac, PANEL_GOLD * float4 { 1.0, 1.0, 1.0, if queue.length: 1.0 else: 0.25 })
    // Pictures: sprites (buildings, page buttons) after the boxes, then the textures, text last.
    b_sheet = -1
    let pic_at = float2 { x0 + pad_l, y }
    if b_pic >= 0: draw_building_icon(b_pic, if bi >= 0: b_owner[bi] else: ME, pic_at + float2_1 * 4.0 * s, (P_PORTRAIT - 8.0) * s)
    for(items) it:
        if it.b.building >= 0: draw_building_icon(it.b.building, ME, it.at + float2 { 6.0 * s, 5.0 * s }, it.side - 22.0 * s)
    flush_sprites()
    // (busts render into their own textures the first time: after the sprites above are out)
    if portrait >= 0: draw_type_bust(portrait, pic_at + float2_1 * 2.0 * s, (P_PORTRAIT - 4.0) * s)
    for(tray_k) kk, n: draw_type_bust(kk, float2 { who_x + float(n % 7) * 43.0 * s, tray_y + float(n / 7) * 43.0 * s } + float2_1 * 2.0 * s, 36.0 * s)
    for(items) it:
        btn_picture(it, 5.0 * s, if it.b.costv.length or it.b.note != "": 12.0 * s else: 0.0)
        if not it.b.enabled: ui_fill(it.at + float2_1 * 3.0 * s, float2_1 * (it.side - 6.0 * s), float4 { 0.0, 0.0, 0.0, 0.35 })
        if it.b.glyph != "": tb_icon("glyph/" + it.b.glyph, it.at + float2 { it.side - 29.0 * s, 3.0 * s }, 26.0 * s, if it.b.enabled: 1.0 else: 0.5)
    for(q_items) it: btn_picture(it, 3.0 * s, 0.0)
    // The crest (a texture: after the sprites).
    tb_icon_wide("crest_" + hud_crest, float2 { x0 + pw * 0.5, cy }, crest_h)
    // Text.
    tb_text(float2 { who_x, y + 1.0 * s }, title, int(23.0 * s), ui_look.title, 2)
    if hp_now >= 0:
        let ht = "{hp_now} / {hp_max}"
        tb_text(float2 { who_x + who_w - tb_text_w(ht, int(14.0 * s), 0), y + title_h + 5.0 * s }, ht, int(14.0 * s), ui_look.dim, 0)
    for(info_lines) l, n: tb_text(float2 { who_x, info_y + float(n) * 20.0 * s }, l, int(15.0 * s), ui_look.dim, 0)
    for(tray_k.length) n:
        if tray_n[n] > 1:
            let ct = string(tray_n[n])
            edged_text(float2 { who_x + float(n % 7) * 43.0 * s + 38.0 * s - tb_text_w(ct, int(13.0 * s), 1), tray_y + float(n / 7) * 43.0 * s + 22.0 * s }, ct, int(13.0 * s), float4_1, 1)
    if acts:
        for(grps) g:  // each group's caption over its first button
            let first = filter(items) it: it.b.group == g
            if first.length and g != " ": tb_text(float2 { first[0].at.x, y - 1.0 * s }, g.uppercase(), int(13.0 * s), ui_look.metal + (float4_1 - ui_look.metal) * 0.25, 3)  // (theme.gd's Caption)
    for(items) it:
        let b = it.b
        if b.hotkey != "": edged_text(it.at + float2 { 7.0 * s, 3.0 * s }, b.hotkey, int(14.0 * s), PANEL_GOLD, 1)
        if b.costv.length: cost_row(b.costv, it.at + float2 { 0.0, it.side - 19.0 * s }, it.side)
        elif b.note != "":
            let fsz = int(13.0 * s)
            edged_text(it.at + float2 { (it.side - tb_text_w(b.note, fsz, 1)) * 0.5, it.side - 19.0 * s }, b.note, fsz, float4_1, 1)
    if has_queue:
        let cap = if queue.length and head_tech(bi) == AGE_UP_ENTRY: "AGEING UP" elif queue.length and head_tech(bi) != -1: "RESEARCHING" else: "TRAINING"
        tb_text(float2 { qx + 10.0 * s, y + 7.0 * s }, cap, int(13.0 * s), ui_look.metal + (float4_1 - ui_look.metal) * 0.25, 3)
    // A hover's card over the panel: its name, its cost, a line.
    var q_hover = -1
    for(q_items) it, n:
        if mpos.x >= it.at.x and mpos.y >= it.at.y and mpos.x <= it.at.x + it.side and mpos.y <= it.at.y + it.side: q_hover = n
    if hover >= 0: tip_card(mpos, items[hover].b.label, items[hover].b.costv, items[hover].b.tip, items[hover].b.enabled)
    elif q_hover >= 0: tip_card(mpos, q_items[q_hover].b.label, []::int, "Click to cancel.", true)
    tb_flush()
    ui_flush()

// The cost along a button's foot: each part a number and the resource's icon, shrunk to fit; red when short.
def cost_row(c:[int], at:float2, w:float):
    let s = hud_s()
    let parts = filter(c.length) n: c[n] > 0
    if not parts.length: return
    var fs = 13.0 * s
    def row_w(f:float) -> float:
        var t = 0.0
        for(parts) n: t += tb_text_w(string(c[n]), int(f), 1) + f * 1.15 + 2.0 * s
        return t
    while row_w(fs) > w - 6.0 * s and fs > 7.0 * s: fs -= 1.0
    var x = at.x + (w - row_w(fs)) / 2.0
    for(parts) n:
        let txt = string(c[n])
        let tw = tb_text_w(txt, int(fs), 1)
        edged_text(float2 { x, at.y }, txt, int(fs), if stock[n][ME] < c[n]: PANEL_SHORT else: float4_1, 1)
        tb_icon("res_" + resource_names[n], float2 { x + tw + 1.0 * s, at.y + 1.0 * s }, fs * 1.15, 1.0)
        x += tw + fs * 1.15 + 2.0 * s

// ---- the pad's wheel (D-133; also touch's): the panel's own buttons, bigger, in a ring round the screen's middle
// (a page a group when there are many), over the battle dimmed; the one pointed at lifted, its card beside the ring.
let WHEEL_BIG = 1.35
let WHEEL_PAGE_MAX = 10
let WHEEL_GAP = 34.0

def wheel_items() -> [Btn]:  // (workers: their orders, then the civilian and the military buildings, a page each)
    if not selected_workers().length: return panel_buttons()
    let was_page = build_page
    let was_menu = build_menu
    build_menu = false
    build_page = -1
    let out = filter(panel_buttons()) b: b.act != 6
    for(2) page:
        build_page = page
        for(panel_buttons()) b:
            if b.act == 3: out.push(b)
    build_page = was_page
    build_menu = was_menu
    return out

def wheel_open():  // (a worker's wheel opens on its civilian buildings)
    pad_wheel = wheel_items()
    pad_pick = 0
    pad_page = max(0, find_s(wheel_groups(), "Civilian"))

def wheel_groups() -> [string]:  // the pages' captions ("": one page)
    let builds = (filter(pad_wheel) b: b.group == "Civilian").length > 0
    if pad_wheel.length <= WHEEL_PAGE_MAX and not builds: return [ "" ]
    let out = []::string
    for(pad_wheel) b:
        if not has_s(out, b.group): out.push(b.group)
    return out

def wheel_pages() -> int: return wheel_groups().length

def wheel_page_items() -> [Btn]:
    let gs = wheel_groups()
    if gs.length == 1: return pad_wheel
    let g = gs[clamp(pad_page, 0, gs.length - 1)]
    return filter(pad_wheel) b: b.group == g

def wheel_choose(b:Btn):
    if not b.enabled: return
    press(b)
    pad_wheel = if placing >= 0: []::Btn else: wheel_items()  // (a building to place: the wheel gives way to it)

// The ring's buttons this frame, and its radius.
def wheel_layout() -> [PItem], float:
    let items = wheel_page_items()
    let bw = P_BUTTON * hud_s() * WHEEL_BIG
    let n = max(1, items.length)
    let r = max(150.0 * hud_s(), float(n) * (bw + WHEEL_GAP * hud_s()) / TAU)
    let mid = float(gl.window_size()) / 2.0
    let out = map(items) b, k:
        let a = -90.0 + 360.0 * float(k) / float(n)
        PItem { b, mid + float2 { cos(a), sin(a) } * r - float2_1 * bw / 2.0, bw }
    return out, r

def wheel_draw():
    pad_wheel = wheel_items()  // (costs and what can be afforded, as they change)
    if not pad_wheel.length: return
    pad_page = clamp(pad_page, 0, wheel_pages() - 1)
    hud_look()
    let s = hud_s()
    let ws = float(gl.window_size())
    let mid = ws / 2.0
    let mpos = mouse_px()
    ui_frame(false)
    ui_fill(float2_0, ws, float4 { 0.0, 0.0, 0.0, 0.28 })
    let items, r = wheel_layout()
    var hot = -1
    for(items) it, n:
        if mpos.x >= it.at.x and mpos.y >= it.at.y and mpos.x <= it.at.x + it.side and mpos.y <= it.at.y + it.side: hot = n
    if hot < 0 and not touch_play and pad_pick < items.length: hot = pad_pick
    if hot >= 0:  // (lifted)
        let it = items[hot]
        items[hot] = PItem { it.b, it.at - float2_1 * it.side * 0.09, it.side * 1.18 }
    var pressed = -1
    for(items) it, n:
        if hud_button(it.at, float2_1 * it.side, it.b.accent or n == hot, it.b.enabled): pressed = n
    b_sheet = -1
    for(items) it:
        if it.b.building >= 0: draw_building_icon(it.b.building, ME, it.at + float2 { 6.0 * s, 5.0 * s }, it.side - 22.0 * s)
    flush_sprites()
    for(items) it:
        btn_picture(it, 5.0 * s, if it.b.costv.length or it.b.note != "": 12.0 * s else: 0.0)
        if not it.b.enabled: ui_fill(it.at + float2_1 * 3.0 * s, float2_1 * (it.side - 6.0 * s), float4 { 0.0, 0.0, 0.0, 0.35 })
        if it.b.glyph != "": tb_icon("glyph/" + it.b.glyph, it.at + float2 { it.side - 29.0 * s, 3.0 * s }, 26.0 * s, if it.b.enabled: 1.0 else: 0.5)
    for(items) it:
        if it.b.costv.length: cost_row(it.b.costv, it.at + float2 { 0.0, it.side - 19.0 * s }, it.side)
        elif it.b.note != "":
            let fsz = int(13.0 * s)
            edged_text(it.at + float2 { (it.side - tb_text_w(it.b.note, fsz, 1)) * 0.5, it.side - 19.0 * s }, it.b.note, fsz, float4_1, 1)
    let bw = P_BUTTON * s * WHEEL_BIG
    let gs = wheel_groups()
    if gs.length > 1:  // the pages, over the ring (LB or a tap in the middle turns them)
        let fsz = int(16.0 * s)
        let caps = map(gs) g: if g.length: g.uppercase() else: "MORE"
        var w = 0.0
        for(caps) c: w += tb_text_w(c, fsz, 2) + 18.0 * s
        var x = mid.x - w / 2.0
        let ty = mid.y - r - bw * 0.5 - 44.0 * s
        hud_box(float2 { x - 12.0 * s, ty - 6.0 * s }, float2 { w + 6.0 * s, float(fsz) + 14.0 * s }, 2.0, ui_look.face, false, 3.0)
        for(caps) c, k:
            edged_text(float2 { x, ty }, c, fsz, if k == pad_page: PANEL_GOLD else: float4 { 0.8, 0.76, 0.66, 0.7 }, 2)
            x += tb_text_w(c, fsz, 2) + 18.0 * s
    let card_at = mid + float2 { r + bw * 0.5 + 36.0 * s, 40.0 * s }
    if hot >= 0: tip_card(card_at, items[hot].b.label, items[hot].b.costv, items[hot].b.tip, items[hot].b.enabled)
    else:
        let hint = if touch_play: "Tap to choose, tap elsewhere to close" else: "Point, A to choose, B to close"
        tb_text(float2 { mid.x - tb_text_w(hint, int(15.0 * s), 0) / 2.0, mid.y + r + bw * 0.5 + 18.0 * s }, hint, int(15.0 * s), ui_look.dim, 0)
    tb_flush()
    ui_flush()
    if pressed >= 0: wheel_choose(items[pressed].b)

// ---- touch's Build button (over the minimap): your workers' build wheel in one tap; with none selected, an idle
// worker's (else the one nearest the middle of the screen).
def build_button_rect() -> float4:
    let s = hud_s()
    let side = P_BUTTON * 1.1 * s
    let at = float2 { float(gl.window_size().x) - side - 24.0 * s, mm_box().y - side - 30.0 * s }
    return float4 { at.x, at.y, side, side }

def in_build_button(m:float2) -> bool:
    let r = build_button_rect()
    return m.x >= r.x and m.y >= r.y and m.x <= r.x + r.z and m.y <= r.y + r.w

def build_button():
    if placing >= 0 or pad_wheel.length: return
    hud_look()
    let s = hud_s()
    let r = build_button_rect()
    let at = float2 { r.x, r.y }
    ui_frame(false)
    let pressed = hud_button(at, float2_1 * r.z, true, true)
    b_sheet = -1
    let house = btype_named("house")
    if house >= 0: draw_building_icon(house, ME, at + float2 { 6.0 * s, 4.0 * s }, r.z - 24.0 * s)
    flush_sprites()
    let fsz = int(14.0 * s)
    edged_text(at + float2 { (r.z - tb_text_w("BUILD", fsz, 2)) * 0.5, r.z - 20.0 * s }, "BUILD", fsz, PANEL_GOLD, 2)
    tb_flush()
    ui_flush()
    if pressed:
        if not selected_workers().length:
            let mine = filter(u_id.length) i: u_owner[i] == ME and t_worker[u_kind[i]] != 0
            let idle = filter(mine) i: u_task[i] == T_NONE and u_moving[i] == 0
            let pick = if idle.length: idle else: mine
            if not pick.length: return
            let mid = float(gl.window_size()) / 2.0
            var best = pick[0]
            for(pick) i:
                if magnitude(to_screen(iso(float(u_x[i]), float(u_y[i]))) - mid) < magnitude(to_screen(iso(float(u_x[best]), float(u_y[best]))) - mid): best = i
            selected = [ u_id[best] ]
            sel_building = 0
        wheel_open()

// A tooltip card (theme.gd's tip_card): the name in bold, the cost (each part a number and its icon, red when
// short), then the tip's lines, wrapped. A line can start with a mark: "!" red (what stops it), "+" green (what it
// gives), "~" dim (an aside). A disabled button's plain tip, with no marks at all, shows red. Drawn after everything
// queued under it, so the panel's own words don't show through (Dominic, 2026-11-04).
let TIP_GOOD = float4 { 0.56, 0.82, 0.45, 1.0 }
let TIP_TEXT = float4 { 0.94, 0.89, 0.78, 1.0 }

def tip_line_marked(l:string) -> bool:
    if l == "": return false
    let mark = l.substring(0, 1)
    return mark == "!" or mark == "+" or mark == "~"

def tip_card(m:float2, name:string, costv:[int], tip:string, ok:bool):
    tb_flush()
    ui_flush()
    let s = hud_s()
    let fs = int(14.0 * s)
    let lh = 19.0 * s
    let maxw = 360.0 * s
    let rows = []::string
    let cols = []::float4
    let tiplines = tokenize(tip, "\n", "")
    let has_marks = exists(tiplines): tip_line_marked(_)
    for(tiplines) raw:
        if raw == "": continue
        let mark = raw.substring(0, 1)
        let col = if mark == "!": PANEL_SHORT elif mark == "+": TIP_GOOD elif mark == "~": ui_look.dim elif not ok and not has_marks: PANEL_SHORT else: TIP_TEXT
        let body = if tip_line_marked(raw): raw.substring(1, raw.length - 1) else: raw
        for(wrap(body, fs, 0, maxw)) l:
            rows.push(l)
            cols.push(col)
    let parts = filter(costv.length) r: costv[r] > 0
    let ifs = 14.0 * s
    var cost_w = 0.0
    for(parts) r: cost_w += tb_text_w(string(costv[r]), int(ifs), 1) + ifs * 1.2 + 10.0 * s
    var w = tb_text_w(name, int(16.0 * s), 1)
    w = max(w, cost_w)
    for(rows) l: w = max(w, tb_text_w(l, fs, 0))
    w += 28.0 * s
    let cost_h = if parts.length: lh + 2.0 * s else: 0.0
    let h = 16.0 * s + 22.0 * s + cost_h + float(rows.length) * lh + 8.0 * s
    let at = float2 { clamp(m.x - w * 0.3, 4.0, float(gl.window_size().x) - w - 4.0), max(4.0, m.y - h - 14.0 * s) }
    hud_box(at, float2 { w, h }, 3.0, ui_look.face * float4 { 1.08, 1.08, 1.08, 1.0 }, false, 4.0)
    tb_text(at + float2 { 14.0 * s, 9.0 * s }, name, int(16.0 * s), ui_look.title, 1)
    var y = at.y + 9.0 * s + 22.0 * s
    if parts.length:
        var x = at.x + 14.0 * s
        for(parts) r:
            let txt = string(costv[r])
            let tw = tb_text_w(txt, int(ifs), 1)
            edged_text(float2 { x, y }, txt, int(ifs), if stock[r][ME] < costv[r]: PANEL_SHORT else: float4_1, 1)
            tb_icon("res_" + resource_names[r], float2 { x + tw + 2.0 * s, y + 1.0 * s }, ifs * 1.15, 1.0)
            x += tw + ifs * 1.2 + 10.0 * s
        y += cost_h
    for(rows) l, n: tb_text(float2 { at.x + 14.0 * s, y + float(n) * lh }, l, fs, cols[n], 0)
    tb_flush()
    ui_flush()
