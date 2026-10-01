//! Page scripts from `shared/scripts`, wrapped the way `shared/README.md` describes:
//! each file is the body of a function of `(wake, params)`.

use rust_embed::RustEmbed;
use serde_json::Value;

#[derive(RustEmbed)]
#[folder = "../../shared/scripts"]
struct Files;

/// Channels pages post on. Wake's world and the page's world have their own reply
/// channels because a WebKit message handler belongs to one world.
pub const CHANNEL: &str = "wake";
pub const DEV_CHANNEL: &str = "wakeDev";
pub const DEVTOOLS_CHANNEL: &str = "wakeDT";
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub const POPOUT_CHANNEL: &str = "wakePopOut";
pub const REPLY_CHANNEL: &str = "wakeReply";
pub const PAGE_REPLY_CHANNEL: &str = "wakePageReply";

pub fn body(name: &str) -> String {
    match Files::get(&format!("{name}.js")) {
        Some(file) => String::from_utf8_lossy(&file.data).into_owned(),
        None => {
            eprintln!("shared/scripts/{name}.js is missing");
            String::new()
        }
    }
}

/// `bridge.js`, called: an expression for the bridge object.
pub fn bridge() -> String {
    format!("(function () {{\n{}\n}})()", body("bridge"))
}

/// A statement that runs the script with `params`.
pub fn source(name: &str, params: &Value) -> String {
    format!("(function (wake, params) {{\n{}\n}})({}, {});", body(name), bridge(), params)
}

/// A function body that runs a shared script and returns what it returns
/// (awaited, for `async-` scripts).
pub fn call_body(name: &str, params: &Value) -> String {
    let kind = if name.starts_with("async-") { "async function" } else { "function" };
    format!("return await ({kind} (wake, params) {{\n{}\n}})({}, {});", body(name), bridge(), params)
}

/// Runs `body` (an async function body) and posts its result to `channel` as
/// `{ id, ok, value }` or `{ id, ok: false, error }`. This is how every evaluation
/// that wants a value back works, on both engines and in both worlds: WebKitGTK's
/// and WebView2's own "evaluate" calls don't await promises, and WebKitGTK's
/// doesn't return values from a named world through wry.
pub fn with_reply(body: &str, channel: &str, id: u64) -> String {
    format!(
        r#"(function () {{
  const __w = {bridge};
  const __send = (m) => {{ try {{ __w.post({ch}, m); }} catch (e) {{}} }};
  (async function () {{
{body}
  }})().then(
    (value) => {{
      let clean = null;
      try {{ clean = value === undefined ? null : JSON.parse(JSON.stringify(value)); }} catch (e) {{}}
      __send({{ id: {id}, ok: true, value: clean }});
    }},
    (error) => __send({{ id: {id}, ok: false, error: String((error && error.message) || error) }})
  );
}})();"#,
        bridge = bridge(),
        ch = serde_json::to_string(channel).unwrap(),
    )
}

/// The scripts every page gets at document start, in Wake's world: link
/// interception, the scroll probe, page state, scroll sync, live reporters, and
/// (desktop only) trail wheel routing.
pub fn base_script() -> String {
    let params = serde_json::json!({ "channel": CHANNEL, "backgroundKey": "ctrl" });
    ["link-interceptor", "scroll-probe", "page-state", "scroll-sync", "live", "trail-wheel"]
        .iter()
        .map(|name| source(name, &params))
        .collect::<Vec<_>>()
        .join("\n")
}

/// Developer-mode hooks, in the page's world.
pub fn dev_hooks_script() -> String {
    source("dev-hooks", &serde_json::json!({ "channel": DEV_CHANNEL }))
}
