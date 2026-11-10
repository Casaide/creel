// What a game must define for Creel to compile: the hook points the sim calls, and packs_loaded for the pack loader.
// These do nothing, which is a valid game. A real game puts its rules here (integers and the sim's rng only: rule
// code runs on every machine in lockstep).

// The packs are merged (gen/mods.lobster): the game's turn to work out what it derives from the data.
def packs_loaded(root:string): return

// The state the rules keep, declared at the match start (hook_declare_unit, hook_declare_player).
def hook_declare(): return

// A blow or shot is about to land on unit slot `target` from unit id `by`: the damage it does.
def hook_on_hit(by:int, target:int, damage:int) -> int: return damage

// After the tick's blows: unit slot `target` is still alive and was hurt, last by unit id `by`.
def hook_on_hurt(target:int, by:int): return

// Unit slot `i` is dying, last hurt by unit id `killer`, and it's still there to read.
def hook_on_death(i:int, killer:int): return

// Each tick, for each unit whose type asks ("tick": true in its row of the table).
def hook_unit_tick(i:int): return

// An order with a code from HOOK_ORDER_BASE up. ids: the unit ids it was given to; x, y: its two arguments.
def hook_on_order(code:int, p:int, ids:[int], x:int, y:int): return

// What a bot makes of training type k of this slot: `score` is its counter-pick's.
def hook_ai_train_score(p:int, slot:string, k:int, score:int) -> int: return score
