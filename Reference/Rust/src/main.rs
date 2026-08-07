use helut_reference::e256::verify_kat;
use helut_reference::e256_v3::verify_fixture;
use helut_reference::yosys::verify_standard_fixtures;
use helut_reference::{ReferenceError, Result};
use std::collections::BTreeMap;
use std::env;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::ExitCode;

fn usage() -> &'static str {
    "usage:\n  helut-reference e256-kat --profile PATH --bundle DIR --receipt PATH\n  helut-reference e256-v3-kat --bundle DIR\n  helut-reference yosys-parity --full-adder PATH --counter PATH --toy-isa PATH"
}

fn parse_paths(arguments: &[OsString], allowed: &[&str]) -> Result<BTreeMap<String, PathBuf>> {
    if !arguments.len().is_multiple_of(2) {
        return Err(ReferenceError::new(usage()));
    }
    let mut parsed = BTreeMap::new();
    for pair in arguments.chunks_exact(2) {
        let flag = pair[0]
            .to_str()
            .ok_or_else(|| ReferenceError::new("option names must be UTF-8"))?;
        if !allowed.contains(&flag) {
            return Err(ReferenceError::new(format!(
                "unknown option {flag}\n{}",
                usage()
            )));
        }
        if parsed
            .insert(flag.to_owned(), PathBuf::from(&pair[1]))
            .is_some()
        {
            return Err(ReferenceError::new(format!("duplicate option {flag}")));
        }
    }
    for required in allowed {
        if !parsed.contains_key(*required) {
            return Err(ReferenceError::new(format!(
                "missing required option {required}\n{}",
                usage()
            )));
        }
    }
    Ok(parsed)
}

fn required_path<'a>(paths: &'a BTreeMap<String, PathBuf>, flag: &str) -> Result<&'a PathBuf> {
    paths
        .get(flag)
        .ok_or_else(|| ReferenceError::new(format!("missing required option {flag}")))
}

fn run() -> Result<()> {
    let mut arguments = env::args_os();
    let _program = arguments.next();
    let command = arguments
        .next()
        .and_then(|value| value.into_string().ok())
        .ok_or_else(|| ReferenceError::new(usage()))?;
    let rest: Vec<OsString> = arguments.collect();

    match command.as_str() {
        "e256-v3-kat" => {
            let paths = parse_paths(&rest, &["--bundle"])?;
            let report = verify_fixture(required_path(&paths, "--bundle")?)?;
            println!(
                "E256 fixture-v5 KAT PASS (internal consumer only): {} bytes, {} artifacts, {} recurrence basis rows, {} declared negative vectors, profile {}, reciprocal decrypt PASS",
                report.stream_bytes,
                report.artifact_count,
                report.recurrence_basis_count,
                report.negative_vector_declaration_count,
                report.profile_sha256
            );
        }
        "e256-kat" => {
            let paths = parse_paths(&rest, &["--profile", "--bundle", "--receipt"])?;
            let report = verify_kat(
                required_path(&paths, "--profile")?,
                required_path(&paths, "--bundle")?,
                required_path(&paths, "--receipt")?,
            )?;
            println!(
                "E256 fixture-v{} KAT PASS (internal consumer only): {} bytes, {} tables, {} trace files, {} artifacts, manifest {}, trace schema {}, profile {}, reciprocal decrypt PASS",
                report.fixture_schema_version,
                report.stream_bytes,
                report.table_count,
                report.trace_count,
                report.artifact_count,
                report.manifest_schema,
                report.trace_schema,
                report.profile_sha256
            );
        }
        "yosys-parity" => {
            let paths = parse_paths(&rest, &["--full-adder", "--counter", "--toy-isa"])?;
            let report = verify_standard_fixtures(
                required_path(&paths, "--full-adder")?,
                required_path(&paths, "--counter")?,
                required_path(&paths, "--toy-isa")?,
            )?;
            println!(
                "Yosys parity PASS: {}/8 full-adder rows, {} counter transitions, {} toy-ISA transitions",
                report.full_adder_rows, report.counter_transitions, report.toy_isa_transitions
            );
        }
        _ => return Err(ReferenceError::new(usage())),
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("helut-reference: {error}");
            ExitCode::from(2)
        }
    }
}
