// ------------------------------------------------------------------ the ground (src/view/art/terrain_view.gd, scenes/art_pixel/terrain.gdshader)
// One quad over the map drawn by the terrain shader: no grid. Terrain from blurred masks (R water,
// G swamp, B reed-bed ground, A rock) perturbed by noise (D-241): grass in a soft tone over several
// tiles with grain and blades a device px, voxel tufts and stones in the units' voxel size, bog and
// standing pools, rock, trails worn by walkers, each meeting the next along a height noise per
// pixel, and water with sand, a wet edge, depth, the sky and ripples. The fog is drawn over it, per tile. Each culture's paths come from game/paths.lobster.

let MASK_K = 4   // mask samples per tile
let MASK_CH = 6  // build_masks' channels: the masks' four and the props' two
var relief_occlude = 2  // tiles: how far behind a hill's top lower ground makes it a near edge, drawn again over what stands behind it (2 hides behind a drop of a level or so; a higher drop hides more)
let OCCLUDE_SORT = 6.0
var relief_faces = []::resource<mesh>?  // per level group 1..MAX_LEVEL
var relief_tops = []::resource<mesh>?
var relief_rims = []::resource<mesh>?
class Occluder:
    sort_y:float  // art px: the row's top corner, as units are keyed on the base plane
    tops:resource<mesh>
    rims:resource<mesh>?
    cells:[int]  // its tops' cells, and the fog over them (drawn after them: build_fog)
    fog:resource<mesh>? = nil
var occluders = []::Occluder
let TERRAIN_SHADERS = """
PIXELFUNCTIONS
    float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
    }
    float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.03 + 5.2) * 0.3 + vnoise(p * 4.1 + 9.7) * 0.2; }
    float zn(vec2 p) { return vnoise(p) * 0.65 + vnoise(p * 2.03 + 5.2) * 0.35; }  // (two octaves: enough for zones over many tiles)
    // A pixel's own number: an integer hash (sin's loses its way on device px far from the origin).
    float hs(vec2 p, uint s) {
        uvec2 q = uvec2(ivec2(floor(p))) * uvec2(1597334673u, 3812015801u);
        uint n = (q.x ^ q.y ^ (s * 2654435761u)) * 1597334673u;
        n ^= n >> 15;
        return float(n >> 8) * (1.0 / 16777216.0);
    }
    vec3 stones(vec2 p, float jitter, out vec2 id, out vec2 off) {
        vec2 ip = floor(p);
        float d1 = 9.0;
        float d2 = 9.0;
        id = ip;
        off = vec2(0.0);
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec2 o = ip + vec2(float(i), float(j));
                vec2 q = o + 0.5 + (vec2(hash(o), hash(o + 3.1)) - 0.5) * jitter;
                float d = length(p - q);
                if (d < d1) { d2 = d1; d1 = d; id = o; off = p - q; } else if (d < d2) { d2 = d; }
            }
        }
        return vec3(d2 - d1, hash(id + 9.0), 0.0);
    }
    vec3 ramp4(vec3 a, vec3 b, vec3 c, vec3 d, float v) {
        float q = floor(clamp(v, 0.0, 0.999) * 4.0);
        return q < 1.0 ? a : q < 2.0 ? b : q < 3.0 ? c : d;
    }
    float bayer(ivec2 ap) {
        int k = (ap.y % 4) * 4 + (ap.x % 4);
        float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
        return BAYER[k] / 16.0 - 0.5;
    }
    // A voxel tuft, in a cell of 7 art px: three blades (light left, mid middle, dark right), 2 to 4 px tall, lit from
    // the top left as the units are, and its shadow on the ground. 0 none, 1 light, 2 mid, 3 dark, 4 tip, 5 shadow.
    float tuft(vec2 ap, float density, float tall, uint s) {
        vec2 c = floor(ap / 7.0);
        if (hs(c, s) >= density) return 0.0;
        float h = min(2.0 + floor(hs(c, s + 1u) * 3.0) + tall, 5.0);
        vec2 d = ap - (c * 7.0 + vec2(2.0 + floor(hs(c, s + 2u) * 3.0), 5.0));
        if (d.y == 1.0 && (d.x == 1.0 || d.x == 2.0)) return 5.0;
        if (d.y > 0.0) return 0.0;
        if (d.x == 0.0 && d.y > -h) return d.y == 1.0 - h ? 4.0 : 2.0;
        if (d.x == -1.0 && d.y > 1.0 - h) return 1.0;
        if (d.x == 1.0 && d.y > 2.0 - h) return 3.0;
        return 0.0;
    }
    vec3 tufted(vec3 col, float k) {
        return k == 1.0 ? col * 1.18 + vec3(0.02, 0.025, 0.0) : k == 2.0 ? col * 1.06 + vec3(0.0, 0.01, 0.0) : k == 3.0 ? col * 0.8
             : k == 4.0 ? col * 1.26 + vec3(0.04, 0.04, 0.0) : k == 5.0 ? col * 0.9 : col;
    }
    // A voxel stone, in a cell of 5 art px: 2 by 2, its top lit, its left side mid and its right dark, its shadow down
    // to the right. 0 none, 1 top, 2 left, 3 right, 4 shadow.
    float stone(vec2 ap, float density, uint s) {
        vec2 c = floor(ap / 5.0);
        if (hs(c, s) >= density) return 0.0;
        vec2 d = ap - (c * 5.0 + vec2(floor(hs(c, s + 1u) * 2.0), floor(hs(c, s + 2u) * 2.0)));
        if (d.x < 0.0 || d.y < 0.0 || d.x > 2.0 || d.y > 2.0) return 0.0;
        if (d.y == 0.0) return d.x < 2.0 ? 1.0 : 0.0;
        if (d.y == 1.0) return d.x == 0.0 ? 2.0 : d.x == 1.0 ? 3.0 : 4.0;
        return d.x > 0.0 ? 4.0 : 0.0;
    }
    vec3 stoned(vec3 col, vec3 rock, float k) {
        return k == 1.0 ? rock * 1.1 + vec3(0.02) : k == 2.0 ? rock * 0.94 : k == 3.0 ? rock * 0.8 : k == 4.0 ? col * 0.9 : col;
    }

    // A texel of the ground atlas (data/ground/atlas.png, src/ground_textures.lobster): tile k, at p art px, wrapping.
    // Where a second atlas is turning in over the first (nmix above 0: ground_atlas_mix), each texel is the one or the
    // other, never a mix of the two, so the ground stays as crisp as its art: the next atlas comes in a texel at a time,
    // in small patches (half of a texel's turn is its own, half its patch's).
    vec4 gtex(sampler2D atlas, sampler2D next, float nmix, int k, vec2 p) {
        ivec2 q = ivec2(mod(floor(p), 256.0)) + ivec2(k % 4, k / 4) * 256;
        if (nmix > 0.0 && hs(vec2(q), 91u) * 0.5 + hs(floor(vec2(q) / 5.0), 92u) * 0.5 < nmix) return texelFetch(next, q, 0);
        return texelFetch(atlas, q, 0);
    }
    // One terrain's texture with no repeat to see: two grids of big cells half a cell apart, each cell offsetting the
    // texture its own way, faded towards its edges, the higher texel of the two showing where both are strong.
    vec4 ground(sampler2D atlas, sampler2D next, float nmix, int k, vec2 ap) {
        vec2 g = ap / 150.0;
        vec2 c1 = floor(g);
        vec2 c2 = floor(g + 0.5);
        vec2 f1 = fract(g);
        vec2 f2 = fract(g + 0.5);
        float w1 = min(min(f1.x, 1.0 - f1.x), min(f1.y, 1.0 - f1.y));
        float w2 = min(min(f2.x, 1.0 - f2.x), min(f2.y, 1.0 - f2.y));
        uint s = uint(k) * 7u + 3u;
        vec4 a = gtex(atlas, next, nmix, k, ap + vec2(hs(c1, s), hs(c1, s + 1u)) * 256.0);
        vec4 b = gtex(atlas, next, nmix, k, ap + vec2(hs(c2, s + 2u), hs(c2, s + 3u)) * 256.0 + 128.0);
        return mix(a, b, smoothstep(-0.05, 0.05, (b.a - a.a) * 0.25 + (w2 - w1) * 1.5));
    }
    // A layer laid over the ground where its weight w passes 0.5, its edge ragged by the two heights: the higher shows
    // through near the line (blades over dirt, stones through grass), in a band a few texels wide.
    void splat(inout vec3 col, inout float h, vec4 s, float w) {
        float t = smoothstep(-0.09, 0.09, (s.a - h) * 0.8 + (w - 0.5) * 2.2);
        col = mix(col, s.rgb, t);
        h = mix(h, s.a, t);
    }
    // How close to an edge a layer of weight w is: 1 on its line, 0 well clear of it.
    float near(float w) { return 1.0 - smoothstep(0.0, 0.12, abs(w - 0.5)); }

SHADER terrain
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        iworld = vec3(apos.xy / 1.5 + vec2(0.0, atc.x), 1.0 + atc.y);   // canvas units (64 x 32 a tile) on the base plane (raised ground says how far it was lifted), and a shade
    PIXEL
        INPUTS iworld:3
        UNIFORMS tex0 tex1 tex2 tex3 tex4 tex5 tex6
        UNIFORM float atlas_mix
        UNIFORM vec2 map_size
        UNIFORM float art_px
        UNIFORM float dev_px
        UNIFORM float time
        UNIFORM float bank_px
        UNIFORM float water_edge
        UNIFORM float shore_soft
        UNIFORM float tile_h
        UNIFORM float litter_fringe
        UNIFORM vec3 water_shallow
        UNIFORM vec3 water_deep
        UNIFORM float water_ripples
        vec2 world = iworld.xy;
        float ishade = iworld.z;
        float a = world.x / 32.0;
        float b = world.y / tile_h;
        vec2 t = vec2((a + b) * 0.5, (b - a) * 0.5);
        if (t.x < 0.0 || t.y < 0.0 || t.x > map_size.x || t.y > map_size.y) discard;
        // The textures are sized on the screen and pinned to the world: a texel an art px (the units' voxel; a device px
        // on a Retina Mac, and never less than one when zoomed out), so the ground stays fine at every zoom.
        vec2 ap = floor(world * 1.5 * dev_px / max(1.0, floor(art_px + 0.5)));
        vec4 m = texture(tex0, t / map_size);
        vec4 pm = texture(tex5, t / map_size);  // (the ground under props: R woods, G stone and gold)
        float n = vnoise(t * 2.3) * 0.6 + vnoise(t * 6.1) * 0.4;
        float edge_n = zn(t * 1.1 + 3.0) - 0.5 + (vnoise(t * 3.7 + 11.0) - 0.5) * 0.4 + (vnoise(t * 9.0 + 5.0) - 0.5) * 0.25 + (vnoise(t * 21.0 + 2.0) - 0.5) * 0.12;  // (ragged edges, at a few scales)
        // the grass in zones over many tiles: lush by water, darker by woods and reeds, dry and yellow on open and
        // raised ground, flowered meadows, patches of bare earth; each laid over the last along its own ragged edge
        float lush = smoothstep(0.04, 0.35, m.r);
        float raised = clamp((ishade - 1.0) * 4.0, 0.0, 1.0);
        vec4 s = ground(tex4, tex6, atlas_mix, 0, ap);
        vec3 col = s.rgb;
        float h = s.a;
        float w_olive = (zn(t * 0.22 + 80.0) - 0.5) * 1.6 + 0.5 + edge_n * 0.3;  // (a second and third grass mixed in over a few tiles)
        if (w_olive > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 12, ap), w_olive);
        float w_worn = (zn(t * 0.45 + 95.0) - 0.5) * 1.6 + 0.24 + edge_n * 0.3;
        if (w_worn > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 13, ap), w_worn);
        float w_dark = max(m.b * 1.3, smoothstep(0.62, 0.8, zn(t * 0.05 + 7.0)) * 0.9) + edge_n * 0.35;
        if (w_dark > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 2, ap), w_dark);
        float dry_zone = smoothstep(0.42, 0.68, zn(t * 0.06 + 17.0));
        float w_dry = dry_zone * (1.0 - lush) * (1.0 - m.b) + raised * 0.35 + edge_n * 0.35;
        if (w_dry > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 1, ap), w_dry);
        float w_meadow = smoothstep(0.6, 0.75, zn(t * 0.09 + 30.0)) * (1.0 - m.b) + edge_n * 0.3;
        if (w_meadow > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 3, ap), w_meadow);
        float w_earth = smoothstep(0.6, 0.88, zn(t * 0.16 + 50.0)) * (0.55 + 0.45 * dry_zone) * (1.0 - lush) * (1.0 - m.b) + edge_n * 0.3;
        if (w_earth > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 9, ap), w_earth);
        col *= mix(vec3(1.06, 1.0, 0.86), vec3(0.92, 1.0, 1.08), zn(t * 0.12 + 61.0));  // (a drift of hue from region to region)
        col *= 0.94 + 0.12 * zn(t * 0.35 + 70.0);  // (and of tone, within a zone)
        float grass = 1.0;  // (how much of the top is grass, for the tufts)
        // the ground under props: a forest floor under the woods, scree about stone and gold
        float w_forest = pm.r * 1.5 - 0.1 + edge_n * 0.35 + (hash(ap) - 0.5) * litter_fringe;  // (litter_fringe: the floor's edge scattered a pixel at a time)
        if (w_forest > 0.35) {
            splat(col, h, ground(tex4, tex6, atlas_mix, 10, ap), w_forest);
            grass *= 1.0 - smoothstep(0.45, 0.55, w_forest);
        }
        float w_scree = pm.g * 1.7 - 0.05 + edge_n * 0.6;
        if (w_scree > 0.35) {
            splat(col, h, ground(tex4, tex6, atlas_mix, 11, ap), w_scree);
            grass *= 1.0 - smoothstep(0.45, 0.55, w_scree);
        }
        // swamp: mud with standing pools between reeds
        float w_mud = m.g + (n - 0.5) * 0.3 + edge_n * 0.3;
        bool pool_here = false;
        if (w_mud > 0.35) {
            splat(col, h, ground(tex4, tex6, atlas_mix, 8, ap), w_mud);
            float hummock = (zn(t * 0.7 + 90.0) - 0.5) * 1.4 + 0.5 + edge_n * 0.3;  // (tussocks of bog grass in the mud)
            if (hummock > 0.35) splat(col, h, ground(tex4, tex6, atlas_mix, 2, ap) * vec4(0.9, 0.92, 0.8, 1.0), hummock);
            float pool = vnoise(t * 0.55 + 13.0) * 0.75 + vnoise(t * 2.0 + 3.0) * 0.25 + (h - 0.4) * 0.05;
            if (w_mud > 0.5 && pool > 0.6) {
                col = mix(vec3(0.17, 0.27, 0.24), vec3(0.22, 0.33, 0.29), smoothstep(0.6, 0.75, pool)) * (0.97 + 0.06 * h);
                if (pool < 0.612) col = vec3(0.24, 0.21, 0.14);
                h = 0.1;
                pool_here = true;
            }
            grass *= 1.0 - smoothstep(0.45, 0.55, w_mud);
        }
        // rock: weathered stone through the grass
        float w_rock = m.a + (n - 0.5) * 0.3 + edge_n * 0.3;
        if (w_rock > 0.35) {
            splat(col, h, ground(tex4, tex6, atlas_mix, 5, ap), w_rock);
            grass *= 1.0 - smoothstep(0.45, 0.55, w_rock);
        }
        // the paths (game/paths.lobster: a channel a style) and the trails worn by walkers
        vec4 pth = texture(tex1, t / map_size);
        vec2 wob = vec2(vnoise(t * 1.3 + 11.0), vnoise(t * 1.3 + 29.0)) - 0.5;
        float trod = texture(tex2, (t + wob * 0.5) / map_size).r * 0.4;
        for (int k = 0; k < 4; k++) {
            float ak = float(k) * 1.570796 + 0.4;
            trod += texture(tex2, (t + wob * 0.8 + vec2(cos(ak), sin(ak)) * 0.7) / map_size).r * 0.15;
        }
        pth.r = max(pth.r, smoothstep(0.12, 0.5, trod) * 0.7);
        float st_trail = pth.r + (n - 0.5) * 0.3 + edge_n * 0.25;
        float st_board = pth.g + (n - 0.5) * 0.12;
        float st_cob = pth.b + (n - 0.5) * 0.15;
        float st_road = pth.a + (n - 0.5) * 0.08;
        float paved = max(st_cob, st_road);
        float w_dirt = max(st_trail, paved + 0.08 + edge_n * 0.15);  // (a dirt fringe along a paved road)
        if (w_dirt > 0.35) {
            splat(col, h, ground(tex4, tex6, atlas_mix, 4, ap), w_dirt);
            grass *= 1.0 - smoothstep(0.45, 0.55, w_dirt);
        }
        float u = texture(tex3, t / map_size).r * 9.0;  // (boards a ninth of a tile wide, their seams a device px: the slope out here, where every pixel takes it)
        float uw = fwidth(u);
        vec3 dirt = vec3(0.54, 0.43, 0.29);
        float top = max(st_board, paved);
        if (top > 0.5) {
            grass = 0.0;
            if (top == st_board) {
                float plank = floor(u);
                float seam = fract(u) / max(uw, 1e-4);
                col = mix(vec3(0.46, 0.33, 0.19), vec3(0.60, 0.45, 0.27), hash(vec2(plank, 7.0)));
                col *= 0.92 + 0.12 * vnoise(vec2(plank * 5.0, ap.x * 0.35 + ap.y * 0.7)) + 0.05 * hs(ap, 7u);
                if (hash(vec2(plank, 3.0)) > 0.86) col = mix(col, vec3(0.50, 0.48, 0.42), 0.35);
                if (seam < 1.0) col = vec3(0.20, 0.13, 0.07);
                else if (seam < 2.0) col *= 1.14;
                if (st_board < 0.56) {
                    col = vec3(0.30, 0.20, 0.11) * (0.95 + 0.1 * hs(ap, 7u));
                    if (mod(plank, 6.0) < 1.0) col = (fract(u) < 0.5) ? vec3(0.46, 0.33, 0.19) : vec3(0.20, 0.13, 0.07);
                }
            } else {
                bool cob = top == st_cob;
                vec2 id;
                vec2 off;
                vec3 v = cob ? stones(t * 7.0, 0.85, id, off) : stones(t * vec2(3.2, 3.6), 0.55, id, off);
                vec3 paving = cob ? mix(vec3(0.42, 0.41, 0.37), vec3(0.62, 0.60, 0.54), v.y) : mix(vec3(0.58, 0.56, 0.50), vec3(0.72, 0.70, 0.63), v.y);
                paving *= 0.95 + 0.1 * hs(ap, 7u);
                float facing = dot(normalize(off + vec2(1e-4)), normalize(vec2(-0.6, -0.8)));
                if (v.x < (cob ? 0.3 : 0.2)) paving *= facing > 0.25 ? 1.14 : (facing < -0.25 ? 0.76 : 1.0);
                if (v.x < (cob ? 0.12 : 0.06)) paving = mix(col, vec3(0.30, 0.26, 0.19), 0.5);
                if ((cob ? st_cob : st_road) < 0.58 && hash(id + 5.0) > 0.5) paving = col;  // (stones missing at the edge)
                col = paving;
            }
        } else if (top > 0.44 && top == st_board) {
            col *= 0.78;  // (the walk's shadow on the ground beside it)
        }
        // voxel accents, sparse: a few tufts on grass, more along the edges of rock and dirt; a few stones on rock and trails
        float edgy = max(max(near(w_rock), near(w_dirt)), near(w_earth) * 0.6);
        if (!pool_here && top <= 0.5) {
            float sk = stone(ap, 0.015 + 0.12 * smoothstep(0.5, 0.6, max(w_rock, st_trail)) * (1.0 - grass), 51u);
            if (sk > 0.0) col = stoned(col, mix(vec3(0.50, 0.48, 0.44), vec3(0.64, 0.62, 0.57), hs(floor(ap / 5.0), 71u)), sk);
            else if (grass > 0.5) {
                float tk = tuft(ap, 0.012 + 0.16 * edgy + 0.08 * m.b, floor(m.b * 2.0), 21u);
                if (tk > 0.0) col = tufted(col, tk);
            }
        }
        // light: a soft roll over several tiles
        float macro = zn(t * 0.21);
        float lit = clamp(0.5 + (macro - zn(t * 0.21 + vec2(0.35, 0.12))) * 2.2, 0.0, 1.0);
        col *= 0.93 + 0.13 * lit;
        // the shore: a sand fringe, a darker wet band, then water (deep to shallow), its foam, the sky and fine ripples
        float water = m.r + (n - 0.5) * 0.3 + edge_n * 0.06;
        if (shore_soft > 0.0) {
            // (shore_soft: no sand, the ground slopes down to the water over this much of the mask: its own cover goes
            // on down the slope, damper and darker in ragged steps, earth showing through by the waterline; the slope
            // turned to the sun, up and left of the screen, is lit, the one turned from it in shade)
            float wn = m.r + (n - 0.5) * 0.1 + edge_n * 0.04;
            float sl = clamp((wn - (water_edge - shore_soft)) / shore_soft, 0.0, 1.0);
            if (sl > 0.0) {
                float sd = sl + (hs(ap, 61u) - 0.5) * 0.16;
                float face = clamp((texture(tex0, (t + vec2(-0.2, 0.0)) / map_size).r - m.r) * 6.0, -1.0, 1.0);
                vec3 earth = mix(vec3(0.36, 0.27, 0.17), vec3(0.24, 0.18, 0.12), smoothstep(0.5, 1.0, sd));
                col = mix(col, earth, smoothstep(0.45, 0.95, sd) * 0.8);
                col *= 1.0 - 0.26 * floor(clamp(sd, 0.0, 0.999) * 5.0) / 4.0 * (face < 0.0 ? 1.0 : 0.4);
                col *= 1.0 + 0.1 * max(face, 0.0) * sl;
            }
        } else if (water > water_edge - 0.22) {
            float lift = 0.93 + 0.13 * lit;
            splat(col, h, ground(tex4, tex6, atlas_mix, 6, ap) * vec4(lift, lift, lift, 1.0), water - (water_edge - 0.14) + 0.5);
            if (water > water_edge - 0.1) splat(col, h, ground(tex4, tex6, atlas_mix, 7, ap) * vec4(lift, lift, lift, 1.0), water - (water_edge - 0.04) + 0.5);
        }
        // (water_edge: where on the mask the water begins: 0.5 fills its tiles, more makes a stream narrower than them)
        if (water > water_edge) {
            float depth = smoothstep(water_edge, 1.0, m.r + (n - 0.5) * 0.12);
            col = mix(water_shallow, water_deep, depth);
            col *= 0.96 + 0.08 * fbm(t * 0.5 + 12.0);
            if (depth < 0.18) col = mix(col, vec3(0.50, 0.50, 0.40), (0.18 - depth) * 2.4);
            vec2 sp = vec2(world.x * 0.018, world.y * 0.16);
            float sky = vnoise(sp + vec2(time * 0.03, 0.0)) * 0.6 + vnoise(sp * 2.3 + vec2(-time * 0.05, 3.0)) * 0.4;
            col = mix(col, vec3(0.52, 0.68, 0.70), smoothstep(0.6, 0.85, sky) * 0.25 * (0.4 + depth * 0.6));
            vec2 rp = ap * vec2(0.055, 0.42) + vec2(time * 0.6, time * 0.08);
            float rip = vnoise(rp) * 0.7 + vnoise(rp * 2.1 + 7.0) * 0.3;
            float above = vnoise(rp - vec2(0.0, 0.42)) * 0.7 + vnoise((rp - vec2(0.0, 0.42)) * 2.1 + 7.0) * 0.3;
            float gate = vnoise(ap * vec2(0.02, 0.1) + vec2(-time * 0.2, 4.0));
            // (water_ripples: 0 a calm lake's few glints; toward 1 a running stream's white dabs all along it)
            float rip_at = 0.74 - 0.16 * water_ripples;
            float gate_at = 0.45 - 0.3 * water_ripples;
            if (rip > rip_at && gate > gate_at) col = mix(col, mix(vec3(0.66, 0.80, 0.80), vec3(0.90, 0.95, 0.97), water_ripples), 0.4 + 0.35 * water_ripples);
            else if (above > rip_at && gate > gate_at) col *= 0.9;
            float foam = water_edge + 0.015 + 0.01 * sin(time * 1.1 + n * 9.0);
            if (water < foam && hs(ap, 91u) > 0.3) col = mix(col, vec3(0.78, 0.84, 0.80), 0.55);
            else if (water < foam + 0.025) col *= 0.88;
            // a bank (bank_px art px high; 0: none): the water lies that far below the ground, so under the far
            // shore the bank's earth shows: the ground's cover over its lip, soil, and a dark wet foot at the water
            if (bank_px > 0.0) {
                for (int bk = 0; bk < 3; bk++) {
                    vec2 w2 = world - vec2(0.0, bank_px * (bk == 0 ? 1.0 : bk == 1 ? 0.66 : 0.3) / 1.5);
                    vec2 t2 = vec2((w2.x / 32.0 + w2.y / tile_h) * 0.5, (w2.y / tile_h - w2.x / 32.0) * 0.5);
                    float wa = texture(tex0, t2 / map_size).r + (vnoise(t2 * 2.3) * 0.6 + vnoise(t2 * 6.1) * 0.4 - 0.5) * 0.3 + edge_n * 0.06;
                    if (wa <= water_edge) {
                        float e = hs(floor(ap / vec2(2.0, 1.0)), 77u);
                        vec3 soil = e < 0.3 ? vec3(0.21, 0.15, 0.10) : e < 0.7 ? vec3(0.28, 0.20, 0.13) : e < 0.95 ? vec3(0.35, 0.25, 0.16) : vec3(0.50, 0.47, 0.41);
                        col = bk == 0 ? soil * 0.6 : bk == 1 ? soil : soil * 1.25;
                    }
                }
            }
        }
        col *= ishade;
        float rim = min(min(t.x, t.y), min(map_size.x - t.x, map_size.y - t.y));
        col *= mix(0.25, 1.0, smoothstep(0.0, 0.9, rim));
        frag_color = vec4(col, 1.0);

SHADER cliff
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        iface = atc;
        iinfo = vec4(acolor.r * 9.0, acolor.g, acolor.b * 9.0, acolor.a);   // the rim's height, which way it faces (0 to 1), the foot's height, 1 on a tile's edge (0.5 off the grid)
    PIXEL
        INPUTS iface:2 iinfo:4
        UNIFORM float art_px
        UNIFORM float level_px
        UNIFORM float snow
        vec2 face = iface;
        float rim = iinfo.x;
        float foot = iinfo.z;
        float side = iinfo.y;
        float bay = bayer(ivec2(gl_FragCoord.xy / art_px));
        vec2 p = floor(vec2(face.x * 35.8 + (iinfo.w > 0.75 ? side * 300.0 : 0.0), (rim - face.y) * level_px) / 1.5) * 1.5;
        float hpx = face.y * level_px;
        float depth = max((rim - foot) * level_px, 1.0);
        float k = clamp(p.y / depth, 0.0, 1.0);
        float g = clamp(vnoise(p * 0.21) * 0.6 + vnoise(p * 0.6) * 0.4 + bay * 0.25, 0.0, 0.999);
        float hw = hpx + (vnoise(vec2(p.x * 0.045, 3.0)) - 0.5) * 7.0 + p.x * 0.06;
        float course = floor(hw / 6.5);
        float cy = fract(hw / 6.5);
        float off = hash(vec2(course, 7.0)) * 23.0;
        float bw = 11.0 + 14.0 * hash(vec2(course, 3.0));
        float bx = floor((p.x + off) / bw);
        float fx = fract((p.x + off) / bw);
        float tone = hash(vec2(bx, course));
        vec3 col = mix(vec3(0.33, 0.31, 0.27), vec3(0.50, 0.47, 0.40), tone);
        col *= mix(vec3(1.0), vec3(1.08, 1.0, 0.88), hash(vec2(bx + 5.0, course)));
        col *= 0.86 + 0.26 * g;
        float lip_c = 0.72 + 0.12 * hash(vec2(bx, course + 1.0));
        if (cy > lip_c) col *= 1.16;
        else if (cy < 0.2) col *= 0.62;
        if (fx < 0.05 && hash(vec2(bx, course + 9.0)) > 0.35) col *= 0.55;
        if (vnoise(vec2(p.x * 0.4, p.y * 0.07) + course) > 0.84 && fx > 0.45 && fx < 0.52) col *= 0.62;
        if (iinfo.w > 0.75 && vnoise(p * 0.12 + 40.0) > 0.68 && cy > 0.45 && hash(floor(p / 1.5)) > 0.3) col = mix(col, vec3(0.36, 0.45, 0.20), 0.6);
        float lip = 2.0 + 2.5 * vnoise(vec2(p.x * 0.3, 2.0)) + (hash(vec2(floor(p.x / 1.5), 5.0)) > 0.8 ? 2.0 : 0.0);
        if (p.y < lip) {
            col = mix(vec3(0.31, 0.416, 0.173), vec3(0.47, 0.53, 0.23), g);
            if (p.y < 1.5) col *= 1.15;
        } else if (p.y < lip + 1.5) {
            col *= 0.55;
        }
        col *= mix(0.74, 1.0, clamp(side, 0.0, 1.0));
        col *= mix(1.0, 0.8, floor(clamp(k + bay * 0.2, 0.0, 0.999) * 3.0) / 2.0);
        float scree = 2.0 + 3.0 * vnoise(vec2(p.x * 0.25, 9.0));
        if (depth - p.y < scree && hash(floor(p / 1.5) + 31.0) > 0.45) col = mix(col, vec3(0.30, 0.26, 0.19), 0.6);
        if (depth - p.y < 1.6) col *= 0.55;
        if (snow > 0.0) {  // (snow lies on the lip, on each course's top and in the scree, a few pixels at a time)
            vec3 sn = vec3(0.84, 0.87, 0.92) * mix(0.78, 1.0, clamp(side, 0.0, 1.0));
            float hs1 = hash(floor(p / 1.5) + 61.0);
            if (p.y < lip && hs1 < snow * 1.2) col = sn;
            else if (cy > lip_c - 0.06 && hs1 < snow * 0.9) col = mix(col, sn, 0.85);
            else if (depth - p.y < scree && hs1 < snow) col = mix(col, sn, 0.75);
        }
        frag_color = vec4(col, 1.0);
"""

var mask_tex:resource<texture>? = nil
var ground_bank_px = 0.0     // the water lies this many art px below its banks (0: level with the ground)
var ground_water_edge = 0.5  // where on its mask the water begins (more: narrower than its tiles)
var ground_litter_fringe = 0.0  // more than 0: the forest floor's edge is scattered a pixel at a time over this much of its weight (leaves strewn out onto the grass)
var ground_shore_soft = 0.0  // more than 0: no sand at the shore, the ground slopes down to the water over this much of the mask
var ground_water_shallow = float3 { 0.310, 0.541, 0.549 }  // the water's colour at its edge, and where it's deep
var ground_water_deep = float3 { 0.141, 0.314, 0.416 }
var ground_water_ripples = 0.0  // 0: a calm water's few glints; toward 1: a running stream's white dabs all along it
var prop_tex:resource<texture>? = nil  // the ground under props (prop_channel)
var mask_bytes = []::int               // the masks as Godot's image holds them (RGBA bytes, MASK_K a tile)
var paths_tex:resource<texture>? = nil
var arc_tex:resource<texture>? = nil
var wear_tex:resource<texture>? = nil
var ground_quad:resource<mesh>? = nil
var relief_snow = 0.0  // 0 to 1: how much snow lies on the cliff faces' ledges, lips and scree
var fog_mesh:resource<mesh>? = nil
let GROUND_HZ = 15.0  // how often still ground redraws (only its water moves; a fragment shader over every pixel: the laptop ran hot)
var ground_tex:resource<texture>? = nil
var ground_tex_size = int2_0
var ground_tex_cam = float2_0
var ground_tex_zoom = 0.0
var ground_tex_step = -1.0
var ground_stale = true                        // a texture its shader reads was rebuilt
var ground_atlas_tex:resource<texture>? = nil  // the ground's textures (data/ground/atlas.png: src/ground_textures.lobster)
// A second atlas turning in over the first, for a ground that changes while you watch (a season coming on): at
// ground_atlas_mix 0 the ground is all ground_atlas_tex, at 1 all ground_atlas_next, and between them each texel is
// one or the other, the next coming in a texel at a time in small patches. A game that moves the mix says so with
// ground_stale = true (the ground is kept in a texture between changes).
var ground_atlas_next:resource<texture>? = nil
var ground_atlas_mix = 0.0

// A game turns the next atlas in by this (nil: none).
def ground_atlas_turn(next:resource<texture>?, mix:float):
    ground_atlas_next = next
    ground_atlas_mix = mix
    ground_stale = true

def ground_atlas() -> resource<texture>:
    if not ground_atlas_tex:
        ground_atlas_tex = gl.load_texture("../data/ground/atlas.png", texture_format_clamp | texture_format_nomipmap | texture_format_nearest_mag | texture_format_nearest_min)
    return assert ground_atlas_tex

def mask_channel(name:string) -> int:
    return switch name:
        case "water", "shallows", "river", "deep_river", "ford": 0
        case "swamp": 1
        case "reeds", "tree", "stump": 2
        case "rock": 3
        default: -1

// The ground under the props (D-242), blurred as the masks are into prop_tex: R woods (a forest floor), G stone, gold and
// rubble (scree). Channels 4 and 5 of build_masks' samples.
def prop_channel(name:string) -> int:
    return switch name:
        case "tree", "stump": 4
        case "stone", "gold", "rubble": 5
        default: -1

def prop_weight(name:string) -> float:
    return switch name:
        case "stump": 0.6
        case "rubble": 0.7
        default: 1.0

def mask_weight(name:string) -> float:
    return switch name:
        case "shallows": 0.62
        case "ford": 0.56
        case "river": 0.8
        case "tree": 0.75
        case "stump": 0.35
        default: 1.0

// The masks (TerrainView.build): K samples a tile, each the weight of its terrain's channel, box
// blurred five times, as bytes.
def build_masks():
    let w = W * MASK_K
    let h = H * MASK_K
    let a = map(w * h * MASK_CH): 0.0
    for(h) y:
        for(w) x:
            let name = tr_names[terrain[(y / MASK_K) * W + x / MASK_K]]
            let ch = mask_channel(name)
            if ch >= 0: a[(y * w + x) * MASK_CH + ch] = mask_weight(name)
            let pc = prop_channel(name)
            if pc >= 0: a[(y * w + x) * MASK_CH + pc] = prop_weight(name)
    let b = map(w * h * MASK_CH): 0.0
    for(5):
        for(h) y:
            for(w) x:
                let x0 = max(x - 1, 0)
                let x1 = min(x + 1, w - 1)
                for(MASK_CH) ch: b[(y * w + x) * MASK_CH + ch] = (a[(y * w + x0) * MASK_CH + ch] + a[(y * w + x) * MASK_CH + ch] + a[(y * w + x1) * MASK_CH + ch]) / 3.0
        for(h) y:
            let y0 = max(y - 1, 0)
            let y1 = min(y + 1, h - 1)
            for(w) x:
                for(MASK_CH) ch: a[(y * w + x) * MASK_CH + ch] = (b[(y0 * w + x) * MASK_CH + ch] + b[(y * w + x) * MASK_CH + ch] + b[(y1 * w + x) * MASK_CH + ch]) / 3.0
    mask_bytes = map(w * h * 4) i: clamp(int(a[(i / 4) * MASK_CH + i % 4] * 255.0 + 0.5), 0, 255)
    def texel(k:int, c:int) -> float4: return float4 { byte_of(a[k * MASK_CH + c]), byte_of(a[k * MASK_CH + c + 1]), byte_of(a[k * MASK_CH + c + 2]), byte_of(a[k * MASK_CH + c + 3]) }
    mask_tex = gl.create_texture(map(h) y: map(w) x: texel(y * w + x, 0), texture_format_clamp | texture_format_nomipmap)
    prop_tex = gl.create_texture(map(h) y: map(w) x: float4 { byte_of(a[(y * w + x) * MASK_CH + 4]), byte_of(a[(y * w + x) * MASK_CH + 5]), 0.0, 0.0 }, texture_format_clamp | texture_format_nomipmap)
    ground_stale = true
    if not paths_tex:  // (until the paths are painted: game/paths.lobster)
        let zero = map(4): map(4): float4_0
        paths_tex = gl.create_texture(zero, texture_format_clamp | texture_format_nomipmap)
        arc_tex = gl.create_texture(zero, texture_format_clamp | texture_format_nomipmap)
    let c0 = iso(0.0, 0.0)
    let c1 = iso(float(W * 1000), 0.0)
    let c2 = iso(float(W * 1000), float(H * 1000))
    let c3 = iso(0.0, float(H * 1000))
    ground_quad = gl.new_mesh("PT", [ float3 { c0.x, c0.y, 0.0 }, float3 { c1.x, c1.y, 0.0 }, float3 { c2.x, c2.y, 0.0 }, float3 { c3.x, c3.y, 0.0 } ],
                              []::float4, []::float3, map(4): float2_0, []::float2, [ 0, 2, 1, 0, 3, 2 ])

def byte_of(v:float) -> float: return float(clamp(int(v * 255.0 + 0.5), 0, 255)) / 255.0

// The trails worn by walkers (trails.lobster's wear, per tile), for the shader.
def build_wear():
    ground_stale = true
    wear_tex = gl.create_texture(map(H) y: map(W) x: float4 { float(if y * W + x < wear.length: wear[y * W + x] else: 0) / 255.0, 0.0, 0.0, 0.0 },
                                 texture_format_clamp | texture_format_nomipmap)

// The fog over the ground, per tile (out of sight: dimmed, seen or not, #334), corners blended; over the cliff faces
// that show (a tile's edge above its neighbour's), and over each hill's near-edge tops, which are drawn again after
// the fog (game.lobster: what's behind a hill hides).
def build_fog(me:int):
    let fg = fog[me]
    let dark = map(W * H) c: fog_dark(fg[c])
    let corner = map((W + 1) * (H + 1)) v:
        let vx = v % (W + 1)
        let vy = v / (W + 1)
        var sum = 0.0
        var n = 0
        for([ int2 { -1, -1 }, int2 { 0, -1 }, int2 { -1, 0 }, int2 { 0, 0 } ]) d:
            let x = vx + d.x
            let y = vy + d.y
            if x >= 0 and y >= 0 and x < W and y < H:
                sum += dark[y * W + x]
                n++
        sum / float(max(1, n))
    let pos = []::float3
    let col = []::float4
    let idx = []::int
    for(W * H) c:
        fog_cell(pos, col, idx, c, dark, corner)
        if relief.length:
            let cx = c % W
            let cy = c / W
            if cx + 1 < W: fog_face(pos, col, idx, corner, c, c + 1, int2 { cx + 1, cy }, int2 { cx + 1, cy + 1 }, 1, 2, 0, 3)
            if cy + 1 < H: fog_face(pos, col, idx, corner, c, c + W, int2 { cx, cy + 1 }, int2 { cx + 1, cy + 1 }, 3, 2, 0, 1)
    fog_mesh = gl.new_mesh("PC", pos, col, []::float3, []::float2, []::float2, idx)
    for(occluders) o:
        let op = []::float3
        let oc = []::float4
        let oi = []::int
        for(o.cells) c: fog_cell(op, oc, oi, c, dark, corner)
        o.fog = gl.new_mesh("PC", op, oc, []::float3, []::float2, []::float2, oi)

// One tile's fog: a fan from its middle (its own darkness) to its corners (blended), at its height.
def fog_cell(pos:[float3], col:[float4], idx:[int], c:int, dark:[float], corner:[float]):
    let cx = c % W
    let cy = c / W
    let n = pos.length
    let m = iso(float(cx * 1000 + 500), float(cy * 1000 + 500)) - float2 { 0.0, lift_at(float(cx * 1000 + 500), float(cy * 1000 + 500)) * 1.5 }
    pos.push(float3 { m.x, m.y, 0.0 })
    col.push(float4 { 0.0, 0.0, 0.0, dark[c] })
    for([ int2 { 0, 0 }, int2 { 1, 0 }, int2 { 1, 1 }, int2 { 0, 1 } ]) d:
        let p = iso(float((cx + d.x) * 1000), float((cy + d.y) * 1000)) - float2 { 0.0, (if relief.length: height_in(c, float(d.x), float(d.y)) else: 0.0) * LEVEL_PX * 1.5 }
        pos.push(float3 { p.x, p.y, 0.0 })
        col.push(float4 { 0.0, 0.0, 0.0, corner[(cy + d.y) * (W + 1) + cx + d.x] })
    for([ 0, 2, 1, 0, 3, 2, 0, 4, 3, 0, 1, 4 ]) v: idx.push(n + v)

// The fog down a cliff face: the edge a-b shared by tile c (its corners ca, cb) and its near neighbour n (na, nb),
// when c stands above n there (a face that shows; one facing away lies under n's top, fogged already).
def fog_face(pos:[float3], col:[float4], idx:[int], corner:[float], c:int, n:int, a:int2, b:int2, ca:int, cb:int, na:int, nb:int):
    let hca = relief[c * 4 + ca]
    let hcb = relief[c * 4 + cb]
    let hna = relief[n * 4 + na]
    let hnb = relief[n * 4 + nb]
    if hca < hna or hcb < hnb or hca + hcb <= hna + hnb: return
    let k = pos.length
    for([ a, b, b, a ]) v, i:
        let h = [ hca, hcb, hnb, hna ][i]
        let p = iso(float(v.x * 1000), float(v.y * 1000)) - float2 { 0.0, h * LEVEL_PX * 1.5 }
        pos.push(float3 { p.x, p.y, 0.0 })
        col.push(float4 { 0.0, 0.0, 0.0, corner[v.y * (W + 1) + v.x] })
    for([ 0, 1, 2, 0, 2, 3 ]) v: idx.push(k + v)

// ---- high ground (Iso.corner_heights, TerrainView.build_relief): raised tops, cliff faces, rims

class MeshParts:
    pos:[float3] = []
    tc:[float2] = []
    col:[float4] = []

def corner_px(x:int, y:int) -> float2: return iso(float(x * 1000), float(y * 1000))

// The light on raised ground at m (tiles), height h (levels) there: lit as it faces the sun, a little with its height.
// The slope is found on either side of the point, a side across a drop left out, so the light runs smoothly over a
// rough top and down a ramp, and turns sharply only at a rim.
def slope_shade(m:float2, h:float) -> float:
    let e = 0.25
    let g = map([ float2 { 1.0, 0.0 }, float2 { 0.0, 1.0 } ]) d:
        let hi = lift_at((m.x + d.x * e) * 1000.0, (m.y + d.y * e) * 1000.0) / LEVEL_PX - h
        let lo = h - lift_at((m.x - d.x * e) * 1000.0, (m.y - d.y * e) * 1000.0) / LEVEL_PX
        let ok_hi = abs(hi) < e * 1.6
        let ok_lo = abs(lo) < e * 1.6
        if ok_hi and ok_lo: (hi + lo) / (2.0 * e)
        else: if ok_hi: hi / e else: if ok_lo: lo / e else: 0.0
    return 0.05 * h + clamp(g[0] * 0.8 + g[1] * 0.3, -1.0, 1.0) * 0.16

// A cliff tile's lattice cells, nearest the back first, each cut in two triangles: steep ones facing the camera go to
// the faces (the cliff shader, its rock in courses), ones facing away are left out (the ground in front hides them),
// the rest go to the tops. Each triangle goes in the group of its highest point (one list of one: all in that one).
let CLIFF_STEEP = 0.5  // levels a tile: a triangle steeper than this is rock (a face, or the scree at its foot)
def cliff_cells(tops:[MeshParts], faces:[MeshParts], x:int, y:int, c:int):
    let k = CLIFF_STEPS
    let gw = W * k + 1
    let step = 1.0 / float(k)
    var s = 0
    while s <= 2 * k - 2:
        var i = max(0, s - k + 1)
        while i <= min(s, k - 1):
            let j = s - i
            let o = (y * k + j) * gw + x * k + i
            let hk = [ cliff_h[o], cliff_h[o + 1], cliff_h[o + gw + 1], cliff_h[o + gw] ]
            let mk = [ float2 { float(x) + float(i) * step, float(y) + float(j) * step }, float2 { float(x) + float(i + 1) * step, float(y) + float(j) * step },
                       float2 { float(x) + float(i + 1) * step, float(y) + float(j + 1) * step }, float2 { float(x) + float(i) * step, float(y) + float(j + 1) * step } ]
            if max(max(hk[0], hk[1]), max(hk[2], hk[3])) > 0.0:
                // (cut along the diagonal whose ends lie nearest in height: it runs along the rim, so a rim at 45
                // degrees is drawn straight and not as a saw)
                let cut = if abs(hk[1] - hk[3]) < abs(hk[0] - hk[2]) - 0.01: [ [ 0, 1, 3 ], [ 1, 2, 3 ] ] else: [ [ 0, 1, 2 ], [ 0, 2, 3 ] ]
                for(cut) tri:
                    cliff_tri(tops, faces, map(tri) v: mk[v], map(tri) v: hk[v])
            i++
        s++

def cliff_tri(tops:[MeshParts], faces:[MeshParts], m:[float2], h:[float]):
    let q = map(3) v: iso(m[v].x * 1000.0, m[v].y * 1000.0) - float2 { 0.0, h[v] * LEVEL_PX * 1.5 }
    let flat = map(3) v: iso(m[v].x * 1000.0, m[v].y * 1000.0)
    let area = (q[1].x - q[0].x) * (q[2].y - q[0].y) - (q[1].y - q[0].y) * (q[2].x - q[0].x)
    let area0 = (flat[1].x - flat[0].x) * (flat[2].y - flat[0].y) - (flat[1].y - flat[0].y) * (flat[2].x - flat[0].x)
    if area * area0 <= 0.0: return
    let top = max(max(h[0], h[1]), h[2])
    let foot = min(min(h[0], h[1]), h[2])
    let g = max(1, min(int(ceiling(top - 0.001)), MAX_LEVEL))
    // the slope: the plane through the three points
    let ax = m[1].x - m[0].x
    let ay = m[1].y - m[0].y
    let ah = h[1] - h[0]
    let bx = m[2].x - m[0].x
    let by = m[2].y - m[0].y
    let bh = h[2] - h[0]
    let nx = ay * bh - ah * by
    let ny = ah * bx - ax * bh
    let nz = ax * by - ay * bx
    let gx = -nx / nz
    let gy = -ny / nz
    // (a ramp climbs a level a tile: it stays ground, unless a wall cuts into it)
    let on_ramp = ramp[clamp(int((m[0].y + m[1].y + m[2].y) / 3.0), 0, H - 1) * W + clamp(int((m[0].x + m[1].x + m[2].x) / 3.0), 0, W - 1)] == 1
    if sqrt(gx * gx + gy * gy) > (if on_ramp: 1.6 else: CLIFF_STEEP):
        // (a face and the scree at its foot are the rock's: their rim the level it falls from, their foot the one
        // it falls to, so the courses, the lip and the scree run on across the triangles)
        let rim = float(int(ceiling(top - 0.15)))
        let base = float(int(floor(foot + 0.001)))
        let out = faces[if faces.length == 1: 0 else: g]
        // (which way it faces: down the slope; toward +y is lit, toward +x is in shade, as the edges' faces are)
        let dn = abs(gx) + abs(gy)
        let side = clamp(0.5 + 0.5 * (gx - gy) / max(dn, 0.001), 0.0, 1.0)
        for(3) v:
            out.pos.push(float3 { q[v].x, q[v].y, 0.0 })
            out.tc.push(float2 { q[v].x / 48.0, h[v] })
            out.col.push(float4 { rim / float(MAX_LEVEL), side, base / float(MAX_LEVEL), 0.5 })
    else:
        let out = tops[if tops.length == 1: 0 else: g]
        for(3) v:
            out.pos.push(float3 { q[v].x, q[v].y, 0.0 })
            out.tc.push(float2 { h[v] * LEVEL_PX, slope_shade(m[v], h[v]) })
            out.col.push(float4_1)

def top_quad(out:MeshParts, x:int, y:int, c:int):
    if is_cliff_tile(c):
        cliff_cells([ out ], [ MeshParts {} ], x, y, c)
        return
    let rough = tile_rough(c)
    let n = if rough: ROUGH_STEPS else: 1
    let step = 1.0 / float(n)
    let sub = [ float2 { 0.0, 0.0 }, float2 { 1.0, 0.0 }, float2 { 1.0, 1.0 }, float2 { 0.0, 1.0 } ]
    for(n) j:
        for(n) i:
            let hk = map(sub) s: height_in(c, (float(i) + s.x) * step, (float(j) + s.y) * step)
            let gx = (hk[1] + hk[2] - hk[0] - hk[3]) * 0.5
            let gy = (hk[2] + hk[3] - hk[0] - hk[1]) * 0.5
            let flat = 0.05 * (hk[0] + hk[1] + hk[2] + hk[3]) * 0.25 + clamp(gx * 0.8 + gy * 0.3, -1.0, 1.0) * 0.16
            for([ 0, 1, 2, 0, 2, 3 ]) k:
                let lift = hk[k] * LEVEL_PX
                let m = float2 { float(x) + (float(i) + sub[k].x) * step, float(y) + (float(j) + sub[k].y) * step }
                let q = iso(m.x * 1000.0, m.y * 1000.0) - float2 { 0.0, lift * 1.5 }
                out.pos.push(float3 { q.x, q.y, 0.0 })
                out.tc.push(float2 { lift, if rough: slope_shade(m, hk[k]) else: flat })
                out.col.push(float4_1)

def band(out:MeshParts, a:float2, b:float2, y0:float, y1:float, col:float4):
    let q = [ a + float2 { 0.0, y0 }, b + float2 { 0.0, y0 }, b + float2 { 0.0, y1 }, a + float2 { 0.0, y1 } ]
    for([ 0, 1, 2, 0, 2, 3 ]) k:
        out.pos.push(float3 { q[k].x, q[k].y, 0.0 })
        out.tc.push(float2_0)
        out.col.push(col)

// The points along the edge tile c shares with tile n (side 0: c's right-hand edge, n beside it; 1: c's lower edge,
// n below it), each as the tile coordinate, c's height there and n's: one segment a tile, or strips when rough.
def edge_points(c:int, n:int, side:int) -> [[float]]:
    let x = c % W
    let y = c / W
    let k = if tile_rough(c) or tile_rough(n): ROUGH_STEPS else: 1
    return map(k + 1) i:
        let t = float(i) / float(k)
        if side == 0: [ float(x + 1), float(y) + t, height_in(c, 1.0, t), height_in(n, 0.0, t) ]
        else: [ float(x) + t, float(y + 1), height_in(c, t, 1.0), height_in(n, t, 0.0) ]

def rims_of(out:MeshParts, x:int, y:int, c:int):
    if is_cliff_tile(c) or (x > 0 and is_cliff_tile(c - 1)) or (y > 0 and is_cliff_tile(c - W)): return
    let edges = []::[[float]]
    if x > 0 and not (relief[c * 4] - relief[(c - 1) * 4 + 1] < 0.5 and relief[c * 4 + 3] - relief[(c - 1) * 4 + 2] < 0.5):
        edges.push(map(edge_points(c - 1, c, 0)) p: [ p[0], p[1], p[3] ])
    if y > 0 and not (relief[c * 4] - relief[(c - W) * 4 + 3] < 0.5 and relief[c * 4 + 1] - relief[(c - W) * 4 + 2] < 0.5):
        edges.push(map(edge_points(c - W, c, 1)) p: [ p[0], p[1], p[3] ])
    for(edges) e:
        for(e.length - 1) i:
            let a = iso(e[i][0] * 1000.0, e[i][1] * 1000.0) - float2 { 0.0, e[i][2] * LEVEL_PX * 1.5 }
            let b = iso(e[i + 1][0] * 1000.0, e[i + 1][1] * 1000.0) - float2 { 0.0, e[i + 1][2] * LEVEL_PX * 1.5 }
            band(out, a, b, -1.6 * 1.5, 0.0, float4 { 0.12, 0.10, 0.06, 0.5 })
            band(out, a, b, 0.0, 1.2 * 1.5, float4 { 0.55, 0.66, 0.30, 0.9 })

// The cliff face down from tile c to its neighbour n (side as edge_points), where c stands above it.
def face_of(out:MeshParts, c:int, n:int, side:int):
    let pts = edge_points(c, n, side)
    for(pts.length - 1) i:
        let pa = pts[i]
        let pb = pts[i + 1]
        let ha = pa[2]
        let hb = pb[2]
        let na = min(pa[3], ha)
        let nb = min(pb[3], hb)
        if not (ha - na < 0.01 and hb - nb < 0.01):
            let sa = iso(pa[0] * 1000.0, pa[1] * 1000.0)
            let sb = iso(pb[0] * 1000.0, pb[1] * 1000.0)
            let along_a = if side == 0: pa[1] else: pa[0]
            let along_b = if side == 0: pb[1] else: pb[0]
            let quad = [ [ sa.x, sa.y, ha, along_a, ha, na ], [ sb.x, sb.y, hb, along_b, hb, nb ], [ sb.x, sb.y, nb, along_b, hb, nb ],
                         [ sa.x, sa.y, na, along_a, ha, na ] ]
            for([ 0, 1, 2, 0, 2, 3 ]) k:
                let q = quad[k]
                out.pos.push(float3 { q[0], q[1] - q[2] * LEVEL_PX * 1.5, 0.0 })
                out.tc.push(float2 { q[3], q[2] })
                out.col.push(float4 { q[4] / float(MAX_LEVEL), float(side), q[5] / float(MAX_LEVEL), 1.0 })

def near_back_edge(x:int, y:int, top:float) -> bool:
    var dy = -relief_occlude
    while dy <= 0:
        var dx = -relief_occlude
        while dx <= 0:
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 and ny >= 0 and not (dx == 0 and dy == 0):
                if float(level[ny * W + nx] + ramp[ny * W + nx]) < top: return true
            dx++
        dy++
    return false

def tiles_from_back() -> [int]:
    let out = []::int
    for(W + H - 1) d:
        var x = max(0, d - H + 1)
        while x <= min(d, W - 1):
            out.push((d - x) * W + x)
            x++
    return out

// The highest point of cliff tile c.
def cliff_top(c:int) -> float:
    let k = CLIFF_STEPS
    let gw = W * k + 1
    var top = 0.0
    for(k + 1) j:
        for(k + 1) i:
            top = max(top, cliff_h[(c / W * k + j) * gw + c % W * k + i])
    return top

def parts_mesh(m:MeshParts) -> resource<mesh>?:
    if not m.pos.length: return nil
    return gl.new_mesh("PCT", m.pos, m.col, []::float3, m.tc, []::float2, map(m.pos.length) i: i)

def build_relief():
    relief = []
    relief_faces = []
    relief_tops = []
    relief_rims = []
    occluders = []
    if not has_heights: return
    corner_heights()
    let faces = map(MAX_LEVEL + 1): MeshParts {}
    let tops = map(MAX_LEVEL + 1): MeshParts {}
    let rims = map(MAX_LEVEL + 1): MeshParts {}
    let rows = dictionary<int, MeshParts>(256)
    let row_rims = dictionary<int, MeshParts>(256)
    let row_cells = dictionary<int, [int]>(256)
    // (with cliffs, tile by tile from the back, so where the ground folds over itself the near part is drawn last)
    let order = if cliff_tile.length: tiles_from_back() else: map(W * H) c: c
    for(order) c:
        let x = c % W
        let y = c / W
        let top = if is_cliff_tile(c): cliff_top(c) else: max(max(relief[c * 4], relief[c * 4 + 1]), max(relief[c * 4 + 2], relief[c * 4 + 3]))
        if top > 0.0:
            let g = min(int(ceiling(top)), MAX_LEVEL)
            if is_cliff_tile(c): cliff_cells(tops, faces, x, y, c)
            else: top_quad(tops[g], x, y, c)
            rims_of(rims[g], x, y, c)
            if x + 1 < W: face_of(faces[g], c, c + 1, 0)
            if y + 1 < H: face_of(faces[g], c, c + W, 1)
            if near_back_edge(x, y, top):
                let d = x + y
                if not rows.get(d): rows.set(d, MeshParts {})
                if not row_rims.get(d): row_rims.set(d, MeshParts {})
                let rm = rows.get(d)
                let rr = row_rims.get(d)
                if rm: top_quad(rm, x, y, c)
                let cs = row_cells.get(d)
                if cs: cs.push(c)
                else: row_cells.set(d, [ c ])
                if rr: rims_of(rr, x, y, c)
    var g = 1
    while g <= MAX_LEVEL:
        relief_faces.push(parts_mesh(faces[g]))
        relief_tops.push(parts_mesh(tops[g]))
        relief_rims.push(parts_mesh(rims[g]))
        g++
    for(sorted_ints_g(rows.get_keys())) d:
        let rm = rows.get(d)
        if rm:
            let tm = parts_mesh(rm)
            if tm:
                let rr = row_rims.get(d)
                occluders.push(Occluder { sort_y: (float(d) * iso_k * 2000.0 / 3.0 - OCCLUDE_SORT) * 1.5, tops: tm, rims: if rr: parts_mesh(rr) else: nil,
                                          cells: row_cells.get(d) or [] })

def sorted_ints_g(xs:[int]) -> [int]:
    let out = copy(xs)
    insertion_sort(out) a, b: a < b
    return out

// The raised ground under everything, level by level: faces, then tops, then rims.
def draw_relief(art_px:float):
    let mt = mask_tex
    let pt = paths_tex
    let wt = wear_tex
    let at = arc_tex
    if not mt or not pt or not wt or not at: return
    for(relief_faces) f, k:
        if f:
            gl.set_shader("cliff")
            gl.set_uniform("art_px", art_px)
            gl.set_uniform("level_px", LEVEL_PX)
            gl.set_uniform("snow", relief_snow)
            gl.render_mesh(f)
        let t = relief_tops[k]
        if t: draw_terrain_mesh(t, art_px)
        let r = relief_rims[k]
        if r:
            gl.set_shader("color_attr")
            gl.render_mesh(r)

def draw_terrain_mesh(m:resource<mesh>, art_px:float):
    let mt = mask_tex
    let pt = paths_tex
    let wt = wear_tex
    let at = arc_tex
    if not mt or not pt or not wt or not at: return
    gl.set_shader("terrain")
    gl.set_uniform("map_size", float2 { float(W), float(H) })
    gl.set_uniform("art_px", art_px)
    gl.set_uniform("dev_px", art_px * ART_K)
    gl.set_uniform("time", ground_step())
    gl.set_uniform("bank_px", ground_bank_px)
    gl.set_uniform("water_edge", ground_water_edge)
    gl.set_uniform("shore_soft", ground_shore_soft)
    gl.set_uniform("tile_h", iso_k * 2000.0 / 3.0)  // (half a tile down the screen, canvas px: 16 at 30 degrees)
    gl.set_uniform("litter_fringe", ground_litter_fringe)
    gl.set_uniform("water_shallow", ground_water_shallow)
    gl.set_uniform("water_deep", ground_water_deep)
    gl.set_uniform("water_ripples", ground_water_ripples)
    gl.set_uniform("atlas_mix", if ground_atlas_next: ground_atlas_mix else: 0.0)
    gl.set_mesh_texture(m, 0, 0, mt)
    gl.set_mesh_texture(m, 0, 1, pt)
    gl.set_mesh_texture(m, 0, 2, wt)
    gl.set_mesh_texture(m, 0, 3, at)
    gl.set_mesh_texture(m, 0, 4, ground_atlas())
    gl.set_mesh_texture(m, 0, 5, assert prop_tex)
    gl.set_mesh_texture(m, 0, 6, ground_atlas_next or ground_atlas())
    gl.render_mesh(m)

def draw_occluder(o:Occluder, art_px:float):
    draw_terrain_mesh(o.tops, art_px)
    gl.set_shader("color_attr")
    let r = o.rims
    if r: gl.render_mesh(r)
    let f = o.fog
    if f: gl.render_mesh(f)

def draw_ground(art_px:float):
    let gq = ground_quad
    let mt = mask_tex
    let pt = paths_tex
    let wt = wear_tex
    let at = arc_tex
    if not gq or not mt or not pt or not wt or not at: return
    gl.set_shader("terrain")
    gl.set_uniform("map_size", float2 { float(W), float(H) })
    gl.set_uniform("art_px", art_px)
    gl.set_uniform("dev_px", art_px * ART_K)
    gl.set_uniform("time", ground_step())
    gl.set_uniform("bank_px", ground_bank_px)
    gl.set_uniform("water_edge", ground_water_edge)
    gl.set_uniform("shore_soft", ground_shore_soft)
    gl.set_uniform("tile_h", iso_k * 2000.0 / 3.0)  // (half a tile down the screen, canvas px: 16 at 30 degrees)
    gl.set_uniform("litter_fringe", ground_litter_fringe)
    gl.set_uniform("water_shallow", ground_water_shallow)
    gl.set_uniform("water_deep", ground_water_deep)
    gl.set_uniform("water_ripples", ground_water_ripples)
    gl.set_uniform("atlas_mix", if ground_atlas_next: ground_atlas_mix else: 0.0)
    gl.set_mesh_texture(gq, 0, 0, mt)
    gl.set_mesh_texture(gq, 0, 1, pt)
    gl.set_mesh_texture(gq, 0, 2, wt)
    gl.set_mesh_texture(gq, 0, 3, at)
    gl.set_mesh_texture(gq, 0, 4, ground_atlas())
    gl.set_mesh_texture(gq, 0, 5, assert prop_tex)
    gl.set_mesh_texture(gq, 0, 6, ground_atlas_next or ground_atlas())
    gl.render_mesh(gq)

// The ground's heights for the low fog (view/atmosphere's atmo_low_begin), placed as draw_ground_at places the ground:
// the flat ground, then the raised ground level by level, faces and tops. The hills' near edges that hide what's
// behind them are draw_occluder_heights.
def draw_ground_heights():
    gl.set_shader("atmo_low_top")
    gl.set_uniform("level_px", LEVEL_PX)
    let gq = ground_quad
    if gq: gl.render_mesh(gq)
    for(relief_faces) f, k:
        if f:
            gl.set_shader("atmo_low_face")
            gl.render_mesh(f)
        let t = relief_tops[k]
        if t:
            gl.set_shader("atmo_low_top")
            gl.set_uniform("level_px", LEVEL_PX)
            gl.render_mesh(t)

def draw_occluder_heights(o:Occluder):
    gl.set_shader("atmo_low_top")
    gl.set_uniform("level_px", LEVEL_PX)
    gl.render_mesh(o.tops)

// The time the terrain shader sees: in steps, so the water moves only when the still ground is redrawn.
def ground_step() -> float: return floor(gl.time() * GROUND_HZ) / GROUND_HZ

// The ground and hills under everything, as they lie in the world's transform.
def draw_ground_at(fs:float2, cam_px:float2, zoom:float, art_px:float):
    gl.translate(fs / 2.0):
        gl.scale(zoom):
            gl.translate(-cam_px):
                draw_ground(art_px)
                draw_relief(art_px)

// The same through a window-sized picture while the camera holds still, redrawn only when a texture they read changes
// or the water's next step comes. A moving camera draws them straight (the picture would cost more than it saves).
// (A framebuffer's rows run bottom up: read flipped. gl_FragCoord is the window's there too, so the dither lines up.)
def draw_ground_cached(ws:int2, cam_px:float2, zoom:float, art_px:float):
    let fs = float(ws)
    if cam_px != ground_tex_cam or zoom != ground_tex_zoom:
        ground_tex_cam = cam_px
        ground_tex_zoom = zoom
        ground_stale = true
        draw_ground_at(fs, cam_px, zoom, art_px)
        return
    if ground_tex_size != ws:
        ground_tex = gl.create_blank_texture(int3 { ws.x, ws.y, 0 }, texture_format_nomipmap | texture_format_nearest_mag | texture_format_nearest_min | texture_format_clamp)
        ground_tex_size = ws
        ground_stale = true
    let step = ground_step()
    if ground_stale or step != ground_tex_step:
        gl.switch_to_framebuffer(ground_tex)
        gl.ortho()
        gl.clear(float4 { 0.05, 0.05, 0.05, 1.0 })  // (the frame's own, off the map's edge)
        draw_ground_at(fs, cam_px, zoom, art_px)
        gl.switch_to_framebuffer(nil)
        gl.ortho()
        ground_stale = false
        ground_tex_step = step
    let was = gl.blend(blend_none)
    gl.set_shader("sprite_copy")
    gl.set_primitive_texture(0, assert ground_tex)
    gl.draw_mesh("PT", [ float3 { 0.0, 0.0, 0.0 }, float3 { fs.x, 0.0, 0.0 }, float3 { fs.x, fs.y, 0.0 }, float3 { 0.0, fs.y, 0.0 } ],
                 []::float4, []::float3, [ float2 { 0.0, 1.0 }, float2 { 1.0, 1.0 }, float2 { 1.0, 0.0 }, float2 { 0.0, 0.0 } ], []::float2,
                 [ 0, 2, 1, 0, 3, 2 ])
    gl.blend(was)

def draw_fog():
    let fm = fog_mesh
    if fm:
        gl.set_shader("color_attr")
        gl.render_mesh(fm)
