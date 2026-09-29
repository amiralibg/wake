//! Plain HTTP for the UI, which can't make cross-origin requests from its own
//! webview: search suggestions, update checks, dev-server probes. Runs on a
//! worker thread and replies through the event loop.

use crate::{Proxy, UserEvent};
use serde_json::{json, Value};
use std::io::Read;
use std::sync::OnceLock;
use std::time::Duration;

fn agent() -> &'static ureq::Agent {
    static AGENT: OnceLock<ureq::Agent> = OnceLock::new();
    AGENT.get_or_init(|| {
        ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(20)))
            .user_agent(concat!("Wake/", env!("CARGO_PKG_VERSION")))
            .build()
            .into()
    })
}

/// `request`: `{ url, method?, headers?, body?, timeoutMs?, maxBytes? }`.
/// Answers `{ status, headers, text }`.
pub fn fetch(proxy: Proxy, window: u64, req: u64, request: Value) {
    std::thread::spawn(move || {
        let result = run(&request);
        let _ = proxy.send_event(UserEvent::Reply { window, req, result });
    });
}

fn run(request: &Value) -> Result<Value, String> {
    let url = request.get("url").and_then(Value::as_str).ok_or("no url")?;
    let method = request.get("method").and_then(Value::as_str).unwrap_or("GET").to_ascii_uppercase();
    let max_bytes = request.get("maxBytes").and_then(Value::as_u64).unwrap_or(4 * 1024 * 1024);
    let headers: Vec<(String, String)> = request
        .get("headers")
        .and_then(Value::as_object)
        .map(|map| map.iter().filter_map(|(k, v)| v.as_str().map(|v| (k.clone(), v.to_string()))).collect())
        .unwrap_or_default();
    let timeout = request.get("timeoutMs").and_then(Value::as_u64).map(Duration::from_millis);

    let response = if method == "GET" || method == "HEAD" {
        let mut builder = if method == "GET" { agent().get(url) } else { agent().head(url) };
        for (k, v) in &headers {
            builder = builder.header(k, v);
        }
        if let Some(timeout) = timeout {
            builder = builder.config().timeout_global(Some(timeout)).build();
        }
        builder.call()
    } else {
        let mut builder = agent().post(url);
        for (k, v) in &headers {
            builder = builder.header(k, v);
        }
        if let Some(timeout) = timeout {
            builder = builder.config().timeout_global(Some(timeout)).build();
        }
        builder.send(request.get("body").and_then(Value::as_str).unwrap_or(""))
    };
    let mut response = response.map_err(|e| e.to_string())?;
    let status = response.status().as_u16();
    let mut out_headers = serde_json::Map::new();
    for (name, value) in response.headers() {
        if let Ok(value) = value.to_str() {
            out_headers.insert(name.as_str().to_string(), json!(value));
        }
    }
    let mut bytes = Vec::new();
    if method != "HEAD" {
        response
            .body_mut()
            .as_reader()
            .take(max_bytes)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
    }
    Ok(json!({ "status": status, "headers": out_headers, "text": String::from_utf8_lossy(&bytes) }))
}
