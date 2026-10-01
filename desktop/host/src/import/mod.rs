//! Import from another browser (the Mac app's Features/Import): finds Chromium and
//! Firefox-family profiles, and reads their history, search terms, cookies and
//! localStorage. Reading happens here; merging into Wake (history rows, cookies,
//! site storage) is driven by the UI.
//!
//! Limitations:
//! - Chrome 127+ on Windows encrypts cookies with app-bound encryption ("v20"),
//!   which only Chrome itself can undo: those cookies are skipped and counted.
//! - On Linux, cookies encrypted with the keyring password ("v11") need the
//!   Secret Service; Wake asks it through `secret-tool`. Without it, only
//!   "v10" cookies (the built-in password) come across.
//! - IndexedDB, Cache Storage and service workers are engine-specific formats and
//!   don't move between engines.

mod crypto;
mod leveldb;

use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};

/// Most browsers keep 90 days; Firefox can keep years. The newest pages win.
const HISTORY_LIMIT: usize = 25_000;
const SITE_LIMIT: usize = 2_000;
const ITEMS_PER_SITE: usize = 2_000;

#[derive(Clone)]
pub enum Engine {
    /// `secret` names the browser in the Secret Service (Linux).
    Chromium { secret: &'static str, local_state: PathBuf },
    Firefox,
}

#[derive(Clone)]
pub struct Profile {
    pub browser: String,
    pub name: Option<String>,
    pub dir: PathBuf,
    pub engine: Engine,
}

impl Profile {
    pub fn json(&self) -> Value {
        json!({
            "id": self.dir.to_string_lossy(),
            "browser": self.browser,
            "profile": self.name,
            "title": match &self.name { Some(n) => format!("{} · {n}", self.browser), None => self.browser.clone() },
            "engine": match self.engine { Engine::Chromium { .. } => "chromium", Engine::Firefox => "firefox" },
        })
    }
}

#[cfg_attr(windows, allow(dead_code))]
fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_default()
}

/// (browser, root relative to its base folder, Secret Service application)
#[cfg(target_os = "linux")]
fn chromium_roots() -> Vec<(&'static str, PathBuf, &'static str)> {
    let config = dirs::config_dir().unwrap_or_else(|| home().join(".config"));
    let flatpak = |app: &str, rest: &str| home().join(".var/app").join(app).join("config").join(rest);
    vec![
        ("Chrome", config.join("google-chrome"), "chrome"),
        ("Chrome", flatpak("com.google.Chrome", "google-chrome"), "chrome"),
        ("Chrome Beta", config.join("google-chrome-beta"), "chrome"),
        ("Chromium", config.join("chromium"), "chromium"),
        ("Chromium", home().join("snap/chromium/common/chromium"), "chromium"),
        ("Chromium", flatpak("org.chromium.Chromium", "chromium"), "chromium"),
        ("Edge", config.join("microsoft-edge"), "chromium"),
        ("Brave", config.join("BraveSoftware/Brave-Browser"), "brave"),
        ("Brave", flatpak("com.brave.Browser", "BraveSoftware/Brave-Browser"), "brave"),
        ("Vivaldi", config.join("vivaldi"), "chrome"),
        ("Opera", config.join("opera"), "chromium"),
    ]
}

#[cfg(windows)]
fn chromium_roots() -> Vec<(&'static str, PathBuf, &'static str)> {
    let local = dirs::data_local_dir().unwrap_or_default();
    let roaming = dirs::data_dir().unwrap_or_default();
    vec![
        ("Chrome", local.join("Google/Chrome/User Data"), ""),
        ("Chrome Beta", local.join("Google/Chrome Beta/User Data"), ""),
        ("Chromium", local.join("Chromium/User Data"), ""),
        ("Edge", local.join("Microsoft/Edge/User Data"), ""),
        ("Brave", local.join("BraveSoftware/Brave-Browser/User Data"), ""),
        ("Vivaldi", local.join("Vivaldi/User Data"), ""),
        ("Opera", roaming.join("Opera Software/Opera Stable"), ""),
        ("Opera GX", roaming.join("Opera Software/Opera GX Stable"), ""),
    ]
}

#[cfg(not(any(target_os = "linux", windows)))]
fn chromium_roots() -> Vec<(&'static str, PathBuf, &'static str)> {
    Vec::new()
}

fn firefox_roots() -> Vec<(&'static str, PathBuf)> {
    #[cfg(windows)]
    {
        let roaming = dirs::data_dir().unwrap_or_default();
        vec![
            ("Firefox", roaming.join("Mozilla/Firefox")),
            ("Zen", roaming.join("zen")),
            ("Waterfox", roaming.join("Waterfox")),
            ("LibreWolf", roaming.join("librewolf")),
            ("Floorp", roaming.join("Floorp")),
        ]
    }
    #[cfg(not(windows))]
    {
        let h = home();
        vec![
            ("Firefox", h.join(".mozilla/firefox")),
            ("Firefox", h.join("snap/firefox/common/.mozilla/firefox")),
            ("Firefox", h.join(".var/app/org.mozilla.firefox/.mozilla/firefox")),
            ("Zen", h.join(".zen")),
            ("Zen", h.join(".var/app/app.zen_browser.zen/.zen")),
            ("Waterfox", h.join(".waterfox")),
            ("LibreWolf", h.join(".librewolf")),
            ("Floorp", h.join(".floorp")),
        ]
    }
}

pub fn profiles() -> Vec<Profile> {
    let mut found = Vec::new();
    for (browser, root, secret) in chromium_roots() {
        for (name, dir) in chromium_profiles(&root) {
            found.push(Profile {
                browser: browser.into(),
                name,
                dir,
                engine: Engine::Chromium { secret, local_state: root.join("Local State") },
            });
        }
    }
    for (browser, root) in firefox_roots() {
        for (name, dir) in firefox_profiles(&root) {
            found.push(Profile { browser: browser.into(), name, dir, engine: Engine::Firefox });
        }
    }
    // The same folder reached two ways (a symlinked config) counts once.
    let mut seen = std::collections::HashSet::new();
    found.retain(|p| seen.insert(p.dir.canonicalize().unwrap_or_else(|_| p.dir.clone())));
    found
}

/// "Local State" names each profile; with one profile its name is left out. Opera
/// keeps a single profile in the root itself.
fn chromium_profiles(root: &Path) -> Vec<(Option<String>, PathBuf)> {
    if root.join("History").exists() {
        return vec![(None, root.to_path_buf())];
    }
    let names: Map<String, Value> = std::fs::read_to_string(root.join("Local State"))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| v.pointer("/profile/info_cache").and_then(Value::as_object).cloned())
        .unwrap_or_default();
    let mut folders: Vec<String> = std::fs::read_dir(root)
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| n == "Default" || n.starts_with("Profile "))
                .filter(|n| root.join(n).join("History").exists())
                .collect()
        })
        .unwrap_or_default();
    folders.sort_by(|a, b| match (a == "Default", b == "Default") {
        (true, _) => std::cmp::Ordering::Less,
        (_, true) => std::cmp::Ordering::Greater,
        _ => natural(a).cmp(&natural(b)),
    });
    let many = folders.len() > 1;
    folders
        .into_iter()
        .map(|folder| {
            let name = names.get(&folder).and_then(|i| i.get("name")).and_then(Value::as_str).map(str::to_string);
            (if many { Some(name.unwrap_or_else(|| folder.clone())) } else { None }, root.join(folder))
        })
        .collect()
}

fn natural(name: &str) -> u64 {
    name.trim_start_matches("Profile ").parse().unwrap_or(u64::MAX)
}

/// Profiles listed in profiles.ini that have history.
fn firefox_profiles(root: &Path) -> Vec<(Option<String>, PathBuf)> {
    let Ok(text) = std::fs::read_to_string(root.join("profiles.ini")) else { return Vec::new() };
    let mut profiles = Vec::new();
    let (mut name, mut path, mut relative): (Option<String>, Option<String>, bool) = (None, None, true);
    let mut flush = |name: &mut Option<String>, path: &mut Option<String>, relative: &mut bool| {
        if let Some(p) = path.take() {
            let dir = if *relative { root.join(&p) } else { PathBuf::from(&p) };
            if dir.join("places.sqlite").exists() {
                profiles.push((name.clone(), dir));
            }
        }
        *name = None;
        *relative = true;
    };
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            flush(&mut name, &mut path, &mut relative);
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            match k {
                "Name" => name = Some(v.to_string()),
                "Path" => path = Some(v.to_string()),
                "IsRelative" => relative = v == "1",
                _ => {}
            }
        }
    }
    flush(&mut name, &mut path, &mut relative);
    if profiles.len() == 1 {
        profiles[0].0 = None;
    }
    profiles
}

/// Opens a copy of a database the browser may have open (and locked), with its WAL.
fn open_copy(file: &Path) -> Result<(Connection, tempdir::Dir), String> {
    let dir = tempdir::Dir::new()?;
    let copy = dir.path.join("db.sqlite");
    std::fs::copy(file, &copy).map_err(|e| format!("Couldn't read {}: {e}", file.display()))?;
    for suffix in ["-wal", "-shm"] {
        let side = PathBuf::from(format!("{}{suffix}", file.display()));
        if side.exists() {
            let _ = std::fs::copy(&side, dir.path.join(format!("db.sqlite{suffix}")));
        }
    }
    let conn = Connection::open_with_flags(&copy, OpenFlags::SQLITE_OPEN_READ_WRITE).map_err(|e| e.to_string())?;
    Ok((conn, dir))
}

mod tempdir {
    use std::path::PathBuf;

    /// A scratch folder removed when dropped.
    pub struct Dir {
        pub path: PathBuf,
    }

    impl Dir {
        pub fn new() -> Result<Self, String> {
            let path = std::env::temp_dir().join(format!("wake-import-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir_all(&path).map_err(|e| e.to_string())?;
            Ok(Self { path })
        }
    }

    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }
}

/// Chromium counts microseconds from 1601.
fn chromium_seconds(value: i64) -> f64 {
    value as f64 / 1_000_000.0 - 11_644_473_600.0
}

fn is_web(url: &str) -> bool {
    url.starts_with("http://") || url.starts_with("https://")
}

pub struct Options {
    pub history: bool,
    pub searches: bool,
    pub cookies: bool,
    pub site_data: bool,
}

/// Reads what was asked for. `progress` reports each phase for the UI.
pub fn read(profile: &Profile, options: &Options, progress: &dyn Fn(String)) -> Value {
    let mut notes: Vec<String> = Vec::new();
    let mut visits = Vec::new();
    let mut searches = Vec::new();
    let mut cookies = Vec::new();
    let mut sites = Map::new();
    let source = profile.browser.clone();

    if options.history || options.searches {
        progress(format!("Reading {source} history…"));
        match history(profile) {
            Ok(v) => visits = v,
            Err(e) => notes.push(e),
        }
        if options.searches {
            if let Engine::Chromium { .. } = profile.engine {
                searches = chromium_searches(profile).unwrap_or_default();
            }
        }
    }
    if options.cookies {
        progress(format!("Reading {source} cookies…"));
        match profile.engine {
            Engine::Chromium { secret, ref local_state } => match chromium_cookies(profile, secret, local_state) {
                Ok((c, skipped)) => {
                    cookies = c;
                    if skipped > 0 {
                        notes.push(format!(
                            "{skipped} cookies were skipped: {source} encrypts them with a key only it can use{}.",
                            if cfg!(windows) { " (app-bound encryption)" } else { " (the desktop keyring didn't hand it over)" }
                        ));
                    }
                }
                Err(e) => notes.push(e),
            },
            Engine::Firefox => match firefox_cookies(profile) {
                Ok(c) => cookies = c,
                Err(e) => notes.push(e),
            },
        }
    }
    if options.site_data {
        progress(format!("Reading {source} site data…"));
        sites = match profile.engine {
            Engine::Chromium { .. } => chromium_local_storage(&profile.dir.join("Local Storage/leveldb")),
            Engine::Firefox => firefox_local_storage(&profile.dir.join("storage/default")),
        };
        notes.push("IndexedDB, caches and service workers can't move between browser engines; sites rebuild them as you use them.".into());
    }
    json!({
        "source": source,
        "visits": visits,
        "searches": searches,
        "cookies": cookies,
        "sites": sites,
        "notes": notes,
    })
}

fn history(profile: &Profile) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    match profile.engine {
        Engine::Chromium { .. } => {
            let (db, _dir) = open_copy(&profile.dir.join("History"))?;
            let mut stmt = db
                .prepare(&format!("SELECT url, title, visit_count, last_visit_time FROM urls WHERE last_visit_time > 0 ORDER BY last_visit_time DESC LIMIT {HISTORY_LIMIT}"))
                .map_err(|e| e.to_string())?;
            let rows = stmt
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)))
                .map_err(|e| e.to_string())?;
            for (url, title, count, time) in rows.flatten() {
                if is_web(&url) {
                    out.push(json!({ "url": url, "title": title.unwrap_or_default(), "visitCount": count, "lastVisit": chromium_seconds(time) }));
                }
            }
        }
        Engine::Firefox => {
            let (db, _dir) = open_copy(&profile.dir.join("places.sqlite"))?;
            let mut stmt = db
                .prepare(&format!("SELECT url, title, visit_count, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 ORDER BY last_visit_date DESC LIMIT {HISTORY_LIMIT}"))
                .map_err(|e| e.to_string())?;
            let rows = stmt
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)))
                .map_err(|e| e.to_string())?;
            for (url, title, count, time) in rows.flatten() {
                if is_web(&url) {
                    out.push(json!({ "url": url, "title": title.unwrap_or_default(), "visitCount": count, "lastVisit": time as f64 / 1_000_000.0 }));
                }
            }
        }
    }
    Ok(out)
}

/// Chromium records search terms itself; the UI also recognises results pages in
/// the imported history.
fn chromium_searches(profile: &Profile) -> Result<Vec<Value>, String> {
    let (db, _dir) = open_copy(&profile.dir.join("History"))?;
    let mut stmt = db
        .prepare("SELECT k.term, u.url, u.last_visit_time FROM keyword_search_terms k JOIN urls u ON u.id = k.url_id ORDER BY u.last_visit_time DESC LIMIT 10000")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?)))
        .map_err(|e| e.to_string())?;
    Ok(rows
        .flatten()
        .filter(|(term, _, _)| !term.trim().is_empty())
        .map(|(term, url, time)| json!({ "query": term.trim(), "url": url, "date": chromium_seconds(time) }))
        .collect())
}

fn same_site(value: i64) -> Option<&'static str> {
    match value {
        1 => Some("lax"),
        2 => Some("strict"),
        _ => None,
    }
}

fn chromium_cookies(profile: &Profile, secret: &str, local_state: &Path) -> Result<(Vec<Value>, usize), String> {
    let file = [profile.dir.join("Network/Cookies"), profile.dir.join("Cookies")].into_iter().find(|p| p.exists());
    let Some(file) = file else { return Ok((Vec::new(), 0)) };
    let (db, _dir) = open_copy(&file)?;
    // From version 24, the decrypted value starts with a SHA-256 of the domain.
    let version: i64 = db
        .query_row("SELECT value FROM meta WHERE key = 'version'", [], |r| r.get::<_, String>(0))
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let keys = crypto::Keys::load(secret, local_state);
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0);
    let mut stmt = db
        .prepare("SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, has_expires FROM cookies")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Vec<u8>>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, i64>(5)?,
                r.get::<_, i64>(6)?,
                r.get::<_, i64>(7)?,
                r.get::<_, i64>(8)?,
                r.get::<_, i64>(9)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    let mut skipped = 0;
    for (domain, name, value, encrypted, path, expires, secure, http_only, samesite, has_expires) in rows.flatten() {
        let value = if value.is_empty() && !encrypted.is_empty() {
            match keys.decrypt(&encrypted, version >= 24) {
                Some(v) => v,
                None => {
                    skipped += 1;
                    continue;
                }
            }
        } else {
            value
        };
        let expires = if has_expires == 0 { None } else { Some(chromium_seconds(expires)) };
        if expires.map_or(false, |e| e < now) {
            continue;
        }
        out.push(json!({
            "domain": domain, "name": name, "value": value, "path": if path.is_empty() { "/".to_string() } else { path },
            "expires": expires, "secure": secure != 0, "httpOnly": http_only != 0, "sameSite": same_site(samesite),
        }));
    }
    Ok((out, skipped))
}

fn firefox_cookies(profile: &Profile) -> Result<Vec<Value>, String> {
    let (db, _dir) = open_copy(&profile.dir.join("cookies.sqlite"))?;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0);
    // Container tabs keep their own cookies (non-empty originAttributes); Wake has one jar.
    let mut stmt = db
        .prepare("SELECT host, name, value, path, expiry, isSecure, isHttpOnly, sameSite FROM moz_cookies WHERE originAttributes = ''")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, i64>(5)?,
                r.get::<_, i64>(6)?,
                r.get::<_, i64>(7)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for (domain, name, value, path, expiry, secure, http_only, samesite) in rows.flatten() {
        // Firefox switched expiry from seconds to milliseconds.
        let raw = expiry as f64;
        let expires = if raw > 100_000_000_000.0 { raw / 1000.0 } else { raw };
        if expires <= now {
            continue;
        }
        out.push(json!({
            "domain": domain, "name": name, "value": value, "path": if path.is_empty() { "/".to_string() } else { path },
            "expires": expires, "secure": secure != 0, "httpOnly": http_only != 0, "sameSite": same_site(samesite),
        }));
    }
    Ok(out)
}

fn add_site(sites: &mut Map<String, Value>, origin: &str, key: String, value: String) {
    if sites.len() >= SITE_LIMIT && !sites.contains_key(origin) {
        return;
    }
    let entry = sites.entry(origin.to_string()).or_insert_with(|| json!([]));
    if let Some(list) = entry.as_array_mut() {
        if list.len() < ITEMS_PER_SITE {
            list.push(json!([key, value]));
        }
    }
}

/// Keys are `_` + origin + NUL + encoded key; strings start with a format byte:
/// 0 for UTF-16LE, 1 for Latin-1.
fn chromium_local_storage(folder: &Path) -> Map<String, Value> {
    let mut sites = Map::new();
    for (key, value) in leveldb::read(folder) {
        if key.first() != Some(&b'_') {
            continue;
        }
        let Some(nul) = key.iter().position(|&b| b == 0) else { continue };
        let Ok(origin) = std::str::from_utf8(&key[1..nul]) else { continue };
        if !is_web(origin) {
            continue;
        }
        let (Some(name), Some(text)) = (decode_chromium_string(&key[nul + 1..]), decode_chromium_string(&value)) else { continue };
        add_site(&mut sites, origin, name, text);
    }
    sites
}

fn decode_chromium_string(data: &[u8]) -> Option<String> {
    let (&format, body) = data.split_first()?;
    match format {
        0 => {
            let units: Vec<u16> = body.chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect();
            String::from_utf16(&units).ok()
        }
        1 => Some(body.iter().map(|&b| b as char).collect()),
        _ => None,
    }
}

/// One `ls/data.sqlite` per origin folder ("https+++example.com+8443"); values may be
/// Snappy-compressed (compression_type 1) and UTF-8 (conversion_type 1).
fn firefox_local_storage(folder: &Path) -> Map<String, Value> {
    let mut sites = Map::new();
    let Ok(entries) = std::fs::read_dir(folder) else { return sites };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        // "^userContextId=…" folders belong to container tabs.
        if name.contains('^') {
            continue;
        }
        let Some(origin) = firefox_origin(&name) else { continue };
        let file = entry.path().join("ls/data.sqlite");
        if !file.exists() {
            continue;
        }
        let Ok((db, _dir)) = open_copy(&file) else { continue };
        let Ok(mut stmt) = db.prepare(&format!("SELECT key, value, compression_type, conversion_type FROM data LIMIT {ITEMS_PER_SITE}")) else { continue };
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Vec<u8>>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)));
        let Ok(rows) = rows else { continue };
        for (key, bytes, compression, conversion) in rows.flatten() {
            let bytes = if compression == 1 { leveldb::snappy(&bytes).unwrap_or_default() } else { bytes };
            let text = if conversion == 1 {
                String::from_utf8_lossy(&bytes).into_owned()
            } else {
                let units: Vec<u16> = bytes.chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect();
                String::from_utf16(&units).unwrap_or_else(|_| String::from_utf8_lossy(&bytes).into_owned())
            };
            add_site(&mut sites, &origin, key, text);
        }
    }
    sites
}

/// "https+++example.com+8443" → "https://example.com:8443".
fn firefox_origin(folder: &str) -> Option<String> {
    let (scheme, rest) = folder.split_once("+++")?;
    let (host, port) = match rest.rsplit_once('+') {
        Some((host, port)) if !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()) => (host, format!(":{port}")),
        _ => (rest, String::new()),
    };
    let origin = format!("{scheme}://{host}{port}");
    is_web(&origin).then_some(origin)
}
