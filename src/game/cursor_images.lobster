// Which image each mouse cursor is (#222): src/icons/os_cursor/, made by icons.sh (the art at the size it's shown, the
// tool cursors with their small pointer). The game makes OS cursors of them (game/cursors.lobster).

let CURSOR_KINDS = [ "pointer", "move", "attack", "wall", "chop", "mine", "forage", "build" ]

// The image for a display's scale (1, or 2 on Retina).
def cursor_image(kind:string, scale:int) -> string:
    return "icons/os_cursor/" + kind + (if scale == 2: "@2x.png" else: ".png")

// The spot that counts, in points from the top left: the arrow's tip, the target's centre, a tool's small pointer.
def cursor_hot(kind:string) -> int2:
    if kind == "attack": return int2 { 2, 2 }
    if kind == "pointer" or kind == "move" or kind == "wall": return int2 { 2, 1 }
    return int2 { 1, 1 }
