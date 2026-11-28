// A pack's own events as rings and floating text (#243): what the rules' event_fx makes of each, headless.
// ../../../check.sh runs it.
//   lobster test_pack_fx.lobster
import all_modules

var fails = 0
var passes = 0

def check(ok:bool, what:string):
    if ok: passes++
    else:
        fails++
        print "FAIL: {what}"

W = 10
H = 10
u_id = [ 5, 6 ]
u_x = [ 2500, 7500 ]
u_y = [ 3500, 8500 ]
u_owner = [ 0, 1 ]
fog = [ map(W * H): 2, map(W * H): 0 ]
su_rules = parse_json("\{\"event_fx\": \{\"6\": \{\"at\": \"a\", \"ring\": 6, \"colour\": \"#ff0000\", \"text\": \"Found \{n\}\"\}, " +
                      "\"4\": \{\"at\": \"bc\", \"ring\": 2, \"to\": \"seen\"\}\}\}")
var ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 6, 5, 0, 0, 0, 0, 3 }, 0)
check(ok and p.x == 2500 and p.y == 3500 and tiles == 6 and text == "Found 3" and col.x == 1.0 and col.y == 0.0, "an event is drawn at unit a, its ring and its text with n")
ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 6, 5, 0, 0, 0, 0, 3 }, 1)
check(not ok, "only for unit a\'s owner")
ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 6, 6, 0, 0, 0, 0, 3 }, 0)
check(not ok, "and not for another player\'s unit")
ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 4, 6, 4200, 1300, 0, 0, 0 }, 0)
check(ok and p.x == 4200 and p.y == 1300 and tiles == 2 and text == "", "bc: a point, seen by whoever sees it")
ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 4, 6, 4200, 1300, 0, 0, 0 }, 1)
check(not ok, "not by one who doesn\'t")
ok, p, tiles, col, text = pack_fx_of(Event { EV_PACK + 9, 5, 0, 0, 0, 0, 0 }, 0)
check(not ok, "a code with no look draws nothing")
ok, p, tiles, col, text = pack_fx_of(Event { EV_HIT, 5, 6, 0, 0, 0, 0 }, 0)
check(not ok, "nor does an engine event")
events = [ Event { EV_PACK + 6, 5, 0, 0, 0, 0, 2 } ]
pack_fx_events(0) x, y: float2 { float(x), float(y) }
check(fx_rings.length == 1 and fx_texts.length == 1 and fx_texts[0].text == "Found 2", "this tick\'s events make their rings and texts")
check(pack_fx_sound(Event { EV_PACK + 6, 5, 0, 0, 0, 0, 2 }) == "", "a look with no sound plays none")
su_rules = parse_json("\{\"event_fx\": \{\"6\": \{\"at\": \"a\", \"sound\": \"chirp\"\}\}\}")
check(pack_fx_sound(Event { EV_PACK + 6, 5, 0, 0, 0, 0, 2 }) == "chirp" and pack_fx_sound(Event { EV_HIT, 5, 0, 0, 0, 0, 2 }) == "", "a look\'s sound is read (#253), an engine event has none")
fx_tick(5.0)
check(fx_rings.length == 0 and fx_texts.length == 0, "and they fade")
print "test_pack_fx: {passes} passed, {fails} failed"
