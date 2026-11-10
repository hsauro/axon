"""Axon against Python: the same kernels in both, timed the same way.

Run from anywhere:  python bench/vs_python.py  [path to axon.exe]

The Python kernels are below; Axon's are in vs_python.sci, which this script
runs with Win64/Release/axon.exe (build Release first) and reads back. Every
kernel is timed as Axon's time.bench times it: the calls per run double until
a run takes 0.2 s, then the best of 5 runs, per call. Loop kernels run in
plain Python (CPython); the library kernels use NumPy and SciPy, which, like
Axon, call OpenBLAS and LAPACK. Each side prints a check value, and the table
marks a kernel whose values differ.
"""

import math
import os
import subprocess
import sys
import time

import numpy as np
from scipy.integrate import solve_ivp


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


# ---------------------------------------------------------------- loops

def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def harmonic(n):
    s = 0.0
    for k in range(1, n + 1):
        s = s + 1.0 / k
    return s


def sieve(n):
    flags = [1.0] * (n + 1)          # flags[1..n], as Axon's 1-based vector
    flags[1] = 0.0
    count = 0
    for i in range(2, n + 1):
        if flags[i] == 1.0:
            count = count + 1
            j = i * i
            while j <= n:
                flags[j] = 0.0
                j = j + i
    return count


def escape(cr, ci, maxit):
    zr = 0.0
    zi = 0.0
    k = 0
    while k < maxit and zr * zr + zi * zi <= 4.0:
        t = zr * zr - zi * zi + cr
        zi = 2.0 * zr * zi + ci
        zr = t
        k = k + 1
    return k


def mandel(n, maxit):
    total = 0
    for i in range(1, n + 1):
        for j in range(1, n + 1):
            total = total + escape(-2.0 + 2.5 * (j - 1) / n, -1.25 + 2.5 * (i - 1) / n, maxit)
    return total


def matmul(A, B):
    n = len(A)
    m = len(B[0])
    p = len(B)
    C = [[0.0] * m for _ in range(n)]
    for i in range(n):
        Ai = A[i]
        for j in range(m):
            s = 0.0
            for k in range(p):
                s = s + Ai[k] * B[k][j]
            C[i][j] = s
    return C


def nbody(steps):
    x = [0.0, 4.84, 8.34, 12.89, 15.38]
    y = [0.0, -1.16, 4.12, -15.11, -25.92]
    z = [0.0, -0.10, -0.40, -0.22, 0.18]
    vx = [0.0, 0.606, -1.010, 1.083, 0.979]
    vy = [0.0, 2.812, 1.825, 0.869, 0.595]
    vz = [0.0, -0.025, 0.008, -0.010, -0.035]
    m = [39.47, 0.0377, 0.0113, 0.0017, 0.0020]
    n = 5
    dt = 0.01
    for s in range(steps):
        for i in range(n):
            for j in range(i + 1, n):
                dx = x[i] - x[j]
                dy = y[i] - y[j]
                dz = z[i] - z[j]
                d2 = dx * dx + dy * dy + dz * dz
                mag = dt / (d2 * math.sqrt(d2))
                vx[i] = vx[i] - dx * m[j] * mag
                vy[i] = vy[i] - dy * m[j] * mag
                vz[i] = vz[i] - dz * m[j] * mag
                vx[j] = vx[j] + dx * m[i] * mag
                vy[j] = vy[j] + dy * m[i] * mag
                vz[j] = vz[j] + dz * m[i] * mag
        for i in range(n):
            x[i] = x[i] + dt * vx[i]
            y[i] = y[i] + dt * vy[i]
            z[i] = z[i] + dt * vz[i]
    e = 0.0
    for i in range(n):
        e = e + 0.5 * m[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i])
        for j in range(i + 1, n):
            dx = x[i] - x[j]
            dy = y[i] - y[j]
            dz = z[i] - z[j]
            e = e - m[i] * m[j] / math.sqrt(dx * dx + dy * dy + dz * dz)
    return e


def test_matrix(n, shift):
    """sin(0.37 i j + shift) with i, j from 0, plus n on the diagonal, as in vs_python.sci."""
    i = np.arange(n).reshape(-1, 1)
    j = np.arange(n).reshape(1, -1)
    return np.sin(0.37 * i * j + shift) + n * np.eye(n)


# ---------------------------------------------------------------- lists, text

def build_list(n):
    l = []
    for k in range(1, n + 1):
        l.append(k)
    return len(l)


def dict_words(n):
    d = {}
    for k in range(1, n + 1):
        d["w" + str(k)] = k
    total = 0
    for k in range(1, n + 1):
        total = total + d["w" + str(k)]
    return total


def split_join(text):
    return len(",".join(text.split()))


# ---------------------------------------------------------------- the kernels

def python_results():
    A100 = test_matrix(100, 0).tolist()
    B100 = test_matrix(100, 1).tolist()
    A = test_matrix(500, 0)
    B = test_matrix(500, 1)
    b = A[:, 0].copy()
    v = np.linspace(0.0, 1.0, 1000000)
    w = np.sin(np.linspace(0.0, 1000.0, 1000000))
    A200 = A[:200, :200] + A[:200, :200].T
    lv = lambda t, y: [y[0] - 0.1 * y[0] * y[1], 0.075 * y[0] * y[1] - 1.5 * y[1]]
    rob = lambda t, y: [-0.04 * y[0] + 1e4 * y[1] * y[2],
                        0.04 * y[0] - 1e4 * y[1] * y[2] - 3e7 * y[1] ** 2, 3e7 * y[1] ** 2]
    words = "alpha beta gamma delta " * 50000
    kernels = [
        ("fib(25)", lambda: fib(25)),
        ("harmonic(1e6)", lambda: harmonic(1000000)),
        ("sieve(1e6)", lambda: sieve(1000000)),
        ("mandel(100, 100)", lambda: mandel(100, 100)),
        ("matmul 100x100 loops", lambda: sum(map(sum, matmul(A100, B100)))),
        ("nbody(10000)", lambda: nbody(10000)),
        ("A * B 500x500 (BLAS)", lambda: (A @ B)[0, 0]),
        ("A \\ b 500 (LAPACK)", lambda: np.linalg.solve(A, b)[0]),
        ("eig 200x200", lambda: np.linalg.eigvals(A200).real.max()),
        ("exp(v), 1e6", lambda: np.exp(v)[-1]),
        ("v .* v + 2 * v, 1e6", lambda: (v * v + 2.0 * v)[-1]),
        ("sum(v), 1e6", lambda: v.sum()),
        ("sort 1e6", lambda: np.sort(w)[499999]),
        ("ode RK45 Lotka-Volterra", lambda: solve_ivp(lv, [0, 50], [10.0, 5.0], method="RK45",
                                                      rtol=1e-8).y[0, -1]),
        ("ode BDF Robertson", lambda: solve_ivp(rob, [0, 40], [1.0, 0.0, 0.0], method="BDF",
                                                rtol=1e-8, atol=1e-12).y[0, -1]),
        ("list append 1e5", lambda: build_list(100000)),
        ("dict 1e5 words", lambda: dict_words(100000)),
        ("split + join 2e5 words", lambda: split_join(words)),
    ]
    out = {}
    for name, f in kernels:
        c = f()
        out[name] = (bench(f), c)
        print("  python:", name, file=sys.stderr)
    return out


def axon_results(exe):
    here = os.path.dirname(os.path.abspath(__file__))
    r = subprocess.run([exe, "vs_python.sci"], cwd=here, capture_output=True, text=True,
                       encoding="utf-8")
    if r.returncode != 0:
        sys.exit("axon failed:\n" + r.stdout + r.stderr)
    out = {}
    for line in r.stdout.splitlines():
        name, ti, tc, c = line.split("\t")
        out[name] = (float(ti), float(tc), c)
    return out


def fmt(t):
    if t >= 1:
        return "%.2f s" % t
    if t >= 1e-3:
        return "%.1f ms" % (t * 1e3)
    return "%.0f us" % (t * 1e6)


def same(a, b):
    try:
        x, y = float(a), float(b)
    except ValueError:
        return a == b
    return abs(x - y) <= 1e-6 * max(1.0, abs(x), abs(y))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    exe = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Win64", "Release", "axon.exe")
    print("Running Axon (vs_python.sci)...", file=sys.stderr)
    ax = axon_results(exe)
    print("Running Python...", file=sys.stderr)
    py = python_results()
    print()
    print("%-26s %10s %10s %10s   %s" % ("kernel", "Python", "Axon int.", "Axon JIT", "Axon is"))
    for name, (tp, cp) in py.items():
        ti, tc, ca = ax[name]
        loop = ti != tc
        ratio = tp / tc
        tag = "" if same(cp, ca) else "   (check differs: %r vs %s)" % (cp, ca)
        if ratio >= 1:
            verdict = "%.0fx faster" % ratio if ratio >= 10 else "%.1fx faster" % ratio
        else:
            verdict = "%.0fx slower" % (1 / ratio) if ratio <= 0.1 else "%.1fx slower" % (1 / ratio)
        print("%-26s %10s %10s %10s   %s%s" % (
            name, fmt(tp), fmt(ti) if loop else "", fmt(tc), verdict, tag))


if __name__ == "__main__":
    main()
