No, it doesn't reduce the system the way libRoadRunner does. It keeps all *m* species as unknowns and adds a term so the system is still square and solvable.

## What it does

With $L$ an orthonormal basis of the null space of $N^T$ (`linalg.null(N')`, so $L^TN = 0$), `steady_state` solves

$$
F(y) = N\,v(y) + L\,(L^Ty - L^Ty_0) = 0
$$

for all $m$ species. The first term lies in the column space of $N$ and the second in the column space of $L$. Those two spaces are orthogonal, so $F = 0$ only when both terms vanish: $N v(y) = 0$, and the conserved totals $L^Ty$ equal their initial values $L^Ty_0$.

## Why the Jacobian isn't singular

The Jacobian is $J = N \dfrac{\partial v}{\partial y} + L L^T$.

- Suppose $Jz = 0$. By the same orthogonality, both $N \dfrac{\partial v}{\partial y} z = 0$ and $L^Tz = 0$.
- So $z$ lies in the stoichiometric subspace, and $N \dfrac{\partial v}{\partial y}$ is zero on it.
- That can only happen when the reduced Jacobian is itself singular.

So $J$ is nonsingular exactly when the reduced Jacobian is. Without the added term, $N \dfrac{\partial v}{\partial y}$ alone always has $c$ zero eigenvalues (one per conserved total), and Newton fails. That is what the conservation term fixes.

## Compared with libRoadRunner's reduction

| | libRoadRunner | Axon now |
|---|---|---|
| **Unknowns** | $m - c$ independent species, from a QR factorisation of $N$; dependent species from the conservation laws | all $m$ species |
| **Conservation** | link matrix $L_0$ and integer-like conservation laws | orthonormal basis from the SVD |
| **Jacobian** | $(m-c) \times (m-c)$ | $m \times m$ |
| **Cost per Newton iteration** | $m - c$ extra calls of $f$ | $m$ extra calls of $f$ |
| **Solutions** | same steady state | same steady state |

## What the full reduction would add

For the models so far, the extra $c$ unknowns cost almost nothing. The reduction becomes worth it if you want:

- the reduced Jacobian itself, for its eigenvalues and so the stability of a steady state;
- the conservation laws reported in their usual integer form;
- control coefficients later.

### Two side effects of the current approach

- The reported `fnorm` includes the conservation part of the residual.
- The totals are combinations from the SVD rather than the familiar ones like $E + ES$. The steady state is the same either way.

If you want parity with libRoadRunner, I can add the reduction to the antimony module. That would be the link matrix, the independent species, and the reduced Jacobian at the steady state.


What the paper actually contains. Obatake and Walker (2022) bound how many steady states a reaction network can have, using Newton–Okounkov bodies. The only overlap with our method is one definition in Section 2.1, equation (3), which they call "the system augmented by conservation laws":
- For each conservation law w, they drop the steady-state equation of the first species with a nonzero entry in w.
- In its place they put w·x − c = 0.

That gives a square system whose positive roots are the steady states in one conservation class. They use it to count roots algebraically, not to solve for them. It also differs from our version in needing a choice of which equations to replace, which the orthogonal K Kᵀ term avoids. My manual entry gave no author names or section, and "for example" made it look like a general source on the method.