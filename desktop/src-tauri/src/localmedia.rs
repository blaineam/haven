//! On-device media store, byte-compatible with the iOS `MediaStore` and Android `LocalMedia`:
//! photos/videos are content-addressed (sha-256 of the plaintext, so the ref is identical on
//! every device for the cross-device MediaReq/Chunk fetch) and kept **sealed at rest** to the
//! circle. Videos carry a `v:` ref prefix so the feed renders them as players.

use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use haven_ffi::HavenSocial;
use sha2::{Digest, Sha256};

pub struct LocalMedia {
    dir: PathBuf,
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

fn bare_id(reference: &str) -> &str {
    reference
        .strip_prefix("v:")
        .or_else(|| reference.strip_prefix("i:"))
        .unwrap_or(reference)
}

impl LocalMedia {
    pub fn new(dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&dir);
        Self { dir }
    }

    pub fn is_video(reference: &str) -> bool {
        reference.starts_with("v:")
    }

    /// Store plaintext bytes sealed to `circle_id`; returns a media ref.
    pub fn store(&self, social: &Arc<HavenSocial>, circle_id: &str, bytes: &[u8], is_video: bool) -> String {
        let hash = sha256_hex(bytes);
        let to_write = social
            .seal_circle_media(circle_id.to_string(), bytes.to_vec())
            .unwrap_or_else(|_| bytes.to_vec());
        let _ = fs::write(self.dir.join(&hash), &to_write);
        if is_video {
            format!("v:{hash}")
        } else {
            hash
        }
    }

    /// Load + decrypt a stored media ref, or `None` if we don't have it.
    pub fn load(&self, social: &Arc<HavenSocial>, circle_id: &str, reference: &str) -> Option<Vec<u8>> {
        let f = self.dir.join(bare_id(reference));
        let stored = fs::read(&f).ok()?;
        Some(
            social
                .open_circle_media(circle_id.to_string(), stored.clone())
                .unwrap_or(stored),
        )
    }

    pub fn has(&self, reference: &str) -> bool {
        self.dir.join(bare_id(reference)).exists()
    }

    /// Load decrypted bytes trying every circle's key (for serving a media request).
    pub fn load_any_circle(&self, social: &Arc<HavenSocial>, reference: &str) -> Option<Vec<u8>> {
        let f = self.dir.join(bare_id(reference));
        let stored = fs::read(&f).ok()?;
        for c in social.circles() {
            if let Some(open) = social.open_circle_media(c.id, stored.clone()) {
                return Some(open);
            }
        }
        Some(stored)
    }

    /// Store received plaintext bytes under an exact ref (sealed at rest to the circle).
    pub fn store_under_ref(&self, social: &Arc<HavenSocial>, circle_id: &str, reference: &str, bytes: &[u8]) {
        let to_write = social
            .seal_circle_media(circle_id.to_string(), bytes.to_vec())
            .unwrap_or_else(|_| bytes.to_vec());
        let _ = fs::write(self.dir.join(bare_id(reference)), &to_write);
    }

    /// The at-rest sealed blob for a ref — uploaded to the relay verbatim.
    pub fn raw_sealed(&self, reference: &str) -> Option<Vec<u8>> {
        fs::read(self.dir.join(bare_id(reference))).ok()
    }

    /// Write a sealed blob fetched from the relay straight to disk.
    pub fn write_raw_sealed(&self, reference: &str, blob: &[u8]) {
        let _ = fs::write(self.dir.join(bare_id(reference)), blob);
    }

    /// Delete every stored media file (part of "start over").
    pub fn clear(&self) {
        if let Ok(entries) = fs::read_dir(&self.dir) {
            for e in entries.flatten() {
                let _ = fs::remove_file(e.path());
            }
        }
    }
}
