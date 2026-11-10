// ------------------------------------------------------------------ the ground's doodads (TerrainView.scatter)
// A rock outcrop on every rock cell (big inside it, small at its edge), stones, flowers and tufts on
// open grass, lilies on water, reeds along the shore. Godot's own random numbers (view/node.lobster's
// PCG), seeded by the map's name as Godot seeds them: the same places as in the Godot game.

class Doodad:
    t:float2  // tiles
    name:string
    scale:float

var doodad_list = []::Doodad

def mask_at(t:float2) -> float4:
    let w = W * MASK_K
    let h = H * MASK_K
    let x = clamp(int(t.x * float(MASK_K)), 0, w - 1)
    let y = clamp(int(t.y * float(MASK_K)), 0, h - 1)
    let o = (y * w + x) * 4
    return float4 { mask_bytes[o] / 255.0, mask_bytes[o + 1] / 255.0, mask_bytes[o + 2] / 255.0, mask_bytes[o + 3] / 255.0 }

def doodad_name(kind:string, pick:int, counts:dictionary<string, int>) -> string:
    return kind + string(pick % max(1, counts.get(kind, 1)))

// keep_clear(t): no stones, flowers or shore reeds there (sim_debug._keep_clear: by resources,
// buildings, bridges and the starts).
def build_doodads(map_id:string, counts:dictionary<string, int>, keep_clear) -> void:
    doodad_list = []
    let rng = pcg_seed(jstr_hash(map_id))
    let rock = str_index(tr_names, "rock")
    let grass = str_index(tr_names, "grass")
    for(W * H) c:
        if terrain[c] == rock:
            let x = c % W
            let y = c / W
            var inner = 0
            for([ int2 { 1, 0 }, int2 { -1, 0 }, int2 { 0, 1 }, int2 { 0, -1 } ]) d:
                let nx = x + d.x
                let ny = y + d.y
                if nx >= 0 and ny >= 0 and nx < W and ny < H and terrain[ny * W + nx] == rock: inner++
            let size = lerpf(0.75, 1.6, float(inner) / 4.0) * randf_range(rng, 0.85, 1.15)
            let ax = float(x) + 0.5 + randf_range(rng, -0.22, 0.22)
            let ay = float(y) + 0.5 + randf_range(rng, -0.22, 0.22)
            doodad_list.push(Doodad { float2 { ax, ay }, doodad_name("rock", randi(rng), counts), size })
    let area = W * H
    for([ [ "stones", "40" ], [ "flowers", "22" ], [ "tuft", "12" ] ]) kw:
        let kind = kw[0]
        let want = area / string_to_int(kw[1])
        var placed = 0
        var i = 0
        while i < want * 8 and placed < want:
            let t = float2 { randf_range(rng, 0.3, float(W) - 0.3), randf_range(rng, 0.3, float(H) - 0.3) }
            let c = int(t.y) * W + int(t.x)
            let m = mask_at(t)
            if not (terrain[c] != grass or cliff[c] == 1 or m.x > 0.3 or m.w > 0.3 or keep_clear(t)):
                doodad_list.push(Doodad { t, doodad_name(kind, randi(rng), counts), 1.0 })
                placed++
            i++
    for(area * 2):
        let t = float2 { randf_range(rng, 0.3, float(W) - 0.3), randf_range(rng, 0.3, float(H) - 0.3) }
        let m = mask_at(t)
        if m.x > 0.7 and randf(rng) < 0.08: doodad_list.push(Doodad { t, doodad_name("lily", randi(rng), counts), 1.0 })
        elif m.x > 0.4 and m.x < 0.5 and randf(rng) < 0.25 and not keep_clear(t): doodad_list.push(Doodad { t, doodad_name("shore", randi(rng), counts), 1.0 })
