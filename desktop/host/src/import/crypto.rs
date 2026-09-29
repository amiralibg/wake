//! Chromium's cookie encryption on Linux and Windows.
//!
//! - Linux: AES-128-CBC with a key from PBKDF2-SHA1("saltysalt", 1 round) of a
//!   password: "peanuts" for "v10" values, the Secret Service password for "v11".
//! - Windows: AES-256-GCM with a key from "Local State" (os_crypt.encrypted_key),
//!   itself protected by DPAPI, for "v10"/"v11". "v20" is app-bound: only the
//!   browser can decrypt it.

use std::path::Path;

pub struct Keys {
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    v10: Option<[u8; 16]>,
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    v11: Option<[u8; 16]>,
    #[cfg_attr(not(windows), allow(dead_code))]
    gcm: Option<Vec<u8>>,
}

#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn derive(password: &[u8]) -> [u8; 16] {
    let mut key = [0u8; 16];
    pbkdf2::pbkdf2_hmac::<sha1::Sha1>(password, b"saltysalt", 1, &mut key);
    key
}

impl Keys {
    #[allow(unused_variables)]
    pub fn load(secret: &str, local_state: &Path) -> Self {
        #[cfg(target_os = "linux")]
        {
            let v11 = secret_service_password(secret).map(|p| derive(p.as_bytes()));
            Keys { v10: Some(derive(b"peanuts")), v11, gcm: None }
        }
        #[cfg(windows)]
        {
            Keys { v10: None, v11: None, gcm: windows_key(local_state) }
        }
        #[cfg(not(any(target_os = "linux", windows)))]
        {
            Keys { v10: None, v11: None, gcm: None }
        }
    }

    /// The cookie's value, or None when it can't be decrypted here.
    pub fn decrypt(&self, encrypted: &[u8], strips_domain_hash: bool) -> Option<String> {
        if encrypted.len() <= 3 {
            return None;
        }
        let (prefix, payload) = encrypted.split_at(3);
        let plain = self.decrypt_payload(prefix, payload)?;
        let plain = if strips_domain_hash && plain.len() >= 32 { plain[32..].to_vec() } else { plain };
        String::from_utf8(plain).ok()
    }

    #[allow(unused_variables)]
    fn decrypt_payload(&self, prefix: &[u8], payload: &[u8]) -> Option<Vec<u8>> {
        #[cfg(target_os = "linux")]
        {
            use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyIvInit};
            let key = match prefix {
                b"v10" => self.v10?,
                b"v11" => self.v11?,
                _ => return None,
            };
            let iv = [b' '; 16];
            return cbc::Decryptor::<aes::Aes128>::new(&key.into(), &iv.into()).decrypt_padded_vec_mut::<Pkcs7>(payload).ok();
        }
        #[cfg(windows)]
        {
            use aes_gcm::aead::Aead;
            use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
            // "v20" is app-bound encryption.
            if prefix != b"v10" && prefix != b"v11" {
                return None;
            }
            let key = self.gcm.as_ref()?;
            if payload.len() < 12 + 16 {
                return None;
            }
            let (nonce, body) = payload.split_at(12);
            let cipher = Aes256Gcm::new_from_slice(key).ok()?;
            return cipher.decrypt(Nonce::from_slice(nonce), body).ok();
        }
        #[allow(unreachable_code)]
        None
    }
}

/// Chromium's keyring password, through libsecret's command-line tool.
#[cfg(target_os = "linux")]
fn secret_service_password(application: &str) -> Option<String> {
    let output = std::process::Command::new("secret-tool").args(["lookup", "application", application]).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let password = String::from_utf8(output.stdout).ok()?.trim().to_string();
    (!password.is_empty()).then_some(password)
}

#[cfg(windows)]
fn windows_key(local_state: &Path) -> Option<Vec<u8>> {
    use base64::Engine;
    use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};
    let text = std::fs::read_to_string(local_state).ok()?;
    let json: serde_json::Value = serde_json::from_str(&text).ok()?;
    let encoded = json.pointer("/os_crypt/encrypted_key")?.as_str()?;
    let mut blob = base64::engine::general_purpose::STANDARD.decode(encoded).ok()?;
    if !blob.starts_with(b"DPAPI") {
        return None;
    }
    let mut data = blob.split_off(5);
    let input = CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_mut_ptr() };
    let mut output = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptUnprotectData(&input, None, None, None, None, 0, &mut output).ok()?;
        let key = std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec();
        let _ = windows::Win32::Foundation::LocalFree(Some(windows::Win32::Foundation::HLOCAL(output.pbData as _)));
        Some(key)
    }
}
