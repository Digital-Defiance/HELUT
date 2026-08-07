use helut_reference::e256::{EXPECTED_PROFILE_SHA256, verify_kat};
use helut_reference::yosys::verify_standard_fixtures;
use std::path::PathBuf;

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn consumes_the_frozen_schema_4_e256_bundle() {
    let root = repository_root();
    let report = verify_kat(
        &root.join("Fixtures/enigma256_generation.json"),
        &root.join("Fixtures/enigma256_golden"),
        &root.join("logs/e256-v2-gen0-nlff-search.json"),
    )
    .expect("the checked-in E256 schema-4 KAT must verify");

    assert_eq!(report.profile_sha256, EXPECTED_PROFILE_SHA256);
    assert_eq!(
        report.compatibility_key,
        format!("E256/v2/gen0/{EXPECTED_PROFILE_SHA256}/fixture-v4")
    );
    assert_eq!(report.fixture_schema_version, 4);
    assert_eq!(report.manifest_schema, "E256-KAT-MANIFEST-4");
    assert_eq!(report.trace_schema, "E256-KAT-TRACE-4");
    assert_eq!(report.stream_bytes, 1_024);
    assert_eq!(report.artifact_count, 25);
    assert_eq!(report.table_count, 9);
    assert_eq!(report.trace_count, 10);
    assert_eq!(
        report.final_byte_counter,
        report.initial_byte_counter + report.stream_bytes as u64
    );
    assert!(report.reciprocal_decrypt_verified);
}

#[test]
fn matches_the_checked_in_yosys_examples() {
    let root = repository_root();
    let report = verify_standard_fixtures(
        &root.join("Generated/Netlists/Examples/netlist.json"),
        &root.join("Generated/Netlists/Examples/counter_netlist.json"),
        &root.join("Generated/Netlists/Examples/toy_isa_netlist.json"),
    )
    .expect("the checked-in Yosys examples must match their independent formulas");

    assert_eq!(report.full_adder_rows, 8);
    assert_eq!(report.counter_transitions, 16);
    assert_eq!(report.toy_isa_transitions, 1_024);
}
