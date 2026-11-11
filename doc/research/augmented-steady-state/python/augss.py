"""Steady states of reaction networks with conservation laws.

Two ways to make the steady-state equations N v(y) = 0 square and
non-singular when the stoichiometry matrix N (m species x n reactions) has
rank r < m, that is, when there are c = m - r conservation laws:

* the classical reduction (Reder 1988; Sauro and Ingalls 2004;
  Vallabhajosyula, Chickarmane and Sauro 2006): solve N_R v(y) = 0 for the
  r independent species, the dependent ones following from the link matrix
  and the conserved totals;

* the augmented system studied in this project:

      F(y) = N v(y) + s K M (K^T y - K^T y0) = 0

  for all m species, where the columns of K span the left null space of N
  (K^T N = 0), M is a non-singular c x c matrix (alpha * I by default) and
  s = +1 or -1.

Everything here is dense linear algebra with numpy/scipy, meant for models
of up to a few hundred species and for checking the theory, not for speed.
Jacobians use the complex-step derivative, exact to rounding for rate laws
written with analytic numpy operations.
"""

import numpy as np
from scipy.linalg import null_space, qr, solve_triangular


# --------------------------------------------------------------------------
# Models

class Model:
    """A reaction network: species names, stoichiometry N (m x n), a rate
    function rates(y, p) returning the n reaction rates, initial values y0
    and parameters p (a dict). rates must accept complex y (complex step)."""

    def __init__(self, name, species, N, rates, y0, p):
        self.name = name
        self.species = list(species)
        self.N = np.asarray(N, dtype=float)
        self.rates = rates
        self.y0 = np.asarray(y0, dtype=float)
        self.p = dict(p)

    @property
    def m(self):
        return self.N.shape[0]

    def f(self, y, p=None):
        """dy/dt = N v(y)."""
        return self.N @ self.rates(y, self.p if p is None else p)

    def with_params(self, **changes):
        q = dict(self.p)
        q.update(changes)
        return Model(self.name, self.species, self.N, self.rates, self.y0, q)


def jacobian(fun, y, h=1e-20):
    """d fun / d y by the complex step: Im(fun(y + i h e_j)) / h."""
    y = np.asarray(y, dtype=float)
    f0 = fun(y)
    J = np.empty((len(f0), len(y)))
    for j in range(len(y)):
        yc = y.astype(complex)
        yc[j] += 1j * h
        J[:, j] = np.imag(fun(yc)) / h
    return J


def elasticities(model, y):
    """dv/dy, the unscaled elasticities (n x m)."""
    return jacobian(lambda z: model.rates(z, model.p), y)


# --------------------------------------------------------------------------
# Conservation analysis

class Conservation:
    """Independent and dependent species, link matrix and conservation
    matrix, from QR with column pivoting of N^T."""

    def __init__(self, N, tol=None):
        N = np.asarray(N, dtype=float)
        m, n = N.shape
        Q, R, piv = qr(N.T, mode="economic", pivoting=True)
        d = np.abs(np.diag(R))
        if tol is None:
            tol = max(m, n) * np.finfo(float).eps * (d[0] if len(d) else 0.0)
        r = int(np.sum(d > tol))
        self.rank = r
        self.c = m - r
        ind, dep = piv[:r], piv[r:]
        # N[dep] = L0 N[ind] with L0 = (R11^-1 R12)^T.
        if r > 0 and self.c > 0:
            L0 = solve_triangular(R[:r, :r], R[:r, r:m]).T
        else:
            L0 = np.zeros((self.c, r))
        # List both sets in model order.
        oi, od = np.argsort(ind), np.argsort(dep)
        self.ind, self.dep = ind[oi], dep[od]
        self.L0 = L0[od][:, oi]
        self.Nr = N[self.ind]
        self.link = np.zeros((m, r))
        self.link[self.ind] = np.eye(r)
        self.link[self.dep] = self.L0
        self.gamma = np.zeros((self.c, m))     # Gamma N = 0
        self.gamma[:, self.dep] = np.eye(self.c)
        self.gamma[:, self.ind] = -self.L0

    def full(self, x, totals):
        """All species from the independent ones: y[dep] = L0 x + totals."""
        y = np.empty(len(self.ind) + len(self.dep), dtype=np.result_type(x, float))
        y[self.ind] = x
        y[self.dep] = self.L0 @ x + totals
        return y


def left_null_basis(N, kind="orthonormal"):
    """A basis of {k : k^T N = 0} as the columns of a matrix: orthonormal
    (from the SVD), or the conservation matrix Gamma^T of the link-matrix
    analysis ("gamma"), which for integer stoichiometry has small integer
    entries."""
    if kind == "orthonormal":
        return null_space(np.asarray(N, dtype=float).T)
    if kind == "gamma":
        return Conservation(N).gamma.T
    raise ValueError(kind)


# --------------------------------------------------------------------------
# The two square systems

def augmented(model, K=None, M=None, alpha=1.0, sign=+1.0, y_ref=None):
    """F(y) = N v(y) + sign K M (K^T y - K^T y_ref), and its parts.

    Returns (F, K, M). y_ref fixes the conservation class (default y0)."""
    if K is None:
        K = left_null_basis(model.N)
    c = K.shape[1]
    if M is None:
        M = alpha * np.eye(c)
    y_ref = model.y0 if y_ref is None else y_ref
    totals = K.T @ y_ref

    def F(y):
        return model.f(y) + sign * (K @ (M @ (K.T @ y - totals)))

    return F, K, M


def reduced(model, cons=None, y_ref=None):
    """G(x) = N_R v(full(x)) for the independent species x. Returns
    (G, cons, totals), totals = Gamma y_ref."""
    cons = Conservation(model.N) if cons is None else cons
    y_ref = model.y0 if y_ref is None else y_ref
    totals = cons.gamma @ y_ref

    def G(x):
        return model.f(cons.full(x, totals))[cons.ind]

    return G, cons, totals


# --------------------------------------------------------------------------
# Newton's method

class NewtonResult:
    def __init__(self, x, converged, iterations, history, reason=""):
        self.x = x
        self.converged = converged
        self.iterations = iterations
        self.history = history          # the iterates, x_0 first
        self.reason = reason

    def __repr__(self):
        return (f"NewtonResult(converged={self.converged}, iterations={self.iterations}, "
                f"reason={self.reason!r})")


def newton(F, x0, tol=1e-10, max_iter=100, line_search=True, step=None):
    """Newton's method on F(x) = 0 with an optional backtracking line search
    on |F|_2 (Armijo, halving). step(F, x) may supply the step instead of
    the Jacobian solve, for the pseudo-inverse variant. Converged when
    max |F_i| <= tol."""
    x = np.array(x0, dtype=float)
    hist = [x.copy()]
    for k in range(max_iter + 1):
        Fx = F(x)
        if not np.all(np.isfinite(Fx)):
            return NewtonResult(x, False, k, hist, "non-finite F")
        if np.max(np.abs(Fx)) <= tol:
            return NewtonResult(x, True, k, hist)
        if k == max_iter:
            break
        if step is None:
            J = jacobian(F, x)
            if np.linalg.cond(J) > 1e14:
                return NewtonResult(x, False, k, hist, "singular Jacobian")
            d = np.linalg.solve(J, -Fx)
        else:
            d = step(F, x)
        lam = 1.0
        if line_search:
            f0 = np.linalg.norm(Fx)
            while lam > 1e-12:
                Ft = F(x + lam * d)
                if np.all(np.isfinite(Ft)) and np.linalg.norm(Ft) <= (1 - 1e-4 * lam) * f0:
                    break
                lam /= 2
            if lam <= 1e-12:
                return NewtonResult(x, False, k, hist, "line search failed")
        x = x + lam * d
        hist.append(x.copy())
    return NewtonResult(x, False, max_iter, hist, "max iterations")


def pinv_step(F, x):
    """The minimum-norm Newton step, -J^+ F (Gauss-Newton on a singular J)."""
    return -np.linalg.lstsq(jacobian(F, x), F(x), rcond=None)[0]


# --------------------------------------------------------------------------
# Steady states and sensitivities

def steady_state(model, method="augmented", guess=None, **kw):
    """Steady state in the conservation class of model.y0.

    method: "augmented" (all species), "reduced" (independent species),
    "naive" (Newton on N v(y) = 0, singular with conservation laws) or
    "pinv" (minimum-norm steps on N v(y) = 0). Returns (y, NewtonResult)."""
    guess = model.y0 if guess is None else np.asarray(guess, dtype=float)
    opts = {k: v for k, v in kw.items() if k in ("tol", "max_iter", "line_search")}
    if method == "augmented":
        F, _, _ = augmented(model, **{k: v for k, v in kw.items()
                                      if k in ("K", "M", "alpha", "sign")})
        res = newton(F, guess, **opts)
        return res.x, res
    if method == "reduced":
        G, cons, totals = reduced(model)
        res = newton(G, guess[cons.ind], **opts)
        return cons.full(res.x, totals), res
    if method == "naive":
        res = newton(model.f, guess, **opts)
        return res.x, res
    if method == "pinv":
        res = newton(model.f, guess, step=pinv_step, **opts)
        return res.x, res
    raise ValueError(method)


def concentration_sensitivities(model, y, way="augmented", alpha=1.0, sign=+1.0):
    """Unscaled concentration control coefficients C^s (m x n): the change
    in the steady state per unit change in each reaction rate, within the
    conservation class, so that dy/dp = C^s dv/dp.

    "augmented": -J_F^{-1} N.  "reduced": -L J_R^{-1} N_R (Reder 1988)."""
    E = elasticities(model, y)
    if way == "augmented":
        K = left_null_basis(model.N)
        JF = model.N @ E + sign * alpha * K @ K.T
        return -np.linalg.solve(JF, model.N)
    cons = Conservation(model.N)
    JR = cons.Nr @ E @ cons.link
    return -cons.link @ np.linalg.solve(JR, cons.Nr)


def flux_control(model, y, Cs):
    """Unscaled flux control coefficients C^J = I + (dv/dy) C^s."""
    return np.eye(model.N.shape[1]) + elasticities(model, y) @ Cs
