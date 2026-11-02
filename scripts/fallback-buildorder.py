#!/usr/bin/env python3
"""Urutan build cadangan, dipakai hanya kalau scripts/buildorder.py upstream gagal.

Pemakaian: fallback-buildorder.py <folder termux-packages>  > buildorder.txt
Keluaran : satu baris per paket, "<folder>/<nama>", yang dependensinya dibangun lebih dulu.

Cara kerja:
  * membaca packages/, root-packages/, x11-packages/ (folder berisi build.sh)
  * sub-paket (<nama>.subpackage.sh) dianggap bagian dari paket induknya,
    jadi dependensi ke sub-paket = dependensi ke induk, dan dependensi ke diri sendiri dibuang
  * siklus yang tersisa (lintas paket) dipecah dengan melewati sisi balik saat DFS
  * hanya TERMUX_PKG_DEPENDS dan TERMUX_PKG_BUILD_DEPENDS yang dibaca; nilai berisi variabel ($...) dilewati
Catatan stderr: jumlah paket, jumlah sisi, dan sisi yang dipecah.
"""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
DIRS = ["packages", "root-packages", "x11-packages"]
ASSIGN = re.compile(
    r"^[ \t]*TERMUX_PKG_(?:BUILD_)?DEPENDS\+?=(?:\"([^\"]*)\"|'([^']*)'|([^\s#]+))",
    re.M)

pkgs = {}      # nama -> folder
alias = {}     # nama sub-paket -> nama induk
files = {}
for d in DIRS:
    base = os.path.join(root, d)
    if not os.path.isdir(base):
        continue
    for name in sorted(os.listdir(base)):
        if os.path.isfile(os.path.join(base, name, "build.sh")):
            pkgs.setdefault(name, d)
            files[name] = os.path.join(base, name)
for name, path in files.items():
    for f in os.listdir(path):
        if f.endswith(".subpackage.sh"):
            alias.setdefault(f[: -len(".subpackage.sh")], name)

def parse_deps(text):
    out = set()
    for m in ASSIGN.finditer(text):
        val = next(g for g in m.groups() if g is not None)
        for item in re.split(r"[,|\n]", val):
            item = re.sub(r"\(.*?\)", "", item).strip()
            if not item or "$" in item or " " in item:
                continue
            out.add(item)
    return out

deps = {}
edges = 0
for name, path in files.items():
    try:
        txt = open(os.path.join(path, "build.sh"), encoding="utf-8", errors="replace").read()
    except OSError:
        txt = ""
    raw = parse_deps(txt)
    for f in sorted(os.listdir(path)):
        if f.endswith(".subpackage.sh"):
            try:
                raw |= parse_deps(open(os.path.join(path, f), encoding="utf-8", errors="replace")
                                  .read().replace("TERMUX_SUBPKG_DEPENDS", "TERMUX_PKG_DEPENDS"))
            except OSError:
                pass
    mapped = set()
    for dep in raw:
        dep = alias.get(dep, dep)       # sub-paket -> induk
        if dep in pkgs and dep != name:  # abaikan yang tidak dikenal dan diri sendiri
            mapped.add(dep)
    deps[name] = mapped
    edges += len(mapped)

# DFS pascaurut, deterministik; sisi balik (siklus) dilewati dan dicatat
order, state, broken = [], {}, []
for start in sorted(deps):
    if start in state:
        continue
    stack = [(start, iter(sorted(deps[start])))]
    state[start] = 1
    while stack:
        v, it = stack[-1]
        for w in it:
            if w not in state:
                state[w] = 1
                stack.append((w, iter(sorted(deps[w]))))
                break
            elif state[w] == 1:
                broken.append((v, w))
        else:
            state[v] = 2
            order.append(v)
            stack.pop()

for n in order:
    print(f"{pkgs[n]}/{n}")
print(f"fallback-buildorder: {len(order)} paket, {edges} sisi dependensi, "
      f"{len(alias)} sub-paket dipetakan, {len(broken)} sisi siklus dipecah", file=sys.stderr)
for a, b in broken[:20]:
    print(f"  siklus dipecah: {a} -> {b}", file=sys.stderr)
