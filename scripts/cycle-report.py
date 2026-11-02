#!/usr/bin/env python3
"""Ringkas keluaran gagal buildorder.py: cari inti siklus (bukan korban).

Membaca teks (stdin atau berkas) yang berisi baris 'nama {'dep1', 'dep2'}'
dan baris 'cycle: a -> b -> a', lalu mencetak siklus sebenarnya.
"""
import re, sys
from collections import defaultdict, deque

text = "".join(open(p, encoding="utf-8", errors="replace").read() for p in sys.argv[1:]) \
    if len(sys.argv) > 1 else sys.stdin.read()

graph = {}
for m in re.finditer(r"^(\S+) \{(.*)\}\s*$", text, re.M):
    graph[m.group(1)] = set(re.findall(r"'([^']+)'", m.group(2)))
for g in list(graph):
    graph[g] = {d for d in graph[g] if d in graph}   # hanya simpul yang masih tertahan

# Tarjan iteratif
index, low, onstack, stack, sccs, counter = {}, {}, set(), [], [], [0]
for root in graph:
    if root in index:
        continue
    work = [(root, iter(sorted(graph[root])))]
    index[root] = low[root] = counter[0]; counter[0] += 1
    stack.append(root); onstack.add(root)
    while work:
        v, it = work[-1]
        advanced = False
        for w in it:
            if w not in index:
                index[w] = low[w] = counter[0]; counter[0] += 1
                stack.append(w); onstack.add(w)
                work.append((w, iter(sorted(graph[w]))))
                advanced = True
                break
            elif w in onstack:
                low[v] = min(low[v], index[w])
        if advanced:
            continue
        work.pop()
        if work:
            low[work[-1][0]] = min(low[work[-1][0]], low[v])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop(); onstack.discard(w); comp.append(w)
                if w == v:
                    break
            if len(comp) > 1 or v in graph[v]:
                sccs.append(sorted(comp))

def shortest_cycle(comp):
    cs = set(comp)
    best = None
    for s in comp:
        prev = {s: None}; q = deque([s]); found = None
        while q and found is None:
            u = q.popleft()
            for w in graph[u] & cs:
                if w == s:
                    found = u; break
                if w not in prev:
                    prev[w] = u; q.append(w)
        if found is not None:
            path = [found]
            while prev[path[-1]] is not None:
                path.append(prev[path[-1]])
            path.reverse()
            if best is None or len(path) < len(best):
                best = path
    return best

print(f"simpul tertahan: {len(graph)}; kelompok siklus: {len(sccs)}")
for comp in sorted(sccs, key=len)[:40]:
    cyc = shortest_cycle(comp)
    if cyc:
        print("siklus:", " -> ".join(cyc + [cyc[0]]))
    if len(comp) > len(cyc or []):
        print("   (kelompok berisi", len(comp), "paket:", ", ".join(comp[:12]), "..." if len(comp) > 12 else "", ")")
