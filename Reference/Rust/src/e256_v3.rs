//! Portable, read-only E256-v3 fixture-v5 consumer.
//!
//! This lane intentionally coexists with `e256`: v1/v2 evidence is historical
//! and is never relabeled. Passing this in-tree verifier is implementation
//! parity, not independent external acceptance or a security proof.

use crate::{ReferenceError, Result, read_regular_file, sha256_hex};
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256, Sha512};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;

pub const EXPECTED_PROFILE_SHA256: &str =
    "0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16";
pub const EXPECTED_COMPATIBILITY_KEY: &str =
    "E256/v3/gen0/0206c00e5084ebafe1f841708d2af3f4a029bcf160f7b22ed63bb5078d376e16/fixture-v5";
const MANIFEST_NAME: &str = "fixture-v5.json";
const MANIFEST_LIMIT: usize = 2 * 1024 * 1024;
const ARTIFACT_LIMIT: usize = 16 * 1024 * 1024;
const TOTAL_ARTIFACT_LIMIT: usize = 64 * 1024 * 1024;
const CHECKPOINTS: [usize; 9] = [0, 1, 2, 58, 59, 60, 64, 128, 1024];
const LFSR_MASK: u64 = 0xd800_0000_0000_0000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct V3VerificationReport {
    pub compatibility_key: String,
    pub profile_sha256: String,
    pub stream_bytes: usize,
    pub artifact_count: usize,
    pub recurrence_basis_count: usize,
    pub negative_vector_declaration_count: usize,
    pub reciprocal_decrypt_verified: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Fixture {
    schema: Schema,
    identity: Identity,
    profile_binding: ProfileBinding,
    semantics: Semantics,
    inputs: Inputs,
    derivation: Derivation,
    recurrence_vectors: RecurrenceVectors,
    stream_kat: StreamKat,
    negative_vectors: Vec<NegativeVector>,
    artifacts: Vec<Artifact>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Schema {
    name: String,
    version: u32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Identity {
    family: String,
    suite_version: u32,
    generation: u32,
    fixture_schema_version: u32,
    profile_sha256: String,
    compatibility_key: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct NamedValue {
    name: String,
    value: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct NamedDigest {
    name: String,
    sha256: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ProfileBinding {
    canonical_encoding: String,
    canonical_profile_bytes: usize,
    canonical_profile_hex: String,
    canonical_profile_sha256: String,
    domains: Vec<NamedValue>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Semantics {
    lfsr_transition: String,
    update_order: String,
    center_construction: String,
    center_mask_prf: String,
    center_mask_counter: String,
    center_mask_extraction: String,
    center_map_order: String,
    domain_encoding: String,
    kdf: String,
    purpose_stream: String,
    bounded_sampler: String,
    zero_policy: String,
    plugboard_policy: String,
    rotor_policy: String,
    rotor_selection: String,
    raw_security_target: String,
    envelope_target: String,
    real_data_policy: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Inputs {
    day_ikm_hex: String,
    day_salt_hex: String,
    message_ikm_hex: String,
    nonce_hex: String,
    plaintext_generator: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct PurposeVector {
    purpose: String,
    first_64_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Derivation {
    purpose_vectors: Vec<PurposeVector>,
    day_table_digests: Vec<NamedDigest>,
    active_table_digests: Vec<NamedDigest>,
    rotor_indices: Vec<usize>,
    positions_hex: String,
    lfsr_seed_hex: String,
    center_mask_key_hex: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct RecurrenceCheckpoint {
    clock: usize,
    state_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RecurrenceVectors {
    seed_hex: String,
    basis_artifact: String,
    checkpoints: Vec<RecurrenceCheckpoint>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct StateCheckpoint {
    byte: usize,
    absolute_byte_counter: u64,
    lfsr_hex: String,
    positions_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct StreamKat {
    byte_count: usize,
    plaintext_artifact: String,
    ciphertext_artifact: String,
    trace_artifact: String,
    reciprocal_decrypt: bool,
    state_checkpoints: Vec<StateCheckpoint>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct NegativeVector {
    id: String,
    mutation: String,
    expected_error: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Artifact {
    path: String,
    logical_id: String,
    encoding: String,
    file_bytes: usize,
    decoded_bytes: usize,
    sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DayKey {
    plugboard: Vec<u8>,
    forward: Vec<Vec<u8>>,
    reverse: Vec<Vec<u8>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MessageKey {
    rotor_indices: [usize; 4],
    positions: [u8; 4],
    lfsr_seed: u64,
    center_mask_key: Vec<u8>,
}

#[derive(Debug, Clone)]
struct Wiring {
    plugboard: Vec<u8>,
    forward: [Vec<u8>; 4],
    reverse: [Vec<u8>; 4],
}

struct PurposeStream {
    key: [u8; 64],
    block_domain: Vec<u8>,
    counter: u64,
    buffer: [u8; 64],
    offset: usize,
}

impl PurposeStream {
    fn new(ikm: &[u8], salt: &[u8], purpose: &str) -> Result<Self> {
        validate_purpose(purpose)?;
        let domain = domain(purpose);
        let mut key_info = domain.clone();
        key_info.push(0);
        key_info.extend_from_slice(b"stream-key");
        let key_bytes = hkdf_sha512(ikm, salt, &key_info, 64)?;
        let key: [u8; 64] = key_bytes
            .try_into()
            .map_err(|_| error("purpose stream key is not 64 bytes"))?;
        let mut block_domain = domain;
        block_domain.push(0);
        block_domain.extend_from_slice(b"stream-block");
        Ok(Self {
            key,
            block_domain,
            counter: 0,
            buffer: [0; 64],
            offset: 64,
        })
    }

    fn read_byte(&mut self) -> Result<u8> {
        if self.offset == self.buffer.len() {
            if self.counter == u64::MAX {
                return Err(error("purpose stream counter exhausted"));
            }
            let mut message = self.block_domain.clone();
            message.push(0);
            message.extend_from_slice(&self.counter.to_be_bytes());
            self.buffer = hmac_sha512(&self.key, &message);
            self.offset = 0;
            self.counter += 1;
        }
        let value = self.buffer[self.offset];
        self.offset += 1;
        Ok(value)
    }

    fn read(&mut self, count: usize) -> Result<Vec<u8>> {
        let mut output = Vec::with_capacity(count);
        for _ in 0..count {
            output.push(self.read_byte()?);
        }
        Ok(output)
    }

    fn read_u16_be(&mut self) -> Result<u16> {
        Ok((u16::from(self.read_byte()?) << 8) | u16::from(self.read_byte()?))
    }

    fn read_u64_le(&mut self) -> Result<u64> {
        let mut bytes = [0_u8; 8];
        for byte in &mut bytes {
            *byte = self.read_byte()?;
        }
        Ok(u64::from_le_bytes(bytes))
    }

    fn sample(&mut self, upper_bound: usize) -> Result<usize> {
        if !(1..=65_536).contains(&upper_bound) {
            return Err(error(format!("invalid sampler bound {upper_bound}")));
        }
        let limit = 65_536 - (65_536 % upper_bound);
        loop {
            let value = usize::from(self.read_u16_be()?);
            if value < limit {
                return Ok(value % upper_bound);
            }
        }
    }
}

#[derive(Clone)]
struct Machine {
    wiring: Wiring,
    center_mask_key: Vec<u8>,
    lfsr: u64,
    positions: [u8; 4],
    counter: u64,
    cached_block_counter: Option<u64>,
    cached_block: [u8; 32],
}

struct Trace {
    input: u8,
    output: u8,
    lfsr_before: u64,
    lfsr_after: u64,
    positions_before: [u8; 4],
    positions_after: [u8; 4],
    step_mask: u8,
    counter_before: u64,
    counter_after: u64,
    center_mask: u8,
    center_input: u8,
    center_output: u8,
}

impl Machine {
    fn new(wiring: Wiring, message: &MessageKey) -> Result<Self> {
        if message.lfsr_seed == 0 {
            return Err(error("external zero LFSR state"));
        }
        if message.center_mask_key.len() != 32 {
            return Err(error("center-mask key is not 32 bytes"));
        }
        Ok(Self {
            wiring,
            center_mask_key: message.center_mask_key.clone(),
            lfsr: message.lfsr_seed,
            positions: message.positions,
            counter: 0,
            cached_block_counter: None,
            cached_block: [0; 32],
        })
    }

    fn process(&mut self, input: u8) -> Result<Trace> {
        if self.counter == u64::MAX {
            return Err(error("absolute byte counter exhausted"));
        }
        let counter_before = self.counter;
        let lfsr_before = self.lfsr;
        let positions_before = self.positions;
        let center_mask = self.center_mask()?;
        let (output, center_input, center_output) = self.scramble(input, center_mask);
        let steps = step_mask(self.lfsr);
        let mut step_bits = 0_u8;
        for (index, enabled) in steps.into_iter().enumerate() {
            if enabled {
                self.positions[index] = self.positions[index].wrapping_add(1);
                step_bits |= 1 << index;
            }
        }
        self.lfsr = lfsr_next(self.lfsr);
        self.counter += 1;
        Ok(Trace {
            input,
            output,
            lfsr_before,
            lfsr_after: self.lfsr,
            positions_before,
            positions_after: self.positions,
            step_mask: step_bits,
            counter_before,
            counter_after: self.counter,
            center_mask,
            center_input,
            center_output,
        })
    }

    fn center_mask(&mut self) -> Result<u8> {
        let block_counter = self.counter / 32;
        if self.cached_block_counter != Some(block_counter) {
            let mut message = domain("center-mask/block");
            message.push(0);
            message.extend_from_slice(&block_counter.to_be_bytes());
            self.cached_block = hmac_sha256(&self.center_mask_key, &message);
            self.cached_block_counter = Some(block_counter);
        }
        Ok(self.cached_block[(self.counter % 32) as usize])
    }

    fn scramble(&self, input: u8, center_mask: u8) -> (u8, u8, u8) {
        let pb = self.wiring.plugboard[input as usize];
        let r1 = lookup(&self.wiring.forward[0], pb, self.positions[0]);
        let r2 = lookup(&self.wiring.forward[1], r1, self.positions[1]);
        let r3 = lookup(&self.wiring.forward[2], r2, self.positions[2]);
        let r4 = lookup(&self.wiring.forward[3], r3, self.positions[3]);
        let center_output = r4 ^ center_mask;
        let rr4 = lookup(&self.wiring.reverse[3], center_output, self.positions[3]);
        let rr3 = lookup(&self.wiring.reverse[2], rr4, self.positions[2]);
        let rr2 = lookup(&self.wiring.reverse[1], rr3, self.positions[1]);
        let rr1 = lookup(&self.wiring.reverse[0], rr2, self.positions[0]);
        (self.wiring.plugboard[rr1 as usize], r4, center_output)
    }
}

fn append_swift_canonical_json(value: &Value, depth: usize, output: &mut String) -> Result<()> {
    match value {
        Value::Null => output.push_str("null"),
        Value::Bool(value) => output.push_str(if *value { "true" } else { "false" }),
        Value::Number(value) => output.push_str(&value.to_string()),
        Value::String(value) => output.push_str(
            &serde_json::to_string(value)
                .map_err(|source| error(format!("cannot encode JSON string: {source}")))?,
        ),
        Value::Array(values) => {
            if values.is_empty() {
                output.push_str("[]");
            } else {
                output.push_str("[\n");
                for (index, element) in values.iter().enumerate() {
                    output.push_str(&"  ".repeat(depth + 1));
                    append_swift_canonical_json(element, depth + 1, output)?;
                    if index + 1 != values.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                output.push_str(&"  ".repeat(depth));
                output.push(']');
            }
        }
        Value::Object(values) => {
            if values.is_empty() {
                output.push_str("{}");
            } else {
                output.push_str("{\n");
                let mut keys: Vec<&String> = values.keys().collect();
                keys.sort_unstable();
                for (index, key) in keys.iter().enumerate() {
                    output.push_str(&"  ".repeat(depth + 1));
                    output
                        .push_str(&serde_json::to_string(key).map_err(|source| {
                            error(format!("cannot encode JSON key: {source}"))
                        })?);
                    output.push_str(" : ");
                    append_swift_canonical_json(&values[*key], depth + 1, output)?;
                    if index + 1 != keys.len() {
                        output.push(',');
                    }
                    output.push('\n');
                }
                output.push_str(&"  ".repeat(depth));
                output.push('}');
            }
        }
    }
    Ok(())
}

fn validate_swift_canonical_json(data: &[u8]) -> Result<()> {
    let value: Value = serde_json::from_slice(data)
        .map_err(|source| error(format!("invalid fixture-v5 JSON: {source}")))?;
    let mut canonical = String::new();
    append_swift_canonical_json(&value, 0, &mut canonical)?;
    canonical.push('\n');
    if canonical.as_bytes() != data {
        return Err(error(
            "manifest is not canonical sorted pretty JSON with one trailing LF",
        ));
    }
    Ok(())
}

fn required_artifact_bindings() -> Vec<String> {
    fn binding(path: &str, logical_id: &str, encoding: &str) -> String {
        format!("{path}\0{logical_id}\0{encoding}")
    }
    fn add_raw_and_hex(bindings: &mut Vec<String>, logical_id: &str, stem: &str) {
        bindings.push(binding(
            &format!("artifacts/{stem}.bin"),
            logical_id,
            "raw_v1",
        ));
        bindings.push(binding(
            &format!("artifacts/{stem}.hex"),
            logical_id,
            "lower_hex_lf_v1",
        ));
    }

    let mut bindings = Vec::new();
    add_raw_and_hex(&mut bindings, "canonical_profile", "canonical-profile");
    add_raw_and_hex(&mut bindings, "ciphertext", "ciphertext");
    add_raw_and_hex(&mut bindings, "plaintext", "plaintext");
    for table in [
        "plugboard",
        "r1_fwd",
        "r1_rev",
        "r2_fwd",
        "r2_rev",
        "r3_fwd",
        "r3_rev",
        "r4_fwd",
        "r4_rev",
    ] {
        add_raw_and_hex(
            &mut bindings,
            &format!("table_{table}"),
            &format!("tables/{table}"),
        );
    }
    bindings.push(binding(
        "artifacts/recurrence-basis.csv",
        "recurrence_basis",
        "ascii_lf_v1",
    ));
    bindings.push(binding(
        "artifacts/stream-trace.csv",
        "stream_trace",
        "ascii_lf_v1",
    ));
    bindings.sort();
    bindings
}

fn validate_artifact_bindings(artifacts: &[Artifact]) -> Result<()> {
    let actual: Vec<String> = artifacts
        .iter()
        .map(|artifact| {
            format!(
                "{}\0{}\0{}",
                artifact.path, artifact.logical_id, artifact.encoding
            )
        })
        .collect();
    if actual != required_artifact_bindings() {
        return Err(error(
            "fixture-v5 artifact bindings do not match the frozen schema",
        ));
    }
    Ok(())
}

pub fn verify_fixture(bundle_directory: &Path) -> Result<V3VerificationReport> {
    require_directory(bundle_directory)?;
    let root_entries = read_entry_names(bundle_directory)?;
    let expected_root = BTreeSet::from([MANIFEST_NAME.to_owned(), "artifacts".to_owned()]);
    if root_entries != expected_root {
        return Err(error(format!(
            "unexpected fixture root layout: {root_entries:?}"
        )));
    }
    let manifest_path = bundle_directory.join(MANIFEST_NAME);
    let manifest_data = read_bounded_regular(&manifest_path, MANIFEST_LIMIT)?;
    validate_swift_canonical_json(&manifest_data)?;
    let fixture: Fixture = serde_json::from_slice(&manifest_data)
        .map_err(|source| error(format!("invalid strict fixture-v5 JSON: {source}")))?;
    validate_identity(&fixture)?;
    validate_artifact_bindings(&fixture.artifacts)?;

    let mut expected_paths = BTreeSet::new();
    let mut logical = BTreeMap::<String, Vec<u8>>::new();
    let mut seen_logical_encodings = BTreeSet::new();
    let mut total = 0_usize;
    for descriptor in &fixture.artifacts {
        validate_artifact_path(&descriptor.path)?;
        if !expected_paths.insert(descriptor.path.clone()) {
            return Err(error(format!(
                "duplicate artifact path {}",
                descriptor.path
            )));
        }
        if !seen_logical_encodings
            .insert(format!("{}|{}", descriptor.logical_id, descriptor.encoding))
        {
            return Err(error("duplicate logical artifact encoding"));
        }
        let data = read_bounded_regular(&bundle_directory.join(&descriptor.path), ARTIFACT_LIMIT)?;
        total = total
            .checked_add(data.len())
            .ok_or_else(|| error("artifact byte total overflow"))?;
        if total > TOTAL_ARTIFACT_LIMIT {
            return Err(error("artifact aggregate exceeds 64 MiB"));
        }
        if data.len() != descriptor.file_bytes {
            return Err(error(format!(
                "artifact size mismatch: {}",
                descriptor.path
            )));
        }
        if sha256_hex(&data) != descriptor.sha256 {
            return Err(error(format!(
                "artifact hash mismatch: {}",
                descriptor.path
            )));
        }
        let decoded = decode_artifact(descriptor, &data)?;
        if let Some(prior) = logical.get(&descriptor.logical_id) {
            if prior != &decoded {
                return Err(error(format!(
                    "duplicate artifact mismatch: {}",
                    descriptor.logical_id
                )));
            }
        } else {
            logical.insert(descriptor.logical_id.clone(), decoded);
        }
    }
    verify_artifact_layout(&bundle_directory.join("artifacts"), &expected_paths)?;

    let canonical = logical
        .get("canonical_profile")
        .ok_or_else(|| error("missing canonical profile artifact"))?;
    if canonical.len() != 2161 || sha256_hex(canonical) != EXPECTED_PROFILE_SHA256 {
        return Err(error("canonical profile artifact mismatch"));
    }
    if decode_hex_exact(
        &fixture.profile_binding.canonical_profile_hex,
        Some(canonical.len()),
        "canonical_profile_hex",
    )? != *canonical
    {
        return Err(error("embedded canonical profile differs from artifact"));
    }

    let day_ikm = decode_hex_exact(&fixture.inputs.day_ikm_hex, None, "day_ikm_hex")?;
    let day_salt = decode_hex_exact(&fixture.inputs.day_salt_hex, None, "day_salt_hex")?;
    let message_ikm = decode_hex_exact(&fixture.inputs.message_ikm_hex, None, "message_ikm_hex")?;
    let nonce = decode_hex_exact(&fixture.inputs.nonce_hex, Some(16), "nonce_hex")?;
    let day = derive_day_key(&day_ikm, &day_salt)?;
    let message = derive_message_key(&message_ikm, &nonce)?;
    validate_derivation(
        &fixture,
        &logical,
        &day_ikm,
        &day_salt,
        &message_ikm,
        &nonce,
        &day,
        &message,
    )?;
    let wiring = active_wiring(&day, &message)?;
    validate_recurrence(&fixture, &logical)?;
    validate_stream(&fixture, &logical, wiring, &message)?;
    validate_negative_vector_declarations(&fixture.negative_vectors)?;

    Ok(V3VerificationReport {
        compatibility_key: fixture.identity.compatibility_key.clone(),
        profile_sha256: fixture.identity.profile_sha256.clone(),
        stream_bytes: fixture.stream_kat.byte_count,
        artifact_count: fixture.artifacts.len(),
        recurrence_basis_count: 64,
        negative_vector_declaration_count: fixture.negative_vectors.len(),
        reciprocal_decrypt_verified: true,
    })
}

fn validate_identity(fixture: &Fixture) -> Result<()> {
    if fixture.schema.name != "E256-FIXTURE-5" || fixture.schema.version != 5 {
        return Err(error("wrong fixture-v5 schema"));
    }
    let identity = &fixture.identity;
    if identity.family != "E256"
        || identity.suite_version != 3
        || identity.generation != 0
        || identity.fixture_schema_version != 5
        || identity.profile_sha256 != EXPECTED_PROFILE_SHA256
        || identity.compatibility_key != EXPECTED_COMPATIBILITY_KEY
    {
        return Err(error("wrong E256-v3 compatibility tuple"));
    }
    let profile = &fixture.profile_binding;
    if profile.canonical_encoding != "e256_key_value_lf_v1"
        || profile.canonical_profile_bytes != 2161
        || profile.canonical_profile_sha256 != EXPECTED_PROFILE_SHA256
    {
        return Err(error("wrong canonical profile binding"));
    }
    let semantics = &fixture.semantics;
    let expected = [
        (
            &semantics.lfsr_transition,
            "right_shift_lsb_galois_d800000000000000",
        ),
        (
            &semantics.update_order,
            "derive_prestep_mask_and_counter_mask_scramble_then_step_and_increment",
        ),
        (
            &semantics.center_construction,
            "conjugated_xor_counter_prf_v1",
        ),
        (&semantics.center_mask_prf, "hmac_sha256_32_byte_blocks_v1"),
        (
            &semantics.center_mask_counter,
            "uint64_be_block_counter_start_0",
        ),
        (
            &semantics.center_mask_extraction,
            "digest_byte_i_mod_32_allow_zero",
        ),
        (
            &semantics.center_map_order,
            "plugboard_forward_rotors_xor_mask_reverse_rotors_plugboard_v1",
        ),
        (&semantics.domain_encoding, "e256_ascii_path_v1"),
        (&semantics.kdf, "hkdf_sha512_rfc5869_v1"),
        (
            &semantics.purpose_stream,
            "hmac_sha512_purpose_u64be_counter_v1",
        ),
        (&semantics.bounded_sampler, "u16be_reject_high_v1"),
        (
            &semantics.zero_policy,
            "external_reject_derive_retry_u64le_v1",
        ),
        (
            &semantics.plugboard_policy,
            "fixed_point_free_involution_v1",
        ),
        (&semantics.rotor_policy, "permutation_inverse_pair_v1"),
        (
            &semantics.rotor_selection,
            "four_distinct_without_replacement_v1",
        ),
        (
            &semantics.raw_security_target,
            "nonce_respecting_ind_cpa_target_conditional_hkdf_hmac_prf",
        ),
        (
            &semantics.envelope_target,
            "encrypt_then_mac_hmac_sha256_independent_keys_v1",
        ),
        (&semantics.real_data_policy, "standard_aead_required"),
    ];
    for (actual, expected) in expected {
        if actual != expected {
            return Err(error(format!("semantic identifier mismatch: {actual}")));
        }
    }
    if fixture.inputs.plaintext_generator != "byte_i=(73*i xor (i>>2)) mod 256" {
        return Err(error("wrong plaintext generator"));
    }
    let expected_domains: Vec<NamedValue> = frozen_purposes()
        .into_iter()
        .map(|purpose| NamedValue {
            value: String::from_utf8(domain(&purpose)).expect("domain is ASCII"),
            name: purpose,
        })
        .collect();
    if profile.domains != expected_domains {
        return Err(error("profile domain registry mismatch"));
    }
    Ok(())
}

fn derive_day_key(ikm: &[u8], salt: &[u8]) -> Result<DayKey> {
    let mut plugboard_stream = PurposeStream::new(ikm, salt, "day/plugboard")?;
    let plug_order = fisher_yates(256, &mut plugboard_stream)?;
    let mut plugboard = vec![0_u8; 256];
    for pair in (0..256).step_by(2) {
        let left = plug_order[pair];
        let right = plug_order[pair + 1];
        plugboard[left] = right as u8;
        plugboard[right] = left as u8;
    }
    let mut forward = Vec::with_capacity(16);
    let mut reverse = Vec::with_capacity(16);
    for rotor in 0..16 {
        let purpose = format!("day/rotor/{rotor:02}");
        let mut stream = PurposeStream::new(ikm, salt, &purpose)?;
        let order = fisher_yates(256, &mut stream)?;
        let mut fwd = vec![0_u8; 256];
        let mut rev = vec![0_u8; 256];
        for (source, destination) in order.into_iter().enumerate() {
            fwd[source] = destination as u8;
            rev[destination] = source as u8;
        }
        forward.push(fwd);
        reverse.push(rev);
    }
    let day = DayKey {
        plugboard,
        forward,
        reverse,
    };
    validate_day(&day)?;
    Ok(day)
}

fn derive_message_key(ikm: &[u8], nonce: &[u8]) -> Result<MessageKey> {
    if nonce.len() != 16 {
        return Err(error("nonce is not 16 bytes"));
    }
    let mut selection = PurposeStream::new(ikm, nonce, "message/rotor-selection")?;
    let mut available: Vec<usize> = (0..16).collect();
    let mut selected = [0_usize; 4];
    for value in &mut selected {
        let index = selection.sample(available.len())?;
        *value = available.remove(index);
    }
    let mut position_stream = PurposeStream::new(ikm, nonce, "message/positions")?;
    let positions: [u8; 4] = position_stream
        .read(4)?
        .try_into()
        .map_err(|_| error("position stream is not four bytes"))?;
    let mut lfsr_stream = PurposeStream::new(ikm, nonce, "message/lfsr-seed")?;
    let lfsr_seed = loop {
        let candidate = lfsr_stream.read_u64_le()?;
        if candidate != 0 {
            break candidate;
        }
    };
    let center_mask_key = hkdf_sha512(ikm, nonce, &domain("message/center-mask-key"), 32)?;
    Ok(MessageKey {
        rotor_indices: selected,
        positions,
        lfsr_seed,
        center_mask_key,
    })
}

fn validate_day(day: &DayKey) -> Result<()> {
    validate_permutation(&day.plugboard, "plugboard")?;
    for index in 0..256 {
        if usize::from(day.plugboard[usize::from(day.plugboard[index])]) != index {
            return Err(error(format!("plugboard involution failure at {index}")));
        }
        if usize::from(day.plugboard[index]) == index {
            return Err(error(format!("plugboard fixed point at {index}")));
        }
    }
    if day.forward.len() != 16 || day.reverse.len() != 16 {
        return Err(error("day rotor pool is not 16 pairs"));
    }
    let mut seen = BTreeSet::new();
    for rotor in 0..16 {
        validate_permutation(&day.forward[rotor], "rotor forward")?;
        validate_permutation(&day.reverse[rotor], "rotor reverse")?;
        if !seen.insert(day.forward[rotor].clone()) {
            return Err(error(format!("duplicate day rotor {rotor}")));
        }
        for index in 0..256 {
            if usize::from(day.reverse[rotor][usize::from(day.forward[rotor][index])]) != index
                || usize::from(day.forward[rotor][usize::from(day.reverse[rotor][index])]) != index
            {
                return Err(error(format!("rotor inverse failure {rotor}:{index}")));
            }
        }
    }
    Ok(())
}

fn active_wiring(day: &DayKey, message: &MessageKey) -> Result<Wiring> {
    let unique: BTreeSet<usize> = message.rotor_indices.into_iter().collect();
    if unique.len() != 4 || message.rotor_indices.iter().any(|index| *index >= 16) {
        return Err(error(
            "message rotor indices are not four distinct pool entries",
        ));
    }
    Ok(Wiring {
        plugboard: day.plugboard.clone(),
        forward: message
            .rotor_indices
            .map(|index| day.forward[index].clone()),
        reverse: message
            .rotor_indices
            .map(|index| day.reverse[index].clone()),
    })
}

#[allow(clippy::too_many_arguments)]
fn validate_derivation(
    fixture: &Fixture,
    logical: &BTreeMap<String, Vec<u8>>,
    day_ikm: &[u8],
    day_salt: &[u8],
    message_ikm: &[u8],
    nonce: &[u8],
    day: &DayKey,
    message: &MessageKey,
) -> Result<()> {
    let mut vectors = Vec::new();
    for purpose in stream_purposes() {
        let (ikm, salt) = if purpose.starts_with("day/") {
            (day_ikm, day_salt)
        } else {
            (message_ikm, nonce)
        };
        let mut stream = PurposeStream::new(ikm, salt, &purpose)?;
        vectors.push(PurposeVector {
            purpose,
            first_64_hex: hex(&stream.read(64)?),
        });
    }
    if fixture.derivation.purpose_vectors != vectors {
        return Err(error("purpose-stream intermediate mismatch"));
    }
    let day_tables = day_tables(day);
    let day_digests: Vec<NamedDigest> = day_tables
        .iter()
        .map(|(name, data)| NamedDigest {
            name: name.clone(),
            sha256: sha256_hex(data),
        })
        .collect();
    if fixture.derivation.day_table_digests != day_digests {
        return Err(error("day table digest mismatch"));
    }
    let wiring = active_wiring(day, message)?;
    let active = active_tables(&wiring);
    let active_digests: Vec<NamedDigest> = active
        .iter()
        .map(|(name, data)| NamedDigest {
            name: name.clone(),
            sha256: sha256_hex(data),
        })
        .collect();
    if fixture.derivation.active_table_digests != active_digests {
        return Err(error("active table digest mismatch"));
    }
    for (name, data) in active {
        let logical_name = format!("table_{name}");
        if logical.get(&logical_name) != Some(&data) {
            return Err(error(format!("active table artifact mismatch: {name}")));
        }
    }
    if fixture.derivation.rotor_indices != message.rotor_indices
        || decode_hex_exact(&fixture.derivation.positions_hex, Some(4), "positions_hex")?
            != message.positions
        || fixture.derivation.lfsr_seed_hex != format!("{:016x}", message.lfsr_seed)
        || decode_hex_exact(
            &fixture.derivation.center_mask_key_hex,
            Some(32),
            "center_mask_key_hex",
        )? != message.center_mask_key
    {
        return Err(error("message derivation mismatch"));
    }
    Ok(())
}

fn validate_recurrence(fixture: &Fixture, logical: &BTreeMap<String, Vec<u8>>) -> Result<()> {
    if fixture.recurrence_vectors.basis_artifact != "artifacts/recurrence-basis.csv" {
        return Err(error("wrong recurrence basis path"));
    }
    let mut expected = String::from("bit,start,next,previous_of_next\n");
    for bit in 0..64 {
        let start = 1_u64 << bit;
        let next = lfsr_next(start);
        let previous = lfsr_previous(next);
        expected.push_str(&format!("{bit},{start:016x},{next:016x},{previous:016x}\n"));
    }
    if logical.get("recurrence_basis").map(Vec::as_slice) != Some(expected.as_bytes()) {
        return Err(error("recurrence 64-basis artifact mismatch"));
    }
    let seed = parse_hex_u64(&fixture.recurrence_vectors.seed_hex, "recurrence seed")?;
    let mut state = seed;
    let mut checkpoints = Vec::new();
    for clock in 0..=1024 {
        if CHECKPOINTS.contains(&clock) {
            checkpoints.push(RecurrenceCheckpoint {
                clock,
                state_hex: format!("{state:016x}"),
            });
        }
        if clock != 1024 {
            state = lfsr_next(state);
        }
    }
    if fixture.recurrence_vectors.checkpoints != checkpoints {
        return Err(error("recurrence checkpoint mismatch"));
    }
    Ok(())
}

fn validate_stream(
    fixture: &Fixture,
    logical: &BTreeMap<String, Vec<u8>>,
    wiring: Wiring,
    message: &MessageKey,
) -> Result<()> {
    let kat = &fixture.stream_kat;
    if kat.byte_count < 1024
        || kat.plaintext_artifact != "artifacts/plaintext.bin"
        || kat.ciphertext_artifact != "artifacts/ciphertext.bin"
        || kat.trace_artifact != "artifacts/stream-trace.csv"
        || !kat.reciprocal_decrypt
    {
        return Err(error("stream KAT metadata mismatch"));
    }
    let plaintext = logical
        .get("plaintext")
        .ok_or_else(|| error("missing plaintext artifact"))?;
    let ciphertext = logical
        .get("ciphertext")
        .ok_or_else(|| error("missing ciphertext artifact"))?;
    if plaintext.len() != kat.byte_count || ciphertext.len() != kat.byte_count {
        return Err(error("stream KAT artifact length mismatch"));
    }
    for (index, value) in plaintext.iter().enumerate() {
        let expected = ((index * 73) ^ (index >> 2)) as u8;
        if *value != expected {
            return Err(error(format!("plaintext generator mismatch at {index}")));
        }
    }
    let mut machine = Machine::new(wiring.clone(), message)?;
    let mut produced = Vec::with_capacity(plaintext.len());
    let mut trace_text = String::from(
        "byte,input,output,counter_before,lfsr_before,positions_before,step_mask,center_mask,center_input,center_output,counter_after,lfsr_after,positions_after\n",
    );
    let mut checkpoints = vec![state_checkpoint(0, &machine)];
    for (index, input) in plaintext.iter().copied().enumerate() {
        let trace = machine.process(input)?;
        produced.push(trace.output);
        trace_text.push_str(&trace_line(index, &trace));
        trace_text.push('\n');
        if CHECKPOINTS[1..].contains(&(index + 1)) {
            checkpoints.push(state_checkpoint(index + 1, &machine));
        }
    }
    if produced != *ciphertext {
        return Err(error("stream ciphertext mismatch"));
    }
    if logical.get("stream_trace").map(Vec::as_slice) != Some(trace_text.as_bytes()) {
        return Err(error("full stream trace mismatch"));
    }
    if kat.state_checkpoints != checkpoints {
        return Err(error("stream state checkpoint mismatch"));
    }
    let mut decryptor = Machine::new(wiring, message)?;
    let mut recovered = Vec::with_capacity(ciphertext.len());
    for value in ciphertext {
        recovered.push(decryptor.process(*value)?.output);
    }
    if recovered != *plaintext {
        return Err(error("reciprocal decrypt mismatch"));
    }
    Ok(())
}

fn validate_negative_vector_declarations(vectors: &[NegativeVector]) -> Result<()> {
    let expected = [
        ("duplicate_json_key", "duplicateJSONKey"),
        ("unknown_json_key", "unknownJSONKey"),
        ("uppercase_hex", "invalidHex"),
        ("external_zero_lfsr", "zeroLFSRState"),
        ("duplicate_rotor", "duplicateRotorIndex"),
        ("rotor_out_of_range", "rotorIndexOutOfRange"),
        ("plugboard_fixed_point", "plugboardFixedPoint"),
        ("table_not_permutation", "notPermutation"),
        ("rotor_inverse_mismatch", "rotorPairNotInverse"),
        ("artifact_hash_mismatch", "artifactHash"),
        ("duplicate_format_mismatch", "duplicateArtifactMismatch"),
        ("extra_file", "unexpectedLayout"),
        ("symlink_artifact", "symlink"),
    ];
    if vectors.len() != expected.len() {
        return Err(error("wrong negative-vector count"));
    }
    for (vector, (identifier, expected_error)) in vectors.iter().zip(expected) {
        if vector.id != identifier
            || vector.expected_error != expected_error
            || vector.mutation.is_empty()
        {
            return Err(error(format!("negative vector mismatch: {}", vector.id)));
        }
    }
    Ok(())
}

fn fisher_yates(count: usize, stream: &mut PurposeStream) -> Result<Vec<usize>> {
    if count == 0 || count > 65_536 {
        return Err(error("invalid Fisher-Yates count"));
    }
    let mut items: Vec<usize> = (0..count).collect();
    for index in (1..count).rev() {
        let other = stream.sample(index + 1)?;
        items.swap(index, other);
    }
    Ok(items)
}

fn validate_permutation(table: &[u8], name: &str) -> Result<()> {
    if table.len() != 256 {
        return Err(error(format!("{name} table length is not 256")));
    }
    let values: BTreeSet<u8> = table.iter().copied().collect();
    if values.len() != 256 {
        return Err(error(format!("{name} is not a permutation")));
    }
    Ok(())
}

fn lookup(table: &[u8], value: u8, offset: u8) -> u8 {
    table[value.wrapping_add(offset) as usize].wrapping_sub(offset)
}

fn lfsr_next(state: u64) -> u64 {
    (state >> 1) ^ if state & 1 == 1 { LFSR_MASK } else { 0 }
}

fn lfsr_previous(state: u64) -> u64 {
    let feedback = state >> 63;
    let unmasked = state ^ if feedback == 1 { LFSR_MASK } else { 0 };
    (unmasked << 1) | feedback
}

const COMPONENTS: [(u64, u64); 8] = [
    (0x5b55_a967_2ee2_2418, 0xa39d_51af_d62a_dcd0),
    (0x7da0_c6a4_7da6_136c, 0x2893_4ec6_d377_6da0),
    (0x0ed1_6430_b978_fe9a, 0x5d60_22ec_0beb_7876),
    (0xabde_9a6a_d30f_2300, 0x61ba_65b5_723f_93c0),
    (0x878c_a934_7804_de34, 0x6e83_562d_6ef4_ded2),
    (0xfd4c_4cb9_dac1_6b34, 0xa84c_3b64_8fc1_1ce9),
    (0x5957_f09a_2523_906a, 0x4674_f9a0_94fa_dda7),
    (0x284e_79e6_de40_8a6a, 0x355c_4728_f7ca_7c6a),
];

const FOLD_TAPS: [[u8; 16]; 4] = [
    [9, 43, 15, 16, 21, 39, 48, 5, 38, 28, 41, 51, 31, 30, 63, 52],
    [42, 13, 53, 32, 1, 11, 36, 50, 0, 45, 19, 22, 6, 23, 12, 29],
    [61, 40, 47, 20, 18, 44, 34, 59, 27, 8, 25, 55, 33, 2, 17, 4],
    [10, 26, 60, 57, 62, 35, 54, 58, 46, 14, 7, 49, 24, 37, 56, 3],
];

fn component(index: usize, input: u8) -> bool {
    let (low, high) = COMPONENTS[index];
    if input < 64 {
        (low >> input) & 1 == 1
    } else {
        (high >> (input - 64)) & 1 == 1
    }
}

fn fold(state: u64, index: usize) -> bool {
    let taps = FOLD_TAPS[index];
    let mut left_input = 0_u8;
    let mut right_input = 0_u8;
    for bit in 0..7 {
        left_input |= (((state >> taps[bit + 1]) & 1) as u8) << bit;
        right_input |= (((state >> taps[bit + 9]) & 1) as u8) << bit;
    }
    let left_pivot = (state >> taps[0]) & 1 == 1;
    let right_pivot = (state >> taps[8]) & 1 == 1;
    let left = left_pivot ^ component(index * 2, left_input);
    let right = right_pivot ^ component(index * 2 + 1, right_input);
    left ^ right
}

fn step_mask(state: u64) -> [bool; 4] {
    [
        fold(state, 0),
        fold(state, 1),
        fold(state, 2),
        fold(state, 3),
    ]
}

fn state_checkpoint(byte: usize, machine: &Machine) -> StateCheckpoint {
    StateCheckpoint {
        byte,
        absolute_byte_counter: machine.counter,
        lfsr_hex: format!("{:016x}", machine.lfsr),
        positions_hex: hex(&machine.positions),
    }
}

fn trace_line(byte: usize, trace: &Trace) -> String {
    format!(
        "{byte},{:02x},{:02x},{:016x},{:016x},{},{:02x},{:02x},{:02x},{:02x},{:016x},{:016x},{}",
        trace.input,
        trace.output,
        trace.counter_before,
        trace.lfsr_before,
        hex(&trace.positions_before),
        trace.step_mask,
        trace.center_mask,
        trace.center_input,
        trace.center_output,
        trace.counter_after,
        trace.lfsr_after,
        hex(&trace.positions_after),
    )
}

fn day_tables(day: &DayKey) -> Vec<(String, Vec<u8>)> {
    let mut values = vec![("plugboard".to_owned(), day.plugboard.clone())];
    for rotor in 0..16 {
        values.push((format!("rotor_{rotor:02}_fwd"), day.forward[rotor].clone()));
        values.push((format!("rotor_{rotor:02}_rev"), day.reverse[rotor].clone()));
    }
    values
}

fn active_tables(wiring: &Wiring) -> Vec<(String, Vec<u8>)> {
    vec![
        ("plugboard".to_owned(), wiring.plugboard.clone()),
        ("r1_fwd".to_owned(), wiring.forward[0].clone()),
        ("r1_rev".to_owned(), wiring.reverse[0].clone()),
        ("r2_fwd".to_owned(), wiring.forward[1].clone()),
        ("r2_rev".to_owned(), wiring.reverse[1].clone()),
        ("r3_fwd".to_owned(), wiring.forward[2].clone()),
        ("r3_rev".to_owned(), wiring.reverse[2].clone()),
        ("r4_fwd".to_owned(), wiring.forward[3].clone()),
        ("r4_rev".to_owned(), wiring.reverse[3].clone()),
    ]
}

fn domain(purpose: &str) -> Vec<u8> {
    format!("E256/v3/gen0/{EXPECTED_PROFILE_SHA256}/{purpose}").into_bytes()
}

fn validate_purpose(purpose: &str) -> Result<()> {
    if frozen_purposes().iter().any(|value| value == purpose) {
        Ok(())
    } else {
        Err(error(format!("unregistered E256-v3 purpose {purpose}")))
    }
}

fn frozen_purposes() -> Vec<String> {
    let mut purposes = vec!["day/plugboard".to_owned()];
    purposes.extend((0..16).map(|index| format!("day/rotor/{index:02}")));
    purposes.extend(
        [
            "message/rotor-selection",
            "message/positions",
            "message/lfsr-seed",
            "message/center-mask-key",
            "center-mask/block",
            "envelope/encryption-key",
            "envelope/mac-key",
            "traffic/send",
            "traffic/receive",
            "handshake/transcript",
            "fixture/v5",
        ]
        .into_iter()
        .map(str::to_owned),
    );
    purposes
}

fn stream_purposes() -> Vec<String> {
    let mut purposes = vec!["day/plugboard".to_owned()];
    purposes.extend((0..16).map(|index| format!("day/rotor/{index:02}")));
    purposes.extend(
        [
            "message/rotor-selection",
            "message/positions",
            "message/lfsr-seed",
        ]
        .into_iter()
        .map(str::to_owned),
    );
    purposes
}

fn hkdf_sha512(ikm: &[u8], salt: &[u8], info: &[u8], length: usize) -> Result<Vec<u8>> {
    if length == 0 || length > 255 * 64 {
        return Err(error("invalid HKDF-SHA512 output length"));
    }
    let zero_salt = [0_u8; 64];
    let extract_salt = if salt.is_empty() {
        &zero_salt[..]
    } else {
        salt
    };
    let prk = hmac_sha512(extract_salt, ikm);
    let mut output = Vec::with_capacity(length);
    let mut previous = Vec::<u8>::new();
    let blocks = length.div_ceil(64);
    for counter in 1..=blocks {
        let mut message = previous;
        message.extend_from_slice(info);
        message.push(counter as u8);
        previous = hmac_sha512(&prk, &message).to_vec();
        output.extend_from_slice(&previous);
    }
    output.truncate(length);
    Ok(output)
}

fn hmac_sha512(key: &[u8], message: &[u8]) -> [u8; 64] {
    let mut normalized = [0_u8; 128];
    if key.len() > 128 {
        normalized[..64].copy_from_slice(&Sha512::digest(key));
    } else {
        normalized[..key.len()].copy_from_slice(key);
    }
    let mut inner_pad = [0x36_u8; 128];
    let mut outer_pad = [0x5c_u8; 128];
    for index in 0..128 {
        inner_pad[index] ^= normalized[index];
        outer_pad[index] ^= normalized[index];
    }
    let mut inner = Sha512::new();
    inner.update(inner_pad);
    inner.update(message);
    let inner_digest = inner.finalize();
    let mut outer = Sha512::new();
    outer.update(outer_pad);
    outer.update(inner_digest);
    outer.finalize().into()
}

fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    let mut normalized = [0_u8; 64];
    if key.len() > 64 {
        normalized[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        normalized[..key.len()].copy_from_slice(key);
    }
    let mut inner_pad = [0x36_u8; 64];
    let mut outer_pad = [0x5c_u8; 64];
    for index in 0..64 {
        inner_pad[index] ^= normalized[index];
        outer_pad[index] ^= normalized[index];
    }
    let mut inner = Sha256::new();
    inner.update(inner_pad);
    inner.update(message);
    let inner_digest = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(outer_pad);
    outer.update(inner_digest);
    outer.finalize().into()
}

fn decode_artifact(descriptor: &Artifact, data: &[u8]) -> Result<Vec<u8>> {
    match descriptor.encoding.as_str() {
        "raw_v1" => {
            if descriptor.decoded_bytes != data.len() {
                return Err(error(format!(
                    "raw artifact size mismatch: {}",
                    descriptor.path
                )));
            }
            Ok(data.to_vec())
        }
        "lower_hex_lf_v1" => {
            if data.last() != Some(&b'\n')
                || data[..data.len().saturating_sub(1)].contains(&b'\n')
                || data.contains(&b'\r')
            {
                return Err(error(format!(
                    "noncanonical hex artifact: {}",
                    descriptor.path
                )));
            }
            let text = std::str::from_utf8(&data[..data.len() - 1])
                .map_err(|_| error("hex artifact is not UTF-8"))?;
            decode_hex_exact(text, Some(descriptor.decoded_bytes), &descriptor.path)
        }
        "ascii_lf_v1" => {
            if descriptor.decoded_bytes != data.len()
                || data.last() != Some(&b'\n')
                || data.contains(&b'\r')
                || data
                    .iter()
                    .any(|byte| *byte != b'\n' && !(0x20..=0x7e).contains(byte))
            {
                return Err(error(format!(
                    "noncanonical ASCII artifact: {}",
                    descriptor.path
                )));
            }
            Ok(data.to_vec())
        }
        other => Err(error(format!("unknown artifact encoding {other}"))),
    }
}

fn decode_hex_exact(text: &str, expected: Option<usize>, field: &str) -> Result<Vec<u8>> {
    if !text.len().is_multiple_of(2)
        || text
            .as_bytes()
            .iter()
            .any(|byte| !byte.is_ascii_digit() && !(b'a'..=b'f').contains(byte))
        || expected.is_some_and(|length| text.len() != length * 2)
    {
        return Err(error(format!("invalid lowercase hex in {field}")));
    }
    let mut output = Vec::with_capacity(text.len() / 2);
    for pair in text.as_bytes().chunks_exact(2) {
        let high = hex_nibble(pair[0]).ok_or_else(|| error(format!("invalid hex in {field}")))?;
        let low = hex_nibble(pair[1]).ok_or_else(|| error(format!("invalid hex in {field}")))?;
        output.push((high << 4) | low);
    }
    Ok(output)
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        _ => None,
    }
}

fn parse_hex_u64(text: &str, field: &str) -> Result<u64> {
    if text.len() != 16 {
        return Err(error(format!("invalid u64 hex in {field}")));
    }
    u64::from_str_radix(text, 16).map_err(|_| error(format!("invalid u64 hex in {field}")))
}

fn hex(data: &[u8]) -> String {
    let mut output = String::with_capacity(data.len() * 2);
    for byte in data {
        use std::fmt::Write as _;
        write!(&mut output, "{byte:02x}").expect("writing to String cannot fail");
    }
    output
}

fn validate_artifact_path(path: &str) -> Result<()> {
    if !path.starts_with("artifacts/")
        || path.ends_with('/')
        || path.contains("//")
        || path.contains("..")
        || path.contains('\\')
        || !path.bytes().all(|byte| (0x20..=0x7e).contains(&byte))
    {
        return Err(error(format!("unsafe artifact path {path}")));
    }
    Ok(())
}

fn verify_artifact_layout(directory: &Path, expected: &BTreeSet<String>) -> Result<()> {
    require_directory(directory)?;
    let root = directory
        .parent()
        .ok_or_else(|| error("artifact directory has no parent"))?;
    let mut actual = BTreeSet::new();
    collect_regular_files(root, directory, &mut actual)?;
    if &actual != expected {
        return Err(error(format!(
            "artifact layout mismatch: actual={actual:?} expected={expected:?}"
        )));
    }
    Ok(())
}

fn collect_regular_files(
    root: &Path,
    directory: &Path,
    output: &mut BTreeSet<String>,
) -> Result<()> {
    for entry in fs::read_dir(directory)
        .map_err(|source| error(format!("cannot list {}: {source}", directory.display())))?
    {
        let entry =
            entry.map_err(|source| error(format!("cannot read directory entry: {source}")))?;
        let path = entry.path();
        let metadata = fs::symlink_metadata(&path)
            .map_err(|source| error(format!("cannot stat {}: {source}", path.display())))?;
        if metadata.file_type().is_symlink() {
            return Err(error(format!("refusing symlink {}", path.display())));
        }
        if metadata.is_dir() {
            collect_regular_files(root, &path, output)?;
        } else if metadata.is_file() {
            let relative = path
                .strip_prefix(root)
                .map_err(|_| error("artifact path escaped root"))?
                .to_string_lossy()
                .replace('\\', "/");
            output.insert(relative);
        } else {
            return Err(error(format!(
                "artifact is not a regular file: {}",
                path.display()
            )));
        }
    }
    Ok(())
}

fn require_directory(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|source| error(format!("cannot stat {}: {source}", path.display())))?;
    if metadata.file_type().is_symlink() {
        return Err(error(format!(
            "refusing symlink directory {}",
            path.display()
        )));
    }
    if !metadata.is_dir() {
        return Err(error(format!("expected directory at {}", path.display())));
    }
    Ok(())
}

fn read_bounded_regular(path: &Path, limit: usize) -> Result<Vec<u8>> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|source| error(format!("cannot stat {}: {source}", path.display())))?;
    if metadata.file_type().is_symlink() {
        return Err(error(format!("refusing symlink input {}", path.display())));
    }
    if !metadata.is_file() {
        return Err(error(format!(
            "expected regular file at {}",
            path.display()
        )));
    }
    let length: usize = metadata
        .len()
        .try_into()
        .map_err(|_| error("file length does not fit usize"))?;
    if length > limit {
        return Err(error(format!(
            "file exceeds size limit: {}",
            path.display()
        )));
    }
    read_regular_file(path)
}

fn read_entry_names(path: &Path) -> Result<BTreeSet<String>> {
    let mut names = BTreeSet::new();
    for entry in fs::read_dir(path)
        .map_err(|source| error(format!("cannot list {}: {source}", path.display())))?
    {
        let entry =
            entry.map_err(|source| error(format!("cannot read directory entry: {source}")))?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| error("fixture path is not UTF-8"))?;
        names.insert(name);
    }
    Ok(names)
}

fn error(message: impl Into<String>) -> ReferenceError {
    ReferenceError::new(message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_and_hkdf_match_complete_sha2_known_answers() {
        let key = vec![0x0b; 20];
        assert_eq!(
            hex(&hmac_sha256(&key, b"Hi There")),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
        assert_eq!(
            hex(&hmac_sha512(&key, b"Hi There")),
            concat!(
                "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde",
                "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"
            )
        );
        let okm = hkdf_sha512(
            &[0x0b; 22],
            &decode_hex_exact("000102030405060708090a0b0c", None, "salt").unwrap(),
            &decode_hex_exact("f0f1f2f3f4f5f6f7f8f9", None, "info").unwrap(),
            42,
        )
        .unwrap();
        assert_eq!(
            hex(&okm),
            "832390086cda71fb47625bb5ceb168e4c8e26a1a16ed34d9fc7fe92c1481579338da362cb8d9f925d7cb"
        );
    }

    #[test]
    fn canonical_json_rejects_reordered_and_alternate_whitespace() {
        let canonical = b"{\n  \"a\" : 1,\n  \"b\" : [\n    true\n  ]\n}\n";
        assert!(validate_swift_canonical_json(canonical).is_ok());
        assert!(
            validate_swift_canonical_json(b"{\n  \"b\" : [\n    true\n  ],\n  \"a\" : 1\n}\n")
                .is_err()
        );
        assert!(
            validate_swift_canonical_json(b"{\n  \"a\": 1,\n  \"b\": [\n    true\n  ]\n}\n")
                .is_err()
        );
    }

    #[test]
    fn rejection_map_has_equal_accepted_counts() {
        for bound in [3_usize, 5, 15, 255, 256] {
            let limit = 65_536 - (65_536 % bound);
            let mut counts = vec![0_usize; bound];
            for value in 0..limit {
                counts[value % bound] += 1;
            }
            assert!(counts.iter().all(|count| *count == counts[0]));
        }
    }
}
