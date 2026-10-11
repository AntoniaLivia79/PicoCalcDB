#!/usr/bin/env python3
"""Prepare /tmp/alm/ for test_almanac.bas: a copy of the CSV, the expected
records (one field per line) and expected search results, computed here
independently of the BASIC code."""
import csv, json, os, shutil, sys
src = sys.argv[1] if len(sys.argv) > 1 else 'almanac.csv'
os.makedirs('/tmp/alm', exist_ok=True)
shutil.copy(src, '/tmp/alm/almanac.csv')
rows = list(csv.DictReader(open(src, encoding='utf-8-sig')))
seq, exp = {}, []
for r in rows:
    seq[r['date']] = seq.get(r['date'], 0) + 1
    rid = f"{r['date']}.{seq[r['date']]:02d}"
    exp.append([rid, r['category'], r['event'], r['detail'], r['saying_or_lore'],
                r['place'], r['certainty'], r['weekday']])
with open('/tmp/alm/expected.txt', 'w', newline='\r\n') as f:
    for e in exp: f.write('\n'.join(e) + '\n')
def find(q):
    ws = [w for w in q.lower().split(' ') if w][:8]
    return sorted(e[0] for e in exp if e[3] and all(w in e[3].lower() for w in ws))
with open('/tmp/alm/search.txt', 'w', newline='\r\n') as f:
    for q in ['moon', 'FULL moon', 'tide', 'bede month', 'eclipse', 'zzzz', 'Cambridge']:
        h = find(q)
        f.write(f"{q}\n{len(h)}\n{h[0] if h else ''}\n{h[-1] if h else ''}\n")
print(len(rows), 'rows prepared in /tmp/alm/')
