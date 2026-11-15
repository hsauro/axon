"""Reference values for Axon's Antimony events, from Tellurium.

Run once, with Tellurium installed (pip install tellurium):

    python tools/tellurium_events_check.py

It simulates each model below with libRoadRunner at evenly spaced times
(none of which is the moment of an event, where the species jump) and writes
the times, the species' names and their values, with each model's Antimony
text, to tests/m13/tellurium/events_reference.json. The Axon test
tests/m13/antimony_events_tellurium.sci simulates the same text with
antimony.simulate and compares the values.
"""

import json
import os

import tellurium as te

# name: (Antimony text, end time, number of times)
MODELS = {
    # A parameter changed at a given time.
    "time_switch": ("""
        J1: -> S1; k1
        J2: S1 -> ; k2*S1
        k1 = 1; k2 = 0.1; S1 = 0
        E1: at (time > 10): k1 = 5
    """, 29.0, 30),
    # A species reset whenever it passes a threshold: the event fires again
    # and again.
    "sawtooth": ("""
        J1: -> S1; k1
        J2: -> S2; k2*S1
        k1 = 1; k2 = 0.5; S1 = 0; S2 = 0
        E1: at (S1 > 2): S1 = 0
    """, 9.8, 29),
    # A pathway whose boundary species is raised for a while.
    "pulse": ("""
        J0: $X0 -> S1; k1*X0
        J1: S1 -> S2; Vm*S1/(Km + S1)
        J2: S2 -> ; k3*S2
        k1 = 1; Vm = 4; Km = 1; k3 = 0.5
        X0 = 1; S1 = 0; S2 = 0
        E1: at (time > 5): X0 = 3
        E2: at (time > 15): X0 = 1
    """, 24.5, 50),
    # A trigger of two conditions, and an assignment that uses the value
    # the species has when it fires.
    "both": ("""
        J1: -> S1; k1
        J2: S1 -> ; k2*S1
        k1 = 2; k2 = 0.1; S1 = 0
        E1: at (time > 1 && S1 > 2.5): S1 = S1 / 2
    """, 9.9, 34),
    # One event's assignment makes another's trigger true at the same time.
    "cascade": ("""
        J1: -> S1; k1
        J2: A -> ; ka*A
        J3: B -> ; kb*B
        k1 = 1; ka = 0.2; kb = 0.3; S1 = 0; A = 0; B = 0
        E1: at (time > 2): k1 = 0, A = 10
        E2: at (A > 5): B = S1
    """, 9.7, 30),
}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, 'tests', 'm13', 'tellurium', 'events_reference.json')
    models = []
    for name, (text, t_end, points) in MODELS.items():
        r = te.loada(text)
        result = r.simulate(0, t_end, points)
        columns = [c.strip('[]') for c in result.colnames]
        species = columns[1:]
        values = [[float(result[i, j]) for j in range(1, len(columns))]
                  for i in range(result.shape[0])]
        models.append({
            'name': name,
            'text': text,
            't_end': t_end,
            'points': points,
            'species': species,
            'values': values,
        })
        print(name, species)
        print(result[-1])
    with open(out, 'w') as f:
        json.dump({'models': models}, f, indent=1)
    print('wrote', out)


if __name__ == '__main__':
    main()
