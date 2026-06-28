//! Multi-device device-roster, parity with iOS `DeviceRoster.swift` / Android `DeviceRoster.kt`.
//!
//! The signed-credential crypto lives in the shared core (`haven_ffi::multidevice::{issue_device_credential,
//! sign_device_list}` + `HavenSocial::set_my_device_roster`), so this is the device-local state + the manager
//! logic over it. Credential / device-list bytes are byte-identical across iOS / Android / desktop.
//!
//! A linked device acts under its OWN device key plus an account-signed credential, so the primary can
//! authorize it and **revoke it individually** without rotating the master seed.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::store::Paths;

#[derive(Clone, Serialize, Deserialize)]
pub struct RosterEntry {
    pub bundle: Vec<u8>,
    pub name: String,
    pub is_primary: bool,
}

/// One device in the account's roster (for the Authorized-Devices UI).
#[derive(Clone, Serialize)]
pub struct RosterDeviceDto {
    pub node_hex: String,
    pub name: String,
    pub is_this_device: bool,
    pub is_primary: bool,
}

/// Device-local roster state (this device's own key + credential + the signed roster it maintains as
/// primary). Persisted to a device-local file, never synced.
#[derive(Default, Serialize, Deserialize)]
pub struct DeviceRoster {
    /// This device's OWN seed (distinct from the account master seed). Generated once.
    pub device_seed: Vec<u8>,
    /// The account-signed credential proving this device is authorized (set once enrollment grants it).
    pub credential: Option<Vec<u8>>,
    pub version: u64,
    pub primary_hex: String,
    pub entries: BTreeMap<String, RosterEntry>,
    pub revoked: Vec<String>,
}

impl DeviceRoster {
    fn file(paths: &Paths) -> PathBuf {
        paths.root.join("device-roster.json")
    }

    pub fn load(paths: &Paths) -> Self {
        let mut r: Self = std::fs::read(Self::file(paths))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        if r.device_seed.len() != 32 {
            // Mint this device's stable key once.
            let acct = haven_ffi::Account::generate();
            r.device_seed = acct.secret_seed();
            let _ = r.save(paths);
        }
        r
    }

    pub fn save(&self, paths: &Paths) -> std::io::Result<()> {
        let _ = std::fs::create_dir_all(&paths.root);
        std::fs::write(Self::file(paths), serde_json::to_vec(self).unwrap_or_default())
    }

    fn device_account(&self) -> std::sync::Arc<haven_ffi::Account> {
        haven_ffi::Account::from_seed(self.device_seed.clone()).expect("valid device seed")
    }
    pub fn device_node_hex(&self) -> String {
        self.device_account().node_id_hex()
    }
    pub fn device_bundle(&self) -> Vec<u8> {
        self.device_account().public_bundle()
    }
    pub fn device_name() -> String {
        format!("{} desktop", std::env::consts::OS)
    }

    pub fn is_enabled(&self) -> bool {
        self.version > 0
    }
    pub fn is_authorized(&self) -> bool {
        self.credential.is_some()
    }

    /// Turn multi-device on: register the account key as the primary "device #0". Idempotent.
    pub fn enable(&mut self, account_bundle: &[u8], account_hex: &str) {
        self.primary_hex = account_hex.to_string();
        self.entries.entry(account_hex.to_string()).or_insert_with(|| RosterEntry {
            bundle: account_bundle.to_vec(),
            name: "Primary (this account's master key)".into(),
            is_primary: true,
        });
    }

    /// Authorize a newly-linked device. Returns that device's credential to hand back.
    pub fn add_linked_device(&mut self, bundle: &[u8], node_hex: &str, name: &str, account_seed: &[u8], now: u64) -> Option<Vec<u8>> {
        self.revoked.retain(|h| h != node_hex);
        self.entries.insert(node_hex.to_string(), RosterEntry { bundle: bundle.to_vec(), name: name.to_string(), is_primary: false });
        haven_ffi::multidevice::issue_device_credential(account_seed.to_vec(), bundle.to_vec(), name.to_string(), now).ok()
    }

    /// Revoke a device: drop it, bump the version on the next resign. Never the master key.
    pub fn revoke(&mut self, node_hex: &str) -> bool {
        if node_hex == self.primary_hex {
            return false;
        }
        self.entries.remove(node_hex);
        if !self.revoked.iter().any(|h| h == node_hex) {
            self.revoked.push(node_hex.to_string());
        }
        true
    }

    /// Forget the roster entirely (the wrong device claimed primary). Reversible.
    pub fn step_down(&mut self) {
        self.version = 0;
        self.primary_hex.clear();
        self.entries.clear();
        self.revoked.clear();
        self.credential = None;
    }

    /// Build a fresh signed (DeviceList, credentials) for every active device, bumping the version.
    /// Returns `None` if signing fails. The caller pushes it via `social.set_my_device_roster`.
    pub fn resign(&mut self, account_seed: &[u8], now: u64) -> Option<(Vec<u8>, Vec<Vec<u8>>)> {
        self.version += 1;
        let mut creds: Vec<Vec<u8>> = Vec::new();
        let mut active_ids: Vec<Vec<u8>> = Vec::new();
        for (hex, e) in &self.entries {
            if self.revoked.iter().any(|r| r == hex) {
                continue;
            }
            let Some(id) = hex_to_bytes(hex) else { continue };
            active_ids.push(id);
            if let Ok(c) = haven_ffi::multidevice::issue_device_credential(account_seed.to_vec(), e.bundle.clone(), e.name.clone(), now) {
                creds.push(c);
            }
        }
        let revoked_ids: Vec<Vec<u8>> = self.revoked.iter().filter_map(|h| hex_to_bytes(h)).collect();
        let list = haven_ffi::multidevice::sign_device_list(account_seed.to_vec(), self.version, now, active_ids, revoked_ids).ok()?;
        Some((list, creds))
    }

    pub fn devices(&self, account_hex: &str) -> Vec<RosterDeviceDto> {
        let me = self.device_node_hex();
        let mut out: Vec<RosterDeviceDto> = self
            .entries
            .iter()
            .map(|(hex, e)| RosterDeviceDto {
                node_hex: hex.clone(),
                name: e.name.clone(),
                is_this_device: *hex == me || (e.is_primary && account_hex == hex),
                is_primary: e.is_primary,
            })
            .collect();
        out.sort_by(|a, b| {
            let ka = (if a.is_primary { 0u8 } else { 1 }, &a.name);
            let kb = (if b.is_primary { 0u8 } else { 1 }, &b.name);
            ka.cmp(&kb)
        });
        out
    }
}

fn hex_to_bytes(hex: &str) -> Option<Vec<u8>> {
    if hex.len() != 64 {
        return None;
    }
    (0..32).map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).ok()).collect()
}
