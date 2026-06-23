//! On-device persistence: the master seed in the OS secure store (Windows Credential
//! Manager / macOS Keychain / Linux Secret Service) — keys never leave the device, the
//! same rule the iOS Keychain and Android Keystore enforce — plus a small JSON prefs file
//! and the binary social-state blob on disk in the app data directory.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use base64::Engine as _;
use serde::{Deserialize, Serialize};

const SERVICE: &str = "com.blaineam.haven";
const SEED_ACCOUNT: &str = "master-seed";

/// Resolved app-data paths.
#[derive(Clone)]
pub struct Paths {
    pub root: PathBuf,
}

impl Paths {
    pub fn resolve() -> Result<Self> {
        let base = dirs::data_dir().ok_or_else(|| anyhow!("no data dir"))?;
        let root = base.join("Haven");
        fs::create_dir_all(&root).with_context(|| format!("create {}", root.display()))?;
        Ok(Self { root })
    }
    pub fn state_file(&self) -> PathBuf {
        self.root.join("haven_social_state.bin")
    }
    pub fn prefs_file(&self) -> PathBuf {
        self.root.join("prefs.json")
    }
    pub fn relay_dir(&self) -> PathBuf {
        self.root.join("relay")
    }
    pub fn media_dir(&self) -> PathBuf {
        self.root.join("media")
    }
}

/// The user's chosen, signed-at-broadcast business card.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Profile {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub bio: String,
    #[serde(default)]
    pub link: String,
    #[serde(default)]
    pub emoji: String,
    /// Base64 JPEG/PNG avatar (small), empty if none.
    #[serde(default)]
    pub avatar: String,
}

/// A known contact (their verified identity + display name).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Contact {
    pub id_hex: String,
    pub name: String,
    pub verify_hex: String,
}

/// Everything that lives in `prefs.json` (mirrors the Android SharedPreferences set).
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Prefs {
    #[serde(default)]
    pub profile: Profile,
    #[serde(default)]
    pub contacts: Vec<Contact>,
    #[serde(default)]
    pub blocked: Vec<String>,
    /// circleId -> relay node hex.
    #[serde(default)]
    pub relay_nodes: std::collections::HashMap<String, String>,
    /// Retention window in seconds for the viewer's own auto-prune (None = keep all).
    #[serde(default)]
    pub retention_secs: Option<u64>,
}

impl Prefs {
    pub fn load(paths: &Paths) -> Self {
        match fs::read(paths.prefs_file()) {
            Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
            Err(_) => Prefs::default(),
        }
    }
    pub fn save(&self, paths: &Paths) -> Result<()> {
        let bytes = serde_json::to_vec_pretty(self)?;
        fs::write(paths.prefs_file(), bytes).context("write prefs")
    }
}

/// Load the 32-byte master seed from the secure store, or `None` if there isn't one yet.
/// Distinguishes "no entry" (new device → caller generates) from a locked/error read, so
/// we never clobber an existing identity by treating a transient failure as "new".
pub fn load_seed() -> Result<Option<[u8; 32]>> {
    let entry = keyring::Entry::new(SERVICE, SEED_ACCOUNT).context("open keyring entry")?;
    match entry.get_password() {
        Ok(b64) => {
            let raw = base64::engine::general_purpose::STANDARD
                .decode(b64.trim())
                .context("decode stored seed")?;
            let seed: [u8; 32] = raw
                .try_into()
                .map_err(|_| anyhow!("stored seed is not 32 bytes"))?;
            Ok(Some(seed))
        }
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(anyhow!("keyring read failed: {e}")),
    }
}

/// Persist the master seed to the secure store.
pub fn save_seed(seed: &[u8; 32]) -> Result<()> {
    let entry = keyring::Entry::new(SERVICE, SEED_ACCOUNT).context("open keyring entry")?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(seed);
    entry.set_password(&b64).context("write seed to keyring")
}

/// Wipe the stored seed (Start Over).
pub fn delete_seed() -> Result<()> {
    let entry = keyring::Entry::new(SERVICE, SEED_ACCOUNT).context("open keyring entry")?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(anyhow!("keyring delete failed: {e}")),
    }
}

/// Read the persisted social-state blob, if any.
pub fn read_state(paths: &Paths) -> Option<Vec<u8>> {
    fs::read(paths.state_file()).ok()
}

/// Write the social-state blob.
pub fn write_state(paths: &Paths, data: &[u8]) -> Result<()> {
    fs::write(paths.state_file(), data).context("write state")
}

/// Remove a file, ignoring "not found".
pub fn remove_if_exists(p: &Path) {
    let _ = fs::remove_file(p);
}
