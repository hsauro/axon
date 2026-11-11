"""Numerical checks of the claims in ../README.md, one function per
experiment. Run:  python experiments.py  (or  python experiments.py E3)."""

import sys
import numpy as np
from scipy.integrate import solve_ivp

import augss as A
import models

np.set_printoptions(precision=4, suppress=True, linewidth=110)
RNG = np.random.default_rng(12345)


def header(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


def simulate_to_steady(model, t_end=1e4):
    sol = solve_ivp(lambda t, y: model.f(y), [0, t_end], model.y0, method="LSODA",
                    rtol=1e-11, atol=1e-13)
    return sol.y[:, -1]


# ---------------------------------------------------------------- E1
def E1_roots():
    """Theorem 1: the roots of F are the steady states in the conservation
    class. Augmented and reduced Newton, and a long simulation, agree."""
    header("E1  Roots: augmented = reduced = long simulation, totals kept")
    print(f"{'model':16s} {'c':>2s} {'|y_aug - y_red|':>16s} {'|y_aug - y_sim|':>16s} "
          f"{'|K^T(y - y0)|':>14s} {'|N v(y)|':>10s}")
    for make in models.ALL:
        mdl = make()
        ya, ra = A.steady_state(mdl, "augmented")
        yr, rr = A.steady_state(mdl, "reduced")
        ys = simulate_to_steady(mdl)
        K = A.left_null_basis(mdl.N)
        print(f"{mdl.name:16s} {K.shape[1]:2d} {np.max(np.abs(ya - yr)):16.2e} "
              f"{np.max(np.abs(ya - ys)):16.2e} {np.max(np.abs(K.T @ (ya - mdl.y0))):14.2e} "
              f"{np.max(np.abs(mdl.f(ya))):10.2e}")


# ---------------------------------------------------------------- E2
def E2_spectrum():
    """Theorem 2: eig(J_F) = eig(J_R) and c copies of sign*alpha;
    det J_F = (sign*alpha)^c det J_R."""
    header("E2  Spectrum: eig(J_F) = eig(J_R) + c copies of s*alpha; det J_F = (s alpha)^c det J_R")
    for make in models.ALL:
        mdl = make()
        y, _ = A.steady_state(mdl, "augmented")
        cons = A.Conservation(mdl.N)
        E = A.elasticities(mdl, y)
        JR = cons.Nr @ E @ cons.link
        K = A.left_null_basis(mdl.N)
        for alpha, s in ((1.0, +1), (3.0, -1)):
            JF = mdl.N @ E + s * alpha * K @ K.T
            ef = np.sort_complex(np.linalg.eigvals(JF))
            er = np.sort_complex(np.concatenate([np.linalg.eigvals(JR),
                                                 np.full(cons.c, s * alpha)]))
            ratio = np.linalg.det(JF) / ((s * alpha) ** cons.c * np.linalg.det(JR))
            print(f"{mdl.name:16s} alpha={s * alpha:+.0f}  max|eig diff| = "
                  f"{np.max(np.abs(ef - er)):.1e}   det ratio = {ratio:.12f}")
        if mdl.name == "enzyme_feed":
            print("   enzyme_feed eig(J_R):", np.sort(np.linalg.eigvals(JR).real))


# ---------------------------------------------------------------- E3
def E3_iterates():
    """Theorem 3: full Newton on F restores the totals in one step, and from
    a point in the class its iterates are the reduced Newton iterates."""
    header("E3  Newton iterates: totals exact after one step; same iterates as reduced Newton")
    mdl = models.glycolysis()
    F, K, _ = A.augmented(mdl)
    G, cons, totals = A.reduced(mdl)
    # (a) Start in the class (the initial values): identical iterates.
    ra = A.newton(F, mdl.y0, line_search=False)
    rr = A.newton(G, mdl.y0[cons.ind], line_search=False)
    print("(a) guess in the class (y0): iterations", ra.iterations, "and", rr.iterations)
    for k, (ya, xr) in enumerate(zip(ra.history, rr.history)):
        yr = cons.full(xr, totals)
        print(f"   k={k}  |y_aug - y_red| = {np.max(np.abs(ya - yr)):.2e}   "
              f"|F(y_aug)| = {np.max(np.abs(F(ya))):.2e}")
    # (b) Start outside the class: totals right after the first full step.
    guess = mdl.y0 + RNG.uniform(0.2, 1.0, mdl.m)
    ra = A.newton(F, guess, line_search=False)
    print("(b) guess outside the class: converged", ra.converged, "in", ra.iterations)
    for k, ya in enumerate(ra.history[:5]):
        print(f"   k={k}  |K^T y - K^T y0| = {np.max(np.abs(K.T @ (ya - mdl.y0))):.2e}")
    # (c) With a damped step lambda the error in the totals shrinks by (1 - lambda).
    y = guess.copy()
    e0 = np.linalg.norm(K.T @ (y - mdl.y0))
    J = A.jacobian(F, y)
    d = np.linalg.solve(J, -F(y))
    for lam in (0.25, 0.5):
        e1 = np.linalg.norm(K.T @ (y + lam * d - mdl.y0))
        print(f"(c) damped step lambda={lam}: totals error ratio {e1 / e0:.12f}"
              f" (1 - lambda = {1 - lam})")


# ---------------------------------------------------------------- E4
def E4_robustness(trials=200):
    """Success from random guesses: augmented vs reduced Newton, both with a
    line search, and two ways of ignoring the conservation laws."""
    header(f"E4  Robustness from {trials} random guesses (log-uniform, 1e-2..1e2 x scale)")
    print(f"{'model':16s} {'method':10s} {'conv':>5s} {'in class':>8s} {'y >= 0':>7s} "
          f"{'= ref':>6s} {'mean it':>7s}")
    for make in models.ALL:
        mdl = make()
        y_ref, _ = A.steady_state(mdl, "reduced")
        K = A.left_null_basis(mdl.N)
        scale = np.maximum(np.abs(mdl.y0), np.abs(y_ref)).max()
        guesses = [scale * 10 ** RNG.uniform(-2, 2, mdl.m) for _ in range(trials)]
        for method in ("augmented", "reduced", "naive", "pinv"):
            conv = inclass = phys = right = its = 0
            for g in guesses:
                y, res = A.steady_state(mdl, method, guess=g, max_iter=200)
                if not res.converged:
                    continue
                conv += 1
                its += res.iterations
                if np.max(np.abs(K.T @ (y - mdl.y0))) < 1e-8 * max(1, scale):
                    inclass += 1
                    if np.min(y) >= -1e-9 * max(1, scale):
                        phys += 1
                    if np.max(np.abs(y - y_ref)) < 1e-6 * max(1, scale):
                        right += 1
            mean = its / conv if conv else float("nan")
            print(f"{mdl.name:16s} {method:10s} {conv:5d} {inclass:8d} {phys:7d} {right:6d} "
                  f"{mean:7.1f}")


# ---------------------------------------------------------------- E5
def E5_sensitivities():
    """Theorem 4: -J_F^{-1} N gives the unscaled concentration control
    coefficients, equal to the link-matrix formula and to finite differences
    of the steady state; dy/dT = s alpha J_F^{-1} K M gives the response to
    the totals."""
    header("E5  Sensitivities without the link matrix")
    for make in (models.enzyme_feed, models.glycolysis):
        mdl = make()
        y, _ = A.steady_state(mdl, "augmented")
        Ca = A.concentration_sensitivities(mdl, y, "augmented")
        Cr = A.concentration_sensitivities(mdl, y, "reduced")
        Ca2 = A.concentration_sensitivities(mdl, y, "augmented", alpha=7.0, sign=-1)
        # Finite differences: scale reaction j's rate by (1 + eps), so dv_j = eps v_j.
        v = mdl.rates(y, mdl.p)
        eps = 1e-6
        Cfd = np.zeros_like(Ca)
        base_rates = mdl.rates
        for j in range(mdl.N.shape[1]):
            def scaled(z, p, j=j, s=1.0):
                r = base_rates(z, p)
                return r * np.where(np.arange(len(r)) == j, s, 1.0)
            up = A.Model(mdl.name, mdl.species, mdl.N,
                         lambda z, p, j=j: scaled(z, p, j, 1 + eps), mdl.y0, mdl.p)
            dn = A.Model(mdl.name, mdl.species, mdl.N,
                         lambda z, p, j=j: scaled(z, p, j, 1 - eps), mdl.y0, mdl.p)
            yu, _ = A.steady_state(up, "augmented", guess=y, tol=1e-13)
            yd, _ = A.steady_state(dn, "augmented", guess=y, tol=1e-13)
            Cfd[:, j] = (yu - yd) / (2 * eps * v[j])
        print(f"{mdl.name}: |C_aug - C_link| = {np.max(np.abs(Ca - Cr)):.1e}, "
              f"|C_aug(alpha=1) - C_aug(alpha=-7)| = {np.max(np.abs(Ca - Ca2)):.1e}, "
              f"|C_aug - C_fd| = {np.max(np.abs(Ca - Cfd)):.1e}")
        CJ = A.flux_control(mdl, y, Ca)
        print(f"   summation theorems (unscaled): max |C^J v - v| = "
              f"{np.max(np.abs(CJ @ v - v)):.1e}, max |C^s v| = {np.max(np.abs(Ca @ v)):.1e}")
        # Response to the conserved totals.
        K = A.left_null_basis(mdl.N)
        E = A.elasticities(mdl, y)
        JF = mdl.N @ E + K @ K.T
        dydT = np.linalg.solve(JF, K)              # s = alpha = 1, M = I
        h = 1e-6
        k = 0
        y0u = mdl.y0 + h * K[:, k]
        y0d = mdl.y0 - h * K[:, k]
        Fu, _, _ = A.augmented(mdl, y_ref=y0u)
        Fd, _, _ = A.augmented(mdl, y_ref=y0d)
        yu = A.newton(Fu, y, tol=1e-13).x
        yd = A.newton(Fd, y, tol=1e-13).x
        print(f"   dy/dT_1: |J_F^-1 K e_1 - finite difference| = "
              f"{np.max(np.abs(dydT[:, k] - (yu - yd) / (2 * h))):.1e}")


# ---------------------------------------------------------------- E6
def E6_sign_and_stability():
    """With s = -1 the extra eigenvalues are -alpha, so J_F is stable exactly
    when J_R is: stability without the reduction. The bistable cycle's three
    steady states."""
    header("E6  Stability from J_F with s = -1 (bistable cycle)")
    mdl = models.bistable_cycle()
    K = A.left_null_basis(mdl.N)
    found = []
    for wp in np.linspace(0.0, 1.0, 21):
        g = np.array([1.0 - wp, wp])
        y, res = A.steady_state(mdl, "augmented", guess=g, sign=-1.0)
        if res.converged and not any(np.allclose(y, f, atol=1e-8) for f in found):
            found.append(y)
    cons = A.Conservation(mdl.N)
    for y in sorted(found, key=lambda z: z[1]):
        E = A.elasticities(mdl, y)
        ef = np.linalg.eigvals(mdl.N @ E - K @ K.T)
        er = np.linalg.eigvals(cons.Nr @ E @ cons.link)
        stable = "stable" if np.all(ef.real < 0) else "unstable"
        if np.min(y) < 0:
            stable += " (not physical: a negative concentration)"
        print(f"   Wp = {y[1]:.4f}: eig(J_F, s=-1) = {np.sort(ef.real)}, eig(J_R) = "
              f"{np.sort(er.real)} -> {stable}")


# ---------------------------------------------------------------- E7
def E7_other_bases():
    """Any basis of the left null space works: with Gamma^T (integer
    conservation laws) the extra eigenvalues are those of Gamma Gamma^T."""
    header("E7  Integer conservation laws instead of an orthonormal basis")
    for make in (models.two_cycles, models.glycolysis):
        mdl = make()
        G = A.left_null_basis(mdl.N, "gamma") + 0.0
        y, res = A.steady_state(mdl, "augmented", K=G)
        yr, _ = A.steady_state(mdl, "reduced")
        E = A.elasticities(mdl, y)
        cons = A.Conservation(mdl.N)
        JF = mdl.N @ E + G @ G.T
        ef = np.sort_complex(np.linalg.eigvals(JF))
        er = np.sort_complex(np.concatenate([np.linalg.eigvals(cons.Nr @ E @ cons.link),
                                             np.linalg.eigvals(G.T @ G)]))
        print(f"{mdl.name}: Gamma =\n{G.T}\n   |y - y_red| = {np.max(np.abs(y - yr)):.1e}, "
              f"iterations {res.iterations}, max|eig(J_F) - eig(J_R) U eig(Gamma Gamma^T)| = "
              f"{np.max(np.abs(ef - er)):.1e}")


# ---------------------------------------------------------------- E8
def E8_scaling():
    """The condition number of J_F depends on alpha; alpha near the size of
    J_R's eigenvalues balances the two parts."""
    header("E8  Conditioning: cond(J_F) as alpha varies (glycolysis, enzyme_feed)")
    for make in (models.glycolysis, models.enzyme_feed):
        mdl = make()
        y, _ = A.steady_state(mdl, "reduced")
        E = A.elasticities(mdl, y)
        cons = A.Conservation(mdl.N)
        JR = cons.Nr @ E @ cons.link
        K = A.left_null_basis(mdl.N)
        ev = np.abs(np.linalg.eigvals(JR))
        print(f"{mdl.name}: cond(J_R) = {np.linalg.cond(JR):.3g}, |eig(J_R)| in "
              f"[{ev.min():.3g}, {ev.max():.3g}]")
        for alpha in (1e-4, 1e-2, 1.0, ev.min(), np.sqrt(ev.min() * ev.max()), 1e2, 1e4):
            JF = mdl.N @ E + alpha * K @ K.T
            print(f"   alpha = {alpha:10.4g}: cond(J_F) = {np.linalg.cond(JF):10.4g}")


# ---------------------------------------------------------------- E9
def E9_drift():
    """The same term as a stabiliser for simulation (Baumgarte):
    dy/dt = N v(y) - beta K (K^T y - T) has the same trajectories when the
    totals are right, and pulls wrong totals back at rate beta."""
    header("E9  Stabilised dynamics: dy/dt = N v - beta K (K^T y - T)")
    mdl = models.enzyme_feed()
    K = A.left_null_basis(mdl.N)
    T = K.T @ mdl.y0
    y_start = mdl.y0 + 0.1 * K[:, 0]           # totals off by 0.1
    for beta in (0.0, 1.0, 5.0):
        def rhs(t, y):
            return mdl.f(y) - beta * K @ (K.T @ y - T)
        sol = solve_ivp(rhs, [0, 5], y_start, rtol=1e-10, atol=1e-12, t_eval=[0, 1, 2, 5])
        errs = [abs(K[:, 0] @ sol.y[:, i] - T[0]) for i in range(sol.y.shape[1])]
        print(f"   beta = {beta}: |K^T y - T| at t = 0, 1, 2, 5:",
              " ".join(f"{e:.2e}" for e in errs),
              f"  (exp(-beta t) at t=1: {np.exp(-beta) * 0.1:.2e})")
    sol0 = solve_ivp(lambda t, y: mdl.f(y), [0, 5], mdl.y0, rtol=1e-11, atol=1e-13,
                     t_eval=[5])
    sol5 = solve_ivp(lambda t, y: mdl.f(y) - 5.0 * K @ (K.T @ y - T), [0, 5], mdl.y0,
                     rtol=1e-11, atol=1e-13, t_eval=[5])
    print(f"   from the right totals, |y(5) with beta = 5 - y(5) without| = "
          f"{np.max(np.abs(sol5.y[:, -1] - sol0.y[:, -1])):.1e}")


# ---------------------------------------------------------------- E10
def E10_random_networks(count=100):
    """Theorems 1 and 2 on random mass-action networks with one or more
    conservation laws."""
    header(f"E10 Random reversible mass-action networks ({count})")
    worst_root = worst_eig = 0.0
    agree = conv_a = conv_r = 0
    cs = []
    for seed in range(count):
        mdl = models.random_closed(m=8, pairs=8, seed=seed)
        cons = A.Conservation(mdl.N)
        cs.append(cons.c)
        ya, ra = A.steady_state(mdl, "augmented", max_iter=200)
        yr, rr = A.steady_state(mdl, "reduced", max_iter=200)
        conv_a += ra.converged
        conv_r += rr.converged
        if ra.converged and rr.converged:
            d = np.max(np.abs(ya - yr))
            worst_root = max(worst_root, d)
            agree += d < 1e-7
            if d >= 1e-7:
                K0 = A.left_null_basis(mdl.N)
                for nm, yy in (("augmented", ya), ("reduced", yr)):
                    print(f"   seed {seed}, {nm}: min y = {np.min(yy):.3g}, |N v| = "
                          f"{np.max(np.abs(mdl.f(yy))):.1e}, |K^T(y - y0)| = "
                          f"{np.max(np.abs(K0.T @ (yy - mdl.y0))):.1e}")
            E = A.elasticities(mdl, ya)
            K = A.left_null_basis(mdl.N)
            ef = np.sort_complex(np.linalg.eigvals(mdl.N @ E + K @ K.T))
            er = np.sort_complex(np.concatenate([np.linalg.eigvals(cons.Nr @ E @ cons.link),
                                                 np.ones(cons.c)]))
            worst_eig = max(worst_eig, np.max(np.abs(ef - er)) / max(1, np.max(np.abs(er))))
    print(f"   conservation laws per network: min {min(cs)}, max {max(cs)}, "
          f"mean {np.mean(cs):.1f}")
    print(f"   converged: augmented {conv_a}/{count}, reduced {conv_r}/{count}; "
          f"same steady state {agree}")
    print(f"   worst |y_aug - y_red| = {worst_root:.1e}; worst relative eigenvalue "
          f"mismatch = {worst_eig:.1e}")


# ---------------------------------------------------------------- E11
def E11_bordered():
    """The augmented system is the Schur complement of a bordered system in
    (y, mu): N v(y) + K mu = 0, K^T y - T - mu / alpha = 0. Newton on the
    bordered system takes the same steps; alpha = infinity gives the
    Lagrange (KKT) form, and mu = 0 at every solution."""
    header("E11 Bordered (y, mu) form: same Newton steps; alpha = inf is the KKT form")
    mdl = models.glycolysis()
    K = A.left_null_basis(mdl.N)
    T = K.T @ mdl.y0
    m, c = mdl.m, K.shape[1]
    for alpha in (1.0, 10.0, np.inf):
        inv = 0.0 if np.isinf(alpha) else 1.0 / alpha

        def B(z):
            y, mu = z[:m], z[m:]
            return np.concatenate([mdl.f(y) + K @ mu, K.T @ y - T - inv * mu])

        z0 = np.concatenate([mdl.y0, np.zeros(c)])
        rb = A.newton(B, z0, line_search=False, tol=1e-12)
        msg = f"alpha = {alpha}: converged {rb.converged} in {rb.iterations}, |mu| = "               f"{np.max(np.abs(rb.x[m:])):.1e}"
        if not np.isinf(alpha):
            F, _, _ = A.augmented(mdl, alpha=alpha)
            ra = A.newton(F, mdl.y0, line_search=False, tol=1e-12)
            diff = max(np.max(np.abs(zb[:m] - ya)) for zb, ya in zip(rb.history, ra.history))
            msg += f", augmented: {ra.iterations} iterations, max |y_bordered - y_aug| over "                    f"the iterates = {diff:.1e}"
        else:
            yr, _ = A.steady_state(mdl, "reduced")
            msg += f", |y - y_red| = {np.max(np.abs(rb.x[:m] - yr)):.1e}"
        print("   " + msg)


ALL = {"E1": E1_roots, "E2": E2_spectrum, "E3": E3_iterates, "E4": E4_robustness,
       "E5": E5_sensitivities, "E6": E6_sign_and_stability, "E7": E7_other_bases,
       "E8": E8_scaling, "E9": E9_drift, "E10": E10_random_networks, "E11": E11_bordered}

if __name__ == "__main__":
    names = sys.argv[1:] or list(ALL)
    for name in names:
        ALL[name]()
