#!/usr/bin/env python3
"""Vendor-neutral reverse emitter prototype: Yosys JSON ($lut + $_DFF*/$_SDFF*/$_SDFFE*/$_SDFFCE*)
-> plain synthesizable Verilog. Each LUT becomes a width-w localparam indexed by its live inputs
(no LUT6 primitive, no padding). DFF semantics follow Yosys, including SDFFCE enable-over-reset.
Unknown cell types fail closed."""
import json, sys
src, mod, out = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.load(open(src))['modules'][mod]
def ref(b):
    if isinstance(b, int): return f"n[{b}]"
    return "1'b1" if b == '1' else "1'b0"
maxnet = 0
for c in m['cells'].values():
    for bs in c['connections'].values():
        for b in bs:
            if isinstance(b, int): maxnet = max(maxnet, b)
for p in m['ports'].values():
    for b in p['bits']:
        if isinstance(b, int): maxnet = max(maxnet, b)
L = [f"module {mod}("]
L.append(",\n".join(f"    {p['direction']} wire [{len(p['bits'])-1}:0] {name}" for name, p in m['ports'].items()))
L.append(");")
L.append(f"    wire [{maxnet}:0] n;")
for name, p in m['ports'].items():
    for i, b in enumerate(p['bits']):
        if not isinstance(b, int): continue
        if p['direction'] == 'input': L.append(f"    assign n[{b}] = {name}[{i}];")
for name, p in m['ports'].items():
    if p['direction'] == 'output':
        for i, b in enumerate(p['bits']):
            L.append(f"    assign {name}[{i}] = {ref(b)};")
k = 0
for cname in sorted(m['cells']):
    c = m['cells'][cname]; t = c['type']
    if t == '$scopeinfo': continue
    if t == '$lut':
        A = c['connections']['A']; w = len(A)
        tt = c['parameters']['LUT']; tt = tt if isinstance(tt, str) else format(tt, 'b'); tt = tt.zfill(1 << w)
        addr = "{" + ", ".join(ref(b) for b in reversed(A)) + "}"
        L.append(f"    localparam [{(1<<w)-1}:0] T{k} = {1<<w}'b{tt};")
        L.append(f"    assign {ref(c['connections']['Y'][0])} = T{k}[{addr}];")
        k += 1
    elif t.startswith('$_') and 'DFF' in t:
        kind, code = t[2:-1].split('_')[:2]
        if kind not in ('DFF', 'DFFE', 'SDFF', 'SDFFE', 'SDFFCE') or code[0] != 'P':
            sys.exit(f"fail-closed: unsupported sequential cell {t} ({cname})")
        q = ref(c['connections']['Q'][0]); d = ref(c['connections']['D'][0])
        en = None
        if 'E' in c['connections']:
            e = ref(c['connections']['E'][0]); en = e if code[-1] == 'P' else f"!{e}"
        rs = None
        if kind.startswith('SDFF'):
            r = ref(c['connections']['R'][0]); rs = (r if code[1] == 'P' else f"!{r}", code[2])
        L.append(f"    reg r{k}; assign {q} = r{k};")
        body = d
        if kind == 'SDFFCE':   # enable gates reset
            body = f"({en}) ? (({rs[0]}) ? 1'b{rs[1]} : {d}) : r{k}"
        else:
            if en: body = f"({en}) ? {d} : r{k}"
            if rs: body = f"({rs[0]}) ? 1'b{rs[1]} : ({body})"
        L.append(f"    always @(posedge clk) r{k} <= {body};")
        k += 1
    else:
        sys.exit(f"fail-closed: unsupported cell {t} ({cname})")
L.append("endmodule")
open(out, 'w').write("\n".join(L) + "\n")
print(f"emitted {out}: {k} cells, no vendor primitives")
