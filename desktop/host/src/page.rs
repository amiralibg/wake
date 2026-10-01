//! Page webviews: one per trail column (and per pinned app, Pop Out, and the
//! Moments watcher). The UI names each one with an id it chose; popups get an id
//! from the host.

use crate::{platform, scripts, with_app, App, Proxy, UserEvent};
use serde_json::{json, Value};
use std::path::PathBuf;
use wry::{NewWindowResponse, PageLoadEvent, WebView, WebViewBuilder};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum World {
    /// Wake's isolated world (WebKitGTK); the page's world on WebView2, which has no
    /// isolated worlds for injected scripts.
    Wake,
    Page,
}

impl World {
    pub fn parse(value: Option<&str>) -> Self {
        if value == Some("page") { World::Page } else { World::Wake }
    }

    pub fn reply_channel(self) -> &'static str {
        match self {
            World::Wake => scripts::REPLY_CHANNEL,
            World::Page => scripts::PAGE_REPLY_CHANNEL,
        }
    }
}

pub struct Page {
    pub id: String,
    pub window: u64,
    pub webview: WebView,
    pub dev_hooks: bool,
    pub visible: bool,
    /// x, y, width, height and corner radius, in logical pixels.
    pub frame: Option<(f64, f64, f64, f64, f64)>,
    pub platform: platform::PageState,
}

#[derive(Default)]
pub struct Options {
    pub url: Option<String>,
    pub user_agent: Option<String>,
    pub dev_hooks: bool,
    pub javascript_disabled: bool,
}

impl Options {
    pub fn from_json(value: &Value) -> Self {
        Self {
            url: value.get("url").and_then(Value::as_str).map(str::to_string),
            user_agent: value.get("userAgent").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string),
            dev_hooks: value.get("devHooks").and_then(Value::as_bool).unwrap_or(false),
            javascript_disabled: value.get("javascriptDisabled").and_then(Value::as_bool).unwrap_or(false),
        }
    }
}

/// What a popup's webview has to be tied to (WebKit's related view; WebView2's environment).
pub type Opener = wry::NewWindowOpener;

pub fn create(app: &mut App, window: u64, id: String, options: Options, opener: Option<Opener>) -> Result<(Page, Option<NativeView>), String> {
    let Some(host_window) = app.windows.get(&window) else { return Err("no such window".into()) };
    let proxy = app.proxy.clone();
    #[cfg(windows)]
    let downloads = downloads_dir();

    let mut builder = match &opener {
        // A popup must share the opener's context (WebKit: related view).
        Some(_) if cfg!(target_os = "linux") => WebViewBuilder::new(),
        _ => WebViewBuilder::new_with_web_context(&mut app.web_context),
    };
    builder = builder
        .with_visible(false)
        .with_bounds(wry::Rect {
            position: wry::dpi::LogicalPosition::new(0.0, 0.0).into(),
            size: wry::dpi::LogicalSize::new(1.0, 1.0).into(),
        })
        .with_devtools(true)
        .with_hotkeys_zoom(false)
        .with_back_forward_navigation_gestures(false)
        .with_clipboard(true);
    if let Some(agent) = &options.user_agent {
        builder = builder.with_user_agent(agent.clone());
    }
    if options.javascript_disabled {
        builder = builder.with_javascript_disabled();
    }
    if let Some(url) = &options.url {
        builder = builder.with_url(url.clone());
    }

    // Wake's scripts. On WebKitGTK they go into Wake's own script world, which wry
    // doesn't support, so `platform::setup_page` adds them.
    #[cfg(windows)]
    {
        builder = builder.with_initialization_script_for_main_only(scripts::base_script(), true);
        let (proxy, page) = (proxy.clone(), id.clone());
        builder = builder.with_ipc_handler(move |request| {
            let body = request.into_body();
            let Ok(Value::Object(envelope)) = serde_json::from_str::<Value>(&body) else { return };
            let channel = envelope.get("channel").and_then(Value::as_str).unwrap_or("").to_string();
            let message = envelope.get("message").cloned().unwrap_or(Value::Null);
            dispatch_message(&proxy, &page, &channel, message);
        });
    }

    {
        let (proxy, page) = (proxy.clone(), id.clone());
        builder = builder.with_navigation_handler(move |url| {
            let scheme = url.split(':').next().unwrap_or("").to_ascii_lowercase();
            if ["http", "https", "about", "blob", "data", "file", "javascript"].contains(&scheme.as_str()) {
                return true;
            }
            // mailto:, tel:, app deep links… belong to other apps.
            let _ = proxy.send_event(UserEvent::Page { page: page.clone(), name: "page.external", payload: json!({ "url": url }) });
            false
        });
    }
    {
        let (proxy, page) = (proxy.clone(), id.clone());
        builder = builder.with_document_title_changed_handler(move |title| {
            let _ = proxy.send_event(UserEvent::Page { page: page.clone(), name: "page.state", payload: json!({ "title": title }) });
        });
    }
    {
        let (proxy, page) = (proxy.clone(), id.clone());
        builder = builder.with_on_page_load_handler(move |event, url| {
            let phase = match event {
                PageLoadEvent::Started => "started",
                PageLoadEvent::Finished => "finished",
            };
            let _ = proxy.send_event(UserEvent::Page { page: page.clone(), name: "page.load", payload: json!({ "phase": phase, "url": url }) });
        });
    }
    // WebKitGTK: wry would connect a context-wide download handler per page (so
    // every open page would answer every download); `platform` registers one.
    #[cfg(windows)]
    {
        {
        let (proxy, page) = (proxy.clone(), id.clone());
        let folder = downloads.clone();
        builder = builder.with_download_started_handler(move |url, path| {
            let name = path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .filter(|n| !n.is_empty())
                .unwrap_or_else(|| file_name_from_url(&url));
            *path = unique_path(&folder, &name);
            let _ = proxy.send_event(UserEvent::Page {
                page: page.clone(),
                name: "page.download",
                payload: json!({ "state": "started", "url": url, "path": path.to_string_lossy() }),
            });
            true
        });
    }
        {
        let (proxy, page) = (proxy.clone(), id.clone());
        builder = builder.with_download_completed_handler(move |url, path, success| {
            let _ = proxy.send_event(UserEvent::Page {
                page: page.clone(),
                name: "page.download",
                payload: json!({ "state": if success { "finished" } else { "failed" }, "url": url, "path": path.map(|p| p.to_string_lossy().into_owned()) }),
            });
        });
    }
    }
    {
        let (proxy, opener_id, window_id) = (proxy.clone(), id.clone(), window);
        builder = builder.with_new_window_req_handler(move |url, features| popup(&proxy, window_id, &opener_id, url, features));
    }

    #[cfg(target_os = "linux")]
    let webview = {
        use wry::WebViewBuilderExtUnix;
        if let Some(opener) = &opener {
            builder = builder.with_related_view(opener.webview.clone());
        }
        builder.build_gtk(&host_window.layout).map_err(|e| e.to_string())?
    };
    #[cfg(windows)]
    let webview = {
        use wry::WebViewBuilderExtWindows;
        if let Some(opener) = &opener {
            builder = builder.with_environment(opener.environment.clone());
        }
        builder.build_as_child(&host_window.window).map_err(|e| e.to_string())?
    };
    #[cfg(not(any(target_os = "linux", windows)))]
    let webview = builder.build_as_child(&host_window.window).map_err(|e| e.to_string())?;

    let state = platform::setup_page(&webview, &id, &proxy, &app.keys, options.dev_hooks);
    let native = opener.as_ref().map(|_| platform::native_view(&webview));
    Ok((
        Page { id, window, webview, dev_hooks: options.dev_hooks, visible: false, frame: None, platform: state },
        native,
    ))
}

#[cfg(target_os = "linux")]
pub type NativeView = webkit2gtk::WebView;
#[cfg(windows)]
pub type NativeView = webview2_com::Microsoft::Web::WebView2::Win32::ICoreWebView2;
#[cfg(not(any(target_os = "linux", windows)))]
pub type NativeView = ();

/// `target=_blank` and `window.open`: a new column with its own webview, tied to
/// the opener so `window.opener` works (OAuth sign-in flows need it).
fn popup(proxy: &Proxy, window: u64, opener: &str, url: String, features: wry::NewWindowFeatures) -> NewWindowResponse {
    let id = uuid::Uuid::new_v4().to_string();
    let created = with_app(|app| {
        let options = Options { url: None, ..Default::default() };
        let dev_hooks = app.pages.get(opener).map(|p| p.dev_hooks).unwrap_or(false);
        let options = Options { dev_hooks, ..options };
        create(app, window, id.clone(), options, Some(features.opener)).map(|(page, native)| {
            app.pages.insert(id.clone(), page);
            native
        })
    });
    match created {
        Some(Ok(Some(native))) => {
            let _ = proxy.send_event(UserEvent::Page { page: id, name: "page.popup", payload: json!({ "opener": opener, "url": url }) });
            #[cfg(any(target_os = "linux", windows))]
            return NewWindowResponse::Create { webview: native };
            #[cfg(not(any(target_os = "linux", windows)))]
            {
                let _ = native;
                NewWindowResponse::Deny
            }
        }
        _ => {
            // Couldn't make a related webview right now: open it as a plain column.
            let _ = proxy.send_event(UserEvent::Page {
                page: opener.to_string(),
                name: "page.message",
                payload: json!({ "channel": scripts::CHANNEL, "message": { "type": "openLink", "href": url, "background": false } }),
            });
            NewWindowResponse::Deny
        }
    }
}

/// A message a page posted through the bridge.
pub fn dispatch_message(proxy: &Proxy, page: &str, channel: &str, message: Value) {
    let event = if channel == scripts::REPLY_CHANNEL || channel == scripts::PAGE_REPLY_CHANNEL {
        let id = message.get("id").and_then(Value::as_u64).unwrap_or(0);
        let result = if message.get("ok").and_then(Value::as_bool).unwrap_or(false) {
            Ok(message.get("value").cloned().unwrap_or(Value::Null))
        } else {
            Err(message.get("error").and_then(Value::as_str).unwrap_or("script error").to_string())
        };
        UserEvent::PageReply { page: page.to_string(), id, result }
    } else {
        UserEvent::Page { page: page.to_string(), name: "page.message", payload: json!({ "channel": channel, "message": message }) }
    };
    let _ = proxy.send_event(event);
}

impl Page {
    pub fn load(&self, url: &str) {
        let _ = self.webview.load_url(url);
    }

    /// Runs `body` (an async function body) in `world` and routes its result to
    /// eval `id` (see `scripts::with_reply`).
    pub fn eval_with_reply(&self, body: &str, world: World, id: u64) {
        platform::eval(&self.webview, &scripts::with_reply(body, world.reply_channel(), id), world);
    }

    pub fn eval(&self, script: &str, world: World) {
        platform::eval(&self.webview, script, world);
    }

    pub fn set_frame(&mut self, frame: Option<(f64, f64, f64, f64, f64)>, layout: &crate::window::BrowserWindow) {
        match frame {
            Some(rect) => {
                if self.frame != Some(rect) {
                    platform::set_frame(&self.webview, rect, layout);
                    self.frame = Some(rect);
                }
                if !self.visible {
                    let _ = self.webview.set_visible(true);
                    self.visible = true;
                }
            }
            None => {
                if self.visible {
                    let _ = self.webview.set_visible(false);
                    self.visible = false;
                }
            }
        }
    }

    pub fn set_dev_hooks(&mut self, on: bool) {
        if on == self.dev_hooks {
            return;
        }
        self.dev_hooks = on;
        platform::set_dev_hooks(&self.webview, &self.platform, on);
    }
}

pub fn downloads_dir() -> PathBuf {
    dirs::download_dir().unwrap_or_else(|| dirs::home_dir().unwrap_or_default())
}

fn file_name_from_url(url: &str) -> String {
    let path = url.split(['?', '#']).next().unwrap_or("");
    let name = path.rsplit('/').next().unwrap_or("").trim();
    if name.is_empty() { "download".into() } else { name.to_string() }
}

/// `name`, or `name (2)`, `name (3)`… if taken.
fn unique_path(folder: &std::path::Path, name: &str) -> PathBuf {
    let clean: String = name.chars().map(|c| if "/\\:*?\"<>|".contains(c) { '_' } else { c }).collect();
    let first = folder.join(&clean);
    if !first.exists() {
        return first;
    }
    let (stem, ext) = match clean.rfind('.') {
        Some(i) if i > 0 => (&clean[..i], &clean[i..]),
        _ => (clean.as_str(), ""),
    };
    (2..10_000).map(|n| folder.join(format!("{stem} ({n}){ext}"))).find(|p| !p.exists()).unwrap_or(first)
}

/// Where a download goes: the Downloads folder, under the name the server
/// suggested (or the URL's last path segment), made unique.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn unique_download_path(suggested: &str, url: &str) -> PathBuf {
    let name = if suggested.trim().is_empty() { file_name_from_url(url) } else { suggested.to_string() };
    unique_path(&downloads_dir(), &name)
}
