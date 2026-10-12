#!/usr/bin/env python3
"""Check the deepest possible nesting of SUB/FUNCTION calls.

PicoMite MMBasic runs programs on a small fixed stack, and every nested
SUB or FUNCTION call uses part of it: too deep a chain stops the program
with "Stack overflow ... at depth N". PCs (MMB4L) have no such limit, so
this static check guards the budgets below.

    python3 tools/check_depth.py          # report; exit 1 if over budget

It finds every call in every routine of src/ and computes the longest
chain from each entry point. Recursion is counted once. It is an upper
bound: a chain is counted even if no input can make it happen.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
FILES = ['dbcore.bas', 'dbstore.bas', 'dbquery.bas', 'dbexec.bas', 'dbapi.bas',
         'dbgui.bas', 'almanac.bas', 'adv_model.bas', 'adv_view.bas', 'adv_ctrl.bas']

# entry point: budget (levels, the entry routine counting as 1). The
# applications' entries are what their main programs call.
BUDGET = {
    'UiStep': 9,          # explorer: called from the main loop in dbmain.bas
    'AmMenu': 9,          # almanac: called from the main code of almanac.bas
    'GcRun': 10,          # adventure: called from adv_main.bas
    'DbQuery%': 8, 'DbFind%': 6, 'DbFindNum%': 7, 'DbGet$': 4, 'DbPut%': 6,
    'DbInsert%': 6, 'DbUpdate%': 6, 'DbDelete%': 6, 'DbSetText%': 7, 'DbSetNum%': 7,
    'DbSetRaw%': 7, 'DbUnset%': 7, 'DbOpen%': 7, 'DbClose': 6, 'DbVacuum%': 7,
    'DbIndexAdd%': 7, 'DbCreate%': 4, 'DbDrop%': 4,
}


def routines():
    R = {}
    for f in FILES:
        cur = None
        for l in open(os.path.join(SRC, f)).read().split('\n'):
            m = re.match(r'^\s*(SUB|FUNCTION)\s+([A-Za-z_][A-Za-z0-9_.]*[$%!]?)', l)
            if m:
                cur = m.group(2); R[cur] = []; continue
            if re.match(r'^\s*END\s+(SUB|FUNCTION)\b', l):
                cur = None; continue
            if cur:
                R[cur].append(l)
    return R


def code(l):
    """A line without its comment, with string contents blanked."""
    out, inq = [], False
    for ch in l:
        if ch == '"':
            inq = not inq; out.append(' '); continue
        if ch == "'" and not inq:
            break
        out.append(' ' if inq else ch)
    return ''.join(out)


def graph(R):
    names = {n.upper(): n for n in R}
    G = {}
    for n, body in R.items():
        calls = set()
        for l in body:
            for tok in re.findall(r'[A-Za-z_][A-Za-z0-9_.]*[$%!]?', code(l)):
                t = names.get(tok.upper())
                if t and t != n:
                    calls.add(t)
        G[n] = calls
    return G


def longest(G, root):
    memo = {}
    def go(n, stack):
        if n in memo:
            return memo[n]
        best = [n]
        for c in G.get(n, ()):
            if c not in stack:
                p = go(c, stack | {n})
                if len(p) + 1 > len(best):
                    best = [n] + p
        memo[n] = best
        return best
    return go(root, frozenset())


def main():
    G = graph(routines())
    bad = 0
    for root, limit in BUDGET.items():
        if root not in G:
            print(f'{root:12} MISSING'); bad += 1; continue
        p = longest(G, root)
        ok = len(p) <= limit
        bad += not ok
        print(f"{root:12} {len(p):2} / {limit:2} {'ok  ' if ok else 'OVER'} {' > '.join(p)}")
    print('all within budget' if not bad else f'{bad} over budget')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
