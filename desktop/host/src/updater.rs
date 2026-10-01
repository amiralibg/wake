//! Auto-update from GitHub releases, signed with minisign (Ed25519). The macOS app
//! uses Sparkle with its own key; this app has a key of its own, built in from
//! `WAKE_UPDATE_PUBLIC_KEY` at compile time. Without one, updates are off.
//!
//! Release assets, per platform (made by `.github/workflows/desktop-release.yml`):
//! - `Wake-<version>-windows-x64-setup.exe` (NSIS), installed silently
//! - `Wake-<version>-linux-<arch>.AppImage`, swapped in place of the running one
//! each with a `.minisig` beside it. Installs made any other way (a .deb, a
//! Flatpak) update through their package manager.

use serde_json::{json, Value};
use std::io::Read;
use std::path::{Path, PathBuf};

const REPO: &str = "amiralibg/wake";
const PUBLIC_KEY: Option<&str> = option_env!("WAKE_UPDATE_PUBLIC_KEY");

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// How this copy was installed, and so whether it can update itself.
fn install_kind() -> Result<&'static str, String> {
    if PUBLIC_KEY.map_or(true, |k| k.trim().is_empty()) {
        return Err("Updates are off in this build: it has no update signing key.".into());
    }
    if cfg!(windows) {
        return Ok("windows");
    }
    if cfg!(target_os = "linux") {
        return match std::env::var_os("APPIMAGE") {
            Some(_) => Ok("appimage"),
            None => Err("Installed by a package manager: update Wake through it.".into()),
        };
    }
    Err("Updates aren't supported on this platform.".into())
}

pub fn info() -> Value {
    match install_kind() {
        Ok(_) => json!({ "version": version(), "canUpdate": true, "reason": "" }),
        Err(reason) => json!({ "version": version(), "canUpdate": false, "reason": reason }),
    }
}

fn asset_name(version: &str) -> Option<String> {
    let arch = match std::env::consts::ARCH {
        "x86_64" => "x86_64",
        "aarch64" => "aarch64",
        _ => return None,
    };
    match install_kind().ok()? {
        "windows" => Some(format!("Wake-{version}-windows-x64-setup.exe")),
        "appimage" => Some(format!("Wake-{version}-linux-{arch}.AppImage")),
        _ => None,
    }
}

fn newer(candidate: &str, current: &str) -> bool {
    let parse = |v: &str| -> Vec<u64> { v.trim_start_matches('v').split(['.', '-']).take(3).map(|p| p.parse().unwrap_or(0)).collect() };
    parse(candidate) > parse(current)
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(std::time::Duration::from_secs(120)))
        .user_agent(concat!("Wake/", env!("CARGO_PKG_VERSION")))
        .build()
        .into()
}

/// A release newer than this one with a package for this platform, if any.
pub struct Available {
    pub version: String,
    pub notes: String,
    pub page: String,
    pub asset: String,
    pub signature: String,
}

/// The update found by the last check, for `install`.
pub static FOUND: std::sync::Mutex<Option<Available>> = std::sync::Mutex::new(None);

pub fn check() -> Result<Option<Available>, String> {
    install_kind()?;
    let url = format!("https://api.github.com/repos/{REPO}/releases/latest");
    let mut response = agent()
        .get(&url)
        .header("Accept", "application/vnd.github+json")
        .call()
        .map_err(|e| format!("Couldn't reach GitHub: {e}"))?;
    let release: Value = response.body_mut().read_json().map_err(|e| e.to_string())?;
    let tag = release.get("tag_name").and_then(Value::as_str).unwrap_or("");
    let version = tag.trim_start_matches('v').to_string();
    if !newer(&version, env!("CARGO_PKG_VERSION")) {
        return Ok(None);
    }
    let Some(name) = asset_name(&version) else { return Ok(None) };
    let assets = release.get("assets").and_then(Value::as_array).cloned().unwrap_or_default();
    let find = |wanted: &str| {
        assets
            .iter()
            .find(|a| a.get("name").and_then(Value::as_str) == Some(wanted))
            .and_then(|a| a.get("browser_download_url").and_then(Value::as_str))
            .map(str::to_string)
    };
    // A release without this platform's package (a Mac-only fix) isn't an update here.
    let (Some(asset), Some(signature)) = (find(&name), find(&format!("{name}.minisig"))) else { return Ok(None) };
    Ok(Some(Available {
        version,
        notes: release.get("body").and_then(Value::as_str).unwrap_or("").to_string(),
        page: release.get("html_url").and_then(Value::as_str).unwrap_or("").to_string(),
        asset,
        signature,
    }))
}

fn download(url: &str, limit: u64) -> Result<Vec<u8>, String> {
    let mut response = agent().get(url).call().map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    response
        .body_mut()
        .as_reader()
        .take(limit)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    Ok(bytes)
}

/// Downloads, verifies and installs `update`, then starts the new version. On
/// success the caller quits.
pub fn install(update: &Available, data_dir: &Path) -> Result<(), String> {
    let kind = install_kind()?;
    let key = minisign_verify::PublicKey::from_base64(PUBLIC_KEY.unwrap_or("").trim())
        .or_else(|_| minisign_verify::PublicKey::decode(PUBLIC_KEY.unwrap_or("").trim()))
        .map_err(|e| format!("Bad update key: {e}"))?;
    let package = download(&update.asset, 600 << 20)?;
    let signature_text = String::from_utf8(download(&update.signature, 1 << 16)?).map_err(|e| e.to_string())?;
    let signature = minisign_verify::Signature::decode(&signature_text).map_err(|e| format!("Bad signature: {e}"))?;
    key.verify(&package, &signature, false)
        .map_err(|_| "The update's signature doesn't match: not installing it.".to_string())?;

    let folder = data_dir.join("updates");
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    match kind {
        "windows" => install_windows(&package, &folder),
        "appimage" => install_appimage(&package),
        _ => Err("Can't update this install.".into()),
    }
}

#[allow(unused_variables)]
fn install_windows(package: &[u8], folder: &Path) -> Result<(), String> {
    let installer = folder.join("Wake-setup.exe");
    std::fs::write(&installer, package).map_err(|e| e.to_string())?;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    // The silent installer replaces the files once Wake has quit, then Wake starts again.
    let script = format!(
        "timeout /t 2 /nobreak >nul & \"{}\" /S & start \"\" \"{}\"",
        installer.display(),
        exe.display()
    );
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const DETACHED_PROCESS: u32 = 0x0000_0008;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        std::process::Command::new("cmd")
            .args(["/C", &script])
            .creation_flags(DETACHED_PROCESS | CREATE_NO_WINDOW)
            .spawn()
            .map_err(|e| e.to_string())?;
        return Ok(());
    }
    #[allow(unreachable_code)]
    Err(format!("not Windows: {script}"))
}

fn install_appimage(package: &[u8]) -> Result<(), String> {
    let current = PathBuf::from(std::env::var_os("APPIMAGE").ok_or("not running as an AppImage")?);
    let staged = current.with_extension("AppImage.new");
    std::fs::write(&staged, package).map_err(|e| format!("Can't write next to {}: {e}", current.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&staged, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }
    // Renaming over a running AppImage is safe: the old file stays open until we exit.
    std::fs::rename(&staged, &current).map_err(|e| e.to_string())?;
    std::process::Command::new(&current).spawn().map_err(|e| e.to_string())?;
    Ok(())
}
