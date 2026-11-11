# Steady states with conservation laws, without reduction: an augmented Newton system

**Project description.** Status: exploratory; theory worked out and checked numerically, not yet written up or compared on real models. Started November 2026 by Herbert Sauro and Claude (Anthropic), during work on the Axon language, whose `antimony` module uses the method (`steady_state(model, method = "augmented")`).

| File | Contents |
| --- | --- |
| `README.md` | This document: background, the method, theory with proofs, experiments, limitations, open questions and a work plan |
| `python/augss.py` | A reference implementation: conservation analysis (link matrix), the augmented and reduced systems, Newton's method, control coefficients |
| `python/models.py` | Test models: small classics, a Goldbeter–Koshland cycle, a bistable cycle, a toy glycolysis with three conservation laws, random mass-action networks |
| `python/experiments.py` | Experiments E1–E11, one per claim below. `python experiments.py` runs all (about 10 s); `python experiments.py E3` runs one |
| `python/results.txt` | The output of the last full run, quoted in section 6 |

Requirements: Python 3.10 or later with numpy and scipy (developed with Python 3.12, numpy 2.2, scipy 1.16).

---

## 1. Summary

When a reaction network has conservation laws (conserved moieties such as ATP + ADP, or total enzyme), its steady-state equations N v(y) = 0 do not determine a steady state, and their Jacobian is singular. The standard remedy, used in COPASI, libRoadRunner and most simulators, is to reduce the system: choose a set of independent species with the link matrix, express the others through the conserved totals, and solve a smaller system.

This project studies an alternative that needs no choice of species. With the columns of K a basis of the left null space of N (Kᵀ N = 0), solve, for all m species,

$$F(y) = N v(y) + K\,(K^T y - K^T y_0) = 0 .$$

The two terms lie in orthogonal subspaces, so F(y) = 0 exactly when the rates balance and the conserved totals keep their initial values. We show that:

1. the roots of F are exactly the steady states in the conservation class of y₀ (Theorem 1);
2. the Jacobian of F has the eigenvalues of the reduced Jacobian plus c eigenvalues fixed by the method (1, or any chosen value), and the same determinant up to a constant, so it is non-singular exactly when the reduced Jacobian is (Theorem 2);
3. Newton's method on F, started in the conservation class, produces exactly the iterates of Newton's method on the reduced system; started outside it, one full step restores the totals (Theorem 3);
4. the unscaled concentration control coefficients are −J_F⁻¹ N, with no link matrix (Theorem 4), and the response to the totals is J_F⁻¹ K;
5. any basis of the conservation laws works, including integer ones, and with the sign of the added term reversed, J_F is stable exactly when the reduced Jacobian is, so stability can be read from J_F (Theorems 5 and 6);
6. F is the Schur complement of a sparse bordered system with a Lagrange multiplier, which suggests how to scale the method to genome-scale networks (Theorem 7).

All of this is checked numerically (section 6). The method is not faster than the reduction at a solution (the iterations are the same), and its robustness from poor starting guesses is mixed. Its appeal is simplicity: a residual that is one line of code, no species selection, sensitivities and stability without the link matrix, and a direct path to a sparse formulation. We have not found this formulation in the systems biology literature; section 8 lists what to check.

---

## 2. Background

### 2.1 Notation

A network has m species with concentrations y ∈ ℝᵐ, n reactions with rates v(y) ∈ ℝⁿ (any differentiable rate laws, with parameters p), and stoichiometry matrix N ∈ ℝ^{m×n}:

$$\frac{dy}{dt} = N v(y).$$

Let r = rank N and c = m − r. A row vector γ with γ N = 0 is a conservation law: d(γ y)/dt = γ N v = 0, so γ y keeps its initial value. The conservation laws form the left null space of N, of dimension c. Their totals T = Γ y₀ define the conservation class (stoichiometric compatibility class) {y : Γ y = Γ y₀}, within which the dynamics stays.

The elasticity matrix is E = ∂v/∂y (n × m), and the Jacobian of the right-hand side is N E (m × m).

### 2.2 Why conservation laws are a problem

- **The steady state is not determined.** If N v(y) = 0 at y*, every conservation class has its own steady state; the equations alone do not say which class. The totals T must be imposed.
- **The Jacobian is singular.** Γ (N E) = 0, so N E has c zero eigenvalues (its rows are dependent). Newton's method on N v(y) = 0 fails, and stability cannot be read from the eigenvalues of N E without first discounting the c zeros.
- **Least-squares and pseudo-inverse Newton converge to the wrong class.** Minimum-norm steps (−(NE)⁺ N v) converge to some steady state, but in a class set by the starting guess, not by y₀ (experiment E4: 0 of 200 runs in the right class for every model).

### 2.3 The standard remedy: reduction with the link matrix

Following Reder (1988), Sauro and Ingalls (2004) and Vallabhajosyula, Chickarmane and Sauro (2006): order the species so that the first r rows of N are independent, N_R. The other rows are combinations of these, N₀ = L₀ N_R, so

$$N = \begin{bmatrix} I \\ L_0 \end{bmatrix} N_R = L\,N_R ,$$

with L the link matrix. The conservation matrix is Γ = [−L₀  I] (Γ L = 0), and the dependent species follow from the independent ones, y_dep = L₀ y_ind + T. The reduced system N_R v(y(y_ind)) = 0 has r equations in r unknowns and the reduced Jacobian

$$J_R = N_R\,E\,L ,$$

which is non-singular at an isolated steady state and whose eigenvalues decide stability. Vallabhajosyula et al. choose the independent species by QR factorisation of Nᵀ with column pivoting (LAPACK `dgeqp3`): Nᵀ P = Q [R₁₁ R₁₂], and L₀ = (R₁₁⁻¹ R₁₂)ᵀ. Henderson et al. (2015/16 draft) extend this to genome-scale networks with sparse rank-revealing QR (SuiteSparseQR) and sparse LU (LUSOL), keeping the null-space basis and the link matrix as operators.

As far as their documentation shows, COPASI (Householder QR with column pivoting; rank determination from LAPACK `dgelsy`) and libRoadRunner (libStructural, `analyzeWithQR`) both use this reduction. Neither source code has been checked for this project.

### 2.4 Replacing equations

Algebraic reaction network theory uses a different square system, the "system augmented by conservation laws" (Obatake and Walker 2022, section 2.1, eq. (3), there cited as standard): for each conservation law (a row w of a conservation matrix W), the steady-state equation of the first species with a non-zero entry in w is replaced by w y − w y₀ = 0. Its positive roots are the positive steady states in the class. It is used to count steady states (mixed volumes, Newton–Okounkov bodies), not to compute them, and it needs a choice of which equations to replace. Note the name clash: this project's "augmented system" adds a term instead of replacing equations.

---

## 3. The method

### 3.1 Definition

Let K ∈ ℝ^{m×c} have columns spanning the left null space of N (Kᵀ N = 0, rank K = c). Let M ∈ ℝ^{c×c} be non-singular and s = ±1. The augmented residual is

$$F(y) = N v(y) + s\,K M\,(K^T y - K^T y_0) .$$

The default in this project is K orthonormal (from the SVD: `scipy.linalg.null_space(N.T)`, Axon's `linalg.null(N')`), M = α I with α = 1, and s = +1. The Axon implementation (`stdlib/antimony.sci`, `steady_state(model, method = "augmented")`) uses exactly this, with KINSOL's Newton method and line search.

The Jacobian is

$$J_F = N E + s\,K M K^T .$$

### 3.2 In one sentence

Add to the rates of change a restoring term that lies entirely in the directions the reactions cannot move (the conservation directions), proportional to how far the totals are from their required values.

### 3.3 Implementation in Python

```python
from scipy.linalg import null_space
K = null_space(N.T)                     # orthonormal, K.T @ N = 0
T = K.T @ y0
F = lambda y: N @ v(y) + K @ (K.T @ y - T)
# solve F(y) = 0 with any Newton solver, e.g. scipy.optimize.root(F, guess)
```

`python/augss.py` has the full version (`augmented`, `newton`, `steady_state(model, "augmented")`).

---

## 4. Theory

Throughout, R(A) is the column space of A. Two facts are used repeatedly:

- **(F1)** R(N) and R(K) are orthogonal complements in ℝᵐ: R(K) is the left null space of N, which is R(N)^⊥. Hence also Kᵀ x = 0 ⇔ x ∈ R(N) for any x.
- **(F2)** R(L) = R(N): N = L N_R with N_R of full row rank r, and L has full column rank r. So Kᵀ L = 0 and the columns of [L K] form a basis of ℝᵐ (T := [L K] is invertible).

### Theorem 1 (roots)

F(y) = 0 if and only if N v(y) = 0 and Kᵀ y = Kᵀ y₀ (that is, y is a steady state in the conservation class of y₀).

*Proof.* N v(y) ∈ R(N) and s K M (Kᵀ y − Kᵀ y₀) ∈ R(K). By (F1) these subspaces intersect only in 0, so their sum is zero only if both are. The second is zero iff Kᵀ y = Kᵀ y₀, since K has full column rank and M is non-singular. ∎

Equivalently, multiply F by Kᵀ: Kᵀ F = s Kᵀ K M (Kᵀ y − Kᵀ y₀) (since Kᵀ N = 0), so F = 0 forces the totals; then F = N v(y) = 0.

### Theorem 2 (Jacobian spectrum and determinant)

At any y,

$$J_F\,[L\;\;K] = [L\;\;K] \begin{bmatrix} J_R & X \\ 0 & s\,M K^T K \end{bmatrix}$$

for some r × c matrix X, where J_R = N_R E L. Hence

- the eigenvalues of J_F are those of J_R together with those of s M KᵀK (for orthonormal K and M = α I: c eigenvalues equal to sα);
- det J_F = det(s M KᵀK) · det J_R;
- J_F is non-singular if and only if J_R is.

*Proof.* J_F L = N E L + s K M Kᵀ L = L N_R E L = L J_R, using Kᵀ L = 0 (F2). J_F K = N E K + s K (M Kᵀ K); the first term lies in R(N) = R(L), so equals L X for some X. Since T = [L K] is invertible, J_F = T B T⁻¹ with B the block upper-triangular matrix shown, which has the stated eigenvalues and determinant. ∎

Without the added term (N E alone) the lower-right block would be 0: the c zero eigenvalues of N E are exactly what the term replaces. Note that the similarity transform T is not orthogonal, so the condition number of J_F is not that of J_R (section 4.8).

### Theorem 3 (Newton iterates)

Let y_k be a point and Δ the full Newton step for F: J_F Δ = −F(y_k).

(a) **Totals.** Kᵀ(y_k + λΔ) − Kᵀ y₀ = (1 − λ)(Kᵀ y_k − Kᵀ y₀) for any step length λ. A full step (λ = 1) puts the iterate in the conservation class, exactly in exact arithmetic, and every later iterate stays there.

(b) **Equivalence with reduction.** If y_k is in the class, the Newton step for F is the Newton step for the reduced system, lifted through the link matrix: Δ = L Δ_R with J_R Δ_R = −N_R v(y_k). So full Newton on F from a point in the class produces the same iterates as full Newton on the reduced system from the corresponding independent species.

*Proof.* (a) Multiply J_F Δ = −F by Kᵀ. Kᵀ J_F = Kᵀ N E + s KᵀK M Kᵀ = s KᵀK M Kᵀ and Kᵀ F = s KᵀK M (Kᵀ y_k − Kᵀ y₀). Cancelling the non-singular s KᵀK M gives Kᵀ Δ = −(Kᵀ y_k − Kᵀ y₀). (b) If y_k is in the class, Kᵀ Δ = 0, so Δ ∈ R(N) = R(L) (F1, F2): Δ = L a. Then J_F L a = L J_R a (Theorem 2) and F(y_k) = N v(y_k) = L N_R v(y_k), so L (J_R a + N_R v) = 0, and since L has full column rank, J_R a = −N_R v. ∎

Consequences: locally the augmented method converges exactly as the reduced one does (quadratically near a non-singular root). Any difference in practice comes from the globalisation (line search or trust region), because the merit functions differ: for orthonormal K,

$$\|F(y)\|^2 = \|N v(y)\|^2 + \|M (K^T y - K^T y_0)\|^2 \quad\text{versus}\quad \|N_R v(y)\|^2 ,$$

and ‖N v‖ = ‖L N_R v‖ weights the independent rates by LᵀL. With a guess outside the class, the first step also differs: the reduced method silently moves the guess into the class along the dependent species (y_dep := L₀ y_ind + T), while the augmented method moves it along R(K) as part of the first Newton step.

### Theorem 4 (sensitivities without the link matrix)

Let y* be a steady state with J_R non-singular, and let a parameter p change the rates (∂v/∂p). Then, within the conservation class,

$$\frac{dy^*}{dp} = -J_F^{-1} N \frac{\partial v}{\partial p}, \qquad C^s = -J_F^{-1} N ,$$

where C^s is the matrix of unscaled concentration control coefficients, equal to the classical −L J_R⁻¹ N_R (Reder 1988). The result does not depend on K, M or s. The unscaled flux control coefficients are C^J = I + E C^s. The response to the totals T = Kᵀ y₀ is dy*/dT = s J_F⁻¹ K M.

*Proof.* Differentiate F(y*(p), p) = 0: J_F dy*/dp + N ∂v/∂p = 0 (the added term does not depend on p). For the link-matrix form: N ∂v/∂p = L w with w = N_R ∂v/∂p, and J_F⁻¹ L = L J_R⁻¹ (from J_F L = L J_R), so −J_F⁻¹ N ∂v/∂p = −L J_R⁻¹ N_R ∂v/∂p. For the totals, ∂F/∂T = −s K M. ∎

This means metabolic control analysis can be done from one square solve with J_F, without choosing independent species. Checked against the link-matrix formula and against finite differences of the steady state (E5), together with the summation theorems C^s v = 0 and C^J v = v.

### Theorem 5 (other bases and weights)

Theorems 1–4 hold for any K whose columns span the left null space and any non-singular M; only the c extra eigenvalues change, to those of s M KᵀK. In particular K = Γᵀ, the integer conservation matrix of the link-matrix analysis, works without any orthogonalisation; the extra eigenvalues are those of s Γ Γᵀ (E7). This matters for large networks, where Γ can be sparse and an orthonormal K is dense.

### Theorem 6 (stability from J_F)

If s = −1 and the eigenvalues of M KᵀK have positive real parts (for example orthonormal K and M = αI with α > 0), then J_F has all eigenvalues in the open left half-plane exactly when J_R does. A steady state can be classified as stable or unstable from J_F directly. Also, eigenvalues of J_F that cross the imaginary axis as a parameter varies (folds and Hopf bifurcations) are those of J_R, since the c extra eigenvalues stay at −α; det J_F changes sign exactly where det J_R does. For s = +1 (the Axon default) the extra eigenvalues are +α, so J_F always has c positive eigenvalues and cannot be used this way; Newton's method does not care about the sign.

*Proof.* Theorem 2. ∎

### Theorem 7 (bordered and Lagrange forms)

With M = α I, introduce μ = α (Kᵀ y − T). The bordered system

$$N v(y) + K \mu = 0, \qquad K^T y - T - \mu/\alpha = 0$$

in the m + c unknowns (y, μ) has the Jacobian [[N E, K], [Kᵀ, −I/α]], whose Schur complement with respect to the lower-right block is N E + α K Kᵀ = J_F. Newton's method on the bordered system therefore takes the same steps in y as on F (E11: iterates agree to 1e−13). As α → ∞ the bordered system becomes

$$N v(y) + K \mu = 0, \qquad K^T y = T ,$$

the Lagrange (KKT) form of "N v(y) = 0 subject to the conservation laws", with μ a multiplier. At every solution μ = 0, because Kᵀ(N v + K μ) = KᵀK μ = 0. The bordered Jacobian keeps the sparsity of N E and K; the augmented J_F has the dense rank-c term K Kᵀ. So the bordered form, or a Sherman–Morrison–Woodbury treatment of the rank-c update, is the route to sparse, genome-scale use.

### 4.8 Conditioning and the choice of α

J_F mixes rates (units concentration/time) with concentration differences, so its conditioning depends on α. In E8, cond(J_F) is far worse than cond(J_R) for α much smaller or larger than the eigenvalues of J_R, and close to it for α near their geometric mean. Natural defaults to test are α ≈ a typical |eigenvalue| of N E at the guess (its spectral radius, or a norm of N E), or scaling K's columns by typical concentrations. α = 1 works for the test models, whose rate constants are of order 1, but this is an open question for real models with time scales of 10⁻³ to 10³ (section 7).

---

## 5. Relation to known ideas

These are leads to follow up; none has been read in detail for this project.

- **Baumgarte stabilisation** (Baumgarte 1972): constraints of a differential-algebraic system are kept by adding a term proportional to the constraint violation to the dynamics. The dynamic version of the augmented term, dy/dt = N v(y) − β K(Kᵀ y − T), is exactly this applied to the conservation laws: trajectories with the right totals are unchanged, and drift in the totals decays at rate β (E9). It could be used against drift in long simulations.
- **Bordered systems and pseudo-arclength continuation** (Keller 1977; AUTO, MATCONT): Newton's method on systems bordered with extra equations is standard in continuation. Theorem 7 puts the augmented system in that frame.
- **Constrained least squares and KKT systems**: the α → ∞ limit of Theorem 7.
- **Projection and stabilised index reduction for DAEs** (Gear, Gupta and Leimkuhler 1985): related ways of enforcing invariants.
- **The augmented system of reaction network theory** (section 2.4): the replace-equations version.
- **Simulators' steady-state solvers**: COPASI, libRoadRunner (NLEQ2, KINSOL on the reduced system?), Jarnac/SCAMP, PySCeS, AMICI's steady-state sensitivities (Lakrisenko et al. 2023 discuss singular Jacobians from conserved quantities): how each handles conservation laws should be documented from their sources.

---

## 6. Numerical experiments

`python/experiments.py`; full output in `python/results.txt`. Jacobians are complex-step derivatives (exact to rounding). Newton's method: dense, with an optional Armijo backtracking line search on ‖F‖₂, converged when max |Fᵢ| ≤ 10⁻¹⁰.

### Models (`python/models.py`)

| Model | m | n | c | Conservation laws | Notes |
| --- | --- | --- | --- | --- | --- |
| `two_state` | 2 | 2 | 1 | A + B | Linear |
| `enzyme_feed` | 4 | 5 | 1 | E + ES | Mass action, substrate fed in; the Axon manual's example |
| `two_cycles` | 4 | 4 | 2 | A + B, C + D | Linear |
| `gk_cycle` | 2 | 2 | 1 | W + Wp | Goldbeter–Koshland zero-order ultrasensitivity (K = 0.01) |
| `bistable_cycle` | 2 | 2 | 1 | W + Wp | Kinase activated by Wp: steady states Wp ≈ 0.0025, 0.4705, 0.9271 |
| `glycolysis` | 9 | 7 | 3 | ATP + ADP, NAD + NADH, Pyr − NADH | Toy glycolysis with ATP feedback; the third law is not a moiety (it has a negative coefficient): lactate formation consumes one Pyr and one NADH |
| `random_closed(seed)` | 8 | 16 | 1–3 | total "mass" and others | Random reversible mass-action networks |

### Results

**E1, roots (Theorem 1).** Augmented and reduced Newton and a long LSODA simulation agree on every model to 10⁻¹⁰ or better; totals are kept to 10⁻¹⁶.

**E2, spectrum (Theorem 2).** eig(J_F) equals eig(J_R) plus c copies of sα to 10⁻¹³ for α = 1, s = +1 and α = 3, s = −1; det J_F / ((sα)^c det J_R) = 1.000000000000 for all models. Enzyme model: eig(J_R) = −7.3504, −0.8163, −0.5.

**E3, iterates (Theorem 3).** Glycolysis, full Newton without line search. From y₀ (in the class): the augmented and reduced iterates agree to 10⁻¹² at every one of 7 iterations. From a guess outside the class: ‖Kᵀ y − Kᵀ y₀‖ = 0.80, then 2 × 10⁻¹⁶ after the first step. A damped step λ multiplies the error in the totals by exactly 1 − λ (0.750000000000 for λ = 0.25).

**E4, robustness from 200 random guesses** (each component log-uniform in [10⁻², 10²] times the model's scale; line search; at most 200 iterations). Columns: converged, in the right class, non-negative, equal to the reference steady state, mean iterations.

| Model | Method | Conv. | In class | y ≥ 0 | = ref | Mean it. |
| --- | --- | --- | --- | --- | --- | --- |
| enzyme_feed | augmented | 200 | 200 | 200 | 200 | 2.5 |
| | reduced | 200 | 200 | 200 | 200 | 2.5 |
| | naive (N v = 0) | 0 | 0 | 0 | 0 | |
| | pseudo-inverse | 200 | 0 | 0 | 0 | 3.2 |
| gk_cycle | augmented | 130 | 130 | 130 | 130 | 6.5 |
| | reduced | 200 | 200 | 117 | 117 | 6.6 |
| | pseudo-inverse | 175 | 0 | 0 | 0 | 7.1 |
| bistable_cycle | augmented | 164 | 164 | 136 | 50 | 5.9 |
| | reduced | 200 | 200 | 155 | 16 | 5.4 |
| glycolysis | augmented | 190 | 190 | 179 | 179 | 11.2 |
| | reduced | 175 | 175 | 175 | 175 | 11.7 |

(two_state and two_cycles, which are linear: augmented and reduced converge in one iteration from every guess; naive Newton fails and the pseudo-inverse converges outside the class, as for enzyme_feed.) Reading: naive Newton always fails (singular Jacobian); the pseudo-inverse converges but never in the right class. Between augmented and reduced the picture is mixed: on the ultrasensitive cycle the augmented method fails more often but never converges to a negative root, while the reduced method always converges but in 83 of 200 cases to a non-physical one; on glycolysis the augmented method converges more often. With several steady states (bistable) the two methods land on different ones from the same guesses ("= ref" is the state reached from y₀). These differences come from the line search's merit function and from how a guess outside the class is mapped into it (Theorem 3), not from the local behaviour.

**E5, sensitivities (Theorem 4).** Enzyme and glycolysis models: −J_F⁻¹ N equals −L J_R⁻¹ N_R to 10⁻¹⁴, is independent of α and s (α = 1, s = +1 versus α = 7, s = −1: 10⁻¹⁴), and matches central finite differences of the steady state with respect to each rate to 10⁻⁹. The summation theorems hold: max |C^J v − v| ≤ 4 × 10⁻¹⁶, max |C^s v| ≤ 4 × 10⁻¹⁵. dy*/dT₁ = J_F⁻¹ K e₁ matches finite differences in the total to 10⁻⁹.

**E6, stability (Theorem 6).** Bistable cycle with s = −1: Newton from 21 guesses finds Wp = 0.0025 (eig J_F = −18.10, −1: stable), 0.4705 (1.60, −1: unstable), 0.9271 (−4.90, −1: stable), and a non-physical root at Wp = −0.545. Each J_F spectrum is J_R's plus −1.

**E7, integer basis (Theorem 5).** With K = Γᵀ (for glycolysis Γ has rows ATP + ADP, Pyr + NAD, NADH − Pyr) the method finds the same steady states, and eig(J_F) = eig(J_R) ∪ eig(Γ Γᵀ) to 10⁻¹⁴.

**E8, conditioning (section 4.8).** Glycolysis, cond(J_R) = 583, |eig(J_R)| ∈ [0.08, 16.3]: cond(J_F) = 1.9 × 10⁶ (α = 10⁻⁴), 1.9 × 10⁴ (10⁻²), 740 (1), 734 (1.14, the geometric mean), 3300 (100), 3.3 × 10⁵ (10⁴). Enzyme model similar, best near α ≈ 2.

**E9, stabilised dynamics (section 5).** dy/dt = N v − β K (Kᵀ y − T) from totals off by 0.1: the error decays as e^{−βt} (β = 1: 0.0368 at t = 1; β = 5: 6.7 × 10⁻⁴), and from the right totals the trajectory is unchanged (10⁻¹⁶ at t = 5).

**E10, random networks.** 100 random reversible mass-action networks (8 species, 16 reactions, 1–3 conservation laws, mean 1.6): both methods converged in all 100 from y₀. In 98 they found the same steady state; in the other two (seeds 39 and 83) both found valid steady states in the class, but different boundary steady states (some species at zero), so these networks have more than one steady state in the class. eig(J_F) = eig(J_R) ∪ {1} to a relative 4 × 10⁻¹⁵ in every case.

**E11, bordered form (Theorem 7).** Glycolysis: Newton on the (y, μ) system takes 7 iterations, as on F, with iterates equal to 3 × 10⁻¹³ for α = 1 and 10; the KKT limit (α = ∞) converges to the reduced solution (10⁻¹³), and μ = 0 at every solution.

---

## 7. Limitations and open questions

**What the method does not change.**

- Local convergence is the same as for the reduction (Theorem 3): no gain in speed near a root, and the same failure at singular J_R (folds, non-isolated steady states).
- Like any Newton method it finds a root near the guess: possibly negative concentrations (E4, E6), one of several steady states (E6, E10), or none. Positivity is not enforced; KINSOL's constraint option or a log transform could be tried.

**Costs.**

- m unknowns instead of r: c more evaluations of the rates per finite-difference Jacobian, and an m × m instead of r × r linear solve. Small for c ≪ m.
- An orthonormal K costs an SVD (O(m³), dense) and K Kᵀ is a dense rank-c matrix. For large sparse networks use an integer Γ (Theorem 5) from a sparse factorisation (Henderson et al.), and the bordered form or a Woodbury update (Theorem 7).
- The rank decision (which singular values or R diagonals count as zero) is the same as in the reduction, with the same tolerance issues for non-integer stoichiometry.

**Scaling.** The added term must be commensurate with the rates (section 4.8). How to choose α (or M) automatically for real models with stiff, widely separated time scales is open. Candidates: α from the spectral radius or a norm of N E at the guess; M = diag of typical rates / typical concentrations per law; column scaling of K by typical concentrations.

**Globalisation.** The line search sees ‖N v‖² + ‖M(Kᵀy − T)‖², not the reduced merit function. E4 shows this can help or hurt. Should a guess be projected into the class first (y ← y + K (KᵀK)⁻¹ (T − Kᵀ y), cheap), which by Theorem 3 makes the full-step iterates those of the reduction while keeping the simple residual? Does weighting the totals term heavily make the method behave like "fix the totals first, then solve"?

**Interpretation.** The extra c eigenvalues are artefacts. With s = +1 (the Axon default) J_F always has c positive eigenvalues, so anyone reading stability from J_F must use s = −1 (Theorem 6). Should Axon switch to s = −1? Newton's method is indifferent.

**What we have not shown.**

- Whether the method is new (section 8, task 1).
- Performance on real models (section 8, task 3).
- Behaviour with ODE solvers' "simulate to steady state" hybrids (as in COPASI and libRoadRunner).
- The sparse/bordered form in practice.

---

## 8. Work plan

Each task lists what to do and what counts as done.

1. **Literature check.** Search for the formulation N v + K(Kᵀy − T) = 0, or "add a multiple of the conservation-law violation", in: steady-state and MCA literature (Reder; Hofmeyr; Heinrich and Schuster's book; Cornish-Bowden), software papers (COPASI; libRoadRunner and its steady-state solvers; PySCeS; Jarnac/SCAMP; AMICI, Lakrisenko et al. 2023), continuation (Keller; Allgower and Georg; Govaerts; MATCONT), DAE stabilisation (Baumgarte; Gear–Gupta–Leimkuhler; Ascher), reaction network theory (Feinberg; Conradi, Feliu and others on augmented systems), and optimisation (penalty and augmented Lagrangian methods). *Done when:* a short annotated bibliography says whether and where it appears, and how Theorems 2–7 relate to known results.
2. **Tidy the theory.** Write Theorems 1–7 as a short note with full proofs; add the complex-eigenvalue case (Hopf) to Theorem 6 and the statement for general M. Decide on notation that matches the MCA literature (Γ, L, N_R, J_R, C^s, C^J). *Done when:* the note reads as a self-contained methods section.
3. **Benchmark on real models.** Take curated SBML models from BioModels with conservation laws (load with libRoadRunner/tellurium for N, rates and Jacobians, or with the Axon antimony reader for simple ones). For each: steady state from the initial values and from perturbed guesses with (a) reduction, (b) augmented with α = 1, (c) augmented with scaled α, (d) augmented with projected guess, (e) the bordered/KKT form, (f) libRoadRunner's own steady-state solver. Record success, physical correctness, iterations, time. *Done when:* a table over ≥ 50 models, with the scripts in `python/`.
4. **Scaling of α.** From task 3, find a rule for α (or M) that keeps cond(J_F) near cond(J_R); test it on stiff models. *Done when:* a default with evidence.
5. **Sparse version.** Implement the bordered form with a sparse LU (scipy `splu`, or SuiteSparse/UMFPACK) and an integer Γ from a sparse factorisation; test on a genome-scale model (BiGG Recon, with simple kinetics) for feasibility. *Done when:* timing and memory against the reduced sparse approach of Henderson et al.
6. **MCA without the link matrix.** Package Theorem 4 (control coefficients, response to totals, sensitivities to parameters) and compare with libRoadRunner/COPASI MCA output on the benchmark models. *Done when:* agreement to solver tolerance on all models.
7. **Dynamics.** Test the stabilised ODE (E9) against drift in long simulations with loose tolerances. *Done when:* a figure showing drift with and without, and the effect on step counts.
8. **Write-up.** A methods paper or application note for the systems biology community (candidates: *Bioinformatics*, *BMC Bioinformatics*, *Journal of Mathematical Biology*, *PLoS Computational Biology* Methods, or an arXiv preprint first). Include the Python reference implementation.

---

## 9. Implementations

**Python (this folder).** `augss.py`:

| Function | Purpose |
| --- | --- |
| `Model(name, species, N, rates, y0, p)` | A network; `f(y)` = N v(y); `rates(y, p)` must accept complex y |
| `jacobian(fun, y)` | Complex-step Jacobian |
| `Conservation(N)` | QR with column pivoting: `ind`, `dep`, `L0`, `link`, `gamma`, `Nr`, `full(x, totals)` |
| `left_null_basis(N, kind)` | Orthonormal K (SVD) or Γᵀ |
| `augmented(model, K, M, alpha, sign)` | The residual F and its K, M |
| `reduced(model)` | The reduced residual on the independent species |
| `newton(F, x0, ...)` | Dense Newton with Armijo backtracking; records the iterates |
| `steady_state(model, method, guess)` | `"augmented"`, `"reduced"`, `"naive"`, `"pinv"` |
| `concentration_sensitivities(model, y, way)` | C^s by Theorem 4 or by the link matrix |
| `flux_control(model, y, Cs)` | C^J = I + E C^s |

**Axon.** `stdlib/antimony.sci` in this repository: `conservation(model)` (QR with column pivoting through `linalg.qrp`), `steady_state(model; method = "reduced" | "augmented")` (KINSOL through `nonlin.solve`), `jacobian`, `reduced_jacobian`. The Axon manual's section "Conservation laws and the link matrix" presents both methods and the proof of Theorem 2.

---

## 10. Picking the project up again

1. Run `python python/experiments.py` from this folder and compare with `python/results.txt`; all checks should reproduce (they are deterministic, seeded).
2. Read sections 4 (theory) and 7 (open questions); the next task in order is 8.1 (literature), then 8.3 (benchmarks).
3. Claims and their status:

| Claim | Proof | Numerical check |
| --- | --- | --- |
| Theorem 1, roots | Section 4 | E1, E10 |
| Theorem 2, spectrum and determinant | Section 4 | E2, E10 |
| Theorem 3, iterates | Section 4 | E3 |
| Theorem 4, sensitivities | Section 4 | E5 |
| Theorem 5, other bases | Follows from Theorem 2 | E7 |
| Theorem 6, stability | Follows from Theorem 2 | E6 |
| Theorem 7, bordered/KKT forms | Section 4 | E11 |
| Conditioning versus α | Not proved; observation | E8 |
| Robustness versus reduction | Open; mixed evidence | E4 |
| Novelty | Open | Task 8.1 |

---

## References

Checked for this project (at least the abstract and the relevant passage):

- C. Reder. Metabolic control theory: a structural approach. *Journal of Theoretical Biology* 135(2):175–201, 1988.
- H. M. Sauro and B. Ingalls. Conservation analysis in biochemical networks: computational issues for software writers. *Biophysical Chemistry* 109(1):1–15, 2004.
- R. R. Vallabhajosyula, V. Chickarmane and H. M. Sauro. Conservation analysis of large biochemical networks. *Bioinformatics* 22(3):346–353, 2006.
- N. W. Henderson, S. Kim, D. Ma, M. A. Saunders, Y. Sun, R. M. T. Fleming and I. Thiele. Conservation analysis of genome-scale biochemical networks. Draft, January 2016 (Bioinformatics format); https://web.stanford.edu/group/SOL/multiscale/papers/conservation06.pdf. Sparse QR (SuiteSparseQR) and sparse LU (LUSOL); notes that dense Householder QR on Nᵀ, as in Vallabhajosyula et al., needs no Gauss–Jordan step on R₁.
- N. Obatake and E. Walker. Newton–Okounkov bodies of chemical reaction systems. arXiv:2203.03840, 2022. Section 2.1, eq. (3): the system augmented by conservation laws (replacing equations).
- COPASI documentation: user manual, "Mass Conservations" (Householder QR); API documentation of `CLinkMatrix` (column pivoting, rank determination from LAPACK `dgelsy`).

To read (section 8, task 1):

- J. Baumgarte. Stabilization of constraints and integrals of motion in dynamical systems. *Computer Methods in Applied Mechanics and Engineering* 1:1–16, 1972.
- H. B. Keller. Numerical solution of bifurcation and nonlinear eigenvalue problems. In *Applications of Bifurcation Theory*, Academic Press, 1977.
- C. W. Gear, B. Leimkuhler and G. K. Gupta. Automatic integration of Euler–Lagrange equations with constraints. *Journal of Computational and Applied Mathematics* 12–13:77–90, 1985.
- P. Lakrisenko, P. Stapor, S. Grein, Ł. Paszkowski, D. Pathirana, F. Fröhlich, G. T. Lines, D. Weindl and J. Hasenauer. Efficient computation of adjoint sensitivities at steady-state in ODE models of biochemical reaction networks. *PLoS Computational Biology* 19(1):e1010783, 2023.
- R. Heinrich and S. Schuster. *The Regulation of Cellular Systems*. Chapman & Hall, 1996.

The bibliographic details in the second list are from memory and must be checked.
