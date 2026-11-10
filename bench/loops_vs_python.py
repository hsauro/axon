"""Loop micro-benchmarks: Axon (interpreted and compiled, bench/loops.sci)
against Python. Run from anywhere:  python bench/loops_vs_python.py [axon.exe]
Prints the time per loop iteration of each simple loop body."""

import os
import subprocess
import sys
import time


def bench(f):
    loops = 1
    while True:
        t0 = time.perf_counter()
        for _ in range(loops):
            f()
        dt = time.perf_counter() - t0
        if dt >= 0.2:
            break
        loops *= 2
    best = dt / loops
    for _ in range(4):
        t0 = time.perf_counter()
        for _ in range(loops):
            f()
        best = min(best, (time.perf_counter() - t0) / loops)
    return best


def empty_loop(n):
    for k in range(1, n + 1):
        pass
    return n


def while_loop(n):
    k = 0
    while k < n:
        k = k + 1
    return k


def assign_loop(n):
    x = 0
    for k in range(1, n + 1):
        x = k
    return x


def arith_loop(n):
    x = 0.0
    for k in range(1, n + 1):
        x = x + k * 2.0
    return x


def inc(x):
    return x + 1.0


def call_loop(n):
    x = 0.0
    for k in range(1, n + 1):
        x = inc(x)
    return x


def array_loop(n):
    v = [0.0] * (n + 1)
    for k in range(1, n + 1):
        v[k] = v[k] + 1.0
    return v[n]


n = 1000000
py = {
    "empty for loop": bench(lambda: empty_loop(n)) / n * 1e9,
    "while loop, k = k + 1": bench(lambda: while_loop(n)) / n * 1e9,
    "assignment x = k": bench(lambda: assign_loop(n)) / n * 1e9,
    "x = x + k * 2.0": bench(lambda: arith_loop(n)) / n * 1e9,
    "function call x = inc(x)": bench(lambda: call_loop(n)) / n * 1e9,
    "array v[k] = v[k] + 1.0": bench(lambda: array_loop(n)) / n * 1e9,
}
here = os.path.dirname(os.path.abspath(__file__))
exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Win64", "Release", "axon.exe")
r = subprocess.run([exe, "loops.sci"], cwd=here, capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("axon failed:\n" + r.stdout + r.stderr)
out = r.stdout
print("%-28s %12s %12s %12s" % ("per iteration", "Axon interp", "Axon JIT", "Python"))
for line in out.splitlines():
    name, ti, tc = line.split("\t")
    print("%-28s %9.0f ns %9.2f ns %9.0f ns" % (name, float(ti), float(tc), py[name]))
