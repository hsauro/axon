"""Reference values for Axon's metabolic control analysis, from Tellurium.

Run once, with Tellurium installed (pip install tellurium):

    python tools/tellurium_mca_check.py

It loads the models of tests/m13/antimony_control.sci into libRoadRunner,
finds each steady state, and writes the scaled elasticities, the scaled
flux and concentration control coefficients, and the scaled response
coefficients to every parameter and boundary species (getCC, one at a time;
null for a boundary species at 0), with their row and column names, to
tests/m13/tellurium/mca_reference.json. The Axon test
tests/m13/antimony_tellurium.sci then compares antimony.control with them.
Each model's Antimony text goes in the file too, so both sides use the same
model. It also prints the matrices, to read.

The E. coli model in tests/m13/tellurium/ecoli.ant (Millard et al.'s core
metabolism: 64 floating species, 68 reactions, three compartments and three
assignment rules; a copy of UserExamples/ecoli.txt) gets its own file,
tests/m13/tellurium/ecoli_reference.json: the steady state, fluxes, scaled
elasticities and scaled control coefficients, for tests/m13/antimony_ecoli.sci.
"""

import json
import os

import roadrunner
import tellurium as te

MODELS = {
    "two_step": """
        $X0 -> S1; k1*X0 - km1*S1
        S1 -> $X1; k2*S1
        X0 = 10; X1 = 0; k1 = 1; km1 = 0.5; k2 = 2
        S1 = 0
    """,
    "chain": """
        $X0 -> S1; k1*X0 - km1*S1
        S1 -> S2; k2*S1 - km2*S2
        S2 -> $X1; k3*S2
        X0 = 10; X1 = 0; k1 = 1; km1 = 1; k2 = 2; km2 = 1; k3 = 1
        S1 = 0; S2 = 0
    """,
    "cycle": """
        A -> B; k1*A
        B -> A; k2*B
        A = 10; B = 0; k1 = 1; k2 = 0.5
    """,
    "branched": """
        J0: $X0 -> S1; V0*X0/(K0 + X0)/(1 + S3/Ki)
        J1: S1 + ATP -> S2 + ADP; k1*S1*ATP
        J2: S2 -> S3; Vm2*S2/(Km2 + S2)
        J3: S3 -> $X1; k3*S3
        J4: S2 -> $X2; k4*S2
        J5: ADP -> ATP; k5*ADP
        X0 = 5; X1 = 0; X2 = 0; V0 = 10; K0 = 1; Ki = 2
        k1 = 1; Vm2 = 6; Km2 = 1; k3 = 2; k4 = 0.5; k5 = 3
        ATP = 3; ADP = 1; S1 = 0; S2 = 0; S3 = 0
    """,
}


def named(a):
    """A NamedArray as {rows, cols, values}."""
    return {
        "rows": [str(n) for n in a.rownames],
        "cols": [str(n) for n in a.colnames],
        "values": [[float(x) for x in row] for row in a],
    }


def response(r, rows, params):
    """Scaled response coefficients of the variables rows to params, by getCC."""
    values = []
    for v in rows:
        row = []
        for p in params:
            row.append(float(r.getCC(v, p)) if r.getValue(p) != 0 else None)
        values.append(row)
    return {"rows": list(rows), "cols": list(params), "values": values}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, "..", "tests", "m13", "tellurium", "mca_reference.json")
    out = {"tellurium": te.__version__, "roadrunner": roadrunner.__version__, "models": []}
    for name, source in MODELS.items():
        r = te.loada(source)
        r.conservedMoietyAnalysis = True
        r.steadyState()
        model = {
            "name": name,
            "source": source,
            "species": [str(s) for s in r.getFloatingSpeciesIds()],
            "y": [float(v) for v in r.getFloatingSpeciesConcentrations()],
            "reactions": [str(s) for s in r.getReactionIds()],
            "J": [float(v) for v in r.getReactionRates()],
            "elasticities": named(r.getScaledElasticityMatrix()),
            "flux_control": named(r.getScaledFluxControlCoefficientMatrix()),
            "concentration_control": named(r.getScaledConcentrationControlCoefficientMatrix()),
        }
        params = [str(p) for p in r.getGlobalParameterIds()] +             [str(b) for b in r.getBoundarySpeciesIds()]
        model["flux_response"] = response(r, model["reactions"], params)
        model["concentration_response"] = response(r, model["species"], params)
        out["models"].append(model)
        print("==", name)
        print("species", model["species"], model["y"])
        print("fluxes ", model["reactions"], model["J"])
        print("scaled elasticities\n", r.getScaledElasticityMatrix())
        print("scaled flux control\n", r.getScaledFluxControlCoefficientMatrix())
        print("scaled concentration control\n", r.getScaledConcentrationControlCoefficientMatrix())
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print("wrote", os.path.normpath(target))

    # The E. coli model: written compactly (the matrices are 68 x 68 and 64 x 68).
    folder = os.path.dirname(target)
    with open(os.path.join(folder, "ecoli.ant"), encoding="utf-8") as f:
        source = f.read()
    r = te.loada(source)
    r.conservedMoietyAnalysis = True
    r.steadyState()
    ecoli = {
        "tellurium": te.__version__, "roadrunner": roadrunner.__version__,
        "species": [str(s) for s in r.getFloatingSpeciesIds()],
        "y": [float(v) for v in r.getFloatingSpeciesConcentrations()],
        "reactions": [str(s) for s in r.getReactionIds()],
        "J": [float(v) for v in r.getReactionRates()],
        "elasticities": named(r.getScaledElasticityMatrix()),
        "flux_control": named(r.getScaledFluxControlCoefficientMatrix()),
        "concentration_control": named(r.getScaledConcentrationControlCoefficientMatrix()),
    }
    target = os.path.join(folder, "ecoli_reference.json")
    with open(target, "w", encoding="utf-8") as f:
        json.dump(ecoli, f)
    print("wrote", os.path.normpath(target))


if __name__ == "__main__":
    main()
