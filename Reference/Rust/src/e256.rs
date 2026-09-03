//! Read-only E256-v2/gen0 integer reference and schema-4 KAT verifier.
//!
//! This module consumes the frozen repository profile and fixture bundle. It
//! deliberately has no generation, mutation, blessing, or promotion surface.

use crate::{
    ReferenceError, Result, deserialize_unique_btree_map, read_json, read_regular_file, sha256_hex,
};
use serde::Deserialize;
use sha2::{Digest, Sha256, Sha512};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

pub const EXPECTED_PROFILE_SHA256: &str =
    "fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4";
pub const EXPECTED_RECEIPT_SHA256: &str =
    "5c5bc931a145048037ec420b2c0c47ff310570e963bd45b8262f18a1640f0027";
const EXPECTED_COMPATIBILITY_KEY: &str =
    "E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4";
const MANIFEST_SCHEMA: &str = "E256-KAT-MANIFEST-4";
const TRACE_SCHEMA: &str = "E256-KAT-TRACE-4";
const EXPECTED_STREAM_BYTES: usize = 1_024;
const FEEDBACK_MASK: u64 = 0xd800_0000_0000_0000;
const CENTER_MASK_KEY_BYTES: usize = 32;
const CENTER_MASK_BLOCK_BYTES: u64 = 32;

const TABLE_NAMES: [&str; 9] = [
    "plugboard.hex",
    "r1_fwd.hex",
    "r1_rev.hex",
    "r2_fwd.hex",
    "r2_rev.hex",
    "r3_fwd.hex",
    "r3_rev.hex",
    "r4_fwd.hex",
    "r4_rev.hex",
];

const TRACE_NAMES: [&str; 10] = [
    "lfsr_before.hex",
    "lfsr_after.hex",
    "offsets_before.hex",
    "offsets_after.hex",
    "step_mask.hex",
    "byte_counter_before.hex",
    "byte_counter_after.hex",
    "center_mask.hex",
    "center_input.hex",
    "center_output.hex",
];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Component {
    truth_hex: String,
}

impl Component {
    fn truth(&self) -> Result<u128> {
        u128::from_str_radix(&self.truth_hex, 16).map_err(|error| {
            ReferenceError::new(format!(
                "invalid E256 component truth table {}: {error}",
                self.truth_hex
            ))
        })
    }

    fn evaluate(&self, input: u8) -> Result<bool> {
        if input >= 128 {
            return Err(ReferenceError::new("E256 component input exceeds 7 bits"));
        }
        Ok(((self.truth()? >> input) & 1) != 0)
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct Fold {
    taps: Vec<usize>,
    left_component: usize,
    right_component: usize,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    family: String,
    suite_version: usize,
    generation: usize,
    fixture_schema_version: usize,
    lfsr_transition: String,
    update_order: String,
    center_construction: String,
    center_mask_key_kdf: String,
    center_mask_prf: String,
    center_mask_key_domain: String,
    center_mask_block_domain: String,
    center_mask_counter: String,
    center_mask_extraction: String,
    center_map_order: String,
    formula: String,
    components: Vec<Component>,
    folds: Vec<Fold>,
    research_status: String,
    receipt: String,
    receipt_sha256: String,
    profile_sha256: String,
}

impl Profile {
    pub fn load(path: &Path) -> Result<Self> {
        let profile: Self = read_json(path)?;
        profile.validate()?;
        Ok(profile)
    }

    pub fn profile_sha256(&self) -> &str {
        &self.profile_sha256
    }

    pub fn compatibility_key(&self) -> String {
        format!(
            "{}/v{}/gen{}/{}/fixture-v{}",
            self.family,
            self.suite_version,
            self.generation,
            self.computed_profile_sha256(),
            self.fixture_schema_version
        )
    }

    pub fn canonical_profile(&self) -> Vec<u8> {
        let components = self
            .components
            .iter()
            .map(|component| component.truth_hex.as_str())
            .collect::<Vec<_>>()
            .join(",");
        let folds = self
            .folds
            .iter()
            .map(|fold| {
                let taps = fold
                    .taps
                    .iter()
                    .map(usize::to_string)
                    .collect::<Vec<_>>()
                    .join(".");
                format!("{taps}:{}:{}", fold.left_component, fold.right_component)
            })
            .collect::<Vec<_>>()
            .join(",");
        format!(
            "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
            self.family,
            self.suite_version,
            self.generation,
            self.fixture_schema_version,
            self.lfsr_transition,
            self.update_order,
            self.center_construction,
            self.center_mask_key_kdf,
            self.center_mask_prf,
            self.center_mask_key_domain,
            self.center_mask_block_domain,
            self.center_mask_counter,
            self.center_mask_extraction,
            self.center_map_order,
            self.formula,
            components,
            folds
        )
        .into_bytes()
    }

    fn computed_profile_sha256(&self) -> String {
        sha256_hex(&self.canonical_profile())
    }

    fn center_mask_key_info(&self) -> Vec<u8> {
        format!(
            "{}/v{}/gen{}/{}/{}",
            self.family,
            self.suite_version,
            self.generation,
            self.center_mask_key_domain,
            self.computed_profile_sha256()
        )
        .into_bytes()
    }

    fn center_mask_block_info(&self) -> Vec<u8> {
        format!(
            "{}/v{}/gen{}/{}/{}",
            self.family,
            self.suite_version,
            self.generation,
            self.center_mask_block_domain,
            self.computed_profile_sha256()
        )
        .into_bytes()
    }

    fn validate(&self) -> Result<()> {
        let identity_ok = self.family == "E256"
            && self.suite_version == 2
            && self.generation == 0
            && self.fixture_schema_version == 4
            && self.lfsr_transition == "right_shift_lsb_galois_d800000000000000"
            && self.update_order
                == "derive_prestep_mask_and_counter_mask_scramble_then_step_and_increment"
            && self.center_construction == "conjugated_xor_counter_prf_v1"
            && self.center_mask_key_kdf == "hkdf_sha512_nonce_salt_32_v1"
            && self.center_mask_prf == "hmac_sha256_32_byte_blocks_v1"
            && self.center_mask_key_domain == "center-mask-key"
            && self.center_mask_block_domain == "center-mask-block"
            && self.center_mask_counter == "uint64_be_block_counter_start_0"
            && self.center_mask_extraction == "digest_byte_i_mod_32_allow_zero"
            && self.center_map_order
                == "plugboard_forward_rotors_xor_mask_reverse_rotors_plugboard_v1"
            && self.formula == "native_reversible_16"
            && self.research_status == "accepted_bounded_profile"
            && self.receipt == "logs/e256-v2-gen0-nlff-search.json"
            && self.receipt_sha256 == EXPECTED_RECEIPT_SHA256;
        if !identity_ok {
            return Err(ReferenceError::new(
                "unsupported E256 profile identity; only frozen E256-v2/gen0 fixture-v4 is accepted",
            ));
        }

        if self.components.len() != 8 {
            return Err(ReferenceError::new(format!(
                "E256 profile has {} components, expected 8",
                self.components.len()
            )));
        }
        for (index, component) in self.components.iter().enumerate() {
            if component.truth_hex.len() != 32
                || !is_lower_hex(&component.truth_hex)
                || component.truth()?.count_ones() != 64
            {
                return Err(ReferenceError::new(format!(
                    "invalid E256 component {index}"
                )));
            }
        }

        if self.folds.len() != 4 {
            return Err(ReferenceError::new(format!(
                "E256 profile has {} folds, expected 4",
                self.folds.len()
            )));
        }
        let mut all_taps = Vec::with_capacity(64);
        let mut assignments = Vec::with_capacity(8);
        for (index, fold) in self.folds.iter().enumerate() {
            let unique: BTreeSet<usize> = fold.taps.iter().copied().collect();
            if fold.taps.len() != 16
                || unique.len() != 16
                || fold.taps.iter().any(|tap| *tap >= 64)
                || fold.left_component >= 8
                || fold.right_component >= 8
            {
                return Err(ReferenceError::new(format!("invalid E256 fold {index}")));
            }
            all_taps.extend(fold.taps.iter().copied());
            assignments.push(fold.left_component);
            assignments.push(fold.right_component);
        }
        all_taps.sort_unstable();
        if all_taps != (0..64).collect::<Vec<_>>() {
            return Err(ReferenceError::new(
                "E256 fold taps do not partition all 64 state bits",
            ));
        }
        if assignments != (0..8).collect::<Vec<_>>() {
            return Err(ReferenceError::new(
                "E256 component assignments are not the frozen 0...7 order",
            ));
        }

        let computed = self.computed_profile_sha256();
        if self.profile_sha256 != computed || computed != EXPECTED_PROFILE_SHA256 {
            return Err(ReferenceError::new(format!(
                "E256 profile hash mismatch: declared {}, computed {computed}, expected {EXPECTED_PROFILE_SHA256}",
                self.profile_sha256
            )));
        }
        if self.compatibility_key() != EXPECTED_COMPATIBILITY_KEY {
            return Err(ReferenceError::new("E256 compatibility-key mismatch"));
        }
        Ok(())
    }

    fn step_mask(&self, state: u64) -> Result<[bool; 4]> {
        let mut output = [false; 4];
        for (index, fold) in self.folds.iter().enumerate() {
            let mut left_input = 0_u8;
            let mut right_input = 0_u8;
            for bit in 0..7 {
                left_input |= (((state >> fold.taps[bit + 1]) & 1) as u8) << bit;
                right_input |= (((state >> fold.taps[bit + 9]) & 1) as u8) << bit;
            }
            let left_pivot = ((state >> fold.taps[0]) & 1) != 0;
            let right_pivot = ((state >> fold.taps[8]) & 1) != 0;
            let left = left_pivot ^ self.components[fold.left_component].evaluate(left_input)?;
            let right =
                right_pivot ^ self.components[fold.right_component].evaluate(right_input)?;
            output[index] = left ^ right;
        }
        Ok(output)
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema: String,
    trace_schema: String,
    compatibility_key: String,
    profile_sha256: String,
    profile_canonical_hex: String,
    stream_bytes: usize,
    #[serde(deserialize_with = "deserialize_unique_btree_map")]
    artifacts: BTreeMap<String, String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SessionCompatibility {
    family: String,
    suite_version: usize,
    generation: usize,
    fixture_schema_version: usize,
    profile_sha256: String,
    profile_canonical_hex: String,
    lfsr_transition: String,
    update_order: String,
    center_construction: String,
    center_mask_key_kdf: String,
    center_mask_prf: String,
    center_mask_key_domain: String,
    center_mask_block_domain: String,
    center_mask_counter: String,
    center_mask_extraction: String,
    center_map_order: String,
    formula: String,
    receipt_sha256: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SessionMessage {
    rotor_indices: Vec<u8>,
    positions: Vec<u8>,
    lfsr_seed_hex: String,
    initial_byte_counter_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SessionFile {
    version: usize,
    core: String,
    compatibility: SessionCompatibility,
    ikm_hex: String,
    salt_hex: String,
    nonce_hex: String,
    message: SessionMessage,
    plaintext_hex: String,
    ciphertext_hex: String,
    length: usize,
    wr_sel_order: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct Wiring {
    plugboard: [u8; 256],
    r1_fwd: [u8; 256],
    r1_rev: [u8; 256],
    r2_fwd: [u8; 256],
    r2_rev: [u8; 256],
    r3_fwd: [u8; 256],
    r3_rev: [u8; 256],
    r4_fwd: [u8; 256],
    r4_rev: [u8; 256],
}

impl Wiring {
    fn from_tables(tables: Vec<Vec<u8>>) -> Result<Self> {
        if tables.len() != TABLE_NAMES.len() {
            return Err(ReferenceError::new("E256 requires exactly nine tables"));
        }
        let mut iterator = tables.into_iter();
        let mut next = |name: &str| -> Result<[u8; 256]> {
            let values = iterator
                .next()
                .ok_or_else(|| ReferenceError::new(format!("missing E256 table {name}")))?;
            values.try_into().map_err(|values: Vec<u8>| {
                ReferenceError::new(format!(
                    "E256 table {name} has {} entries, expected 256",
                    values.len()
                ))
            })
        };
        let wiring = Self {
            plugboard: next("plugboard")?,
            r1_fwd: next("r1_fwd")?,
            r1_rev: next("r1_rev")?,
            r2_fwd: next("r2_fwd")?,
            r2_rev: next("r2_rev")?,
            r3_fwd: next("r3_fwd")?,
            r3_rev: next("r3_rev")?,
            r4_fwd: next("r4_fwd")?,
            r4_rev: next("r4_rev")?,
        };
        wiring.validate()?;
        Ok(wiring)
    }

    fn validate(&self) -> Result<()> {
        for (name, table) in [
            ("plugboard", &self.plugboard),
            ("r1_fwd", &self.r1_fwd),
            ("r1_rev", &self.r1_rev),
            ("r2_fwd", &self.r2_fwd),
            ("r2_rev", &self.r2_rev),
            ("r3_fwd", &self.r3_fwd),
            ("r3_rev", &self.r3_rev),
            ("r4_fwd", &self.r4_fwd),
            ("r4_rev", &self.r4_rev),
        ] {
            validate_permutation(name, table)?;
        }

        for index in 0..256 {
            if usize::from(self.plugboard[usize::from(self.plugboard[index])]) != index {
                return Err(ReferenceError::new(format!(
                    "plugboard is not an involution at {index}"
                )));
            }
        }

        for (rotor, (forward, reverse)) in [
            (&self.r1_fwd, &self.r1_rev),
            (&self.r2_fwd, &self.r2_rev),
            (&self.r3_fwd, &self.r3_rev),
            (&self.r4_fwd, &self.r4_rev),
        ]
        .into_iter()
        .enumerate()
        {
            for index in 0..256 {
                let forward_then_reverse = reverse[usize::from(forward[index])];
                let reverse_then_forward = forward[usize::from(reverse[index])];
                if usize::from(forward_then_reverse) != index
                    || usize::from(reverse_then_forward) != index
                {
                    return Err(ReferenceError::new(format!(
                        "rotor {} tables are not inverse at {index}",
                        rotor + 1
                    )));
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ByteTrace {
    pub input: u8,
    pub output: u8,
    pub lfsr_before: u64,
    pub lfsr_after: u64,
    pub offsets_before: [u8; 4],
    pub offsets_after: [u8; 4],
    pub step_mask_bits: u8,
    pub byte_counter_before: u64,
    pub byte_counter_after: u64,
    pub center_mask: u8,
    pub center_input: u8,
    pub center_output: u8,
}

pub struct Machine<'a> {
    wiring: &'a Wiring,
    profile: &'a Profile,
    lfsr: u64,
    offsets: [u8; 4],
    center_mask_key: [u8; CENTER_MASK_KEY_BYTES],
    byte_counter: u64,
}

impl<'a> Machine<'a> {
    pub fn new(
        wiring: &'a Wiring,
        profile: &'a Profile,
        lfsr: u64,
        offsets: [u8; 4],
        center_mask_key: [u8; CENTER_MASK_KEY_BYTES],
        byte_counter: u64,
    ) -> Result<Self> {
        if lfsr == 0 {
            return Err(ReferenceError::new(
                "schema-4 E256 external state must not use the zero LFSR seed",
            ));
        }
        wiring.validate()?;
        profile.validate()?;
        Ok(Self {
            wiring,
            profile,
            lfsr,
            offsets,
            center_mask_key,
            byte_counter,
        })
    }

    pub fn process(&mut self, input: u8) -> Result<u8> {
        Ok(self.process_traced(input)?.output)
    }

    pub fn process_traced(&mut self, input: u8) -> Result<ByteTrace> {
        if self.byte_counter == u64::MAX {
            return Err(ReferenceError::new(
                "E256 byte counter exhausted; schedule reuse is forbidden",
            ));
        }
        let lfsr_before = self.lfsr;
        let offsets_before = self.offsets;
        let byte_counter_before = self.byte_counter;
        let mask = self.profile.step_mask(self.lfsr)?;
        let center_mask =
            center_mask_for_counter(self.profile, &self.center_mask_key, byte_counter_before);
        let (output, center_input, center_output) = self.scramble(input, center_mask);
        let step_mask_bits = pack_step_mask(mask);
        for (index, enabled) in mask.into_iter().enumerate() {
            if enabled {
                self.offsets[index] = self.offsets[index].wrapping_add(1);
            }
        }
        self.lfsr = clock_lfsr(self.lfsr);
        self.byte_counter = self
            .byte_counter
            .checked_add(1)
            .ok_or_else(|| ReferenceError::new("E256 byte counter overflow"))?;
        Ok(ByteTrace {
            input,
            output,
            lfsr_before,
            lfsr_after: self.lfsr,
            offsets_before,
            offsets_after: self.offsets,
            step_mask_bits,
            byte_counter_before,
            byte_counter_after: self.byte_counter,
            center_mask,
            center_input,
            center_output,
        })
    }

    fn scramble(&self, input: u8, center_mask: u8) -> (u8, u8, u8) {
        let mut value = self.wiring.plugboard[usize::from(input)];
        value = rotor(&self.wiring.r1_fwd, value, self.offsets[0]);
        value = rotor(&self.wiring.r2_fwd, value, self.offsets[1]);
        value = rotor(&self.wiring.r3_fwd, value, self.offsets[2]);
        value = rotor(&self.wiring.r4_fwd, value, self.offsets[3]);
        let center_input = value;
        let center_output = center_input ^ center_mask;
        value = rotor(&self.wiring.r4_rev, center_output, self.offsets[3]);
        value = rotor(&self.wiring.r3_rev, value, self.offsets[2]);
        value = rotor(&self.wiring.r2_rev, value, self.offsets[1]);
        value = rotor(&self.wiring.r1_rev, value, self.offsets[0]);
        (
            self.wiring.plugboard[usize::from(value)],
            center_input,
            center_output,
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KatReport {
    pub profile_sha256: String,
    pub compatibility_key: String,
    pub fixture_schema_version: usize,
    pub manifest_schema: String,
    pub trace_schema: String,
    pub stream_bytes: usize,
    pub artifact_count: usize,
    pub table_count: usize,
    pub trace_count: usize,
    pub initial_byte_counter: u64,
    pub final_byte_counter: u64,
    pub reciprocal_decrypt_verified: bool,
}

pub fn verify_kat(profile_path: &Path, bundle: &Path, receipt_path: &Path) -> Result<KatReport> {
    let profile = Profile::load(profile_path)?;
    verify_receipt(&profile, receipt_path)?;
    verify_bundle_layout(bundle)?;

    let manifest: Manifest = read_json(&bundle.join("manifest.json"))?;
    verify_manifest(&profile, &manifest, bundle)?;

    let session: SessionFile = read_json(&bundle.join("session.json"))?;
    let canonical_hex = encode_hex(&profile.canonical_profile());
    let state = verify_session_identity(&profile, &session, &canonical_hex)?;

    let plaintext = decode_lower_hex(&session.plaintext_hex, "session plaintext_hex")?;
    let ciphertext = decode_lower_hex(&session.ciphertext_hex, "session ciphertext_hex")?;
    if plaintext.len() != EXPECTED_STREAM_BYTES
        || ciphertext.len() != EXPECTED_STREAM_BYTES
        || session.length != EXPECTED_STREAM_BYTES
        || manifest.stream_bytes != EXPECTED_STREAM_BYTES
    {
        return Err(ReferenceError::new(
            "schema-4 E256 stream length is not exactly 1,024 bytes",
        ));
    }

    let plaintext_bin = read_regular_file(&bundle.join("plaintext.bin"))?;
    let ciphertext_bin = read_regular_file(&bundle.join("ciphertext.bin"))?;
    let plaintext_hex = parse_hex_lines(
        &read_regular_file(&bundle.join("plaintext.hex"))?,
        2,
        EXPECTED_STREAM_BYTES,
        "plaintext.hex",
    )?
    .into_iter()
    .map(|value| value as u8)
    .collect::<Vec<_>>();
    let ciphertext_hex = parse_hex_lines(
        &read_regular_file(&bundle.join("ciphertext.hex"))?,
        2,
        EXPECTED_STREAM_BYTES,
        "ciphertext.hex",
    )?
    .into_iter()
    .map(|value| value as u8)
    .collect::<Vec<_>>();
    if plaintext != plaintext_bin
        || ciphertext != ciphertext_bin
        || plaintext != plaintext_hex
        || ciphertext != ciphertext_hex
    {
        return Err(ReferenceError::new(
            "E256 raw .bin/.hex/session stream duplicates disagree",
        ));
    }

    let tables = TABLE_NAMES
        .iter()
        .map(|name| {
            parse_hex_lines(
                &read_regular_file(&bundle.join("tables").join(name))?,
                2,
                256,
                &format!("tables/{name}"),
            )
            .map(|values| values.into_iter().map(|value| value as u8).collect())
        })
        .collect::<Result<Vec<Vec<u8>>>>()?;
    let wiring = Wiring::from_tables(tables)?;

    let mut machine = Machine::new(
        &wiring,
        &profile,
        state.lfsr_seed,
        state.offsets,
        state.center_mask_key,
        state.initial_byte_counter,
    )?;
    let traces = plaintext
        .iter()
        .copied()
        .map(|byte| machine.process_traced(byte))
        .collect::<Result<Vec<_>>>()?;
    let recomputed = traces.iter().map(|trace| trace.output).collect::<Vec<_>>();
    if recomputed != ciphertext {
        return Err(ReferenceError::new(
            "independent E256 machine does not reproduce ciphertext",
        ));
    }

    verify_trace_files(bundle, &traces)?;
    verify_trace_semantics(
        &profile,
        &state.center_mask_key,
        state.lfsr_seed,
        state.offsets,
        state.initial_byte_counter,
        &traces,
    )?;

    let mut decryptor = Machine::new(
        &wiring,
        &profile,
        state.lfsr_seed,
        state.offsets,
        state.center_mask_key,
        state.initial_byte_counter,
    )?;
    let decrypted = ciphertext
        .iter()
        .copied()
        .map(|byte| decryptor.process(byte))
        .collect::<Result<Vec<_>>>()?;
    if decrypted != plaintext {
        return Err(ReferenceError::new(
            "E256 reciprocal decrypt assertion failed",
        ));
    }

    verify_tb_params(
        bundle,
        &profile,
        state.lfsr_seed,
        state.offsets,
        state.initial_byte_counter,
    )?;
    let final_counter = traces
        .last()
        .ok_or_else(|| ReferenceError::new("E256 KAT contains no traces"))?
        .byte_counter_after;
    Ok(KatReport {
        profile_sha256: profile.profile_sha256().to_owned(),
        compatibility_key: profile.compatibility_key(),
        fixture_schema_version: profile.fixture_schema_version,
        manifest_schema: manifest.schema.clone(),
        trace_schema: manifest.trace_schema.clone(),
        stream_bytes: plaintext.len(),
        artifact_count: manifest.artifacts.len(),
        table_count: TABLE_NAMES.len(),
        trace_count: TRACE_NAMES.len(),
        initial_byte_counter: state.initial_byte_counter,
        final_byte_counter: final_counter,
        reciprocal_decrypt_verified: true,
    })
}

#[derive(Debug, Clone, Copy)]
struct SessionState {
    lfsr_seed: u64,
    offsets: [u8; 4],
    center_mask_key: [u8; CENTER_MASK_KEY_BYTES],
    initial_byte_counter: u64,
}

fn verify_receipt(profile: &Profile, receipt_path: &Path) -> Result<()> {
    let receipt = read_regular_file(receipt_path)?;
    let actual = sha256_hex(&receipt);
    if actual != profile.receipt_sha256 || actual != EXPECTED_RECEIPT_SHA256 {
        return Err(ReferenceError::new(format!(
            "E256 receipt hash mismatch: got {actual}, expected {}",
            profile.receipt_sha256
        )));
    }
    Ok(())
}

fn verify_manifest(profile: &Profile, manifest: &Manifest, bundle: &Path) -> Result<()> {
    let canonical_hex = encode_hex(&profile.canonical_profile());
    let actual_paths = manifest.artifacts.keys().cloned().collect::<BTreeSet<_>>();
    if manifest.schema != MANIFEST_SCHEMA
        || manifest.trace_schema != TRACE_SCHEMA
        || manifest.compatibility_key != EXPECTED_COMPATIBILITY_KEY
        || manifest.compatibility_key != profile.compatibility_key()
        || manifest.profile_sha256 != EXPECTED_PROFILE_SHA256
        || manifest.profile_sha256 != profile.profile_sha256
        || manifest.profile_canonical_hex != canonical_hex
        || manifest.stream_bytes != EXPECTED_STREAM_BYTES
        || actual_paths != expected_artifact_paths()
    {
        return Err(ReferenceError::new(
            "E256 schema-4 manifest identity or exact artifact path set mismatch",
        ));
    }
    for (relative, expected_hash) in &manifest.artifacts {
        if expected_hash.len() != 64 || !is_lower_hex(expected_hash) {
            return Err(ReferenceError::new(format!(
                "E256 manifest hash for {relative} is not 64 lowercase hex digits"
            )));
        }
        let data = read_regular_file(&bundle.join(relative))?;
        let actual_hash = sha256_hex(&data);
        if &actual_hash != expected_hash {
            return Err(ReferenceError::new(format!(
                "E256 artifact hash mismatch for {relative}: got {actual_hash}, expected {expected_hash}"
            )));
        }
    }
    Ok(())
}

fn verify_session_identity(
    profile: &Profile,
    session: &SessionFile,
    canonical_hex: &str,
) -> Result<SessionState> {
    let compatibility = &session.compatibility;
    let expected_order = TABLE_NAMES.map(str::to_owned).to_vec();
    let identity_ok = session.version == 4
        && session.core == "enigma_256_core"
        && session.length == EXPECTED_STREAM_BYTES
        && session.wr_sel_order == expected_order
        && compatibility.family == profile.family
        && compatibility.suite_version == profile.suite_version
        && compatibility.generation == profile.generation
        && compatibility.fixture_schema_version == profile.fixture_schema_version
        && compatibility.profile_sha256 == profile.profile_sha256
        && compatibility.profile_canonical_hex == canonical_hex
        && compatibility.lfsr_transition == profile.lfsr_transition
        && compatibility.update_order == profile.update_order
        && compatibility.center_construction == profile.center_construction
        && compatibility.center_mask_key_kdf == profile.center_mask_key_kdf
        && compatibility.center_mask_prf == profile.center_mask_prf
        && compatibility.center_mask_key_domain == profile.center_mask_key_domain
        && compatibility.center_mask_block_domain == profile.center_mask_block_domain
        && compatibility.center_mask_counter == profile.center_mask_counter
        && compatibility.center_mask_extraction == profile.center_mask_extraction
        && compatibility.center_map_order == profile.center_map_order
        && compatibility.formula == profile.formula
        && compatibility.receipt_sha256 == profile.receipt_sha256;
    if !identity_ok {
        return Err(ReferenceError::new(
            "E256 session fields do not identify the frozen schema-4 KAT",
        ));
    }

    let rotor_indices = session
        .message
        .rotor_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    if session.message.rotor_indices.len() != 4
        || rotor_indices.len() != 4
        || rotor_indices.iter().any(|index| *index >= 16)
    {
        return Err(ReferenceError::new(
            "E256 session must select four distinct rotor indices below 16",
        ));
    }
    let offsets: [u8; 4] = session
        .message
        .positions
        .clone()
        .try_into()
        .map_err(|_| ReferenceError::new("E256 session must contain four positions"))?;
    let lfsr_seed = parse_prefixed_u64(&session.message.lfsr_seed_hex, "E256 LFSR seed", false)?;
    if lfsr_seed == 0 {
        return Err(ReferenceError::new("E256 LFSR seed must be nonzero"));
    }
    let initial_byte_counter = parse_prefixed_u64(
        &session.message.initial_byte_counter_hex,
        "E256 initial byte counter",
        true,
    )?;
    let stream_bytes = u64::try_from(session.length)
        .map_err(|_| ReferenceError::new("E256 stream length does not fit UInt64"))?;
    if initial_byte_counter.checked_add(stream_bytes).is_none() {
        return Err(ReferenceError::new(
            "E256 session byte-counter range would overflow",
        ));
    }

    let ikm = decode_lower_hex(&session.ikm_hex, "session ikm_hex")?;
    let salt = decode_lower_hex(&session.salt_hex, "session salt_hex")?;
    let nonce = decode_lower_hex(&session.nonce_hex, "session nonce_hex")?;
    let expected_nonce = [
        0xe2, 0x56, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
        0x0d,
    ];
    if ikm != b"helut-enigma256-golden-ikm-v1!!!!"
        || salt != b"helut-salt"
        || nonce != expected_nonce
    {
        return Err(ReferenceError::new(
            "E256 session IKM/salt/nonce do not match the frozen KAT",
        ));
    }
    let center_mask_key = derive_center_mask_key(profile, &ikm, &nonce)?;
    Ok(SessionState {
        lfsr_seed,
        offsets,
        center_mask_key,
        initial_byte_counter,
    })
}

fn verify_trace_files(bundle: &Path, traces: &[ByteTrace]) -> Result<()> {
    let lfsr_before = read_trace(bundle, "lfsr_before.hex", 16)?;
    let lfsr_after = read_trace(bundle, "lfsr_after.hex", 16)?;
    let offsets_before = read_trace(bundle, "offsets_before.hex", 8)?;
    let offsets_after = read_trace(bundle, "offsets_after.hex", 8)?;
    let step_mask = read_trace(bundle, "step_mask.hex", 1)?;
    let byte_counter_before = read_trace(bundle, "byte_counter_before.hex", 16)?;
    let byte_counter_after = read_trace(bundle, "byte_counter_after.hex", 16)?;
    let center_mask = read_trace(bundle, "center_mask.hex", 2)?;
    let center_input = read_trace(bundle, "center_input.hex", 2)?;
    let center_output = read_trace(bundle, "center_output.hex", 2)?;

    for (index, trace) in traces.iter().enumerate() {
        let before = pack_offsets(trace.offsets_before);
        let after = pack_offsets(trace.offsets_after);
        if lfsr_before[index] != trace.lfsr_before
            || lfsr_after[index] != trace.lfsr_after
            || offsets_before[index] != u64::from(before)
            || offsets_after[index] != u64::from(after)
            || step_mask[index] != u64::from(trace.step_mask_bits)
            || byte_counter_before[index] != trace.byte_counter_before
            || byte_counter_after[index] != trace.byte_counter_after
            || center_mask[index] != u64::from(trace.center_mask)
            || center_input[index] != u64::from(trace.center_input)
            || center_output[index] != u64::from(trace.center_output)
        {
            return Err(ReferenceError::new(format!(
                "E256 trace mismatch at beat {index}"
            )));
        }
    }
    if step_mask.iter().any(|value| *value > 0x0f)
        || center_mask.iter().any(|value| *value > 0xff)
        || center_input.iter().any(|value| *value > 0xff)
        || center_output.iter().any(|value| *value > 0xff)
    {
        return Err(ReferenceError::new(
            "E256 trace value exceeds its field width",
        ));
    }
    Ok(())
}

fn verify_trace_semantics(
    profile: &Profile,
    center_mask_key: &[u8; CENTER_MASK_KEY_BYTES],
    initial_lfsr: u64,
    initial_offsets: [u8; 4],
    initial_byte_counter: u64,
    traces: &[ByteTrace],
) -> Result<()> {
    let mut lfsr = initial_lfsr;
    let mut offsets = initial_offsets;
    let mut byte_counter = initial_byte_counter;
    for (index, trace) in traces.iter().enumerate() {
        if byte_counter == u64::MAX {
            return Err(ReferenceError::new(format!(
                "E256 trace reaches exhausted byte counter at beat {index}"
            )));
        }
        let mask = profile.step_mask(lfsr)?;
        let mask_bits = pack_step_mask(mask);
        let expected_center_mask = center_mask_for_counter(profile, center_mask_key, byte_counter);
        let mut offsets_after = offsets;
        for (rotor_index, enabled) in mask.into_iter().enumerate() {
            if enabled {
                offsets_after[rotor_index] = offsets_after[rotor_index].wrapping_add(1);
            }
        }
        let lfsr_after = clock_lfsr(lfsr);
        let byte_counter_after = byte_counter
            .checked_add(1)
            .ok_or_else(|| ReferenceError::new("E256 trace byte-counter overflow"))?;
        if trace.lfsr_before != lfsr
            || trace.lfsr_after != lfsr_after
            || trace.offsets_before != offsets
            || trace.offsets_after != offsets_after
            || trace.step_mask_bits != mask_bits
            || trace.byte_counter_before != byte_counter
            || trace.byte_counter_after != byte_counter_after
            || trace.center_mask != expected_center_mask
            || trace.center_output != (trace.center_input ^ trace.center_mask)
        {
            return Err(ReferenceError::new(format!(
                "E256 trace transition, mask, counter, or center XOR mismatch at beat {index}"
            )));
        }
        lfsr = lfsr_after;
        offsets = offsets_after;
        byte_counter = byte_counter_after;
    }
    Ok(())
}

fn verify_tb_params(
    bundle: &Path,
    profile: &Profile,
    lfsr_seed: u64,
    offsets: [u8; 4],
    initial_byte_counter: u64,
) -> Result<()> {
    let expected = expected_tb_params(profile, lfsr_seed, offsets, initial_byte_counter);
    let actual = read_regular_file(&bundle.join("tb_params.vh"))?;
    if actual != expected.as_bytes() {
        return Err(ReferenceError::new(format!(
            "tb_params.vh does not match the verified E256 session: actual {} bytes/{}, expected {} bytes/{}",
            actual.len(),
            sha256_hex(&actual),
            expected.len(),
            sha256_hex(expected.as_bytes())
        )));
    }
    Ok(())
}

fn expected_tb_params(
    profile: &Profile,
    lfsr_seed: u64,
    offsets: [u8; 4],
    initial_byte_counter: u64,
) -> String {
    format!(
        "// Auto-generated by Enigma256Bridge — include at module scope (not inside initial).\n\
// Compatibility: {}\n\
// Receipt SHA-256: {}\n\
localparam int ENIGMA256_N = 1024;\n\
localparam [63:0] ENIGMA256_LFSR = 64'h{lfsr_seed:016x};\n\
localparam [63:0] ENIGMA256_COUNTER = 64'h{initial_byte_counter:016x};\n\
localparam [7:0] ENIGMA256_R1 = 8'h{:02x};\n\
localparam [7:0] ENIGMA256_R2 = 8'h{:02x};\n\
localparam [7:0] ENIGMA256_R3 = 8'h{:02x};\n\
localparam [7:0] ENIGMA256_R4 = 8'h{:02x};",
        profile.compatibility_key(),
        profile.receipt_sha256,
        offsets[0],
        offsets[1],
        offsets[2],
        offsets[3]
    )
}

fn derive_center_mask_key(
    profile: &Profile,
    ikm: &[u8],
    nonce: &[u8],
) -> Result<[u8; CENTER_MASK_KEY_BYTES]> {
    let output = hkdf_sha512(
        ikm,
        nonce,
        &profile.center_mask_key_info(),
        CENTER_MASK_KEY_BYTES,
    )?;
    output.try_into().map_err(|output: Vec<u8>| {
        ReferenceError::new(format!(
            "E256 center-mask key has {} bytes, expected {CENTER_MASK_KEY_BYTES}",
            output.len()
        ))
    })
}

fn center_mask_for_counter(
    profile: &Profile,
    center_mask_key: &[u8; CENTER_MASK_KEY_BYTES],
    byte_counter: u64,
) -> u8 {
    let mut message = profile.center_mask_block_info();
    message.push(0);
    message.extend_from_slice(&(byte_counter / CENTER_MASK_BLOCK_BYTES).to_be_bytes());
    let digest = hmac_sha256(center_mask_key, &message);
    digest[(byte_counter % CENTER_MASK_BLOCK_BYTES) as usize]
}

fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    const BLOCK_BYTES: usize = 64;
    let mut key_block = [0_u8; BLOCK_BYTES];
    if key.len() > BLOCK_BYTES {
        let digest = Sha256::digest(key);
        key_block[..digest.len()].copy_from_slice(&digest);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }
    let mut inner_pad = key_block;
    let mut outer_pad = key_block;
    for byte in &mut inner_pad {
        *byte ^= 0x36;
    }
    for byte in &mut outer_pad {
        *byte ^= 0x5c;
    }
    let mut inner = Sha256::new();
    inner.update(inner_pad);
    inner.update(message);
    let inner_digest = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(outer_pad);
    outer.update(inner_digest);
    let digest = outer.finalize();
    let mut output = [0_u8; 32];
    output.copy_from_slice(&digest);
    output
}

fn hmac_sha512(key: &[u8], message: &[u8]) -> [u8; 64] {
    const BLOCK_BYTES: usize = 128;
    let mut key_block = [0_u8; BLOCK_BYTES];
    if key.len() > BLOCK_BYTES {
        let digest = Sha512::digest(key);
        key_block[..digest.len()].copy_from_slice(&digest);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }
    let mut inner_pad = key_block;
    let mut outer_pad = key_block;
    for byte in &mut inner_pad {
        *byte ^= 0x36;
    }
    for byte in &mut outer_pad {
        *byte ^= 0x5c;
    }
    let mut inner = Sha512::new();
    inner.update(inner_pad);
    inner.update(message);
    let inner_digest = inner.finalize();
    let mut outer = Sha512::new();
    outer.update(outer_pad);
    outer.update(inner_digest);
    let digest = outer.finalize();
    let mut output = [0_u8; 64];
    output.copy_from_slice(&digest);
    output
}

fn hkdf_sha512(ikm: &[u8], salt: &[u8], info: &[u8], length: usize) -> Result<Vec<u8>> {
    const HASH_BYTES: usize = 64;
    const MAX_OUTPUT_BYTES: usize = 255 * HASH_BYTES;
    if length > MAX_OUTPUT_BYTES {
        return Err(ReferenceError::new(format!(
            "HKDF-SHA512 output length {length} exceeds RFC 5869 limit {MAX_OUTPUT_BYTES}"
        )));
    }
    let zero_salt = [0_u8; HASH_BYTES];
    let extract_salt = if salt.is_empty() {
        zero_salt.as_slice()
    } else {
        salt
    };
    let pseudorandom_key = hmac_sha512(extract_salt, ikm);
    let blocks = length.div_ceil(HASH_BYTES);
    let mut output = Vec::with_capacity(length);
    let mut previous = Vec::new();
    for block_index in 1..=blocks {
        let mut message = Vec::with_capacity(previous.len() + info.len() + 1);
        message.extend_from_slice(&previous);
        message.extend_from_slice(info);
        message.push(block_index as u8);
        previous = hmac_sha512(&pseudorandom_key, &message).to_vec();
        output.extend_from_slice(&previous);
    }
    output.truncate(length);
    Ok(output)
}

fn read_trace(bundle: &Path, name: &str, width: usize) -> Result<Vec<u64>> {
    parse_hex_lines(
        &read_regular_file(&bundle.join("trace").join(name))?,
        width,
        EXPECTED_STREAM_BYTES,
        &format!("trace/{name}"),
    )
}

fn parse_hex_lines(data: &[u8], width: usize, count: usize, label: &str) -> Result<Vec<u64>> {
    let text = std::str::from_utf8(data)
        .map_err(|error| ReferenceError::new(format!("{label} is not UTF-8: {error}")))?;
    if text.contains('\r') || !text.ends_with('\n') {
        return Err(ReferenceError::new(format!(
            "{label} must use LF lines and end with a newline"
        )));
    }
    let body = &text[..text.len() - 1];
    let lines = if body.is_empty() {
        Vec::new()
    } else {
        body.split('\n').collect::<Vec<_>>()
    };
    if lines.len() != count {
        return Err(ReferenceError::new(format!(
            "{label} has {} rows, expected {count}",
            lines.len()
        )));
    }
    lines
        .into_iter()
        .enumerate()
        .map(|(index, line)| {
            if line.len() != width || !is_lower_hex(line) {
                return Err(ReferenceError::new(format!(
                    "{label} row {index} is not exactly {width} lowercase hex digits"
                )));
            }
            u64::from_str_radix(line, 16).map_err(|error| {
                ReferenceError::new(format!("invalid {label} row {index}: {error}"))
            })
        })
        .collect()
}

fn decode_lower_hex(text: &str, label: &str) -> Result<Vec<u8>> {
    if !text.len().is_multiple_of(2) || !is_lower_hex(text) {
        return Err(ReferenceError::new(format!(
            "{label} must contain an even number of lowercase hex digits"
        )));
    }
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let pair = std::str::from_utf8(pair)
                .map_err(|error| ReferenceError::new(format!("invalid {label}: {error}")))?;
            u8::from_str_radix(pair, 16)
                .map_err(|error| ReferenceError::new(format!("invalid {label}: {error}")))
        })
        .collect()
}

fn parse_prefixed_u64(text: &str, label: &str, allow_zero: bool) -> Result<u64> {
    let digits = text
        .strip_prefix("0x")
        .ok_or_else(|| ReferenceError::new(format!("{label} must begin with 0x")))?;
    if digits.len() != 16 || !is_lower_hex(digits) {
        return Err(ReferenceError::new(format!(
            "{label} must contain exactly 16 lowercase hex digits"
        )));
    }
    let value = u64::from_str_radix(digits, 16)
        .map_err(|error| ReferenceError::new(format!("invalid {label}: {error}")))?;
    if !allow_zero && value == 0 {
        return Err(ReferenceError::new(format!("{label} must be nonzero")));
    }
    Ok(value)
}

fn is_lower_hex(text: &str) -> bool {
    !text.is_empty()
        && text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn encode_hex(data: &[u8]) -> String {
    let mut output = String::with_capacity(data.len() * 2);
    for byte in data {
        use std::fmt::Write as _;
        write!(&mut output, "{byte:02x}").expect("writing to String cannot fail");
    }
    output
}

fn rotor(table: &[u8; 256], input: u8, offset: u8) -> u8 {
    table[usize::from(input.wrapping_add(offset))].wrapping_sub(offset)
}

fn pack_step_mask(mask: [bool; 4]) -> u8 {
    mask.into_iter()
        .enumerate()
        .fold(0_u8, |bits, (index, enabled)| {
            bits | if enabled { 1 << index } else { 0 }
        })
}

fn clock_lfsr(state: u64) -> u64 {
    (state >> 1) ^ if state & 1 == 0 { 0 } else { FEEDBACK_MASK }
}

fn pack_offsets(offsets: [u8; 4]) -> u32 {
    (u32::from(offsets[0]) << 24)
        | (u32::from(offsets[1]) << 16)
        | (u32::from(offsets[2]) << 8)
        | u32::from(offsets[3])
}

fn validate_permutation(name: &str, table: &[u8; 256]) -> Result<()> {
    let mut seen = [false; 256];
    for value in table {
        if seen[usize::from(*value)] {
            return Err(ReferenceError::new(format!(
                "E256 table {name} is not a permutation"
            )));
        }
        seen[usize::from(*value)] = true;
    }
    Ok(())
}

fn expected_artifact_paths() -> BTreeSet<String> {
    let mut paths = [
        "ciphertext.bin",
        "ciphertext.hex",
        "plaintext.bin",
        "plaintext.hex",
        "session.json",
        "tb_params.vh",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect::<BTreeSet<_>>();
    paths.extend(TABLE_NAMES.map(|name| format!("tables/{name}")));
    paths.extend(TRACE_NAMES.map(|name| format!("trace/{name}")));
    paths
}

fn verify_bundle_layout(bundle: &Path) -> Result<()> {
    verify_directory_entries(
        bundle,
        &[
            ("ciphertext.bin", false),
            ("ciphertext.hex", false),
            ("manifest.json", false),
            ("plaintext.bin", false),
            ("plaintext.hex", false),
            ("session.json", false),
            ("tables", true),
            ("tb_params.vh", false),
            ("trace", true),
        ],
    )?;
    let table_entries = TABLE_NAMES.map(|name| (name, false));
    verify_directory_entries(&bundle.join("tables"), &table_entries)?;
    let trace_entries = TRACE_NAMES.map(|name| (name, false));
    verify_directory_entries(&bundle.join("trace"), &trace_entries)
}

fn verify_directory_entries(directory: &Path, expected: &[(&str, bool)]) -> Result<()> {
    let metadata = fs::symlink_metadata(directory).map_err(|error| {
        ReferenceError::new(format!("cannot stat {}: {error}", directory.display()))
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(ReferenceError::new(format!(
            "expected real directory at {}",
            directory.display()
        )));
    }

    let expected_map = expected
        .iter()
        .map(|(name, is_directory)| ((*name).to_owned(), *is_directory))
        .collect::<BTreeMap<_, _>>();
    let mut actual = BTreeMap::new();
    for entry in fs::read_dir(directory).map_err(|error| {
        ReferenceError::new(format!("cannot list {}: {error}", directory.display()))
    })? {
        let entry = entry.map_err(|error| {
            ReferenceError::new(format!("cannot inspect {}: {error}", directory.display()))
        })?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| ReferenceError::new("E256 bundle contains a non-UTF-8 file name"))?;
        let file_type = entry.file_type().map_err(|error| {
            ReferenceError::new(format!(
                "cannot inspect {}: {error}",
                entry.path().display()
            ))
        })?;
        if file_type.is_symlink() {
            return Err(ReferenceError::new(format!(
                "E256 bundle contains symlink {}",
                entry.path().display()
            )));
        }
        let is_directory = file_type.is_dir();
        if !is_directory && !file_type.is_file() {
            return Err(ReferenceError::new(format!(
                "E256 bundle contains non-regular entry {}",
                entry.path().display()
            )));
        }
        actual.insert(name, is_directory);
    }
    if actual != expected_map {
        return Err(ReferenceError::new(format!(
            "E256 bundle layout mismatch at {}: got {actual:?}, expected {expected_map:?}",
            directory.display()
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn repository_root() -> std::path::PathBuf {
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    fn v4_profile() -> Profile {
        let root = repository_root();
        for path in [
            root.join("Fixtures/enigma256_generation.json"),
            root.join("build/e256-v4-contract/enigma256_generation.json"),
        ] {
            if let Ok(profile) = Profile::load(&path) {
                return profile;
            }
        }
        panic!("a frozen fixture-v4 profile must be available")
    }

    fn valid_identity_tables() -> Vec<Vec<u8>> {
        let identity = (0_u16..=255).map(|value| value as u8).collect::<Vec<_>>();
        vec![identity; TABLE_NAMES.len()]
    }

    struct TemporaryDirectory(std::path::PathBuf);

    impl TemporaryDirectory {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock must follow the Unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "helut-e256-rust-test-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(path.join("tables")).expect("create temporary tables directory");
            fs::create_dir_all(path.join("trace")).expect("create temporary trace directory");
            for name in [
                "ciphertext.bin",
                "ciphertext.hex",
                "manifest.json",
                "plaintext.bin",
                "plaintext.hex",
                "session.json",
                "tb_params.vh",
            ] {
                fs::write(path.join(name), []).expect("create temporary bundle file");
            }
            for name in TABLE_NAMES {
                fs::write(path.join("tables").join(name), []).expect("create temporary table file");
            }
            for name in TRACE_NAMES {
                fs::write(path.join("trace").join(name), []).expect("create temporary trace file");
            }
            Self(path)
        }
    }

    impl Drop for TemporaryDirectory {
        fn drop(&mut self) {
            for name in TABLE_NAMES {
                let _ = fs::remove_file(self.0.join("tables").join(name));
            }
            for name in TRACE_NAMES {
                let _ = fs::remove_file(self.0.join("trace").join(name));
            }
            for name in [
                "ciphertext.bin",
                "ciphertext.hex",
                "manifest.json",
                "plaintext.bin",
                "plaintext.hex",
                "session.json",
                "tb_params.vh",
            ] {
                let _ = fs::remove_file(self.0.join(name));
            }
            let _ = fs::remove_dir(self.0.join("tables"));
            let _ = fs::remove_dir(self.0.join("trace"));
            let _ = fs::remove_dir(&self.0);
        }
    }

    fn empty_artifact_hashes() -> BTreeMap<String, String> {
        let empty_hash = sha256_hex(&[]);
        expected_artifact_paths()
            .into_iter()
            .map(|path| (path, empty_hash.clone()))
            .collect()
    }

    #[test]
    fn fixture_v4_profile_identity_and_canonical_order_are_frozen() {
        let profile = v4_profile();
        assert_eq!(profile.computed_profile_sha256(), EXPECTED_PROFILE_SHA256);
        assert_eq!(profile.compatibility_key(), EXPECTED_COMPATIBILITY_KEY);
        assert_eq!(profile.fixture_schema_version, 4);
        assert_eq!(
            profile
                .canonical_profile()
                .split(|byte| *byte == b'|')
                .count(),
            17
        );

        let mut legacy = profile.clone();
        legacy.fixture_schema_version = 3;
        assert!(legacy.validate().is_err());
        let mut changed = profile;
        changed.center_mask_prf.push_str("-changed");
        assert!(changed.validate().is_err());
    }

    #[test]
    fn manifest_enforces_v4_identity_paths_hashes_and_strict_json() {
        let profile = v4_profile();
        let expected_paths = expected_artifact_paths();
        assert_eq!(expected_paths.len(), 25);
        assert!(
            TABLE_NAMES
                .iter()
                .all(|name| expected_paths.contains(&format!("tables/{name}")))
        );
        assert!(
            TRACE_NAMES
                .iter()
                .all(|name| expected_paths.contains(&format!("trace/{name}")))
        );
        assert!(!expected_paths.contains("tables/reflector.hex"));
        assert!(!expected_paths.contains("trace/center_mode.hex"));

        let mut artifacts = empty_artifact_hashes();
        assert_eq!(
            artifacts.keys().cloned().collect::<BTreeSet<_>>(),
            expected_paths
        );
        assert!(
            artifacts
                .values()
                .all(|hash| hash.len() == 64 && is_lower_hex(hash))
        );
        artifacts.remove("trace/center_mask.hex");
        assert_ne!(
            artifacts.keys().cloned().collect::<BTreeSet<_>>(),
            expected_artifact_paths()
        );

        let manifest_text = format!(
            "{{\"schema\":\"{MANIFEST_SCHEMA}\",\"trace_schema\":\"{TRACE_SCHEMA}\",\"compatibility_key\":\"{}\",\"profile_sha256\":\"{}\",\"profile_canonical_hex\":\"{}\",\"stream_bytes\":1024,\"artifacts\":{{}}}}",
            profile.compatibility_key(),
            profile.profile_sha256,
            encode_hex(&profile.canonical_profile())
        );
        assert!(serde_json::from_str::<Manifest>(&manifest_text).is_ok());
        let unknown = manifest_text.replacen('{', "{\"unexpected\":true,", 1);
        assert!(serde_json::from_str::<Manifest>(&unknown).is_err());
        let duplicate = manifest_text.replacen(
            &format!("\"schema\":\"{MANIFEST_SCHEMA}\""),
            &format!("\"schema\":\"{MANIFEST_SCHEMA}\",\"schema\":\"{MANIFEST_SCHEMA}\""),
            1,
        );
        assert!(serde_json::from_str::<Manifest>(&duplicate).is_err());
    }

    #[test]
    fn tb_params_v4_receipt_includes_counter_in_producer_order() {
        let profile = v4_profile();
        let text = expected_tb_params(
            &profile,
            0x0123_4567_89ab_cdef,
            [0x10, 0x20, 0x30, 0x40],
            0x0102_0304_0506_0708,
        );
        let lines = text.lines().collect::<Vec<_>>();
        assert_eq!(lines.len(), 10);
        assert_eq!(
            lines[4],
            "localparam [63:0] ENIGMA256_LFSR = 64'h0123456789abcdef;"
        );
        assert_eq!(
            lines[5],
            "localparam [63:0] ENIGMA256_COUNTER = 64'h0102030405060708;"
        );
        assert_eq!(lines[6], "localparam [7:0] ENIGMA256_R1 = 8'h10;");
        assert_eq!(lines[9], "localparam [7:0] ENIGMA256_R4 = 8'h40;");
    }

    #[test]
    fn strict_hex_and_nine_table_wiring_reject_malformed_inputs() {
        assert!(parse_hex_lines(b"00\nff\n", 2, 2, "valid").is_ok());
        assert!(parse_hex_lines(b"00\nFF\n", 2, 2, "uppercase").is_err());
        assert!(parse_hex_lines(b"00\n", 2, 2, "short").is_err());
        assert!(parse_hex_lines(b"00\r\nff\r\n", 2, 2, "crlf").is_err());

        assert!(Wiring::from_tables(valid_identity_tables()).is_ok());
        let mut wrong_inverse = valid_identity_tables();
        wrong_inverse[2].swap(0, 1);
        assert!(Wiring::from_tables(wrong_inverse).is_err());
        let mut old_ten_table_layout = valid_identity_tables();
        old_ten_table_layout.push((0_u16..=255).map(|value| value as u8).collect());
        assert!(Wiring::from_tables(old_ten_table_layout).is_err());
    }

    #[test]
    fn bundle_layout_rejects_extra_legacy_and_symlink_entries() {
        let temporary = TemporaryDirectory::new();
        assert!(verify_bundle_layout(&temporary.0).is_ok());
        fs::write(temporary.0.join("extra.txt"), b"unexpected")
            .expect("create extra temporary file");
        assert!(verify_bundle_layout(&temporary.0).is_err());
        fs::remove_file(temporary.0.join("extra.txt")).expect("remove extra temporary file");
        fs::write(temporary.0.join("tables/reflector.hex"), []).expect("create legacy reflector");
        assert!(verify_bundle_layout(&temporary.0).is_err());
        fs::remove_file(temporary.0.join("tables/reflector.hex")).expect("remove legacy reflector");

        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            fs::remove_file(temporary.0.join("plaintext.bin")).expect("remove temporary plaintext");
            symlink("ciphertext.bin", temporary.0.join("plaintext.bin"))
                .expect("create temporary symlink");
            assert!(verify_bundle_layout(&temporary.0).is_err());
        }
    }

    #[test]
    fn hmac_sha256_matches_rfc_4231_known_vectors() {
        let expected = decode_lower_hex(
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
            "RFC 4231 case 1",
        )
        .expect("valid vector");
        assert_eq!(hmac_sha256(&[0x0b; 20], b"Hi There").as_slice(), expected);

        let expected_long = decode_lower_hex(
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
            "RFC 4231 case 6",
        )
        .expect("valid vector");
        assert_eq!(
            hmac_sha256(
                &[0xaa; 131],
                b"Test Using Larger Than Block-Size Key - Hash Key First"
            )
            .as_slice(),
            expected_long
        );
    }

    #[test]
    fn hkdf_sha512_matches_rfc_5869_style_known_vectors() {
        let ikm = vec![0x0b; 22];
        let salt = decode_lower_hex("000102030405060708090a0b0c", "salt").expect("valid salt");
        let info = decode_lower_hex("f0f1f2f3f4f5f6f7f8f9", "info").expect("valid info");
        let expected = decode_lower_hex(
            "832390086cda71fb47625bb5ceb168e4c8e26a1a16ed34d9fc7fe92c1481579338da362cb8d9f925d7cb",
            "HKDF-SHA512 short vector",
        )
        .expect("valid vector");
        assert_eq!(
            hkdf_sha512(&ikm, &salt, &info, 42).expect("valid HKDF"),
            expected
        );

        let long_ikm = (0x00_u8..=0x4f).collect::<Vec<_>>();
        let long_salt = (0x60_u8..=0xaf).collect::<Vec<_>>();
        let long_info = (0xb0_u8..=0xff).collect::<Vec<_>>();
        let expected_long = decode_lower_hex(
            "ce6c97192805b346e6161e821ed165673b84f400a2b514b2fe23d84cd189ddf1b695b48cbd1c8388441137b3ce28f16aa64ba33ba466b24df6cfcb021ecff235f6a2056ce3af1de44d572097a8505d9e7a93",
            "HKDF-SHA512 long vector",
        )
        .expect("valid vector");
        assert_eq!(
            hkdf_sha512(&long_ikm, &long_salt, &long_info, 82).expect("valid HKDF"),
            expected_long
        );
        assert!(hkdf_sha512(&[], &[], &[], 255 * 64 + 1).is_err());
    }

    #[test]
    fn frozen_center_key_and_block_transcript_match_independent_vectors() {
        let profile = v4_profile();
        let ikm = b"helut-enigma256-golden-ikm-v1!!!!";
        let nonce =
            decode_lower_hex("e256000102030405060708090a0b0c0d", "nonce").expect("valid nonce");
        let key = derive_center_mask_key(&profile, ikm, &nonce).expect("derive center key");
        assert_eq!(
            encode_hex(&key),
            "80ed6710f40876647eb9cfa9acddd7ff9641b0f149edd3b86c35650ecc9e28e6"
        );
        let mut block_zero_message = profile.center_mask_block_info();
        block_zero_message.push(0);
        block_zero_message.extend_from_slice(&0_u64.to_be_bytes());
        assert_eq!(
            encode_hex(&hmac_sha256(&key, &block_zero_message)),
            "929d778c74252dc7937c35a9c97b8376afed71e6ef41de99ebdbe36de977046f"
        );
        assert_eq!(center_mask_for_counter(&profile, &key, 0), 0x92);
        assert_eq!(center_mask_for_counter(&profile, &key, 31), 0x6f);
        assert_eq!(center_mask_for_counter(&profile, &key, 32), 0xa7);
    }

    #[test]
    fn machine_verifies_center_xor_reciprocity_and_counter_exhaustion() {
        let profile = v4_profile();
        let wiring = Wiring::from_tables(valid_identity_tables()).expect("valid wiring");
        let key = [0x5a; CENTER_MASK_KEY_BYTES];
        let mut encryptor =
            Machine::new(&wiring, &profile, 1, [0; 4], key, 0).expect("valid machine");
        let trace = encryptor.process_traced(0x87).expect("process byte");
        assert_eq!(trace.byte_counter_before, 0);
        assert_eq!(trace.byte_counter_after, 1);
        assert_eq!(trace.center_output, trace.center_input ^ trace.center_mask);
        verify_trace_semantics(&profile, &key, 1, [0; 4], 0, &[trace])
            .expect("trace semantics must verify");

        let mut decryptor =
            Machine::new(&wiring, &profile, 1, [0; 4], key, 0).expect("valid decryptor");
        assert_eq!(
            decryptor.process(trace.output).expect("decrypt byte"),
            trace.input
        );

        let mut changed = trace;
        changed.center_mask ^= 1;
        assert!(verify_trace_semantics(&profile, &key, 1, [0; 4], 0, &[changed]).is_err());

        let mut final_byte = Machine::new(&wiring, &profile, 1, [0; 4], key, u64::MAX - 1)
            .expect("valid final-byte machine");
        let final_trace = final_byte
            .process_traced(0)
            .expect("last counter value is usable");
        assert_eq!(final_trace.byte_counter_after, u64::MAX);
        assert!(final_byte.process(0).is_err());
        let mut exhausted = Machine::new(&wiring, &profile, 1, [0; 4], key, u64::MAX)
            .expect("construct exhausted machine");
        assert!(exhausted.process(0).is_err());
    }
}
