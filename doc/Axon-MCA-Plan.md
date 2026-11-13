# Metabolic control analysis in Axon: plan

Status (2026-11-13): decisions D1, D2 and D6 agreed. **A1–A8 done**: boundary
species, rates, elasticities, control and response coefficients (confirmed
against Tellurium 2.2.11.1 / libRoadRunner 2.9.1: to 1e-13, and 1e-7 where
Michaelis–Menten rate laws curve; response coefficients to 1e-5, the
accuracy of libRoadRunner's `getCC`), `plot.bar3` with named axes and
`clim`, `fmt.matrix` with row and column names, the manual section
"Metabolic control analysis" and Welcome example 30.

## Goal

For any reaction network written in the `antimony` module's subset, compute at
a steady state:

- the **elasticities**, unscaled and scaled, with respect to the species and
  to the parameters;
- the **flux control coefficients** C^J and **concentration control
  coefficients** C^S, unscaled and scaled;
- optionally, the **response coefficients** of fluxes and concentrations to
  parameters;

correctly for networks with conserved moieties, branches and cycles. Then
plot them, for example as 3D bars with `plot.bar3` (rows are fluxes or
species, columns are the reactions perturbed), and print them as labelled
tables.

## What exists

`stdlib/antimony.sci` already has most of the structure:

| Have | Where |
| --- | --- |
| Reactions, species, parameters (`Model`, `Reaction`) | `load`, `read` |
| Stoichiometry matrix N (species × reactions) | `stoichiometry` |
| dy/dt = N v(y) as one compiled function f(t, y, p) | `rhs_text`, `rhs` |
| Conservation analysis: independent and dependent species, Nr, L0, link matrix L, gamma | `conservation` (Reder; Sauro and Ingalls 2004) |
| Steady state, reduced or augmented | `steady_state` |
| Jacobian and reduced Jacobian by central differences | `jacobian`, `reduced_jacobian` |

What is missing:

1. **Boundary species.** Every species in a reaction is a floating species
   today. Real pathways have fixed sources and sinks (`$X0 -> S1`), which
   Antimony marks with `$`. Without them, an open pathway can only be written
   with the boundary concentration as a parameter. That works, but it isn't
   Antimony and doesn't read like it.
2. **The reaction rates on their own.** `rhs` returns N v; MCA needs v itself
   (the fluxes at the steady state, and the rates to differentiate).
3. **Elasticities**, ∂v/∂s and ∂v/∂p.
4. **The control-coefficient algebra.**
5. **Plotting and printing support:**
   - named ticks on 3D axes (reaction and species names under the bars);
   - a fixed colour range, so that with `"coolwarm"` the grey middle is at 0.
     Control coefficients have both signs, and concentration control
     coefficients sum to zero, so this matters here. The bar plot's current
     colour range runs from the smallest value to the largest;
   - matrices printed with row and column names.

## The theory to implement

Notation: m floating species s, n reactions v, N = L Nr (link matrix L,
m × r; reduced stoichiometry Nr, r × n; r the number of independent species).
All of this is in the unscaled form.

- **Elasticities:** ε = ∂v/∂s (n × m), at the steady state, with the
  parameters and boundary species fixed. Parameter elasticities:
  π = ∂v/∂p (n × p).
- **Reduced Jacobian:** Jr = Nr ε L (r × r). It must be non-singular.
- **Concentration control:** C^S = −L Jr⁻¹ Nr (m × n), computed as
  `-L * (Jr \ Nr)`.
- **Flux control:** C^J = I + ε C^S (n × n).
- **Response coefficients:** R^S = C^S π and R^J = C^J π.
- **Scaled forms**, with J the steady-state fluxes and s the steady-state
  concentrations:
  - C^J_ij · J_j / J_i
  - C^S_ij · J_j / s_i
  - ε_ij · s_j / v_i
  - R_ik · p_k / (J_i or s_i)

  Where a denominator is 0 (a zero flux or concentration), the scaled entry
  is NaN, not an error.

Row i of C^J is flux i; column j is the reaction perturbed. Rows of C^S are
species. This is the orientation Tellurium/libRoadRunner uses, so results can
be compared directly.

**Theorems used as checks** (in tests, and optionally returned):

- Summation:
  - C^J J = J, so each row of scaled C^J sums to 1.
  - C^S J = 0, so each row of scaled C^S sums to 0.
- Connectivity:
  - C^J ε L = 0
  - C^S ε L = −L

These forms hold for any network, including branched ones, cycles, and
networks with conserved moieties (Reder 1988). No independent-flux (K)
matrix is needed.

## Decisions

| # | Question | Decision |
| --- | --- | --- |
| D1 | Where does it live? | **Agreed:** in `antimony`: everything takes a `Model`, and conservation, steady state and Jacobians are already there. About 250 more lines. A separate `mca` module is the alternative if `antimony` grows too large |
| D2 | How are elasticities computed? | **Agreed: five-point finite differences** on the compiled rates function: (f(s−2h) − 8f(s−h) + 8f(s+h) − f(s+2h)) / 12h, with h relative to s (about eps^(1/5) |s|, and a small floor when s = 0). Error is O(h⁴), and it works for any rate law the module accepts. libRoadRunner does the same. Two alternatives: complex-step (exact to machine precision, but fails on `abs`, `min`, `max` and conditionals, and wouldn't run compiled); or symbolic differentiation (exact, but needs an expression differentiator, a project of its own). Keep the step size checked by the tests |
| D3 | Boundary species' values | They go in the parameter vector p after the parameters. That way `set(sim, "X0", ...)` and parameter elasticities and responses with respect to them come for free |
| D4 | The API | One call returning a record (below), plus the separate pieces for people who want only elasticities. Names in Axon's style, not Tellurium's `getuCC` / `getCC` |
| D5 | Scaling where a value is 0 | NaN in that entry |
| D6 | Named ticks on 3D axes | **Agreed:** a Rho3DPlotter change (per-axis tick labels at given positions) |

## Proposed API

```axon
import antimony
m = antimony.load("""
  $X0 -> S1; k1*X0 - km1*S1
  S1 -> S2;  Vm2*S1/(Km2 + S1)
  S2 -> $X1; k3*S2
  X0 = 10; X1 = 0
  k1 = 1; km1 = 0.5; Vm2 = 5; Km2 = 2; k3 = 0.8
""")
mca = antimony.control(m)          # steady state found first
println(mca.reactions, mca.J)
println(mca.flux_control)          # scaled C^J, rows = fluxes, columns = reactions
println(mca.concentration_control) # scaled C^S, rows = species
```

| Function | Result |
| --- | --- |
| `reaction_names(model)` | The reactions' names, in order (the columns of N) |
| `boundary_names(model)` | The boundary (`$`) species |
| `rates_text(model)`, `rates(model)` | The rates v(y, p) as text and as a compiled function, built the way `rhs_text`/`rhs` are. `rhs` can then be written in terms of it |
| `fluxes(model, y)` | v at the species values y |
| `elasticities(model, y; scaled = false)` | ∂v/∂s, reactions × floating species |
| `parameter_elasticities(model, y; scaled = false)` | ∂v/∂p, reactions × (parameters, then boundary species) |
| `control(model; y = nothing, scaled = true)` | A `Control` record. With `y = nothing`, the steady state is computed, and an error is raised if it isn't found |
| `response(model; y = nothing, scaled = true)` | Response coefficients to every parameter: a record with `flux` and `concentration` matrices |

```axon
export record Control
  species: list               # floating species, rows of concentration_control
  reactions: list             # rows and columns of flux_control
  y: vector                   # steady-state concentrations
  J: vector                   # steady-state fluxes
  elasticities: matrix        # scaled or unscaled, as asked
  flux_control: matrix        # C^J
  concentration_control: matrix   # C^S
  scaled: bool
end
```

**Errors:**

- If the reduced Jacobian is singular, `control` raises `SingularMatrix`
  saying so (what `\` raises). Typical causes are a species that nothing depends on, or a degenerate
  steady state.
- If the steady state isn't found, `control` raises with
  `steady_state`'s status.

## Milestones

Each milestone ends with its tests, run in the three JIT modes, plus its
Reference rows and help text.

**A1. Boundary species.**
- `load` reads `$name` on either side of a reaction.
- The name becomes a boundary species: no row in N, value from its
  assignment, given to the rate laws through p (D3).
- `Model` gains a `boundary` dict.
- `species_names` lists floating species only; `boundary_names` lists the
  fixed ones.
- Simulations and steady states treat boundary species as constants. `set`
  and `value` accept their names.
- Existing models (no `$`) behave exactly as before.

**A2. Reaction rates.**
- `reaction_names`, `rates_text`, `rates`, `fluxes`.
- `rhs_text` is rebuilt on the rates (one place for the rate-law text), with
  output unchanged.

**A3. Elasticities.**
- `elasticities` and `parameter_elasticities`, with five-point differences,
  unscaled and scaled.
- Tests compare against analytic derivatives: mass action, Michaelis–Menten,
  and Hill with n = 2.

**A4. Control coefficients.**
- `Control` and `control`.
- Tests (expected values written by hand, as for other tests):
  - **Two-step pathway**, $X0 → S1 → $X1 with v1 = k1 X0 − km1 S1 and
    v2 = k2 S1. By hand:
    - C^J = [k2, km1; k2, km1] / (k2 + km1) on both rows
    - C^S1 = k2/(k2 + km1) · [1, −1]
  - **Three-step linear pathway**, against the textbook closed form.
  - **A branched pathway:** the summation and connectivity theorems, to
    about 1e-8.
  - **A conserved moiety** (an ATP/ADP-coupled step): the link-matrix path.
    Summation and connectivity hold, and C^S for the two moiety species have
    opposite signs.
  - **Cross-check by perturbation:** a test multiplies each reaction's rate
    law text by a factor e_j (the `rate` field is text), solves the steady
    state at e_j = 1 ± δ, and compares d ln J / d ln e_j with C^J (and
    likewise C^S). This check doesn't depend on the algebra.
- **Confirmed against Tellurium** (done). `tools/tellurium_mca_check.py`
  loads the test models into libRoadRunner and writes its steady states,
  fluxes, scaled elasticities, C^J and C^S
  (`getScaledElasticityMatrix`, `getScaledFluxControlCoefficientMatrix`,
  `getScaledConcentrationControlCoefficientMatrix`), with row and column
  names, to `tests/m13/tellurium/mca_reference.json`.
  `tests/m13/antimony_tellurium.sci` compares `antimony.control` with them,
  matching rows and columns by name, since libRoadRunner orders species
  differently. Measured differences:
  - steady states and fluxes: 4e-15;
  - coefficients: 7e-14 for mass action, and 1.1e-7 on the branched model.

  The branched figure comes from libRoadRunner's larger difference step on
  Michaelis–Menten curvature: the perturbation check puts Axon within 1e-8
  there. The test's tolerance is 1e-6.

**A5. Response coefficients.** `response`, checked as R = C π and against
perturbing a parameter directly.

**A6. Plotting control coefficients.**
- `plot.bar3` takes lists of strings for `x` and `y`, as `plot.bar` takes
  categories: the bars go at 1, 2, … and the axes are labelled with the
  names.
  - Rho3DPlotter: per-axis tick labels at given positions (needs approval, D6).
  - `render_3d`: the same names on saved pictures.
  - `uFigureChart3D` loads them.
- A `clim = [lo, hi]` keyword for `bar3` (and `surface`) fixes the colour
  range. `clim = [-1, 1]` puts coolwarm's grey at 0. The component already
  has `ColorMin`/`ColorMax`.

**A7. Labelled tables.**
- `fmt.matrix(A; rows = names, cols = names)`: row names down the left,
  column names across the top, aligned with the entries.
- Useful for any matrix, and the natural way to print C^J and C^S.

**A8. Documentation and example.**
- A manual section, "Metabolic control analysis": what the coefficients
  mean, the formulas above, the theorems, what conserved moieties change,
  and a worked pathway.
- Reference rows for every function.
- A Welcome-tab example: a branched pathway with feedback, its flux and
  concentration control coefficients as two `bar3` subplots with
  `clim = [-1, 1]` and reaction names on the axes, and the summation theorem
  printed as a check.

Order: A1 → A2 → A3 → A4 meets the objective (control coefficients for any
network). A5–A8 make it pleasant to use. A6's component part can go ahead in
parallel once approved.

## Out of scope for now

- Antimony features beyond the current subset: rate rules, events,
  function definitions, units, and parameters defined by expressions
  (`k1 = 2*k2`). Compartments, species declarations and assignment rules were
  added afterwards (2026-11-13) for Millard et al.'s E. coli model
  (`UserExamples/ecoli.txt`), whose control coefficients agree with
  Tellurium's to about 1e-5 (`tests/m13/antimony_ecoli.sci`). Doing that
  exposed a bug in MIR v1.0.0's optimiser, which compiled two of its 68 rate
  laws wrongly; MIR is now pinned to a later commit.
- Second-order (non-linear) control coefficients.
- Time-dependent control coefficients along a simulation.
- Symbolic elasticities (D2).
- Stability analysis beyond what `reduced_jacobian`'s eigenvalues already
  give. `control` does not refuse an unstable steady state; the coefficients
  are still defined.
