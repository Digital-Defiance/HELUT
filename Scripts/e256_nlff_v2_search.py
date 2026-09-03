#!/usr/bin/env python3
"""Deterministic native-NLFF search for the E256-v2/gen0 research profile.

The search evolves reversible seven-wire XOR/Toffoli networks. A coordinate of
a reversible network is balanced by construction. Each rotor step XORs two
independently evolved coordinates over disjoint eight-bit groups:

    step = pivot_a XOR q_a(seven taps) XOR pivot_b XOR q_b(seven taps)

All 64 LFSR bits are used exactly once across the four 16-input folds. This is
bounded research grading, not a security proof, and may emit
NO_ACCEPTABLE_CANDIDATE.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

MASK64 = (1 << 64) - 1
TRUTH_MASK = (1 << 128) - 1
FEEDBACK_MASK = 0xD800000000000000
TRAIN_SEEDS = (
    0x0123456789ABCDEF,
    0xC0FFEE123456789A,
    0xA5A55A5AF00DCAFE,
    0x6D2B79F5B16B00B5,
)
HOLDOUT_SEEDS = (
    0x9E3779B97F4A7C15,
    0xD1B54A32D192ED03,
    0x94D049BB133111EB,
    0xF1357AEA2E62A9C5,
)
LAGS = (1, 2, 3, 4, 8, 16, 32, 64)

# Gate tuple: kind, target, control_a, control_b, control_c.
# kind=1: target ^= a; kind=2: target ^= a&b; kind=3: target ^= a&b&c.
Gate = Tuple[int, int, int, int, int]
Network = Tuple[Tuple[Gate, ...], int]


class SplitMix64:
    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        value = self.state
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & MASK64
        return (value ^ (value >> 31)) & MASK64

    def below(self, upper: int) -> int:
        if upper <= 0:
            raise ValueError("upper must be positive")
        limit = (1 << 64) - ((1 << 64) % upper)
        while True:
            value = self.next()
            if value < limit:
                return value % upper


def popcount(value: int) -> int:
    return bin(value).count("1")


def shuffled(values: Iterable[int], rng: SplitMix64) -> List[int]:
    result = list(values)
    for index in range(len(result) - 1, 0, -1):
        other = rng.below(index + 1)
        result[index], result[other] = result[other], result[index]
    return result


def input_truths() -> List[int]:
    wires = [0] * 7
    for assignment in range(128):
        for bit in range(7):
            if (assignment >> bit) & 1:
                wires[bit] |= 1 << assignment
    return wires


BASE_TRUTHS = input_truths()


def random_gate(rng: SplitMix64) -> Gate:
    roll = rng.below(100)
    kind = 1 if roll < 18 else (2 if roll < 72 else 3)
    count = kind + 1
    wires = shuffled(range(7), rng)[:count]
    target = wires[0]
    controls = wires[1:] + [0, 0, 0]
    return (kind, target, controls[0], controls[1], controls[2])


def random_network(rng: SplitMix64, gate_count: int) -> Network:
    return (tuple(random_gate(rng) for _ in range(gate_count)), rng.below(7))


def evaluate_network(network: Network) -> int:
    gates, output = network
    wires = BASE_TRUTHS[:]
    for kind, target, a, b, c in gates:
        term = wires[a]
        if kind >= 2:
            term &= wires[b]
        if kind >= 3:
            term &= wires[c]
        wires[target] = (wires[target] ^ term) & TRUTH_MASK
    return wires[output]


def truth_bits(truth: int, width: int) -> List[int]:
    return [(truth >> index) & 1 for index in range(width)]


def walsh_metrics(bits: Sequence[int]) -> Tuple[int, int]:
    spectrum = [1 if bit == 0 else -1 for bit in bits]
    width = 1
    while width < len(spectrum):
        for base in range(0, len(spectrum), width * 2):
            for index in range(base, base + width):
                left = spectrum[index]
                right = spectrum[index + width]
                spectrum[index] = left + right
                spectrum[index + width] = left - right
        width *= 2
    maximum = max(abs(value) for value in spectrum[1:])
    return maximum, len(bits) // 2 - maximum // 2


def algebraic_degree(bits: Sequence[int], variables: int) -> int:
    anf = list(bits)
    for variable in range(variables):
        selector = 1 << variable
        for mask in range(len(anf)):
            if mask & selector:
                anf[mask] ^= anf[mask ^ selector]
    return max(popcount(mask) for mask, coefficient in enumerate(anf) if coefficient)


def dependency_count(bits: Sequence[int], variables: int) -> int:
    dependencies = 0
    for variable in range(variables):
        delta = 1 << variable
        if any(bits[value] != bits[value ^ delta] for value in range(len(bits))):
            dependencies += 1
    return dependencies


def max_absolute_autocorrelation(bits: Sequence[int]) -> int:
    maximum = 0
    for delta in range(1, len(bits)):
        value = sum(1 if bits[x] == bits[x ^ delta] else -1 for x in range(len(bits)))
        maximum = max(maximum, abs(value))
    return maximum


@dataclass(frozen=True)
class ComponentGrade:
    ones: int
    max_abs_nonconstant_walsh: int
    max_normalized_linear_correlation: float
    nonlinearity: int
    algebraic_degree: int
    dependent_inputs: int
    max_abs_autocorrelation: int

    @property
    def accepted(self) -> bool:
        return (
            self.ones == 64
            and self.max_abs_nonconstant_walsh <= 24
            and self.nonlinearity >= 52
            and self.algebraic_degree >= 4
            and self.dependent_inputs == 7
            and self.max_abs_autocorrelation <= 64
        )


def component_grade(truth: int, include_autocorrelation: bool = True) -> ComponentGrade:
    bits = truth_bits(truth, 128)
    maximum, nonlinearity = walsh_metrics(bits)
    return ComponentGrade(
        ones=sum(bits),
        max_abs_nonconstant_walsh=maximum,
        max_normalized_linear_correlation=maximum / 128.0,
        nonlinearity=nonlinearity,
        algebraic_degree=algebraic_degree(bits, 7),
        dependent_inputs=dependency_count(bits, 7),
        max_abs_autocorrelation=max_absolute_autocorrelation(bits) if include_autocorrelation else 128,
    )


def network_fitness(network: Network, cache: Dict[Network, Tuple[int, int, int, int]]) -> Tuple[int, int, int, int]:
    cached = cache.get(network)
    if cached is not None:
        return cached
    truth = evaluate_network(network)
    bits = truth_bits(truth, 128)
    maximum, nonlinearity = walsh_metrics(bits)
    fitness = (
        dependency_count(bits, 7),
        nonlinearity,
        algebraic_degree(bits, 7),
        -maximum,
    )
    cache[network] = fitness
    return fitness


def mutate_network(parent: Network, rng: SplitMix64) -> Network:
    gates, output = parent
    child = list(gates)
    edits = 1 + rng.below(3)
    for _ in range(edits):
        action = rng.below(10)
        if action < 8:
            child[rng.below(len(child))] = random_gate(rng)
        else:
            left = rng.below(len(child))
            right = rng.below(len(child))
            child[left], child[right] = child[right], child[left]
    if rng.below(8) == 0:
        output = rng.below(7)
    return (tuple(child), output)


def crossover(left: Network, right: Network, rng: SplitMix64) -> Network:
    left_gates, left_output = left
    right_gates, right_output = right
    cut = 1 + rng.below(len(left_gates) - 1)
    output = left_output if rng.below(2) == 0 else right_output
    return (tuple(left_gates[:cut] + right_gates[cut:]), output)


def evolve_component(
    seed: int,
    gate_count: int,
    population_size: int,
    generations: int,
) -> Tuple[Network, ComponentGrade, int]:
    rng = SplitMix64(seed)
    population = [random_network(rng, gate_count) for _ in range(population_size)]
    cache: Dict[Network, Tuple[int, int, int, int]] = {}
    best_network = population[0]
    best_generation = 0
    for generation in range(generations):
        population.sort(key=lambda item: network_fitness(item, cache), reverse=True)
        if network_fitness(population[0], cache) > network_fitness(best_network, cache):
            best_network = population[0]
            best_generation = generation
        grade = component_grade(evaluate_network(population[0]))
        if grade.accepted:
            return population[0], grade, generation
        elite_count = max(8, population_size // 8)
        elites = population[:elite_count]
        next_population = elites[:]
        while len(next_population) < population_size:
            if rng.below(4) == 0:
                parent_a = elites[rng.below(len(elites))]
                parent_b = elites[rng.below(len(elites))]
                child = crossover(parent_a, parent_b, rng)
            else:
                child = elites[rng.below(len(elites))]
            next_population.append(mutate_network(child, rng))
        population = next_population
    grade = component_grade(evaluate_network(best_network))
    return best_network, grade, best_generation


def lfsr_next(state: int) -> int:
    return (state >> 1) ^ (FEEDBACK_MASK if state & 1 else 0)


def trajectory(seed: int, steps: int) -> List[int]:
    if seed == 0:
        raise ValueError("zero seed is forbidden")
    states = []
    state = seed
    for _ in range(steps):
        states.append(state)
        state = lfsr_next(state)
    return states


def component_table(network: Network) -> List[int]:
    return truth_bits(evaluate_network(network), 128)


def candidate_taps(rng: SplitMix64) -> List[List[int]]:
    pool = shuffled(range(64), rng)
    return [pool[index * 16:(index + 1) * 16] for index in range(4)]


def outputs_for_states(
    states: Sequence[int],
    taps: Sequence[Sequence[int]],
    component_tables: Sequence[Sequence[int]],
) -> List[List[int]]:
    outputs = [[], [], [], []]
    for state in states:
        for fold in range(4):
            fold_taps = taps[fold]
            left_index = 0
            right_index = 0
            for local_bit, tap in enumerate(fold_taps[1:8]):
                left_index |= ((state >> tap) & 1) << local_bit
            for local_bit, tap in enumerate(fold_taps[9:16]):
                right_index |= ((state >> tap) & 1) << local_bit
            value = (
                ((state >> fold_taps[0]) & 1)
                ^ component_tables[fold * 2][left_index]
                ^ ((state >> fold_taps[8]) & 1)
                ^ component_tables[fold * 2 + 1][right_index]
            )
            outputs[fold].append(value)
    return outputs


def phi(left: Sequence[int], right: Sequence[int]) -> float:
    count = len(left)
    ones_left = sum(left)
    ones_right = sum(right)
    both = sum(a & b for a, b in zip(left, right))
    p_left = ones_left / float(count)
    p_right = ones_right / float(count)
    denominator = (p_left * (1.0 - p_left) * p_right * (1.0 - p_right)) ** 0.5
    return 0.0 if denominator == 0.0 else (both / count - p_left * p_right) / denominator


def berlekamp_massey(bits: Sequence[int]) -> int:
    count = len(bits)
    connection = [0] * count
    previous = [0] * count
    connection[0] = previous[0] = 1
    complexity = 0
    offset = -1
    for index in range(count):
        discrepancy = bits[index]
        for tap in range(1, complexity + 1):
            discrepancy ^= connection[tap] & bits[index - tap]
        if discrepancy == 0:
            continue
        saved = connection[:]
        shift = index - offset
        for tap in range(shift, count):
            connection[tap] ^= previous[tap - shift]
        if 2 * complexity <= index:
            complexity = index + 1 - complexity
            offset = index
            previous = saved
    return complexity


@dataclass(frozen=True)
class SequenceGrade:
    max_rate_deviation: float
    max_pair_phi: float
    max_autocorrelation: float
    max_state_bit_phi: float
    min_bm_complexity: int

    @property
    def accepted(self) -> bool:
        return (
            self.max_rate_deviation <= 0.015
            and self.max_pair_phi <= 0.03
            and self.max_autocorrelation <= 0.035
            and self.max_state_bit_phi <= 0.04
            and self.min_bm_complexity >= 900
        )


def cheap_sequence_grade(
    trajectories: Sequence[Sequence[int]],
    taps: Sequence[Sequence[int]],
    tables: Sequence[Sequence[int]],
) -> Tuple[float, float, float]:
    max_rate = 0.0
    max_pair = 0.0
    max_autocorrelation = 0.0
    for states in trajectories:
        outputs = outputs_for_states(states, taps, tables)
        for bits in outputs:
            max_rate = max(max_rate, abs(sum(bits) / float(len(bits)) - 0.5))
            for lag in LAGS:
                correlation = sum(
                    1 if bits[index] == bits[index - lag] else -1
                    for index in range(lag, len(bits))
                ) / float(len(bits) - lag)
                max_autocorrelation = max(max_autocorrelation, abs(correlation))
        for left in range(4):
            for right in range(left + 1, 4):
                max_pair = max(max_pair, abs(phi(outputs[left], outputs[right])))
    return max_rate, max_pair, max_autocorrelation


def full_sequence_grade(
    trajectories: Sequence[Sequence[int]],
    taps: Sequence[Sequence[int]],
    tables: Sequence[Sequence[int]],
    bm_bits: int,
) -> SequenceGrade:
    rate, pair, autocorrelation = cheap_sequence_grade(trajectories, taps, tables)
    max_state_phi = 0.0
    min_bm = bm_bits
    for states in trajectories:
        outputs = outputs_for_states(states, taps, tables)
        state_columns = [
            [int((state >> state_bit) & 1) for state in states]
            for state_bit in range(64)
        ]
        for bits in outputs:
            min_bm = min(min_bm, berlekamp_massey(bits[:bm_bits]))
            for state_bits in state_columns:
                max_state_phi = max(max_state_phi, abs(phi(bits, state_bits)))
    return SequenceGrade(rate, pair, autocorrelation, max_state_phi, min_bm)


def combined_formula_grade(left: ComponentGrade, right: ComponentGrade) -> Dict[str, object]:
    maximum = left.max_abs_nonconstant_walsh * right.max_abs_nonconstant_walsh
    size = 1 << 16
    return {
        "inputs": 16,
        "ones": size // 2,
        "first_order_correlation_immune": True,
        "max_abs_nonconstant_walsh_bound": maximum,
        "max_normalized_linear_correlation_bound": maximum / float(size),
        "algebraic_degree": max(left.algebraic_degree, right.algebraic_degree),
        "accepted": maximum / float(size) <= 0.035,
    }


def gate_json(gate: Gate) -> Dict[str, object]:
    kind, target, a, b, c = gate
    controls = [a] if kind == 1 else ([a, b] if kind == 2 else [a, b, c])
    return {
        "op": "xor" if kind == 1 else ("and2_xor" if kind == 2 else "and3_xor"),
        "target": target,
        "controls": controls,
    }


def network_json(network: Network, grade: ComponentGrade, seed: int, generation: int) -> Dict[str, object]:
    gates, output = network
    return {
        "search_seed_hex": "0x%016x" % seed,
        "accepted_generation": generation,
        "output": output,
        "gates": [gate_json(gate) for gate in gates],
        "truth_hex": "%032x" % evaluate_network(network),
        "grade": {**asdict(grade), "accepted": grade.accepted},
    }


def positive_control() -> Dict[str, object]:
    weak: Network = (tuple(), 0)
    grade = component_grade(evaluate_network(weak))
    detected = not grade.accepted and grade.dependent_inputs == 1 and grade.nonlinearity == 0
    return {
        "name": "raw_state_bit",
        "detected": detected,
        "grade": {**asdict(grade), "accepted": grade.accepted},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--component-gates", type=int, default=24)
    parser.add_argument("--component-population", type=int, default=128)
    parser.add_argument("--component-generations", type=int, default=160)
    parser.add_argument("--tap-trials", type=int, default=512)
    parser.add_argument("--steps", type=int, default=16384)
    parser.add_argument("--bm-bits", type=int, default=2048)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0xE256000200000000)
    parser.add_argument("--out", default="logs/e256-v2-gen0-nlff-search.json")
    args = parser.parse_args()
    if (
        args.component_gates < 8
        or args.component_population < 16
        or args.component_generations < 1
        or args.tap_trials < 1
        or args.steps < 8192
        or args.bm_bits < 1024
        or args.bm_bits > args.steps
    ):
        parser.error("invalid search budget")

    control = positive_control()
    if not control["detected"]:
        raise RuntimeError("positive control was not rejected")

    networks: List[Network] = []
    component_grades: List[ComponentGrade] = []
    component_generations: List[int] = []
    component_seeds: List[int] = []
    seen_truths = set()
    for component in range(8):
        attempt = 0
        while True:
            seed = (args.seed + component * 0x9E3779B97F4A7C15 + attempt * 0xD1B54A32D192ED03) & MASK64
            network, grade, accepted_generation = evolve_component(
                seed,
                args.component_gates,
                args.component_population,
                args.component_generations,
            )
            truth = evaluate_network(network)
            if grade.accepted and truth not in seen_truths:
                networks.append(network)
                component_grades.append(grade)
                component_generations.append(accepted_generation)
                component_seeds.append(seed)
                seen_truths.add(truth)
                break
            attempt += 1
            if attempt >= 8:
                manifest = {
                    "schema": "E256-NATIVE-NLFF-SEARCH-1",
                    "family": "E256",
                    "suite_version": 2,
                    "generation": 0,
                    "status": "NO_ACCEPTABLE_CANDIDATE",
                    "reason": "component search did not produce eight distinct passing networks",
                    "positive_control": control,
                    "failed_component": component,
                    "last_grade": {**asdict(grade), "accepted": grade.accepted},
                }
                output = Path(args.out)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                print(manifest["status"])
                print(manifest["reason"])
                print("receipt:", output)
                return 2

    tables = [component_table(network) for network in networks]
    formula_grades = [
        combined_formula_grade(component_grades[index * 2], component_grades[index * 2 + 1])
        for index in range(4)
    ]
    if not all(bool(grade["accepted"]) for grade in formula_grades):
        raise RuntimeError("combined formula gate failed after accepted components")

    train_trajectories = [trajectory(seed, args.steps) for seed in TRAIN_SEEDS]
    holdout_trajectories = [trajectory(seed, args.steps) for seed in HOLDOUT_SEEDS]
    tap_rng = SplitMix64(args.seed ^ 0x5441505345415243)
    best_taps: Optional[List[List[int]]] = None
    best_score = float("inf")
    for _ in range(args.tap_trials):
        taps = candidate_taps(tap_rng)
        rate, pair, autocorrelation = cheap_sequence_grade(train_trajectories, taps, tables)
        score = rate * 4.0 + pair * 2.0 + autocorrelation * 2.0
        if score < best_score:
            best_score = score
            best_taps = taps
    assert best_taps is not None

    train = full_sequence_grade(train_trajectories, best_taps, tables, args.bm_bits)
    holdout = full_sequence_grade(holdout_trajectories, best_taps, tables, args.bm_bits)
    accepted = train.accepted and holdout.accepted
    manifest = {
        "schema": "E256-NATIVE-NLFF-SEARCH-1",
        "family": "E256",
        "suite_version": 2,
        "generation": 0,
        "status": "ACCEPTED_RESEARCH_PROFILE" if accepted else "NO_ACCEPTABLE_CANDIDATE",
        "security_scope": "bounded deterministic native-NLFF grading; not a security proof",
        "transition": "(state >> 1) xor (lsb ? 0xD800000000000000 : 0)",
        "formula": "dual_balanced_reversible_nlff16",
        "search_seed_hex": "0x%016x" % args.seed,
        "component_gate_count": args.component_gates,
        "component_population": args.component_population,
        "component_generations": args.component_generations,
        "tap_trials": args.tap_trials,
        "steps_per_seed": args.steps,
        "bm_bits": args.bm_bits,
        "train_seeds_hex": ["0x%016x" % seed for seed in TRAIN_SEEDS],
        "holdout_seeds_hex": ["0x%016x" % seed for seed in HOLDOUT_SEEDS],
        "positive_control": control,
        "components": [
            network_json(network, grade, seed, generation)
            for network, grade, seed, generation in zip(
                networks, component_grades, component_seeds, component_generations
            )
        ],
        "folds": [
            {
                "taps": taps,
                "left_component": index * 2,
                "right_component": index * 2 + 1,
            }
            for index, taps in enumerate(best_taps)
        ],
        "combined_formula_grades": formula_grades,
        "train": {**asdict(train), "accepted": train.accepted},
        "holdout": {**asdict(holdout), "accepted": holdout.accepted},
        "thresholds": {
            "component_max_abs_walsh": 24,
            "component_min_nonlinearity": 52,
            "component_min_degree": 4,
            "combined_max_normalized_linear_correlation_bound": 0.035,
            "max_rate_deviation": 0.015,
            "max_pair_phi": 0.03,
            "max_autocorrelation": 0.035,
            "max_state_bit_phi": 0.04,
            "min_bm_complexity": 900,
        },
    }
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(manifest["status"])
    print("component nonlinearities:", [grade.nonlinearity for grade in component_grades])
    print("component degrees:", [grade.algebraic_degree for grade in component_grades])
    print("fold taps:", best_taps)
    print("train:", manifest["train"])
    print("holdout:", manifest["holdout"])
    print("receipt:", output)
    return 0 if accepted else 2


if __name__ == "__main__":
    raise SystemExit(main())
