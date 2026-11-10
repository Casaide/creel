// ------------------------------------------------------------------ SHA-256 (String.sha256_text: the race key)

let SHA_M = 0xFFFFFFFF
let SHA_K = [ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
              0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
              0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
              0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
              0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
              0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
              0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
              0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 ]

def rotr(x:int, n:int) -> int: return ((x >> n) | (x << (32 - n))) & SHA_M

// The hex digest of the string's bytes.
def sha256_text(text:string) -> string:
    let bytes = map(text.length) n: text[n] & 0xFF
    let bitlen = bytes.length * 8
    bytes.push(0x80)
    while bytes.length % 64 != 56: bytes.push(0)
    for(8) n: bytes.push((bitlen >> (56 - n * 8)) & 0xFF)
    var h = [ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 ]
    let w = map(64): 0
    var off = 0
    while off < bytes.length:
        for(16) t: w[t] = (bytes[off + t * 4] << 24) | (bytes[off + t * 4 + 1] << 16) | (bytes[off + t * 4 + 2] << 8) | bytes[off + t * 4 + 3]
        var t = 16
        while t < 64:
            let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
            let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
            w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & SHA_M
            t++
        var a = h[0]
        var b = h[1]
        var c = h[2]
        var d = h[3]
        var e = h[4]
        var f = h[5]
        var g = h[6]
        var hh = h[7]
        for(64) r:
            let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ ((~e & SHA_M) & g)
            let t1 = (hh + S1 + ch + SHA_K[r] + w[r]) & SHA_M
            let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = (S0 + maj) & SHA_M
            hh = g
            g = f
            f = e
            e = (d + t1) & SHA_M
            d = c
            c = b
            b = a
            a = (t1 + t2) & SHA_M
        h = [ (h[0] + a) & SHA_M, (h[1] + b) & SHA_M, (h[2] + c) & SHA_M, (h[3] + d) & SHA_M,
              (h[4] + e) & SHA_M, (h[5] + f) & SHA_M, (h[6] + g) & SHA_M, (h[7] + hh) & SHA_M ]
        off += 64
    return lowercase(concat_string(map(h) x: number_to_string(x, 16, 8), ""))
