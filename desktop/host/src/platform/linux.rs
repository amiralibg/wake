//! WebKitGTK (webkit2gtk-4.1): script worlds, message handlers, page state
//! signals, snapshots, shortcuts and downloads.

use super::{accelerator, SnapshotDone};
use crate::page::World;
use crate::{page, scripts, Keymap, Proxy, UserEvent};
use gtk::prelude::*;
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use webkit2gtk::{
    DownloadExt, LoadEvent, PolicyDecisionType, ResponsePolicyDecision, ResponsePolicyDecisionExt,
    SettingsExt, SnapshotOptions, SnapshotRegion, URIRequestExt, URIResponseExt, UserContentInjectedFrames,
    UserContentManagerExt, UserScript, UserScriptInjectionTime, WebContextExt, WebViewExt,
};
use wry::WebViewExtUnix;

/// Wake's own script world. Pages can't see into it (see shared/README.md).
pub const WORLD: &str = "wake";

pub struct PageState;

thread_local! {
    /// WebKit views → page ids, for context-wide signals (downloads).
    static PAGE_IDS: RefCell<HashMap<usize, String>> = RefCell::new(HashMap::new());
}

pub fn prepare() {
    // A GPU in a VM or container often can't do WebKit's accelerated compositing;
    // WAKE_NO_GPU=1 turns it off without touching the user's environment otherwise.
    if std::env::var("WAKE_NO_GPU").is_ok() {
        std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
}

pub fn native_view(webview: &wry::WebView) -> webkit2gtk::WebView {
    webview.webview()
}

fn install_scripts(manager: &webkit2gtk::UserContentManager, dev_hooks: bool) {
    manager.remove_all_scripts();
    manager.add_script(&UserScript::for_world(
        &scripts::base_script(),
        UserContentInjectedFrames::TopFrame,
        UserScriptInjectionTime::Start,
        WORLD,
        &[],
        &[],
    ));
    if dev_hooks {
        manager.add_script(&UserScript::new(
            &scripts::dev_hooks_script(),
            UserContentInjectedFrames::TopFrame,
            UserScriptInjectionTime::Start,
            &[],
            &[],
        ));
    }
}

pub fn setup_page(webview: &wry::WebView, id: &str, proxy: &Proxy, keys: &Keymap, dev_hooks: bool) -> PageState {
    let view = webview.webview();
    PAGE_IDS.with(|ids| ids.borrow_mut().insert(view.as_ptr() as usize, id.to_string()));
    attach_downloads(&view, proxy);
    {
        let id = id.to_string();
        view.connect_destroy(move |view| {
            PAGE_IDS.with(|ids| ids.borrow_mut().remove(&(view.as_ptr() as usize)));
            let _ = &id;
        });
    }

    if let Some(manager) = view.user_content_manager() {
        // Replaces wry's page-world `window.ipc` script too: pages don't need it.
        install_scripts(&manager, dev_hooks);
        let handlers: [(&'static str, Option<&str>); 6] = [
            (scripts::CHANNEL, Some(WORLD)),
            (scripts::REPLY_CHANNEL, Some(WORLD)),
            (scripts::POPOUT_CHANNEL, Some(WORLD)),
            (scripts::DEV_CHANNEL, None),
            (scripts::DEVTOOLS_CHANNEL, None),
            (scripts::PAGE_REPLY_CHANNEL, None),
        ];
        for (name, world) in handlers {
            let (proxy, page) = (proxy.clone(), id.to_string());
            manager.connect_script_message_received(Some(name), move |_, result| {
                let message = result
                    .js_value()
                    .and_then(|value| javascriptcore::ValueExt::to_json(&value, 0))
                    .and_then(|json| serde_json::from_str::<Value>(json.as_str()).ok())
                    .unwrap_or(Value::Null);
                page::dispatch_message(&proxy, &page, name, message);
            });
            match world {
                Some(world) => manager.register_script_message_handler_in_world(name, world),
                None => manager.register_script_message_handler(name),
            };
        }
    }

    let send = {
        let (proxy, page) = (proxy.clone(), id.to_string());
        move |name: &'static str, payload: Value| {
            let _ = proxy.send_event(UserEvent::Page { page: page.clone(), name, payload });
        }
    };

    {
        let send = send.clone();
        let last = RefCell::new(0.0f64);
        view.connect_estimated_load_progress_notify(move |view| {
            // Only steps of 2% or the ends: each one re-renders the loading line.
            let value = view.estimated_load_progress();
            let mut last = last.borrow_mut();
            if (value - *last).abs() >= 0.02 || value >= 1.0 || value < *last {
                *last = value;
                send("page.state", json!({ "progress": value }));
            }
        });
    }
    {
        let send = send.clone();
        // Also covers same-document navigations (pushState), which change the
        // back list without a load. (The list's own "changed" signal isn't bound.)
        view.connect_uri_notify(move |view| {
            send("page.state", json!({
                "url": view.uri().map(|u| u.to_string()),
                "canGoBack": view.can_go_back(),
                "canGoForward": view.can_go_forward(),
            }));
        });
    }
    {
        let send = send.clone();
        view.connect_is_loading_notify(move |view| {
            send("page.state", json!({ "loading": view.is_loading() }));
        });
    }
    {
        let send = send.clone();
        view.connect_load_changed(move |view, event| {
            if event == LoadEvent::Committed {
                send("page.committed", json!({
                    "url": view.uri().map(|u| u.to_string()),
                    "secure": view.tls_info().is_some(),
                }));
            }
            if event == LoadEvent::Committed || event == LoadEvent::Finished {
                send("page.state", json!({ "canGoBack": view.can_go_back(), "canGoForward": view.can_go_forward() }));
            }
        });
    }
    {
        let send = send.clone();
        view.connect_load_failed(move |_, _, uri, error| {
            let message = error.message().to_string();
            // Cancelled loads, and navigations that became downloads or were
            // handed to the media player, aren't failures.
            let benign = error.matches(webkit2gtk::NetworkError::Cancelled)
                || error.matches(webkit2gtk::PolicyError::FrameLoadInterruptedByPolicyChange)
                || error.matches(webkit2gtk::PluginError::WillHandleLoad);
            if !benign {
                send("page.failed", json!({ "url": uri, "message": message }));
            }
            false
        });
    }
    {
        let send = send.clone();
        view.connect_decide_policy(move |_, decision, kind| {
            if kind == PolicyDecisionType::Response {
                if let Some(decision) = decision.downcast_ref::<ResponsePolicyDecision>() {
                    if decision.is_main_frame_main_resource() {
                        if let Some(response) = decision.response() {
                            send("page.response", json!({
                                "status": response.status_code(),
                                "mime": response.mime_type().map(|m| m.to_string()),
                            }));
                        }
                    }
                }
            }
            false
        });
    }
    {
        let send = send.clone();
        view.connect_close(move |_| send("page.closeRequest", json!({})));
    }
    view.connect_web_process_terminated(|view, _| view.reload());
    {
        let send = send.clone();
        view.connect_focus_in_event(move |_, _| {
            send("page.focused", json!({}));
            glib::Propagation::Proceed
        });
    }
    {
        let send = send.clone();
        view.connect_is_playing_audio_notify(move |view| send("page.state", json!({ "audio": view.is_playing_audio() })));
    }
    {
        let send = send.clone();
        view.connect_enter_fullscreen(move |_| {
            send("page.fullscreen", json!({ "on": true }));
            false
        });
    }
    {
        let send = send.clone();
        view.connect_leave_fullscreen(move |_| {
            send("page.fullscreen", json!({ "on": false }));
            false
        });
    }
    {
        let (proxy, page, keys) = (proxy.clone(), id.to_string(), keys.clone());
        view.connect_key_press_event(move |_, event| {
            let Some(accel) = accelerator_for(event) else { return glib::Propagation::Proceed };
            if keys.borrow().contains(&accel) {
                let _ = proxy.send_event(UserEvent::Key { page: page.clone(), accel });
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
    }
    // Middle-click and ⌘-click on links are handled by the link interceptor; the
    // default context menu is fine as it is.
    PageState
}

/// wry keeps its WebKit context private, so the one download handler is attached
/// through the first page's view (every page shares that context).
pub fn setup_downloads(_context: &wry::WebContext, _proxy: &Proxy) {}

thread_local! {
    static DOWNLOADS_READY: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// One download handler for the whole context, finding the page by its view.
fn attach_downloads(view: &webkit2gtk::WebView, proxy: &Proxy) {
    if DOWNLOADS_READY.with(|ready| ready.replace(true)) {
        return;
    }
    let Some(context) = view.context() else { return };
    let proxy = proxy.clone();
    context.connect_download_started(move |_, download| {
        let page = download
            .web_view()
            .and_then(|view| PAGE_IDS.with(|ids| ids.borrow().get(&(view.as_ptr() as usize)).cloned()))
            .unwrap_or_default();
        let url = download.request().and_then(|r| r.uri()).map(|u| u.to_string()).unwrap_or_default();
        {
            let (proxy, page, url) = (proxy.clone(), page.clone(), url.clone());
            download.connect_decide_destination(move |download, suggested| {
                let path = crate::page::unique_download_path(suggested, &url);
                download.set_destination(&format!("file://{}", path.to_string_lossy()));
                let _ = proxy.send_event(UserEvent::Page {
                    page: page.clone(),
                    name: "page.download",
                    payload: json!({ "state": "started", "url": url, "path": path.to_string_lossy() }),
                });
                true
            });
        }
        {
            let (proxy, page, url) = (proxy.clone(), page.clone(), url.clone());
            let failed = std::rc::Rc::new(std::cell::Cell::new(false));
            let flag = failed.clone();
            download.connect_failed(move |_, _| flag.set(true));
            download.connect_finished(move |download| {
                let path = download.destination().map(|d| d.trim_start_matches("file://").to_string());
                let _ = proxy.send_event(UserEvent::Page {
                    page: page.clone(),
                    name: "page.download",
                    payload: json!({ "state": if failed.get() { "failed" } else { "finished" }, "url": url, "path": path }),
                });
            });
        }
    });
}

fn accelerator_for(event: &gdk::EventKey) -> Option<String> {
    let state = event.state();
    // The key at this position without Shift, in the first layout: ⇧⌘= stays "=",
    // and shortcuts keep working on non-Latin layouts that list a Latin one first.
    let keyval = gdk::Display::default()
        .and_then(|display| gdk::Keymap::for_display(&display))
        .and_then(|map| map.translate_keyboard_state(event.hardware_keycode() as u32, gdk::ModifierType::empty(), 0))
        .map(|(keyval, _, _, _)| gdk::keys::Key::from(keyval))
        .unwrap_or_else(|| event.keyval());
    let name = key_name(keyval.to_lower().name()?.as_str())?;
    Some(accelerator(
        state.contains(gdk::ModifierType::CONTROL_MASK),
        state.contains(gdk::ModifierType::MOD1_MASK),
        state.contains(gdk::ModifierType::SHIFT_MASK),
        state.contains(gdk::ModifierType::SUPER_MASK),
        &name,
    ))
}

fn key_name(gdk_name: &str) -> Option<String> {
    let name = match gdk_name {
        "equal" | "plus" | "KP_Add" => "=",
        "minus" | "underscore" | "KP_Subtract" => "-",
        "bracketleft" => "[",
        "bracketright" => "]",
        "comma" | "less" => ",",
        "period" | "greater" => ".",
        "slash" | "question" => "/",
        "semicolon" => ";",
        "grave" => "`",
        "apostrophe" => "'",
        "backslash" => "\\",
        "Left" => "arrowleft",
        "Right" => "arrowright",
        "Up" => "arrowup",
        "Down" => "arrowdown",
        "Escape" => "escape",
        "Return" | "KP_Enter" => "enter",
        "Tab" | "ISO_Left_Tab" => "tab",
        "BackSpace" => "backspace",
        "Delete" => "delete",
        "space" => "space",
        "Page_Up" => "pageup",
        "Page_Down" => "pagedown",
        "Home" => "home",
        "End" => "end",
        other if other.len() == 1 => return Some(other.to_ascii_lowercase()),
        other if other.starts_with('F') && other[1..].parse::<u8>().is_ok() => return Some(other.to_ascii_lowercase()),
        _ => return None,
    };
    Some(name.to_string())
}

pub fn eval(webview: &wry::WebView, script: &str, world: World) {
    let view = webview.webview();
    let world = match world {
        World::Wake => Some(WORLD),
        World::Page => None,
    };
    view.evaluate_javascript(script, world, None, None::<&gtk::gio::Cancellable>, |_| {});
}

pub fn set_frame(webview: &wry::WebView, (x, y, w, h): (f64, f64, f64, f64), window: &crate::window::BrowserWindow) {
    let view = webview.webview();
    window.layout.move_(&view, x.round() as i32, y.round() as i32);
    view.set_size_request(w.round().max(1.0) as i32, h.round().max(1.0) as i32);
}

pub fn set_dev_hooks(webview: &wry::WebView, _state: &PageState, on: bool) {
    if let Some(manager) = webview.webview().user_content_manager() {
        install_scripts(&manager, on);
    }
}

pub fn set_user_agent(webview: &wry::WebView, agent: Option<&str>) {
    if let Some(settings) = WebViewExt::settings(&webview.webview()) {
        settings.set_user_agent(agent);
    }
}

pub fn set_javascript_enabled(webview: &wry::WebView, on: bool) {
    if let Some(settings) = WebViewExt::settings(&webview.webview()) {
        settings.set_enable_javascript(on);
    }
}

pub fn reload_bypassing_cache(webview: &wry::WebView) {
    webview.webview().reload_bypass_cache();
}

pub fn stop(webview: &wry::WebView) {
    webview.webview().stop_loading();
}

/// The visible part of the page, as JPEG, scaled to `max_width`.
pub fn snapshot(webview: &wry::WebView, max_width: u32, done: SnapshotDone) {
    let view = webview.webview();
    view.snapshot(SnapshotRegion::Visible, SnapshotOptions::NONE, None::<&gtk::gio::Cancellable>, move |result| {
        let surface = match result {
            Ok(surface) => surface,
            Err(error) => return done(Err(error.to_string())),
        };
        let Ok(mut image) = cairo::ImageSurface::try_from(surface) else { return done(Err("not an image surface".into())) };
        let (width, height, stride) = (image.width() as u32, image.height() as u32, image.stride() as usize);
        if width == 0 || height == 0 {
            return done(Err("empty snapshot".into()));
        }
        image.flush();
        let pixels = match image.data() {
            Ok(data) => data.to_vec(),
            Err(error) => return done(Err(error.to_string())),
        };
        // Encoding is the slow part: off the main thread.
        std::thread::spawn(move || {
            let mut rgb = image::RgbImage::new(width, height);
            for y in 0..height as usize {
                let row = &pixels[y * stride..y * stride + width as usize * 4];
                for x in 0..width as usize {
                    // Cairo ARGB32, little-endian: B, G, R, A (premultiplied; pages are opaque).
                    let p = &row[x * 4..x * 4 + 4];
                    rgb.put_pixel(x as u32, y as u32, image::Rgb([p[2], p[1], p[0]]));
                }
            }
            done(super::encode_jpeg(rgb, max_width));
        });
    });
}

pub fn open_inspector(webview: &wry::WebView) {
    if let Some(inspector) = webview.webview().inspector() {
        use webkit2gtk::WebInspectorExt;
        inspector.show();
    }
}

/// Empties the engine's caches (`cache_only`), or every kind of website data.
pub fn clear_data(webview: &wry::WebView, cache_only: bool, done: super::DataDone) {
    use webkit2gtk::{WebsiteDataManagerExtManual, WebsiteDataTypes};
    let Some(manager) = WebViewExt::context(&webview.webview()).and_then(|c| c.website_data_manager()) else {
        return done(Err("no website data manager".into()));
    };
    let types = if cache_only {
        WebsiteDataTypes::DISK_CACHE | WebsiteDataTypes::MEMORY_CACHE
    } else {
        WebsiteDataTypes::ALL
    };
    // A timespan of 0: everything, however old.
    manager.clear(types, glib::TimeSpan::from_seconds(0), None::<&gtk::gio::Cancellable>, move |result| {
        done(result.map_err(|e| e.to_string()))
    });
}

/// Cookies, storage, caches and databases for one site (DevTools ▸ Clear Site Data).
pub fn clear_site_data(webview: &wry::WebView, host: &str, done: super::DataDone) {
    use webkit2gtk::{WebsiteDataManagerExt, WebsiteDataManagerExtManual, WebsiteDataTypes};
    let Some(manager) = WebViewExt::context(&webview.webview()).and_then(|c| c.website_data_manager()) else {
        return done(Err("no website data manager".into()));
    };
    let host = host.to_lowercase();
    let target = manager.clone();
    manager.fetch(WebsiteDataTypes::ALL, None::<&gtk::gio::Cancellable>, move |result| {
        let records = match result {
            Ok(records) => records,
            Err(error) => return done(Err(error.to_string())),
        };
        let matching: Vec<_> = records
            .iter()
            .filter(|r| r.name().map_or(false, |name| host == name.as_str() || host.ends_with(&format!(".{name}"))))
            .collect();
        if matching.is_empty() {
            return done(Ok(()));
        }
        target.remove(WebsiteDataTypes::ALL, &matching, None::<&gtk::gio::Cancellable>, move |result| done(result.map_err(|e| e.to_string())));
    });
}

/// `prefers-color-scheme` for one page.
///
/// Limitation: WebKitGTK has no per-view override (only the whole GTK theme), so
/// DevTools' color scheme override isn't available on Linux.
pub fn set_color_scheme(_webview: &wry::WebView, _scheme: &str) -> Result<(), String> {
    Err("WebKitGTK can't override the color scheme for one page.".into())
}

/// Loads `html` as if it were `url`: the document runs with the site's origin and
/// storage, but nothing is requested from the site (importing localStorage).
pub fn load_as_origin(webview: &wry::WebView, url: &str, html: &str) {
    webview.webview().load_alternate_html(html, url, Some(url));
}
