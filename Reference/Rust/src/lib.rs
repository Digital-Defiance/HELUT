//! Independent, portable CPU references for HELUT artifacts.
//!
//! This crate is intentionally read-only: it consumes frozen fixtures and
//! generated hardware artifacts, but has no emit, bless, or promotion API.

pub mod e256;
pub mod e256_v3;
pub mod yosys;

use serde::de::{DeserializeOwned, MapAccess, Visitor};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::marker::PhantomData;
use std::path::Path;

/// Error returned by strict reference parsers and verifiers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReferenceError {
    message: String,
}

impl ReferenceError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ReferenceError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ReferenceError {}

pub type Result<T> = std::result::Result<T, ReferenceError>;

pub(crate) fn read_regular_file(path: &Path) -> Result<Vec<u8>> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| ReferenceError::new(format!("cannot stat {}: {error}", path.display())))?;
    if metadata.file_type().is_symlink() {
        return Err(ReferenceError::new(format!(
            "refusing symlink input {}",
            path.display()
        )));
    }
    if !metadata.is_file() {
        return Err(ReferenceError::new(format!(
            "expected regular file at {}",
            path.display()
        )));
    }
    fs::read(path)
        .map_err(|error| ReferenceError::new(format!("cannot read {}: {error}", path.display())))
}

pub(crate) fn read_json<T: DeserializeOwned>(path: &Path) -> Result<T> {
    let data = read_regular_file(path)?;
    serde_json::from_slice(&data).map_err(|error| {
        ReferenceError::new(format!("invalid JSON in {}: {error}", path.display()))
    })
}

pub(crate) fn sha256_hex(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    let mut output = String::with_capacity(64);
    for byte in digest {
        use fmt::Write as _;
        write!(&mut output, "{byte:02x}").expect("writing to String cannot fail");
    }
    output
}

/// Serde field helper that rejects duplicate keys instead of silently keeping
/// one value. JSON objects that represent arbitrary Yosys names or manifest
/// paths use this helper; typed structs already reject duplicate fields.
pub(crate) fn deserialize_unique_btree_map<'de, D, K, V>(
    deserializer: D,
) -> std::result::Result<BTreeMap<K, V>, D::Error>
where
    D: serde::Deserializer<'de>,
    K: DeserializeOwned + Ord + fmt::Debug,
    V: serde::Deserialize<'de>,
{
    struct UniqueMapVisitor<K, V>(PhantomData<(K, V)>);

    impl<'de, K, V> Visitor<'de> for UniqueMapVisitor<K, V>
    where
        K: serde::Deserialize<'de> + Ord + fmt::Debug,
        V: serde::Deserialize<'de>,
    {
        type Value = BTreeMap<K, V>;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("a JSON object with unique keys")
        }

        fn visit_map<A>(self, mut access: A) -> std::result::Result<Self::Value, A::Error>
        where
            A: MapAccess<'de>,
        {
            let mut values = BTreeMap::new();
            while let Some((key, value)) = access.next_entry::<K, V>()? {
                if values.insert(key, value).is_some() {
                    return Err(serde::de::Error::custom("duplicate JSON object key"));
                }
            }
            Ok(values)
        }
    }

    deserializer.deserialize_map(UniqueMapVisitor(PhantomData))
}
