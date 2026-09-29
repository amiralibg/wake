//! The `wake://` protocol: the UI bundle (`desktop/ui/dist`, embedded in release
//! builds and read from disk in debug builds) and files from the data folder
//! (thumbnails, moment snapshots) under `data/`.

use rust_embed::RustEmbed;
use std::borrow::Cow;
use std::path::{Component, Path};
use wry::http::{header, Request, Response, StatusCode};

#[derive(RustEmbed)]
#[folder = "../ui/dist"]
struct Ui;

/// Where the shell loads the UI from. WebView2 serves custom protocols as
/// `http://<scheme>.localhost`.
pub fn ui_url(query: &str) -> String {
    #[cfg(windows)]
    let base = "http://wake.localhost/index.html";
    #[cfg(not(windows))]
    let base = "wake://localhost/index.html";
    if query.is_empty() { base.to_string() } else { format!("{base}?{query}") }
}

pub fn respond(request: &Request<Vec<u8>>, data_dir: &Path) -> Response<Cow<'static, [u8]>> {
    let path = request.uri().path().trim_start_matches('/');
    let path = if path.is_empty() { "index.html" } else { path };
    let path = percent_decode(path);

    if let Some(rest) = path.strip_prefix("data/") {
        let relative = Path::new(rest);
        // Only plain relative paths inside the data folder.
        if relative.components().all(|c| matches!(c, Component::Normal(_))) {
            if let Ok(bytes) = std::fs::read(data_dir.join(relative)) {
                return ok(bytes.into(), mime(&path), "no-cache");
            }
        }
        return not_found();
    }

    match Ui::get(&path) {
        Some(file) => ok(file.data, mime(&path), "no-cache"),
        None => not_found(),
    }
}

fn ok(body: Cow<'static, [u8]>, mime: &str, cache: &str) -> Response<Cow<'static, [u8]>> {
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mime)
        .header(header::CACHE_CONTROL, cache)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(body)
        .unwrap()
}

fn not_found() -> Response<Cow<'static, [u8]>> {
    Response::builder().status(StatusCode::NOT_FOUND).body(Cow::Borrowed(&b""[..])).unwrap()
}

fn mime(path: &str) -> &'static str {
    match path.rsplit('.').next().unwrap_or("") {
        "html" => "text/html; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "json" => "application/json",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "woff2" => "font/woff2",
        "wasm" => "application/wasm",
        _ => "application/octet-stream",
    }
}

fn percent_decode(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(value) = u8::from_str_radix(&input[i + 1..i + 3], 16) {
                out.push(value);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
