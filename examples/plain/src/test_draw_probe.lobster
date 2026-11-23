// The draw probe (#188): a site's stage from the sim alone, and the probe's JSON, headless. ../../../check.sh runs it.
//   lobster test_draw_probe.lobster
import all_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

// Three of one type, 100 ticks to build, its first 20 the foundation: finished, a site levelled, a site 30% built.
bt_build_ticks = [ 100 ]
r_foundation_pct = 20
r_goods_after_foundation = 1
b_id = [ 1, 2, 3 ]
b_kind = [ 0, 0, 0 ]
b_done = [ 1, 0, 0 ]
b_progress = [ 100, 10, 30 ]
b_site = [ []::int, [ 5 ], [ 5 ] ]
check(site_stage(0) == -1, "a finished building shows no stage")
check(site_stage(1) == -2, "a site under its foundation share is still levelled")
check(site_stage(2) == 0, "a site 30% built shows its first stage ({site_stage(2)})")
b_progress[2] = 99
check(site_stage(2) == 3, "and one nearly done its last ({site_stage(2)})")

probe_begin()
probe_units.push(ProbeUnit { 7, "carry_stone", "stone", true })
probe_units.push(ProbeUnit { 3, "walk", "", false })
probe_buildings.push(ProbeBuilding { 2, 0, "hut:stage0", false })
check(probe_json() == "\{\"units\": [\{\"id\": 3, \"state\": \"walk\", \"carried\": \"\", \"exact\": false\}, \{\"id\": 7, \"state\": \"carry_stone\", \"carried\": \"stone\", \"exact\": true\}], \"buildings\": [\{\"id\": 2, \"stage\": 0, \"piece\": \"hut:stage0\", \"front\": false\}]\}", "the probe as JSON, by id: {probe_json()}")
print "test_draw_probe: {passes} passed, {fails} failed"
