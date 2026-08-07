use helut_reference::e256_v3::{
    EXPECTED_COMPATIBILITY_KEY, EXPECTED_PROFILE_SHA256, verify_fixture,
};
use std::path::PathBuf;

fn repository_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn independently_rederives_the_staged_fixture_v5_bundle() {
    let root = repository_root();
    let bundle = root.join(format!(
        "Fixtures/Staging/Enigma256/E256-v3-gen0-{EXPECTED_PROFILE_SHA256}-fixture-v5"
    ));
    let report = verify_fixture(&bundle).expect("the staged E256-v3 fixture-v5 bundle must verify");

    assert_eq!(report.profile_sha256, EXPECTED_PROFILE_SHA256);
    assert_eq!(report.compatibility_key, EXPECTED_COMPATIBILITY_KEY);
    assert_eq!(report.stream_bytes, 1_024);
    assert_eq!(report.artifact_count, 26);
    assert_eq!(report.recurrence_basis_count, 64);
    assert_eq!(report.negative_vector_declaration_count, 13);
    assert!(report.reciprocal_decrypt_verified);
}
