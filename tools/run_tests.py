#!/usr/bin/env python3
"""Run the PicoCalc DB / Almanac test suites in MMB4L (MMBasic for Linux).

    python3 tools/run_tests.py              # all suites
    python3 tools/run_tests.py api store    # selected suites
    python3 tools/run_tests.py --list

Each suite is assembled from the module files and its test file into one
program (MMBasic has no module system), written to a temporary file and
run through a pseudo-terminal: MMBasic buffers its output when stdout is
not a terminal, and asks the terminal for the cursor position at start-up.
A suite passes when it prints "TOTAL FAILS: 0" and no MMBasic error.

Set MMBASIC to the interpreter path (default /tmp/mmb4l/build/mmbasic).
"""
import os, pty, re, select, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MMBASIC = os.environ.get('MMBASIC', '/tmp/mmb4l/build/mmbasic')
EXPLICIT = "OPTION EXPLICIT\n"
STRICT = "OPTION EXPLICIT\nOPTION DEFAULT NONE\n"


def read(name):
    """A module (src/), test file (tests/) or generated file (dist/)."""
    for d in ('src', 'tests', 'dist'):
        p = os.path.join(ROOT, d, name)
        if os.path.exists(p):
            return open(p).read()
    raise FileNotFoundError(name)


def almanac_for_test():
    """almanac.bas with test paths and without its main call."""
    s = read('almanac.bas')
    s = s.replace('"B:/almanac.csv"', '"/tmp/alm/almanac.csv"').replace('"B:/db"', '"/tmp/alm/db"')
    return s[:s.index("' ---- main ----")]


def prep_gui():
    shutil.rmtree('/tmp/dbg', ignore_errors=True)
    shutil.copy(os.path.join(ROOT, 'sdcard', 'db', 'help', 'dbhelp.jsonl'), '/tmp/dbhelp.jsonl')


def prep_almanac():
    subprocess.run([sys.executable, os.path.join(ROOT, 'tests', 'almanac_testprep.py'),
                    os.path.join(ROOT, 'sdcard', 'almanac.csv')], check=True, stdout=subprocess.DEVNULL)
    shutil.rmtree('/tmp/alm/db', ignore_errors=True)


# name: (options, [parts: file name or callable], prepare, timeout seconds)
SUITES = {
    'core':    (EXPLICIT, ['dbcore.bas', 'test_core.bas'], None, 420),
    'store':   (EXPLICIT, ['dbcore.bas', 'dbstore.bas', 'test_store.bas'], None, 300),
    'query':   (EXPLICIT, ['dbcore.bas', 'dbquery.bas', 'test_query.bas'], None, 300),
    'exec':    (EXPLICIT, ['dbcore.bas', 'dbstore.bas', 'dbquery.bas', 'dbexec.bas',
                           'test_exec.bas'], None, 300),
    'gui':     (EXPLICIT, ['dbcore.bas', 'dbstore.bas', 'dbquery.bas', 'dbexec.bas',
                           'dbgui.bas', 'test_gui.bas'], prep_gui, 300),
    'api':     (STRICT, ['dblib_min.bas', 'test_api.bas'],
                lambda: shutil.rmtree('/tmp/dbl', ignore_errors=True), 300),
    'almanac': (STRICT, ['dblib_min.bas', almanac_for_test, 'test_almanac.bas'], prep_almanac, 400),
}


def run_program(path, timeout):
    """Run one .bas file through a pty; return its output as text."""
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['SDL_VIDEODRIVER'] = 'dummy'
        os.environ['SDL_AUDIODRIVER'] = 'dummy'
        os.execv(MMBASIC, [MMBASIC, path])
    out, deadline = b'', time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                break
            if not d:
                break
            out += d
            if b'\x1b[6n' in d:                    # cursor position query
                os.write(fd, b'\x1b[1;1R')
        elif os.waitpid(pid, os.WNOHANG)[0]:
            break
    else:
        os.kill(pid, 9)
        out += b'\nTIMEOUT\n'
    s = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', out.decode('latin1').replace('\r', ''))
    return '\n'.join(l for l in s.split('\n') if l.strip())


def run_suite(name):
    opts, parts, prep, timeout = SUITES[name]
    if prep:
        prep()
    src = opts + ''.join(p() if callable(p) else read(p) + '\n' for p in parts)
    with tempfile.NamedTemporaryFile('w', suffix='.bas', delete=False) as f:
        f.write(src)
    t0 = time.time()
    out = run_program(f.name, timeout)
    os.unlink(f.name)
    m = re.search(r'TOTAL FAILS:\s*(\d+)', out)
    errors = [l for l in out.split('\n') if l.startswith('Error') or l == 'TIMEOUT']
    ok = bool(m) and m.group(1) == '0' and not errors
    print(f"{name:8} {'PASS' if ok else 'FAIL'}  {time.time() - t0:5.0f}s")
    if not ok:
        for l in out.split('\n'):
            if l.startswith(('FAIL', 'Error', 'TOTAL', 'TIMEOUT')):
                print('   ', l[:150])
    return ok


def main(args):
    if '--list' in args:
        print('\n'.join(SUITES)); return 0
    if not os.path.exists(MMBASIC):
        print(f'MMB4L not found at {MMBASIC} (set MMBASIC to the interpreter path)')
        return 2
    names = args or list(SUITES)
    bad = [n for n in names if n not in SUITES]
    if bad:
        print('unknown suite:', ', '.join(bad)); return 2
    results = [run_suite(n) for n in names]
    print(f"{sum(results)} of {len(results)} suites passed")
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
