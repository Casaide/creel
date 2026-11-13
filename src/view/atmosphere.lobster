// The atmosphere (#411): the world drawn into a texture, then to the screen through one pass that grades its colour
// (a cool shadow tint, a warm highlight tint, exposure, contrast, saturation), lays air over it (haze by screen height,
// drifting slowly), darkens the corners and adds a soft bloom. Glows (fires, lit windows, flashes) are drawn into a
// light buffer at a quarter of the size, which the pass uses to light what they fall on. Every value is a mood's in
// data/atmosphere.json (a mod's merges over it); a mood of zeros is the frame drawn straight. No game rules here: the
// game says where the glows are (game/glows.lobster).

// A mood's numbers, each with its range: the pass's uniforms of the same names.
let ATMO_NUMS = [ "exposure", "contrast", "saturation", "shadow", "highlight", "haze", "haze_start", "haze_drift", "vignette",
                  "vignette_radius", "bloom", "bloom_threshold", "glow", "glow_air" ]
let ATMO_MIN = [ -1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 ]
let ATMO_MAX = [ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 1.0, 4.0, 1.0 ]
// A mood's colours ("#rrggbb").
let ATMO_COLS = [ "shadow_tint", "highlight_tint", "haze_colour" ]
// The sun's knobs, each one optional (left out: 0, and its colour white). The ground's shadows are drawn into a shade
// buffer of their own (atmo_shade_begin) instead of onto the world, so they join into one shade where they overlap
// instead of piling up black, and everything standing in them is shaded too: sun_shade is how deep that shade is (its
// colour shade_colour, multiplied in), sun how much the sun's colour (sun_colour) warms what's lit. shafts is light in
// the air: the sun's rays through the gaps in the shade, toward the sun (atmo_sun_dir), shaft_length how far they reach
// (a share of the screen's height), in shaft_colour. mist is a low haze laid over the shade only (the dark woods go
// blue and soft, the lit ground stays clear), in the haze's colour, never lighter than the shade it lies on. deep
// darkens the frame's top, where the far woods are.
// woods darkens and greys what lies under a closed canopy (what the game drew with atmo_shade_canopy: deep in a wood; a
// clearing stays lit), mist lays the haze over it, and shade_grey is how much colour the shade loses. unit_lift keeps
// the units readable where the game marked them (atmo_shade_unit): less shade, wood, mist and haze on them, and a little
// light. unit_rim lights a unit's edge toward the sun, an art pixel wide, so it stands out of the shade behind it.
// low_fog is fog lying in the low ground (a valley's), in low_fog_colour: thickest at the bottom, thinning out up to
// the top the game gives (atmo_low_fog_at, in levels), its top rising and falling by low_fog_drift levels in slow
// drifting banks. Whatever stands in it is fogged by how high each pixel of it is: a tree's top stands out of the fog
// its foot is lost in. The game draws the heights (atmo_low_begin).
// paint softens the picture as a painter's would: each pixel takes the calmest of the four corners round it (a
// Kuwahara filter), so flat colour stays flat and edges stay sharp but the pixels' grain melts into soft patches, as
// in a watercolour; its reach grows with it, up to about two of the art's pixels.
let ATMO_OPT = [ "sun_shade", "sun", "shafts", "shaft_length", "mist", "deep", "woods", "shade_grey", "unit_lift", "unit_rim", "low_fog",
                 "low_fog_drift", "paint" ]
let ATMO_OPT_MAX = [ 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 3.0, 1.0 ]
let ATMO_OPT_COLS = [ "shade_colour", "sun_colour", "shaft_colour", "low_fog_colour" ]
// The glows the game knows how to place (game/glows.lobster), and each one's knobs: colour ("#rrggbb", or "own": the
// thing's own colour), radius (canvas px), strength (0 to 4) and flicker (0 to 1).
let ATMO_SOURCES = [ "building_fire", "ruin_fire", "window", "flash", "shot" ]

class AtmoGlow:
    col:float3
    own:bool
    radius:float
    strength:float
    flicker:float

var atmo_on = false  // a mood is set and the pass runs (atmosphere:off, or no mood: the frame is drawn straight)
var atmo_mood = ""
var atmo_nums = []::float
var atmo_cols = []::float3
var atmo_opt = []::float
var atmo_opt_cols = []::float3
var atmo_sun_dir = float2 { -0.6, 0.8 }  // towards the sun on the screen (y up), for the shafts: the game sets it from its sun
var atmo_shade:resource<texture>? = nil  // the ground's shadows this frame, the screen's size, sampled nearest (red: 1 in shade)
var atmo_ground:resource<texture>? = nil  // the ground's own shade, kept for what stands in it (atmo_shade_standing)
var atmo_shade_used = false              // the game drew shadows into it this frame
var atmo_low:resource<texture>? = nil    // the height of what's drawn at each pixel this frame, for the low fog (atmo_low_begin)
var atmo_low_used = false                // the game drew the heights this frame
var atmo_low_top = 0.0                   // levels: the low fog's top (atmo_low_fog_at; 0: no low fog)
var atmo_low_depth = 1.0                 // levels: from its top down to where it is thickest
var atmo_low_cam = float2_0              // the camera and zoom the heights were drawn with (the fog's banks are pinned to the world)
var atmo_low_zoom = 1.0
var atmo_glows = []::AtmoGlow  // by ATMO_SOURCES; strength 0: the data doesn't name it
var atmo_world:resource<texture>? = nil
var atmo_light:resource<texture>? = nil
var atmo_bloom_a:resource<texture>? = nil
var atmo_bloom_b:resource<texture>? = nil
var atmo_size = int2_0
var atmo_light_used = true  // the light buffer had something in it last frame
var atmo_gpos = []::float3  // this frame's glows, as quads
var atmo_gcol = []::float4
var atmo_gtc = []::float2
var atmo_gidx = []::int

let ATMO_SHADERS = """
PIXELFUNCTIONS
    float atmo_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    vec4 atmo_low_out(float h) {
        float v = clamp(h / 10.0, 0.0, 1.0) * 255.0;
        return vec4(floor(v) / 255.0, fract(v), 0.0, 1.0);
    }
    float atmo_noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(atmo_hash(i), atmo_hash(i + vec2(1, 0)), f.x), mix(atmo_hash(i + vec2(0, 1)), atmo_hash(i + vec2(1, 1)), f.x), f.y);
    }

SHADER atmo_shade_cast
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0
        if (texture(tex0, itc).a < 0.02) discard;
        frag_color = vec4(1.0, 0.0, 0.0, 1.0);
// (the shade of a closed canopy overhead: shade, and its green says deep in a wood)
SHADER atmo_shade_canopy
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0
        if (texture(tex0, itc).a < 0.02) discard;
        frag_color = vec4(1.0, 1.0, 0.0, 1.0);
// (where a unit stands, drawn with additive blending: the buffer's blue says a unit is here, its shade kept)
SHADER atmo_shade_unit
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
    PIXEL
        INPUTS itc:2
        UNIFORMS tex0
        if (texture(tex0, itc).a < 0.02) discard;
        frag_color = vec4(0.0, 0.0, 1.0, 1.0);
// (a unit takes the shade of the ground where it stands, not of whatever lies behind it on the screen: its colour
// carries its foot's place in the buffer, twelve bits across and twelve up (atmo_stand_colour), and all of it takes the
// ground's shade there, read at five places across its feet so it goes into a shadow by degrees; its blue marks it as
// a unit, as atmo_shade_unit does)
SHADER atmo_shade_stand
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
        icolor = acolor;
    PIXEL
        INPUTS itc:2 icolor:4
        UNIFORMS tex0 tex1
        if (texture(tex0, itc).a < 0.02) discard;
        ivec3 c = ivec3(icolor.rgb * 255.0 + 0.5);
        ivec2 foot = ivec2(c.r * 16 + c.g / 16, (c.g % 16) * 256 + c.b);
        ivec2 size = textureSize(tex1, 0);
        vec2 g = vec2(0.0);
        for (int i = -2; i <= 2; i++) g += texelFetch(tex1, clamp(foot + ivec2(i * 4, 0), ivec2(0), size - 1), 0).rg;
        frag_color = vec4(g / 5.0, 1.0, 1.0);
SHADER atmo_copy
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORMS tex0
        frag_color = texelFetch(tex0, ivec2(gl_FragCoord.xy), 0);
// The low fog's heights (atmo_low_begin): what's drawn at a pixel says how high it stands, in levels (0 to 10, in red
// and, finer, green). The ground's tops carry their lift (canvas px) in their first texture coordinate, a cliff's face
// its height (levels) in its second; a sprite standing up is as high as its foot plus how far up the screen from its
// foot the pixel is (its colour: atmo_low_colour).
SHADER atmo_low_top
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        ih = vec2(atc.x, 0.0);
    PIXEL
        INPUTS ih:2
        UNIFORM float level_px
        frag_color = atmo_low_out(ih.x / level_px);
SHADER atmo_low_face
    VERTEX
        INPUTS apos:4 atc:2
        UNIFORMS mvp
        gl_Position = mvp * apos;
        ih = vec2(atc.y, 0.0);
    PIXEL
        INPUTS ih:2
        frag_color = atmo_low_out(ih.x);
SHADER atmo_low_stand
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
        icolor = acolor;
    PIXEL
        INPUTS itc:2 icolor:4
        UNIFORMS tex0
        UNIFORM float level_screen
        if (texture(tex0, itc).a < 0.5) discard;
        ivec3 c = ivec3(icolor.rgb * 255.0 + 0.5);
        float foot_y = float(c.g * 256 + c.b);
        frag_color = atmo_low_out(icolor.r * 10.0 + max(0.0, gl_FragCoord.y - foot_y) / level_screen);
SHADER atmo_shade_clear
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
        icolor = acolor;
    PIXEL
        INPUTS itc:2 icolor:4
        UNIFORMS tex0
        float a = texture(tex0, itc).a * icolor.r;
        if (a < 0.02) discard;
        frag_color = vec4(0.0, 0.0, 0.0, a);
SHADER atmo_glow
    VERTEX
        INPUTS apos:4 atc:2 acolor:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
        itc = atc;
        icolor = acolor;
    PIXEL
        INPUTS itc:2 icolor:4
        float d = length(itc * 2.0 - 1.0);
        float f = clamp(1.0 - d, 0.0, 1.0);
        frag_color = vec4(icolor.rgb * icolor.a * 4.0 * f * f, 0.0);
SHADER atmo_air
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORM vec2 screen
        UNIFORM vec2 cam
        UNIFORM float zoom
        UNIFORM float time
        vec2 sp = gl_FragCoord.xy * 4.0;
        vec2 wp = (vec2(sp.x, screen.y - sp.y) - screen * 0.5) / zoom + cam;
        float n = atmo_noise(wp / 520.0 + vec2(time * 0.021, time * 0.008)) * 0.65 + atmo_noise(wp / 190.0 - vec2(time * 0.034, -time * 0.012)) * 0.35;
        frag_color = vec4(0.0, 0.0, 0.0, n);
SHADER atmo_bright
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORMS tex0
        UNIFORM float bloom_threshold
        ivec2 p = ivec2(gl_FragCoord.xy) * 4;
        vec3 c = (texelFetch(tex0, p + ivec2(1, 1), 0).rgb + texelFetch(tex0, p + ivec2(3, 1), 0).rgb +
                  texelFetch(tex0, p + ivec2(1, 3), 0).rgb + texelFetch(tex0, p + ivec2(3, 3), 0).rgb) * 0.25;
        float m = max(c.r, max(c.g, c.b));
        float k = clamp((m - bloom_threshold) / max(1.0 - bloom_threshold, 0.001), 0.0, 1.0);
        frag_color = vec4(c * k * k, 1.0);
SHADER atmo_blur
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORMS tex0
        UNIFORM vec2 size
        UNIFORM vec2 dir
        vec2 uv = gl_FragCoord.xy / size;
        vec2 o1 = dir * 1.3846 / size;
        vec2 o2 = dir * 3.2308 / size;
        vec3 c = texture(tex0, uv).rgb * 0.2270;
        c += (texture(tex0, uv + o1).rgb + texture(tex0, uv - o1).rgb) * 0.3162;
        c += (texture(tex0, uv + o2).rgb + texture(tex0, uv - o2).rgb) * 0.0703;
        frag_color = vec4(c, 1.0);
SHADER atmo_pass
    VERTEX
        INPUTS apos:4
        UNIFORMS mvp
        gl_Position = mvp * apos;
    PIXEL
        UNIFORMS tex0 tex1 tex2 tex3 tex4
        UNIFORM vec2 screen
        UNIFORM float low_fog
        UNIFORM float low_fog_drift
        UNIFORM vec3 low_fog_colour
        UNIFORM float low_top
        UNIFORM float low_depth
        UNIFORM vec2 cam
        UNIFORM float zoom
        UNIFORM float time
        UNIFORM float sun_shade
        UNIFORM float sun
        UNIFORM float shafts
        UNIFORM float shaft_length
        UNIFORM float mist
        UNIFORM float deep
        UNIFORM float woods
        UNIFORM float shade_grey
        UNIFORM float unit_lift
        UNIFORM float unit_rim
        UNIFORM float paint
        UNIFORM float px
        UNIFORM vec3 shade_colour
        UNIFORM vec3 sun_colour
        UNIFORM vec3 shaft_colour
        UNIFORM vec2 sun_dir
        UNIFORM float exposure
        UNIFORM float contrast
        UNIFORM float saturation
        UNIFORM float shadow
        UNIFORM float highlight
        UNIFORM float haze
        UNIFORM float haze_start
        UNIFORM float haze_drift
        UNIFORM float vignette
        UNIFORM float vignette_radius
        UNIFORM float bloom
        UNIFORM float glow
        UNIFORM float glow_air
        UNIFORM vec3 shadow_tint
        UNIFORM vec3 highlight_tint
        UNIFORM vec3 haze_colour
        const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
        vec2 uv = gl_FragCoord.xy / screen;
        vec3 c = texelFetch(tex0, ivec2(gl_FragCoord.xy), 0).rgb;
        // (paint: the calmest of the four corners round the pixel, its mean colour; a unit is left crisp)
        if (paint > 0.0 && texelFetch(tex3, ivec2(gl_FragCoord.xy), 0).b < 0.5) {
            int r = int(clamp(floor(paint * px * 2.0 + 0.5), 1.0, 8.0));
            ivec2 at = ivec2(gl_FragCoord.xy);
            ivec2 hi = textureSize(tex0, 0) - 1;
            vec3 best = c;
            float least = 1e9;
            for (int q = 0; q < 4; q++) {
                ivec2 dir = ivec2(q % 2 == 0 ? -1 : 1, q < 2 ? -1 : 1);
                vec3 sum = vec3(0.0);
                vec3 sq = vec3(0.0);
                float n = 0.0;
                for (int j = 0; j <= r; j++) for (int i = 0; i <= r; i++) {
                    vec3 s = texelFetch(tex0, clamp(at + dir * ivec2(i, j), ivec2(0), hi), 0).rgb;
                    sum += s;
                    sq += s * s;
                    n += 1.0;
                }
                vec3 m = sum / n;
                vec3 var3 = sq / n - m * m;
                float v = var3.r + var3.g + var3.b;
                if (v < least) { least = v; best = m; }
            }
            c = mix(c, best, clamp(paint * 2.0, 0.0, 1.0));
        }
        // the sun: what's in the ground's shade takes its colour, what's lit the sun's
        // (hard edged, pixel for pixel: the art is crisp, so is its shade)
        vec3 sg = texelFetch(tex3, ivec2(gl_FragCoord.xy), 0).rgb;
        float unit = sg.b * unit_lift;  // (a unit the player must not lose: lifted out of the dark)
        // (its edge toward the sun: a unit here and none an art pixel sunward. Crisp, no blur)
        ivec2 toward = ivec2(round(normalize(sun_dir + vec2(0.0001)) * px));
        float rim = sg.b * (1.0 - texelFetch(tex3, ivec2(gl_FragCoord.xy) + toward, 0).b) * unit_rim;
        float fire = 1.0 - clamp(dot(texture(tex2, uv).rgb, LUM) * glow * 3.0, 0.0, 1.0);  // (a fire's light: no shade by it)
        float sh = sg.r * fire * (1.0 - unit * 0.6);
        // (water keeps most of its light in shade: shade on a stream reads as a road. Told by its colour: blue over red)
        float wet = smoothstep(0.06, 0.22, c.b - c.r);
        float inshade = sh * sun_shade * (1.0 - 0.6 * wet);
        // under a closed canopy (the game's atmo_shade_canopy, pixel for pixel: no blur): deep in a wood it all goes
        // darker, greyer and misty, so a lit clearing stands out of it as the mock-ups' does
        float wood = sg.g * fire * (1.0 - unit);
        float yl = dot(c, LUM);
        // (shade and deep woods lose their colour first; a unit keeps its own, only darkened)
        c = mix(c, vec3(yl), clamp((inshade * shade_grey + wood * woods * 0.5) * (1.0 - unit), 0.0, 1.0));
        c *= mix(mix(vec3(1.0), sun_colour, sun), shade_colour, inshade);
        c *= 1.0 - woods * wood * (0.35 + 0.65 * sh);
        // light in the air: the lit share of the ground between here and the sun, a few taps along its way
        float air = 0.0;
        if (shafts > 0.0) {
            vec2 st = sun_dir * vec2(screen.y / screen.x, 1.0) * shaft_length / 12.0;
            float lit = 0.0;
            float wsum = 0.0;
            for (int i = 1; i <= 12; i++) {
                float w = 1.0 - float(i) / 13.0;
                vec2 at = uv + st * float(i);
                if (at.x < 0.0 || at.y < 0.0 || at.x > 1.0 || at.y > 1.0) break;  // (off the screen: no clamped edge smeared into rays)
                lit += (1.0 - texture(tex3, at).r) * w;
                wsum += w;
            }
            // (near the screen's edge the way to the sun runs off it: fewer taps, and the rays fade with them, no seam)
            float wall = 0.0;
            for (int i = 1; i <= 12; i++) wall += 1.0 - float(i) / 13.0;
            lit = wsum > 0.0 ? lit / wsum * smoothstep(0.0, 1.0, wsum / wall) : 0.0;
            // (rays show where light and shade meet along the way: a lit gap in dark woods, not the open clearing)
            float n = atmo_noise(vec2(dot(gl_FragCoord.xy / screen.y, vec2(sun_dir.y, -sun_dir.x)) * 9.0, 0.5));
            air = lit * (0.55 + 0.45 * n) * shafts * (0.35 + 0.65 * sh);
        }
        vec3 l = texture(tex2, uv).rgb * glow;
        c = c * (1.0 + l) + l * glow_air;
        c += texture(tex1, uv).rgb * bloom;
        c *= 1.0 + exposure;
        float y = dot(c, LUM);
        vec3 st = shadow_tint / max(dot(shadow_tint, LUM), 0.01);
        vec3 ht = highlight_tint / max(dot(highlight_tint, LUM), 0.01);
        c *= mix(vec3(1.0), st, shadow * (1.0 - smoothstep(0.04, 0.42, y)));
        c *= mix(vec3(1.0), ht, highlight * smoothstep(0.08, 0.55, y));
        c = (c - 0.45) * (1.0 + contrast) + 0.45;
        y = dot(c, LUM);
        c = mix(vec3(y), c, 1.0 + saturation * (1.0 - unit));  // (a unit keeps more of its colour than the ground)
        float n = texture(tex2, uv).a;
        float h = haze * mix(0.12, 1.0, pow(smoothstep(haze_start, 1.0, uv.y), 1.4)) * (1.0 + haze_drift * (n * 2.0 - 1.0));
        c = mix(c, haze_colour, clamp(h * (1.0 - unit * 0.6), 0.0, 1.0));
        // (the mist takes the haze's colour but never lightens: where shade overlaps under a closed canopy it must stay
        // at least as dark as one lone tree's shade, never a pale grey)
        float mk = clamp(mist * wood * (0.8 + 0.2 * n) * (0.5 + 0.5 * uv.y), 0.0, 1.0);
        if (mk > 0.0) {
            vec3 misty = mix(c, haze_colour * 0.85, mk);
            c = misty * clamp(max(dot(c, LUM), 0.0) / max(dot(misty, LUM), 0.0001), 0.0, 1.0);
        }
        c += shaft_colour * air * (0.5 + 0.5 * uv.y);
        c *= 1.0 - deep * smoothstep(0.55, 1.0, uv.y) * (0.4 + 0.6 * sh) * (1.0 - unit);
        // the low fog, after the deep woods' darkening (fog is lit air, not shade): by how far below its top the pixel's
        // thing stands, its top drifting in slow banks pinned to the world (a unit in it is kept a little clearer, a dark
        // shape in the fog)
        if (low_fog > 0.0) {
            vec2 wp = (vec2(gl_FragCoord.x, screen.y - gl_FragCoord.y) - screen * 0.5) / zoom + cam;
            float fn = atmo_noise(wp / 340.0 + vec2(time * 0.018, time * 0.005)) * 0.6 + atmo_noise(wp / 120.0 - vec2(time * 0.026, -time * 0.009)) * 0.4;
            float top = low_top + (fn - 0.5) * 2.0 * low_fog_drift;
            // (read over a few art px round the pixel: fog is soft, and an edge between ground deep in it and ground
            // above it is too)
            float f = 0.0;
            float f0 = 0.0;
            ivec2 size = textureSize(tex4, 0);
            for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
                vec4 hv = texelFetch(tex4, clamp(ivec2(gl_FragCoord.xy + vec2(i, j) * px * 1.5), ivec2(0), size - 1), 0);
                float hl = (hv.r * 255.0 + hv.g) / 25.5;
                float t = clamp((top - hl) / max(low_depth, 0.01), 0.0, 1.0);
                float k = 1.0 - (1.0 - t) * (1.0 - t);  // (it closes in quickly below its top)
                f += k * (i == 0 && j == 0 ? 0.2 : 0.1);
                if (i == 0 && j == 0) f0 = k;
            }
            f = min(f, f0 + 0.12);  // (soft within the fog, but no pale rim bled over a ridge standing out of it)
            c = mix(c, low_fog_colour, clamp(low_fog * f * (1.0 - unit * 0.35), 0.0, 1.0));
        }
        c *= 1.0 + unit * 0.35;
        c = mix(c, c * 1.5 + sun_colour * 0.18, rim);  // (the rim: the sun caught on his sunward edge)
        vec2 d = (uv - 0.5) * vec2(screen.x / screen.y, 1.0);
        c *= 1.0 - vignette * smoothstep(vignette_radius, vignette_radius + 0.6, length(d));
        frag_color = vec4(c, 1.0);
"""

def atmo_hex_ok(s:string) -> bool:
    if s.length != 7 or s[0] != '#': return false
    for(6) i:
        let c = s[i + 1]
        if not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')): return false
    return true

def atmo_hex(s:string) -> float3:
    def byte(i:int) -> float: return float(string_to_int(s.substring(i, 2), 16)) / 255.0
    return float3 { byte(1), byte(3), byte(5) }

def atmo_is_num(v:JV) -> bool: return v.kind == J_INT or v.kind == J_FLOAT

// What's wrong with one mood, or [].
def atmo_mood_problems(name:string, m:JV) -> [string]:
    let out = []::string
    if m.kind != J_OBJ: return [ "mood {name} isn\'t an object" ]
    for(m.keys) k:
        if not has_s(ATMO_NUMS, k) and not has_s(ATMO_COLS, k) and not has_s(ATMO_OPT, k) and not has_s(ATMO_OPT_COLS, k) and not starts_with(k, "_"): out.push("mood {name}: no knob \'{k}\'")
    for(ATMO_OPT) k, i:
        let v = get(m, k)
        if v and (not atmo_is_num(v) or as_float(v) < 0.0 or as_float(v) > ATMO_OPT_MAX[i]): out.push("mood {name}: \'{k}\' must be a number from 0 to {ATMO_OPT_MAX[i]}")
    for(ATMO_OPT_COLS) k:
        let v = get(m, k)
        if v and (v.kind != J_STR or not atmo_hex_ok(v.s)): out.push("mood {name}: \'{k}\' must be a colour, \"#rrggbb\"")
    for(ATMO_NUMS) k, i:
        let v = get(m, k)
        if not v: out.push("mood {name}: no \'{k}\'")
        elif not atmo_is_num(v) or as_float(v) < ATMO_MIN[i] or as_float(v) > ATMO_MAX[i]: out.push("mood {name}: \'{k}\' must be a number from {ATMO_MIN[i]} to {ATMO_MAX[i]}")
    for(ATMO_COLS) k:
        let v = get(m, k)
        if not v or v.kind != J_STR or not atmo_hex_ok(v.s): out.push("mood {name}: \'{k}\' must be a colour, \"#rrggbb\"")
    return out

// What's wrong with an atmosphere.json (moods, default, maps, glows), or [].
def atmo_problems(j:JV) -> [string]:
    let out = []::string
    let moods = gobj(j, "moods")
    if not moods.keys.length: out.push("atmosphere.json has no moods")
    for(sorted_strs(moods.keys)) name:
        if not starts_with(name, "_"): append_into(out, atmo_mood_problems(name, at(moods, name)))
    let def_mood = gstr(j, "default", "")
    if not has(moods, def_mood): out.push("atmosphere.json: the default \'{def_mood}\' isn\'t a mood")
    let maps = gobj(j, "maps")
    for(sorted_strs(maps.keys)) id:
        let v = at(maps, id)
        if v.kind != J_STR or not has(moods, v.s): out.push("atmosphere.json: map {id}\'s mood isn\'t a mood")
    let glows = gobj(j, "glows")
    for(sorted_strs(glows.keys)) s:
        if starts_with(s, "_"): continue
        if not has_s(ATMO_SOURCES, s):
            out.push("atmosphere.json: no glow source \'{s}\' (sources: {concat_string(ATMO_SOURCES, ", ")})")
            continue
        let g = at(glows, s)
        let col = get(g, "colour")
        if not col or col.kind != J_STR or not (col.s == "own" or atmo_hex_ok(col.s)): out.push("glow {s}: \'colour\' must be \"#rrggbb\" or \"own\"")
        for([ "radius", "strength", "flicker" ]) k, i:
            let v = get(g, k)
            let top = [ 1000.0, 4.0, 1.0 ][i]
            if not v or not atmo_is_num(v) or as_float(v) < 0.0 or as_float(v) > top: out.push("glow {s}: \'{k}\' must be a number from 0 to {top}")
    return out

// The mood a match on map_id gets: the asked one ("": the map's, else the default).
def atmo_mood_for(j:JV, map_id:string, asked:string) -> string:
    if asked != "": return asked
    return gstr(gobj(j, "maps"), map_id, gstr(j, "default", ""))

// Sets the mood (and the glows) from the data, "off" for none. Returns what's wrong ("" when it's set): an unknown mood.
def atmo_set(j:JV, mood:string) -> string:
    atmo_on = false
    atmo_mood = mood
    if mood == "off": return ""
    let m = get(gobj(j, "moods"), mood)
    if not m: return "no mood \'{mood}\' in atmosphere.json (moods: {concat_string(sorted_strs(filter(gobj(j, "moods").keys) k: not starts_with(k, "_")), ", ")})"
    let bad = atmo_mood_problems(mood, m)
    if bad.length: return bad[0]
    atmo_nums = map(ATMO_NUMS) k: as_float(at(m, k))
    atmo_cols = map(ATMO_COLS) k: atmo_hex(gstr(m, k, ""))
    atmo_opt = map(ATMO_OPT) k: (if get(m, k): as_float(at(m, k)) else: 0.0)
    atmo_opt_cols = map(ATMO_OPT_COLS) k: (if get(m, k): atmo_hex(gstr(m, k, "")) else: float3_1)
    let glows = gobj(j, "glows")
    atmo_glows = map(ATMO_SOURCES) s:
        let g = get(glows, s)
        if g:
            let c = gstr(g, "colour", "own")
            AtmoGlow { if c == "own": float3_1 else: atmo_hex(c), c == "own", as_float(at(g, "radius")), as_float(at(g, "strength")),
                       as_float(at(g, "flicker")) }
        else:
            AtmoGlow { float3_1, true, 0.0, 0.0, 0.0 }
    atmo_on = true
    return ""

// Between two moods: a's light turning into b's, t of the way (0 a .. 1 b), so the day moves through dawn, day, dusk
// and night without a jump. Every number and colour is mixed; the glows are the file's, as atmo_set's. Returns why not.
def atmo_set_between(j:JV, a:string, b:string, t:float) -> string:
    if t <= 0.0 or a == b: return atmo_set(j, a)
    if t >= 1.0: return atmo_set(j, b)
    let why = atmo_set(j, b)
    if why != "" or not atmo_on: return why
    let nb = atmo_nums
    let cb = atmo_cols
    let ob = atmo_opt
    let pb = atmo_opt_cols
    let why_a = atmo_set(j, a)
    if why_a != "" or not atmo_on: return why_a
    atmo_nums = map(atmo_nums) v, i: lerp(v, nb[i], t)
    atmo_cols = map(atmo_cols) v, i: lerp(v, cb[i], t)
    atmo_opt = map(atmo_opt) v, i: lerp(v, ob[i], t)
    atmo_opt_cols = map(atmo_opt_cols) v, i: lerp(v, pb[i], t)
    return ""

def atmo_num(k:string) -> float: return atmo_nums[find(ATMO_NUMS) n: n == k]
def atmo_opt_num(k:string) -> float: return atmo_opt[find(ATMO_OPT) n: n == k]

// Whether the ground's shadows go into the shade buffer this mood (else the game draws them onto the world as before).
def atmo_shading() -> bool: return atmo_on and atmo_opt_num("sun_shade") > 0.0

// The shade buffer is drawn into from here (cleared to lit), placed as the world is (its camera and zoom): the game draws
// its ground shadows with atmo_shade_cast, then what stands up out of them (trees, rocks: not the men, who stand in the
// shade) with atmo_shade_clear, its colour's red how much of it shows. Before atmo_begin.
def atmo_shade_begin():
    let ws = gl.window_size()
    if not atmo_shade or ws != atmo_size:
        atmo_shade = atmo_target(ws, true)
    gl.switch_to_framebuffer(atmo_shade)
    gl.ortho()
    gl.clear(float4 { 0.0, 0.0, 0.0, 1.0 })
    atmo_shade_used = true

// What stands in the shade is drawn from here: call it when the ground's shade is in the buffer (the shadows, the
// canopy) and before anything that stands up. It keeps a copy of the ground's shade, and atmo_shade_stand reads that
// copy, so a man or a horse takes the shade of the ground where he stands, the same from his feet to his head, and a
// tree's shadow on the ground behind him is not painted flat across his back. The game sets its camera again after.
def atmo_shade_standing():
    let ws = gl.window_size()
    if not atmo_ground or gl.texture_size(atmo_ground) != ws: atmo_ground = atmo_target(ws, true)
    let was = gl.blend(blend_none)
    gl.switch_to_framebuffer(atmo_ground)
    gl.ortho()
    gl.set_shader("atmo_copy")
    gl.set_primitive_texture(0, assert atmo_shade)
    atmo_quad(ws)
    gl.switch_to_framebuffer(atmo_shade)
    gl.ortho()
    gl.blend(was)
    gl.set_primitive_texture(1, atmo_ground)

// The colour to draw a unit's sprite with under atmo_shade_stand: foot is where it stands on the screen, in pixels
// from the top left (where the ground's shade is read for all of it).
def atmo_stand_colour(foot:float2) -> float4:
    let ws = gl.window_size()
    let x = clamp(int(foot.x), 0, min(ws.x, 4096) - 1)
    let y = clamp(ws.y - 1 - int(foot.y), 0, min(ws.y, 4096) - 1)
    return float4 { float(x / 16) / 255.0, float((x % 16) * 16 + y / 256) / 255.0, float(y % 256) / 255.0, 1.0 }

// The low fog's place in this map: its top and how deep it is to its thickest, in levels (top 0: none). The mood
// says how thick it is (low_fog), so the same valley's fog thins as the day comes on.
def atmo_low_fog_at(top:float, depth:float):
    atmo_low_top = top
    atmo_low_depth = max(0.01, depth)

// Whether the game should draw the heights this frame: a mood with low fog, in a map with a fog top.
def atmo_low_fogging() -> bool: return atmo_on and atmo_low_top > 0.0 and atmo_opt_num("low_fog") > 0.0

// The heights are drawn from here (cleared to 10 levels: above any fog), placed as the world is (cam and zoom, for
// the fog's banks). The game draws the ground's heights (draw_ground_heights, game/ground.lobster), then what stands
// on it, back to front, with the shader atmo_low_stand and each one's colour atmo_low_colour, and the hills' near
// edges again where they hide what's behind them. Before atmo_begin.
def atmo_low_begin(cam:float2, zoom:float):
    let ws = gl.window_size()
    if not atmo_low or gl.texture_size(atmo_low) != ws: atmo_low = atmo_target(ws, true)
    gl.switch_to_framebuffer(atmo_low)
    gl.ortho()
    gl.clear(float4 { 1.0, 0.0, 0.0, 1.0 })
    atmo_low_used = true
    atmo_low_cam = cam
    atmo_low_zoom = zoom

// The colour to draw a sprite with under atmo_low_stand: its foot on the screen (px from the top left) and the level
// it stands at.
def atmo_low_colour(foot:float2, lv:float) -> float4:
    let ws = gl.window_size()
    let y = clamp(ws.y - 1 - int(foot.y), 0, 65535)
    return float4 { clamp(lv, 0.0, 10.0) / 10.0, float(y / 256) / 255.0, float(y % 256) / 255.0, 1.0 }

// A source's index (ATMO_SOURCES), for atmo_glow.
def atmo_source(name:string) -> int: return find(ATMO_SOURCES) s: s == name

// A glow of source src this frame at p (canvas px, as atmo_end is given them), its own colour col (for "own"), k its
// share (a flash fading: below 1), seed its own flicker.
def atmo_glow(src:int, p:float2, col:float3, k:float, seed:float):
    if not atmo_on: return
    let g = atmo_glows[src]
    if g.strength <= 0.0 or k <= 0.0: return
    let t = gl.time()
    let wave = 0.5 + 0.5 * sin((t * 9.0 + seed) * 57.29578) * sin((t * 2.7 + seed * 1.7) * 57.29578)
    let f = (1.0 - g.flicker * wave) * k
    let r = g.radius * (1.0 + 0.08 * g.flicker * sin((t * 5.3 + seed * 0.6) * 57.29578))
    let c = if g.own: col else: g.col
    let a = min(1.0, g.strength * f / 4.0)
    let v = atmo_gpos.length
    for([ float2 { -1.0, -1.0 }, float2 { 1.0, -1.0 }, float2 { 1.0, 1.0 }, float2 { -1.0, 1.0 } ]) o:
        atmo_gpos.push(float3 { p.x + o.x * r, p.y + o.y * r * 0.62, 0.0 })  // (flattened: it lies on the ground)
        atmo_gcol.push(float4 { c.x, c.y, c.z, a })
        atmo_gtc.push((o + float2_1) * 0.5)
    for([ 0, 1, 2, 0, 2, 3 ]) i: atmo_gidx.push(v + i)

def atmo_target(size:int2, nearest:bool) -> resource<texture>:
    let tf = texture_format_nomipmap | texture_format_clamp | (if nearest: texture_format_nearest_mag | texture_format_nearest_min else: texture_format_none)
    return gl.create_blank_texture(int3 { size.x, size.y, 0 }, tf)

def atmo_quad(size:int2):
    let s = float(size)
    gl.draw_mesh("P", [ float3 { 0.0, 0.0, 0.0 }, float3 { s.x, 0.0, 0.0 }, float3 { s.x, s.y, 0.0 }, float3 { 0.0, s.y, 0.0 } ], []::float4, []::float3,
                 []::float2, []::float2, [ 0, 2, 1, 0, 3, 2 ])

def atmo_quarter() -> int2: return int2 { max(1, atmo_size.x / 4), max(1, atmo_size.y / 4) }

// The world is drawn into the texture from here (cleared to col), when the pass is on. Returns whether it is.
def atmo_begin(col:float4) -> bool:
    if not atmo_on: return false
    let ws = gl.window_size()
    if ws != atmo_size or not atmo_world:
        atmo_size = ws
        atmo_world = atmo_target(ws, true)
        let q = atmo_quarter()
        atmo_light = atmo_target(q, false)
        atmo_light_used = true  // (a new buffer: cleared before it's read)
        atmo_bloom_a = atmo_target(q, false)
        atmo_bloom_b = atmo_target(q, false)
        if not atmo_shade:  // (a game that never draws shade: a lit one, read as none)
            atmo_shade = atmo_target(ws, true)
            gl.switch_to_framebuffer(atmo_shade)
            gl.clear(float4 { 0.0, 0.0, 0.0, 1.0 })
        gl.switch_to_framebuffer(atmo_bloom_a)  // (read with bloom 0: black)
        gl.clear(float4 { 0.0, 0.0, 0.0, 1.0 })
    atmo_gpos = []
    atmo_gcol = []
    atmo_gtc = []
    atmo_gidx = []
    gl.switch_to_framebuffer(atmo_world)
    gl.ortho()
    gl.clear(col)
    return true

// Back into the world's texture, as it was, after something drew into another (the still ground's picture).
def atmo_rebind():
    gl.switch_to_framebuffer(atmo_world)
    gl.ortho()

// The world done: the glows into the light buffer (placed as the world is: its camera and zoom, canvas px of a world
// unit), the bloom, then the pass to the screen. The screen's ortho and blend after.
def atmo_end(cam:float2, zoom:float, canvas:float):
    let q = atmo_quarter()
    let was = gl.blend(blend_none)
    let drift = atmo_num("haze") > 0.0 and atmo_num("haze_drift") > 0.0
    let lit = drift or atmo_gidx.length > 0
    if lit or atmo_light_used:  // (nothing to light and nothing lit last frame: the buffer stays as it is, a switch saved)
        gl.switch_to_framebuffer(atmo_light)
        gl.ortho()
        gl.clear(float4 { 0.0, 0.0, 0.0, 0.5 })  // (alpha: the haze's drift, 0.5 where it doesn't drift)
    atmo_light_used = lit
    if drift:  // (the drift is low in detail: worked out here, at a quarter of the pixels)
        gl.set_shader("atmo_air")
        gl.set_uniform("screen", float(atmo_size))
        gl.set_uniform("cam", cam)
        gl.set_uniform("zoom", zoom)
        gl.set_uniform("time", gl.time())
        atmo_quad(q)
    if atmo_gidx.length:
        gl.blend(blend_add)
        gl.set_shader("atmo_glow")
        gl.scale(float(q.x) / float(atmo_size.x)):
            gl.translate(float(atmo_size) / 2.0):
                gl.scale(zoom):
                    gl.translate(-cam):
                        gl.scale(canvas): gl.draw_mesh("PCT", atmo_gpos, atmo_gcol, []::float3, atmo_gtc, []::float2, atmo_gidx)
        gl.blend(blend_none)
    if atmo_num("bloom") > 0.0:
        gl.switch_to_framebuffer(atmo_bloom_a)
        gl.ortho()
        gl.set_shader("atmo_bright")
        gl.set_uniform("bloom_threshold", atmo_num("bloom_threshold"))
        gl.set_primitive_texture(0, assert atmo_world)
        atmo_quad(q)
        gl.switch_to_framebuffer(atmo_bloom_b)  // (one blur, across then down, its taps spread wide: each switch makes and frees a framebuffer)
        gl.ortho()
        gl.set_shader("atmo_blur")
        gl.set_uniform("size", float(q))
        gl.set_uniform("dir", float2 { 2.5, 0.0 })
        gl.set_primitive_texture(0, assert atmo_bloom_a)
        atmo_quad(q)
        gl.switch_to_framebuffer(atmo_bloom_a)
        gl.ortho()
        gl.set_uniform("dir", float2 { 0.0, 2.5 })
        gl.set_primitive_texture(0, assert atmo_bloom_b)
        atmo_quad(q)
    gl.switch_to_framebuffer(nil)
    gl.ortho()
    gl.blend(blend_none)
    gl.set_shader("atmo_pass")
    gl.set_uniform("screen", float(atmo_size))
    for(ATMO_NUMS) k, i: gl.set_uniform(k, atmo_nums[i])
    for(ATMO_COLS) k, i: gl.set_uniform(k, atmo_cols[i])
    let shaded = atmo_shade_used and atmo_shade != nil
    for(ATMO_OPT) k, i: gl.set_uniform(k, if not shaded and (k == "sun_shade" or k == "shafts" or k == "mist" or k == "woods" or k == "unit_lift" or k == "unit_rim"): 0.0 else: atmo_opt[i])
    for(ATMO_OPT_COLS) k, i: gl.set_uniform(k, atmo_opt_cols[i])
    gl.set_uniform("sun_dir", normalize(atmo_sun_dir))
    let low = atmo_low_used and atmo_low != nil and atmo_low_top > 0.0
    if not low: gl.set_uniform("low_fog", 0.0)
    gl.set_uniform("low_top", atmo_low_top)
    gl.set_uniform("low_depth", atmo_low_depth)
    gl.set_uniform("cam", atmo_low_cam)
    gl.set_uniform("zoom", atmo_low_zoom)
    gl.set_uniform("time", gl.time())
    gl.set_uniform("px", max(1.0, floor(zoom + 0.5)))  // (an art pixel, in screen pixels)
    atmo_shade_used = false
    atmo_low_used = false
    gl.set_primitive_texture(4, if low: assert atmo_low else: assert atmo_shade)
    gl.set_primitive_texture(3, assert atmo_shade)
    gl.set_primitive_texture(0, assert atmo_world)
    gl.set_primitive_texture(1, assert atmo_bloom_a)
    gl.set_primitive_texture(2, assert atmo_light)
    atmo_quad(atmo_size)
    gl.blend(was)
    gl.set_shader("color")
