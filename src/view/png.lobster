// ------------------------------------------------------------------ PNG (RGBA8, stored deflate: no compression)
// png_bytes(rgba, w, h): the file's bytes as a string, for write_file. Baked art is kept this way.

let png_crc_table = map(256) n:
    var c = n
    for(8): c = if c & 1: 0xEDB88320 ^ (c >> 1) else: c >> 1
    c

def png_be32(out:[int], v:int):
    out.push((v >> 24) & 255)
    out.push((v >> 16) & 255)
    out.push((v >> 8) & 255)
    out.push(v & 255)

def png_chunk(out:[int], kind:string, data:[int]):
    png_be32(out, data.length)
    let start = out.length
    for(kind) ch: out.push(ch)
    for(data) b: out.push(b)
    var crc = 0xFFFFFFFF
    var i = start
    while i < out.length:
        crc = png_crc_table[(crc ^ out[i]) & 255] ^ (crc >> 8)
        i++
    png_be32(out, crc ^ 0xFFFFFFFF)

def png_bytes(rgba:[int], w:int, h:int) -> string:
    let raw = []::int
    for(h) y:
        raw.push(0)
        var i = y * w * 4
        let e = i + w * 4
        while i < e:
            raw.push(rgba[i])
            i++
    let z = [ 0x78, 0x01 ]
    var at = 0
    var s1 = 1
    var s2 = 0
    for(raw) b:
        s1 = (s1 + b) % 65521
        s2 = (s2 + s1) % 65521
    while at < raw.length:
        let len = min(65535, raw.length - at)
        z.push(if at + len >= raw.length: 1 else: 0)
        z.push(len & 255)
        z.push(len >> 8)
        z.push((len ^ 0xFFFF) & 255)
        z.push((len ^ 0xFFFF) >> 8)
        for(len) k: z.push(raw[at + k])
        at += len
    png_be32(z, (s2 << 16) | s1)
    let out = [ 137, 80, 78, 71, 13, 10, 26, 10 ]
    let ihdr = []::int
    png_be32(ihdr, w)
    png_be32(ihdr, h)
    for([ 8, 6, 0, 0, 0 ]) b: ihdr.push(b)
    png_chunk(out, "IHDR", ihdr)
    png_chunk(out, "IDAT", z)
    png_chunk(out, "IEND", [])
    return vector_to_buffer(out, 1)
