#!/usr/bin/env python3
"""Table-free test of 'one Grundstellung per net-day' (run from HELUT repo root).
Two messages whose indicators share a bigram at the same position decode (under ANY fixed Tauschtafel)
to the same letter pair. If message keys = Verfahrenkenngruppe enciphered at one daily Grundstellung,
a shared V-carrying position forces a shared message-key letter. Mismatches falsify the model."""
import json, itertools
C = json.load(open('Fixtures/u534_corpus.json'))['messages']
for net in ('438', '568'):
    U, seen = [], set()
    for r in C:
        if r.get('broken') and r.get('indicators') and r['wheels'] == net:
            k = (tuple(r['indicators']), r['wheel_positions'])
            if k not in seen: seen.add(k); U.append(r)
    for a, b in itertools.combinations(U, 2):
        (a1, a2), (b1, b2) = a['indicators'], b['indicators']
        h = [(i, x) for i, (x, y) in enumerate(zip([a1[:2], a1[2:], a2[:2], a2[2:]], [b1[:2], b1[2:], b2[:2], b2[2:]])) if x == y]
        v = [(i, a1[i] + a2[i]) for i in range(4) if a1[i] == b1[i] and a2[i] == b2[i]]
        if h or v:
            same = [w for t, w in enumerate('GLMR') if a['wheel_positions'][t] == b['wheel_positions'][t]]
            print(net, a['id'], b['id'], 'horiz', h, 'vert', v, 'MK', a['wheel_positions'], b['wheel_positions'], 'equal on', same or 'none')
