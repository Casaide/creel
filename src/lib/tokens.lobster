// ------------------------------------------------------------------ the scenario

var tokens = []::string
var tp = 0

def next_int() -> int:
    let v, ok = string_to_int(tokens[tp])
    assert ok
    tp++
    return v

def next_tok() -> string:
    tp++
    return tokens[tp - 1]

def expect(word:string):
    assert tokens[tp] == word
    tp++

def read_ints(n:int) -> [int]:
    let out = []::int
    out.vector_capacity(n)
    for(n): out.push(next_int())
    return out
