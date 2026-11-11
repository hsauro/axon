"""Test models with conservation laws, from two species to random networks.

Every rate function takes (y, p) and uses only analytic numpy operations, so
the complex-step Jacobian in augss is exact to rounding."""

import itertools
import numpy as np
from augss import Model


def two_state():
    """A <-> B: one conservation law, A + B."""
    N = [[-1, 1],
         [1, -1]]

    def rates(y, p):
        A, B = y
        return np.array([p["k1"] * A, p["k2"] * B])

    return Model("two_state", ["A", "B"], N, rates, [10.0, 0.0],
                 {"k1": 1.0, "k2": 0.5})


def enzyme_feed():
    """Substrate fed in, bound by an enzyme, turned into product, which
    leaves: E + ES is conserved. The model in the Axon manual."""
    #      J0  J1  J2  J3  J4
    N = [[1, -1, 1, 0, 0],    # S
         [0, -1, 1, 1, 0],    # E
         [0, 1, -1, -1, 0],   # ES
         [0, 0, 0, 1, -1]]    # P

    def rates(y, p):
        S, E, ES, P = y
        return np.array([p["vin"] + 0 * S, p["k1"] * E * S, p["km1"] * ES,
                         p["k2"] * ES, p["kout"] * P])

    return Model("enzyme_feed", ["S", "E", "ES", "P"], N, rates, [0.0, 1.0, 0.0, 0.0],
                 {"vin": 1.0, "k1": 2.0, "km1": 1.0, "k2": 4.0, "kout": 0.5})


def two_cycles():
    """A <-> B and C <-> D: two conservation laws."""
    N = [[-1, 1, 0, 0],
         [1, -1, 0, 0],
         [0, 0, -1, 1],
         [0, 0, 1, -1]]

    def rates(y, p):
        A, B, C, D = y
        return np.array([p["k1"] * A, p["k2"] * B, p["k3"] * C, p["k4"] * D])

    return Model("two_cycles", ["A", "B", "C", "D"], N, rates, [10.0, 0.0, 4.0, 0.0],
                 {"k1": 1.0, "k2": 0.5, "k3": 2.0, "k4": 2.0})


def gk_cycle(K=0.01):
    """A Goldbeter-Koshland covalent modification cycle, W <-> Wp, with
    Michaelis-Menten kinase and phosphatase. With small K (zero-order
    ultrasensitivity) the steady state switches steeply with the enzymes'
    ratio, a hard case for Newton's method."""
    N = [[-1, 1],
         [1, -1]]

    def rates(y, p):
        W, Wp = y
        return np.array([p["k1"] * p["E1"] * W / (p["K1"] + W),
                         p["k2"] * p["E2"] * Wp / (p["K2"] + Wp)])

    return Model("gk_cycle", ["W", "Wp"], N, rates, [1.0, 0.0],
                 {"k1": 1.0, "E1": 1.05, "K1": K, "k2": 1.0, "E2": 1.0, "K2": K})


def bistable_cycle():
    """A covalent modification cycle whose kinase is activated by the
    modified form: three steady states (two stable) for W + Wp = 1, at
    Wp ~ 0.0025, 0.4705 and 0.9271."""
    N = [[-1, 1],
         [1, -1]]

    def rates(y, p):
        W, Wp = y
        act = p["k1"] + p["kf"] * Wp ** 2 / (p["Kf"] ** 2 + Wp ** 2)
        return np.array([act * W / (p["K1"] + W), p["k2"] * Wp / (p["K2"] + Wp)])

    return Model("bistable_cycle", ["W", "Wp"], N, rates, [1.0, 0.0],
                 {"k1": 0.05, "kf": 2.0, "Kf": 0.5, "K1": 0.05, "k2": 1.0, "K2": 0.05})


def glycolysis():
    """A toy glycolysis with two conserved moieties, ATP + ADP and
    NAD + NADH, feedback inhibition of the second kinase step by ATP, and an
    ATP-consuming load."""
    species = ["Glc", "G6P", "F16BP", "GAP", "Pyr", "ATP", "ADP", "NAD", "NADH"]
    #        J0  J1  J2  J3  J4  J5  J6
    N = [[1, -1, 0, 0, 0, 0, 0],      # Glc
         [0, 1, -1, 0, 0, 0, 0],      # G6P
         [0, 0, 1, -1, 0, 0, 0],      # F16BP
         [0, 0, 0, 2, -1, 0, 0],      # GAP
         [0, 0, 0, 0, 1, -1, 0],      # Pyr
         [0, -1, -1, 0, 2, 0, -1],    # ATP
         [0, 1, 1, 0, -2, 0, 1],      # ADP
         [0, 0, 0, 0, -1, 1, 0],      # NAD
         [0, 0, 0, 0, 1, -1, 0]]      # NADH

    def rates(y, p):
        Glc, G6P, F16BP, GAP, Pyr, ATP, ADP, NAD, NADH = y
        return np.array([
            p["v0"] + 0 * Glc,
            p["k1"] * Glc * ATP,
            p["k2"] * G6P * ATP / (1 + (ATP / p["Ki"]) ** 4),
            p["k3"] * F16BP,
            p["k4"] * GAP * NAD * ADP,
            p["k5"] * Pyr * NADH,
            p["k6"] * ATP])

    y0 = [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.5, 1.0, 0.2]
    p = {"v0": 1.0, "k1": 2.0, "k2": 5.0, "Ki": 1.5, "k3": 3.0, "k4": 4.0, "k5": 5.0,
         "k6": 1.0}
    return Model("glycolysis", species, N, rates, y0, p)


def random_closed(m=8, pairs=8, seed=0):
    """A random reversible mass-action network that conserves a 'mass': each
    species gets a mass 1, 2 or 3, and every reaction is A <-> B (equal
    masses) or A + B <-> C (masses adding up), so the total mass is
    conserved, often with more laws besides. Weakly reversible, so every
    conservation class has a positive steady state."""
    rng = np.random.default_rng(seed)
    mass = rng.integers(1, 4, size=m)
    cands = []
    for a, b in itertools.combinations(range(m), 2):
        if mass[a] == mass[b]:
            cands.append(((a,), (b,)))
    for a, b in itertools.combinations_with_replacement(range(m), 2):
        for cc in range(m):
            if cc not in (a, b) and mass[cc] == mass[a] + mass[b]:
                cands.append(((a, b), (cc,)))
    idx = rng.choice(len(cands), size=min(pairs, len(cands)), replace=False)
    chosen = [cands[i] for i in idx]
    n = 2 * len(chosen)
    N = np.zeros((m, n))
    reactants = []
    for j, (lhs, rhs) in enumerate(chosen):
        for s in lhs:
            N[s, 2 * j] -= 1
            N[s, 2 * j + 1] += 1
        for s in rhs:
            N[s, 2 * j] += 1
            N[s, 2 * j + 1] -= 1
        reactants += [lhs, rhs]
    k = rng.uniform(0.1, 10.0, size=n)

    def rates(y, p):
        return np.array([p["k"][j] * np.prod([y[s] for s in reactants[j]])
                         for j in range(n)])

    y0 = rng.uniform(0.1, 5.0, size=m)
    return Model(f"random_closed(m={m}, pairs={pairs}, seed={seed})",
                 [f"X{i + 1}" for i in range(m)], N, rates, y0, {"k": k})


ALL = [two_state, enzyme_feed, two_cycles, gk_cycle, bistable_cycle, glycolysis]
