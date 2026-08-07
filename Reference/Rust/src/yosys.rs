//! Generic clear evaluator for the Yosys JSON subset used by HELUT.
//!
//! The supported executable cells intentionally match the Swift oracle:
//! exact `$lut` cells plus gate-level `$_...DFF..._` forms. Unsupported cells
//! are parsed but ignored, and each `tick` is one host clock edge.

use crate::{ReferenceError, Result, deserialize_unique_btree_map, read_json};
use serde::Deserialize;
use serde::de::{self, Visitor};
use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum YosysBit {
    Net(i64),
    Constant(u8),
}

impl<'de> Deserialize<'de> for YosysBit {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct BitVisitor;

        impl Visitor<'_> for BitVisitor {
            type Value = YosysBit;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a Yosys net integer or constant string")
            }

            fn visit_i64<E>(self, value: i64) -> std::result::Result<Self::Value, E>
            where
                E: de::Error,
            {
                Ok(YosysBit::Net(value))
            }

            fn visit_u64<E>(self, value: u64) -> std::result::Result<Self::Value, E>
            where
                E: de::Error,
            {
                let value = i64::try_from(value)
                    .map_err(|_| E::custom("Yosys net ID exceeds signed 64-bit range"))?;
                Ok(YosysBit::Net(value))
            }

            fn visit_str<E>(self, value: &str) -> std::result::Result<Self::Value, E>
            where
                E: de::Error,
            {
                match value {
                    "0" => Ok(YosysBit::Constant(0)),
                    "1" => Ok(YosysBit::Constant(1)),
                    "x" | "X" | "z" | "Z" => Ok(YosysBit::Constant(0)),
                    _ => Err(E::custom(format!("unsupported Yosys bit value {value:?}"))),
                }
            }
        }

        deserializer.deserialize_any(BitVisitor)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysNetlist {
    pub creator: Option<String>,
    #[serde(deserialize_with = "deserialize_unique_btree_map")]
    pub modules: BTreeMap<String, YosysModule>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysModule {
    #[serde(deserialize_with = "deserialize_unique_btree_map")]
    pub ports: BTreeMap<String, YosysPort>,
    #[serde(deserialize_with = "deserialize_unique_btree_map")]
    pub cells: BTreeMap<String, YosysCell>,
    #[serde(default, deserialize_with = "deserialize_optional_unique_map")]
    pub netnames: Option<BTreeMap<String, YosysNetname>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysPort {
    pub direction: String,
    pub bits: Vec<YosysBit>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysCell {
    #[serde(rename = "type")]
    pub cell_type: String,
    pub parameters: YosysCellParameters,
    #[serde(deserialize_with = "deserialize_unique_btree_map")]
    pub connections: BTreeMap<String, Vec<YosysBit>>,
    #[serde(default, rename = "port_directions")]
    pub port_directions: Option<BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysCellParameters {
    #[serde(rename = "LUT")]
    pub lut: Option<String>,
    #[serde(rename = "WIDTH")]
    pub width: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct YosysNetname {
    pub bits: Vec<YosysBit>,
}

fn deserialize_optional_unique_map<'de, D>(
    deserializer: D,
) -> std::result::Result<Option<BTreeMap<String, YosysNetname>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct OptionalMapVisitor;

    impl<'de> Visitor<'de> for OptionalMapVisitor {
        type Value = Option<BTreeMap<String, YosysNetname>>;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("null or a Yosys netname object with unique keys")
        }

        fn visit_none<E>(self) -> std::result::Result<Self::Value, E>
        where
            E: de::Error,
        {
            Ok(None)
        }

        fn visit_unit<E>(self) -> std::result::Result<Self::Value, E>
        where
            E: de::Error,
        {
            Ok(None)
        }

        fn visit_some<D>(self, deserializer: D) -> std::result::Result<Self::Value, D::Error>
        where
            D: serde::Deserializer<'de>,
        {
            deserialize_unique_btree_map(deserializer).map(Some)
        }

        fn visit_map<A>(self, mut access: A) -> std::result::Result<Self::Value, A::Error>
        where
            A: de::MapAccess<'de>,
        {
            let mut values = BTreeMap::new();
            while let Some((key, value)) = access.next_entry::<String, YosysNetname>()? {
                if values.insert(key, value).is_some() {
                    return Err(de::Error::custom("duplicate Yosys netname"));
                }
            }
            Ok(Some(values))
        }
    }

    deserializer.deserialize_option(OptionalMapVisitor)
}

pub fn load_netlist(path: &Path) -> Result<YosysNetlist> {
    read_json(path)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LutCell {
    pub name: String,
    pub a_bits: Vec<YosysBit>,
    pub y_wire: i64,
    pub init_msb_first: String,
    pub table: Vec<u8>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DffPolarity {
    pub enable_active_high: Option<bool>,
    pub sync_reset: Option<(bool, u8)>,
    pub clock_enable_gates_reset: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DffCell {
    pub name: String,
    pub cell_type: String,
    pub q_wire: i64,
    pub d_bit: YosysBit,
    pub reset_bit: Option<YosysBit>,
    pub enable_bit: Option<YosysBit>,
    pub polarity: DffPolarity,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LutEvaluation {
    pub name: String,
    pub input_values: Vec<u8>,
    pub address: usize,
    pub output: u8,
}

pub struct CleartextNetlistSimulator {
    pub module_name: String,
    pub input_ports: BTreeMap<String, Vec<YosysBit>>,
    pub output_ports: BTreeMap<String, Vec<YosysBit>>,
    pub luts: Vec<LutCell>,
    pub dffs: Vec<DffCell>,
    state: BTreeMap<i64, u8>,
    pub last_wires: BTreeMap<i64, u8>,
    pub last_lut_evaluations: BTreeMap<String, LutEvaluation>,
    trace_luts: bool,
}

impl CleartextNetlistSimulator {
    pub fn new(
        module_name: impl Into<String>,
        module: &YosysModule,
        trace_luts: bool,
    ) -> Result<Self> {
        let module_name = module_name.into();
        let input_ports = module
            .ports
            .iter()
            .filter(|(_, port)| port.direction == "input")
            .map(|(name, port)| (name.clone(), port.bits.clone()))
            .collect();
        let output_ports = module
            .ports
            .iter()
            .filter(|(_, port)| port.direction == "output")
            .map(|(name, port)| (name.clone(), port.bits.clone()))
            .collect();

        let mut luts = Vec::new();
        let mut dffs = Vec::new();
        for (cell_name, cell) in &module.cells {
            if cell.cell_type == "$lut" {
                let a_bits = cell.connections.get("A").ok_or_else(|| {
                    ReferenceError::new(format!("malformed $lut {cell_name}: missing A"))
                })?;
                let y_bit = cell
                    .connections
                    .get("Y")
                    .and_then(|bits| bits.first())
                    .ok_or_else(|| {
                        ReferenceError::new(format!("malformed $lut {cell_name}: missing Y"))
                    })?;
                let YosysBit::Net(y_wire) = y_bit else {
                    return Err(ReferenceError::new(format!(
                        "malformed $lut {cell_name}: Y is not a net"
                    )));
                };
                let truth = cell.parameters.lut.as_ref().ok_or_else(|| {
                    ReferenceError::new(format!("malformed $lut {cell_name}: missing LUT"))
                })?;
                let width = a_bits.len();
                let entries = 1_usize
                    .checked_shl(u32::try_from(width).map_err(|_| {
                        ReferenceError::new(format!("$lut {cell_name} width is too large"))
                    })?)
                    .ok_or_else(|| {
                        ReferenceError::new(format!("$lut {cell_name} width is too large"))
                    })?;
                let truth_chars = truth.chars().collect::<Vec<_>>();
                if truth_chars.len() != entries {
                    return Err(ReferenceError::new(format!(
                        "LUT width mismatch in {cell_name}: {} truth entries for width {width}",
                        truth_chars.len()
                    )));
                }
                let table = (0..entries)
                    .map(|mask| u8::from(truth_chars[entries - 1 - mask] == '1'))
                    .collect();
                luts.push(LutCell {
                    name: cell_name.clone(),
                    a_bits: a_bits.clone(),
                    y_wire: *y_wire,
                    init_msb_first: truth.clone(),
                    table,
                });
            } else if is_yosys_dff_type(&cell.cell_type) {
                let q_bit = cell
                    .connections
                    .get("Q")
                    .and_then(|bits| bits.first())
                    .ok_or_else(|| {
                        ReferenceError::new(format!("malformed DFF {cell_name}: missing Q"))
                    })?;
                let YosysBit::Net(q_wire) = q_bit else {
                    return Err(ReferenceError::new(format!(
                        "malformed DFF {cell_name}: Q is not a net"
                    )));
                };
                let d_bit = cell
                    .connections
                    .get("D")
                    .and_then(|bits| bits.first())
                    .copied()
                    .ok_or_else(|| {
                        ReferenceError::new(format!("malformed DFF {cell_name}: missing D"))
                    })?;
                dffs.push(DffCell {
                    name: cell_name.clone(),
                    cell_type: cell.cell_type.clone(),
                    q_wire: *q_wire,
                    d_bit,
                    reset_bit: cell
                        .connections
                        .get("R")
                        .and_then(|bits| bits.first())
                        .copied(),
                    enable_bit: cell
                        .connections
                        .get("E")
                        .and_then(|bits| bits.first())
                        .copied(),
                    polarity: parse_yosys_dff_polarity(&cell.cell_type),
                });
            }
        }
        let state = dffs.iter().map(|dff| (dff.q_wire, 0)).collect();
        Ok(Self {
            module_name,
            input_ports,
            output_ports,
            luts,
            dffs,
            state,
            last_wires: BTreeMap::new(),
            last_lut_evaluations: BTreeMap::new(),
            trace_luts,
        })
    }

    pub fn register_bit(&self, q_wire: i64) -> u8 {
        self.state.get(&q_wire).copied().unwrap_or(0)
    }

    pub fn reset_state(&mut self, bits: &BTreeMap<i64, u8>) {
        self.state = self
            .dffs
            .iter()
            .map(|dff| (dff.q_wire, bits.get(&dff.q_wire).copied().unwrap_or(0)))
            .collect();
    }

    pub fn tick(
        &mut self,
        inputs: &BTreeMap<String, Vec<u8>>,
    ) -> Result<BTreeMap<String, Vec<u8>>> {
        if self.trace_luts {
            self.last_lut_evaluations.clear();
        }
        let mut wires = self.state.clone();
        for (port, values) in inputs {
            let Some(port_bits) = self.input_ports.get(port) else {
                continue;
            };
            if values.len() != port_bits.len() {
                return Err(ReferenceError::new(format!(
                    "width mismatch on {port}: got {}, expected {}",
                    values.len(),
                    port_bits.len()
                )));
            }
            for (bit, value) in port_bits.iter().zip(values) {
                if let YosysBit::Net(wire) = bit {
                    wires.insert(*wire, *value);
                }
            }
        }

        let mut pending = (0..self.luts.len()).collect::<Vec<_>>();
        let mut guard_count = pending
            .len()
            .checked_mul(pending.len())
            .and_then(|value| value.checked_add(1))
            .ok_or_else(|| ReferenceError::new("cleartext LUT guard overflow"))?;
        while !pending.is_empty() {
            guard_count = guard_count
                .checked_sub(1)
                .ok_or_else(|| ReferenceError::new("combinational loop in cleartext sim"))?;
            if guard_count == 0 {
                return Err(ReferenceError::new("combinational loop in cleartext sim"));
            }
            let mut still_pending = Vec::new();
            let mut progressed = false;
            for index in pending {
                let lut = &self.luts[index];
                let Some(input_values) = resolve_bits(&lut.a_bits, &wires) else {
                    still_pending.push(index);
                    continue;
                };
                let mut address = 0_usize;
                for (bit_index, value) in input_values.iter().enumerate() {
                    if *value != 0 {
                        address |= 1 << bit_index;
                    }
                }
                let output = lut.table[address];
                wires.insert(lut.y_wire, output);
                if self.trace_luts {
                    self.last_lut_evaluations.insert(
                        lut.name.clone(),
                        LutEvaluation {
                            name: lut.name.clone(),
                            input_values,
                            address,
                            output,
                        },
                    );
                }
                progressed = true;
            }
            if !progressed {
                return Err(ReferenceError::new("stuck cleartext LUT resolve"));
            }
            pending = still_pending;
        }

        let mut next_state = BTreeMap::new();
        for dff in &self.dffs {
            let d_value = resolve_bit(dff.d_bit, &wires).unwrap_or(0);
            let q_current = self.state.get(&dff.q_wire).copied().unwrap_or(0);

            let enabled = if let Some(enable_bit) = dff.enable_bit {
                let raw = resolve_bit(enable_bit, &wires).unwrap_or(0);
                active_level(
                    raw,
                    dff.polarity.enable_active_high.unwrap_or(true),
                    "enable",
                )?
            } else {
                true
            };

            let (reset_asserted, reset_value) = if let Some(reset_bit) = dff.reset_bit {
                let raw = resolve_bit(reset_bit, &wires).unwrap_or(0);
                let (active_high, value) = dff.polarity.sync_reset.unwrap_or((true, 0));
                (active_level(raw, active_high, "reset")?, value)
            } else {
                (false, 0)
            };

            let q_next = if dff.polarity.clock_enable_gates_reset {
                if !enabled {
                    q_current
                } else if reset_asserted {
                    reset_value
                } else {
                    d_value
                }
            } else if reset_asserted {
                reset_value
            } else if enabled {
                d_value
            } else {
                q_current
            };
            next_state.insert(dff.q_wire, q_next);
        }
        self.state = next_state;
        self.last_wires = wires.clone();
        for (wire, value) in &self.state {
            self.last_wires.insert(*wire, *value);
        }

        let mut outputs = BTreeMap::new();
        for (port, bits) in &self.output_ports {
            let values = bits
                .iter()
                .map(|bit| match bit {
                    YosysBit::Net(wire) => self
                        .state
                        .get(wire)
                        .or_else(|| wires.get(wire))
                        .copied()
                        .unwrap_or(0),
                    YosysBit::Constant(value) => *value,
                })
                .collect();
            outputs.insert(port.clone(), values);
        }
        Ok(outputs)
    }
}

pub fn is_yosys_dff_type(cell_type: &str) -> bool {
    if !cell_type.starts_with("$_") || !cell_type.ends_with('_') {
        return false;
    }
    cell_type[2..cell_type.len() - 1]
        .split('_')
        .find(|part| !part.is_empty())
        .is_some_and(|kind| kind.contains("DFF"))
}

pub fn parse_yosys_dff_polarity(cell_type: &str) -> DffPolarity {
    let fallback = DffPolarity {
        enable_active_high: None,
        sync_reset: None,
        clock_enable_gates_reset: false,
    };
    if !cell_type.starts_with("$_") || !cell_type.ends_with('_') {
        return fallback;
    }
    let parts = cell_type[2..cell_type.len() - 1]
        .split('_')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    if parts.len() < 2 {
        return fallback;
    }
    let kind = parts[0];
    let code = parts[1].as_bytes();
    let enable_active_high =
        if kind.contains("DFFE") || kind.contains("DFFCE") || kind.ends_with("CE") {
            match code.last() {
                Some(b'P') => Some(true),
                Some(b'N') => Some(false),
                _ => None,
            }
        } else {
            None
        };
    let sync_reset = if kind.contains("SDFF") && code.len() >= 3 {
        match (code[1], code[2]) {
            (b'P', b'0') => Some((true, 0)),
            (b'P', b'1') => Some((true, 1)),
            (b'N', b'0') => Some((false, 0)),
            (b'N', b'1') => Some((false, 1)),
            _ => None,
        }
    } else {
        None
    };
    DffPolarity {
        enable_active_high,
        sync_reset,
        clock_enable_gates_reset: kind.contains("SDFFCE"),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct YosysParityReport {
    pub full_adder_rows: usize,
    pub counter_transitions: usize,
    pub toy_isa_transitions: usize,
}

pub fn verify_standard_fixtures(
    full_adder_path: &Path,
    counter_path: &Path,
    toy_isa_path: &Path,
) -> Result<YosysParityReport> {
    verify_full_adder(full_adder_path)?;
    verify_counter(counter_path)?;
    verify_toy_isa(toy_isa_path)?;
    Ok(YosysParityReport {
        full_adder_rows: 8,
        counter_transitions: 16,
        toy_isa_transitions: 1_024,
    })
}

fn verify_full_adder(path: &Path) -> Result<()> {
    let netlist = load_netlist(path)?;
    let module = module_named(&netlist, "full_adder", path)?;
    let mut simulator = CleartextNetlistSimulator::new("full_adder", module, false)?;
    if simulator.luts.len() != 3 || !simulator.dffs.is_empty() {
        return Err(ReferenceError::new(
            "full-adder fixture must contain exactly 3 LUTs and 0 DFFs",
        ));
    }
    for a in 0_u8..=1 {
        for b in 0_u8..=1 {
            for carry_in in 0_u8..=1 {
                let inputs = bit_inputs(&[("a", vec![a]), ("b", vec![b]), ("cin", vec![carry_in])]);
                let outputs = simulator.tick(&inputs)?;
                let sum = output_scalar(&outputs, "sum")?;
                let carry_out = output_scalar(&outputs, "cout")?;
                let total = a + b + carry_in;
                if sum != total % 2 || carry_out != u8::from(total >= 2) {
                    return Err(ReferenceError::new(format!(
                        "full-adder parity mismatch for a={a}, b={b}, cin={carry_in}"
                    )));
                }
            }
        }
    }

    let mut traced = CleartextNetlistSimulator::new("full_adder", module, true)?;
    traced.tick(&bit_inputs(&[
        ("a", vec![1]),
        ("b", vec![0]),
        ("cin", vec![1]),
    ]))?;
    let signatures = traced
        .last_lut_evaluations
        .values()
        .map(|evaluation| {
            (
                evaluation.input_values.clone(),
                evaluation.address,
                evaluation.output,
            )
        })
        .collect::<Vec<_>>();
    for expected in [
        (vec![1, 0], 1, 1),
        (vec![1, 1], 3, 0),
        (vec![1, 0, 1], 5, 1),
    ] {
        if !signatures.contains(&expected) {
            return Err(ReferenceError::new(format!(
                "full-adder LUT-endian/relaxation trace is missing {expected:?}"
            )));
        }
    }
    Ok(())
}

fn verify_counter(path: &Path) -> Result<()> {
    let netlist = load_netlist(path)?;
    let module = module_named(&netlist, "stateful_counter", path)?;
    let mut simulator = CleartextNetlistSimulator::new("stateful_counter", module, false)?;
    if simulator.luts.len() != 6 || simulator.dffs.len() != 4 {
        return Err(ReferenceError::new(
            "counter fixture must contain exactly 6 LUTs and 4 DFFs",
        ));
    }
    for tick in 1_u8..=16 {
        let outputs = simulator.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![1])]))?;
        let count = bits_to_u8(output_bits(&outputs, "count")?)?;
        if count != tick & 0x0f {
            return Err(ReferenceError::new(format!(
                "counter mismatch at enabled tick {tick}: got {count}"
            )));
        }
    }

    simulator.reset_state(&BTreeMap::new());
    let held = simulator.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![0])]))?;
    if bits_to_u8(output_bits(&held, "count")?)? != 0 {
        return Err(ReferenceError::new(
            "counter changed while disabled at reset",
        ));
    }
    for _ in 0..5 {
        simulator.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![1])]))?;
    }
    for _ in 0..3 {
        let held = simulator.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![0])]))?;
        if bits_to_u8(output_bits(&held, "count")?)? != 5 {
            return Err(ReferenceError::new("counter did not hold value 5"));
        }
    }

    let seeded = simulator
        .dffs
        .iter()
        .map(|dff| (dff.q_wire, 1))
        .collect::<BTreeMap<_, _>>();
    simulator.reset_state(&seeded);
    let wrapped = simulator.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![1])]))?;
    if bits_to_u8(output_bits(&wrapped, "count")?)? != 0 {
        return Err(ReferenceError::new("counter failed seeded 15 -> 0 wrap"));
    }

    let mut low_clock = CleartextNetlistSimulator::new("stateful_counter", module, false)?;
    let mut high_clock = CleartextNetlistSimulator::new("stateful_counter", module, false)?;
    let low = low_clock.tick(&bit_inputs(&[("clk", vec![0]), ("en", vec![1])]))?;
    let high = high_clock.tick(&bit_inputs(&[("clk", vec![1]), ("en", vec![1])]))?;
    if output_bits(&low, "count")? != output_bits(&high, "count")?
        || bits_to_u8(output_bits(&low, "count")?)? != 1
    {
        return Err(ReferenceError::new(
            "counter does not preserve host-tick/ignored-clock semantics",
        ));
    }
    Ok(())
}

fn verify_toy_isa(path: &Path) -> Result<()> {
    let netlist = load_netlist(path)?;
    let module = module_named(&netlist, "toy_isa", path)?;
    let mut simulator = CleartextNetlistSimulator::new("toy_isa", module, false)?;
    if simulator.luts.len() != 11 || simulator.dffs.len() != 4 {
        return Err(ReferenceError::new(
            "toy-ISA fixture must contain exactly 11 LUTs and 4 DFFs",
        ));
    }
    let acc_bits = module
        .ports
        .get("acc")
        .ok_or_else(|| ReferenceError::new("toy-ISA fixture is missing acc"))?
        .bits
        .clone();

    for accumulator in 0_u8..16 {
        let seed = acc_bits
            .iter()
            .enumerate()
            .map(|(index, bit)| match bit {
                YosysBit::Net(wire) => Ok((*wire, (accumulator >> index) & 1)),
                YosysBit::Constant(_) => Err(ReferenceError::new(
                    "toy-ISA acc output unexpectedly contains a constant",
                )),
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        for operation in 0_u8..4 {
            for immediate in 0_u8..16 {
                simulator.reset_state(&seed);
                let outputs = simulator.tick(&bit_inputs(&[
                    ("clk", vec![0]),
                    ("op", value_bits(operation, 2)),
                    ("imm", value_bits(immediate, 4)),
                ]))?;
                let actual = bits_to_u8(output_bits(&outputs, "acc")?)?;
                let expected = if operation == 1 {
                    accumulator.wrapping_add(immediate) & 0x0f
                } else {
                    accumulator
                };
                if actual != expected {
                    return Err(ReferenceError::new(format!(
                        "toy-ISA mismatch: acc={accumulator}, op={operation}, imm={immediate}, got={actual}, expected={expected}"
                    )));
                }
            }
        }
    }
    Ok(())
}

fn module_named<'a>(netlist: &'a YosysNetlist, name: &str, path: &Path) -> Result<&'a YosysModule> {
    netlist.modules.get(name).ok_or_else(|| {
        ReferenceError::new(format!("{} has no module named {name}", path.display()))
    })
}

fn bit_inputs(entries: &[(&str, Vec<u8>)]) -> BTreeMap<String, Vec<u8>> {
    entries
        .iter()
        .map(|(name, bits)| ((*name).to_owned(), bits.clone()))
        .collect()
}

fn output_bits<'a>(outputs: &'a BTreeMap<String, Vec<u8>>, name: &str) -> Result<&'a [u8]> {
    outputs
        .get(name)
        .map(Vec::as_slice)
        .ok_or_else(|| ReferenceError::new(format!("missing output port {name}")))
}

fn output_scalar(outputs: &BTreeMap<String, Vec<u8>>, name: &str) -> Result<u8> {
    let bits = output_bits(outputs, name)?;
    if bits.len() != 1 {
        return Err(ReferenceError::new(format!(
            "output {name} has width {}, expected 1",
            bits.len()
        )));
    }
    Ok(bits[0])
}

fn bits_to_u8(bits: &[u8]) -> Result<u8> {
    if bits.len() > 8 {
        return Err(ReferenceError::new("cannot pack more than eight bits"));
    }
    let mut value = 0_u8;
    for (index, bit) in bits.iter().enumerate() {
        if *bit > 1 {
            return Err(ReferenceError::new("non-binary bit in fixture output"));
        }
        value |= *bit << index;
    }
    Ok(value)
}

fn value_bits(value: u8, width: usize) -> Vec<u8> {
    (0..width).map(|index| (value >> index) & 1).collect()
}

fn active_level(raw: u8, active_high: bool, label: &str) -> Result<bool> {
    if active_high {
        Ok(raw != 0)
    } else {
        let inverted = 1_u8.checked_sub(raw).ok_or_else(|| {
            ReferenceError::new(format!("non-binary active-low DFF {label} value {raw}"))
        })?;
        Ok(inverted != 0)
    }
}

fn resolve_bits(bits: &[YosysBit], wires: &BTreeMap<i64, u8>) -> Option<Vec<u8>> {
    bits.iter().map(|bit| resolve_bit(*bit, wires)).collect()
}

fn resolve_bit(bit: YosysBit, wires: &BTreeMap<i64, u8>) -> Option<u8> {
    match bit {
        YosysBit::Net(wire) => wires.get(&wire).copied(),
        YosysBit::Constant(value) => Some(value),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dff_module(cell_type: &str, enable: bool, reset: bool) -> YosysModule {
        let mut ports = BTreeMap::from([
            (
                "d".to_owned(),
                YosysPort {
                    direction: "input".to_owned(),
                    bits: vec![YosysBit::Net(1)],
                },
            ),
            (
                "q".to_owned(),
                YosysPort {
                    direction: "output".to_owned(),
                    bits: vec![YosysBit::Net(4)],
                },
            ),
        ]);
        let mut connections = BTreeMap::from([
            ("D".to_owned(), vec![YosysBit::Net(1)]),
            ("Q".to_owned(), vec![YosysBit::Net(4)]),
        ]);
        if enable {
            ports.insert(
                "e".to_owned(),
                YosysPort {
                    direction: "input".to_owned(),
                    bits: vec![YosysBit::Net(2)],
                },
            );
            connections.insert("E".to_owned(), vec![YosysBit::Net(2)]);
        }
        if reset {
            ports.insert(
                "r".to_owned(),
                YosysPort {
                    direction: "input".to_owned(),
                    bits: vec![YosysBit::Net(3)],
                },
            );
            connections.insert("R".to_owned(), vec![YosysBit::Net(3)]);
        }
        YosysModule {
            ports,
            cells: BTreeMap::from([(
                "cell".to_owned(),
                YosysCell {
                    cell_type: cell_type.to_owned(),
                    parameters: YosysCellParameters {
                        lut: None,
                        width: None,
                    },
                    connections,
                    port_directions: None,
                },
            )]),
            netnames: None,
        }
    }

    fn tick_dff(
        simulator: &mut CleartextNetlistSimulator,
        d: u8,
        enable: Option<u8>,
        reset: Option<u8>,
    ) -> u8 {
        let mut inputs = BTreeMap::from([("d".to_owned(), vec![d])]);
        if let Some(value) = enable {
            inputs.insert("e".to_owned(), vec![value]);
        }
        if let Some(value) = reset {
            inputs.insert("r".to_owned(), vec![value]);
        }
        let outputs = simulator.tick(&inputs).expect("synthetic DFF tick");
        output_scalar(&outputs, "q").expect("synthetic q output")
    }

    #[test]
    fn dff_type_and_polarity_parser_matches_swift_contract() {
        let cases = [
            (
                "$_DFF_P_",
                DffPolarity {
                    enable_active_high: None,
                    sync_reset: None,
                    clock_enable_gates_reset: false,
                },
            ),
            (
                "$_DFFE_PN_",
                DffPolarity {
                    enable_active_high: Some(false),
                    sync_reset: None,
                    clock_enable_gates_reset: false,
                },
            ),
            (
                "$_SDFF_PN1_",
                DffPolarity {
                    enable_active_high: None,
                    sync_reset: Some((false, 1)),
                    clock_enable_gates_reset: false,
                },
            ),
            (
                "$_SDFFE_PN0P_",
                DffPolarity {
                    enable_active_high: Some(true),
                    sync_reset: Some((false, 0)),
                    clock_enable_gates_reset: false,
                },
            ),
            (
                "$_SDFFCE_PN0P_",
                DffPolarity {
                    enable_active_high: Some(true),
                    sync_reset: Some((false, 0)),
                    clock_enable_gates_reset: true,
                },
            ),
        ];
        for (cell_type, expected) in cases {
            assert!(is_yosys_dff_type(cell_type));
            assert_eq!(parse_yosys_dff_polarity(cell_type), expected);
        }
        assert!(!is_yosys_dff_type("$dff"));
    }

    #[test]
    fn dff_runtime_covers_enable_reset_value_and_priority() {
        let module = dff_module("$_DFF_P_", false, false);
        let mut plain =
            CleartextNetlistSimulator::new("plain", &module, false).expect("compile plain DFF");
        assert_eq!(tick_dff(&mut plain, 1, None, None), 1);

        let module = dff_module("$_DFFE_PN_", true, false);
        let mut active_low_enable =
            CleartextNetlistSimulator::new("active-low-enable", &module, false)
                .expect("compile active-low DFFE");
        assert_eq!(tick_dff(&mut active_low_enable, 1, Some(1), None), 0);
        assert_eq!(tick_dff(&mut active_low_enable, 1, Some(0), None), 1);

        let module = dff_module("$_SDFFE_PP1P_", true, true);
        let mut reset_over_enable =
            CleartextNetlistSimulator::new("reset-over-enable", &module, false)
                .expect("compile SDFFE");
        assert_eq!(tick_dff(&mut reset_over_enable, 0, Some(0), Some(1)), 1);

        let module = dff_module("$_SDFFCE_PP1P_", true, true);
        let mut enable_gates_reset =
            CleartextNetlistSimulator::new("enable-gates-reset", &module, false)
                .expect("compile SDFFCE");
        assert_eq!(tick_dff(&mut enable_gates_reset, 0, Some(0), Some(1)), 0);
        assert_eq!(tick_dff(&mut enable_gates_reset, 0, Some(1), Some(1)), 1);

        let module = dff_module("$_SDFFE_PN0P_", true, true);
        let mut active_low_reset =
            CleartextNetlistSimulator::new("active-low-reset", &module, false)
                .expect("compile active-low reset DFF");
        active_low_reset.reset_state(&BTreeMap::from([(4, 1)]));
        assert_eq!(tick_dff(&mut active_low_reset, 1, Some(1), Some(0)), 0);
    }
}
