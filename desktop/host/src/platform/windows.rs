//! WebView2: page state events, snapshots, shortcuts and scripts.
//!
//! Limitations, compared with WebKit:
//! - No isolated worlds for injected scripts: Wake's scripts share the page's
//!   world (namespaced under `__wake`), so a page could read or fake them.
//! - No load progress: it is synthesized from navigation events (start, content
//!   loading, DOMContentLoaded, completed).

use super::{accelerator, SnapshotDone};
use crate::page::World;
use crate::{scripts, Keymap, Proxy, UserEvent};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::rc::Rc;
use webview2_com::Microsoft::Web::WebView2::Win32::*;
use webview2_com::*;
use windows::core::{Interface, BOOL, PWSTR};
use windows::Win32::System::Com::{IStream, STREAM_SEEK_SET};
use windows::Win32::UI::Input::KeyboardAndMouse::{GetKeyState, VK_CONTROL, VK_LWIN, VK_MENU, VK_RWIN, VK_SHIFT};
use windows::Win32::UI::Shell::SHCreateMemStream;
use wry::WebViewExtWindows;

pub struct PageState {
    /// The id of the developer-hooks document script, while developer mode is on.
    dev_script: Rc<RefCell<Option<String>>>,
}

pub fn native_view(webview: &wry::WebView) -> ICoreWebView2 {
    webview.webview()
}

pub fn setup_downloads(_context: &wry::WebContext, _proxy: &Proxy) {
    // wry registers WebView2's download handlers per webview (see page.rs).
}

pub fn setup_page(webview: &wry::WebView, id: &str, proxy: &Proxy, keys: &Keymap, dev_hooks: bool) -> PageState {
    let state = PageState { dev_script: Rc::new(RefCell::new(None)) };
    let core = webview.webview();
    let controller = webview.controller();
    if dev_hooks {
        add_dev_script(&core, &state);
    }
    let send = {
        let (proxy, page) = (proxy.clone(), id.to_string());
        move |name: &'static str, payload: Value| {
            let _ = proxy.send_event(UserEvent::Page { page: page.clone(), name, payload });
        }
    };
    let mut token = 0i64;
    unsafe {
        {
            let send = send.clone();
            let _ = core.add_SourceChanged(
                &SourceChangedEventHandler::create(Box::new(move |sender, _| {
                    if let Some(core) = sender {
                        send("page.state", json!({ "url": source(&core) }));
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_HistoryChanged(
                &HistoryChangedEventHandler::create(Box::new(move |sender, _| {
                    if let Some(core) = sender {
                        let (mut back, mut forward) = (BOOL::default(), BOOL::default());
                        let _ = core.CanGoBack(&mut back);
                        let _ = core.CanGoForward(&mut forward);
                        send("page.state", json!({ "canGoBack": back.as_bool(), "canGoForward": forward.as_bool() }));
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_NavigationStarting(
                &NavigationStartingEventHandler::create(Box::new(move |_, _| {
                    send("page.state", json!({ "loading": true, "progress": 0.1 }));
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_ContentLoading(
                &ContentLoadingEventHandler::create(Box::new(move |sender, _| {
                    let url = sender.as_ref().map(source).unwrap_or_default();
                    send("page.committed", json!({ "url": url, "secure": url.starts_with("https:") }));
                    send("page.state", json!({ "progress": 0.35 }));
                    Ok(())
                })),
                &mut token,
            );
        }
        if let Ok(core2) = core.cast::<ICoreWebView2_2>() {
            let send = send.clone();
            let _ = core2.add_DOMContentLoaded(
                &DOMContentLoadedEventHandler::create(Box::new(move |_, _| {
                    send("page.state", json!({ "progress": 0.7 }));
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_NavigationCompleted(
                &NavigationCompletedEventHandler::create(Box::new(move |sender, args| {
                    send("page.state", json!({ "loading": false, "progress": 1.0 }));
                    if let Some(args) = args {
                        if let Ok(args2) = args.cast::<ICoreWebView2NavigationCompletedEventArgs2>() {
                            let mut status = 0i32;
                            if args2.HttpStatusCode(&mut status).is_ok() && status > 0 {
                                send("page.response", json!({ "status": status }));
                            }
                        }
                        let mut success = BOOL::default();
                        let _ = args.IsSuccess(&mut success);
                        if !success.as_bool() {
                            let mut error = COREWEBVIEW2_WEB_ERROR_STATUS::default();
                            let _ = args.WebErrorStatus(&mut error);
                            if error != COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED && error != COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN {
                                let url = sender.as_ref().map(source).unwrap_or_default();
                                send("page.failed", json!({ "url": url, "message": web_error_message(error) }));
                            }
                        }
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_WindowCloseRequested(
                &WindowCloseRequestedEventHandler::create(Box::new(move |_, _| {
                    send("page.closeRequest", json!({}));
                    Ok(())
                })),
                &mut token,
            );
        }
        let _ = core.add_ProcessFailed(
            &ProcessFailedEventHandler::create(Box::new(move |sender, args| {
                if let (Some(core), Some(args)) = (sender, args) {
                    let mut kind = COREWEBVIEW2_PROCESS_FAILED_KIND::default();
                    let _ = args.ProcessFailedKind(&mut kind);
                    if kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED
                        || kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE
                    {
                        let _ = core.Reload();
                    }
                }
                Ok(())
            })),
            &mut token,
        );
        if let Ok(core8) = core.cast::<ICoreWebView2_8>() {
            let send = send.clone();
            let _ = core8.add_IsDocumentPlayingAudioChanged(
                &IsDocumentPlayingAudioChangedEventHandler::create(Box::new(move |sender, _| {
                    if let Some(core) = sender.and_then(|c| c.cast::<ICoreWebView2_8>().ok()) {
                        let mut playing = BOOL::default();
                        let _ = core.IsDocumentPlayingAudio(&mut playing);
                        send("page.state", json!({ "audio": playing.as_bool() }));
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = core.add_ContainsFullScreenElementChanged(
                &ContainsFullScreenElementChangedEventHandler::create(Box::new(move |sender, _| {
                    if let Some(core) = sender {
                        let mut on = BOOL::default();
                        let _ = core.ContainsFullScreenElement(&mut on);
                        send("page.fullscreen", json!({ "on": on.as_bool() }));
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let send = send.clone();
            let _ = controller.add_GotFocus(
                &FocusChangedEventHandler::create(Box::new(move |_, _| {
                    send("page.focused", json!({}));
                    Ok(())
                })),
                &mut token,
            );
        }
        {
            let (proxy, page, keys) = (proxy.clone(), id.to_string(), keys.clone());
            let _ = controller.add_AcceleratorKeyPressed(
                &AcceleratorKeyPressedEventHandler::create(Box::new(move |_, args| {
                    let Some(args) = args else { return Ok(()) };
                    let mut kind = COREWEBVIEW2_KEY_EVENT_KIND::default();
                    let _ = args.KeyEventKind(&mut kind);
                    if kind != COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN && kind != COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN {
                        return Ok(());
                    }
                    let mut key = 0u32;
                    let _ = args.VirtualKey(&mut key);
                    let Some(name) = key_name(key) else { return Ok(()) };
                    let down = |vk: u16| GetKeyState(vk as i32) as u16 & 0x8000 != 0;
                    let accel = accelerator(
                        down(VK_CONTROL.0),
                        down(VK_MENU.0),
                        down(VK_SHIFT.0),
                        down(VK_LWIN.0) || down(VK_RWIN.0),
                        &name,
                    );
                    if keys.borrow().contains(&accel) {
                        let _ = args.SetHandled(true);
                        let _ = proxy.send_event(UserEvent::Key { page: page.clone(), accel });
                    }
                    Ok(())
                })),
                &mut token,
            );
        }
    }
    state
}

fn source(core: &ICoreWebView2) -> String {
    let mut uri = PWSTR::null();
    if unsafe { core.Source(&mut uri) }.is_ok() {
        take_pwstr(uri)
    } else {
        String::new()
    }
}

fn web_error_message(error: COREWEBVIEW2_WEB_ERROR_STATUS) -> &'static str {
    match error {
        COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED => "A server with the specified hostname could not be found.",
        COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT => "Could not connect to the server.",
        COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT => "The request timed out.",
        COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED => "The Internet connection appears to be offline.",
        COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT
        | COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED
        | COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS
        | COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED
        | COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID => "The certificate for this server is invalid.",
        COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE => "The server can't be reached.",
        COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED | COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET => {
            "The network connection was lost."
        }
        _ => "The page couldn't be loaded.",
    }
}

fn key_name(vk: u32) -> Option<String> {
    let name = match vk {
        0x41..=0x5A => return Some(((vk as u8) as char).to_ascii_lowercase().to_string()),
        0x30..=0x39 => return Some(((vk as u8) as char).to_string()),
        0x60..=0x69 => return Some(((vk - 0x30) as u8 as char).to_string()),
        0x70..=0x7B => return Some(format!("f{}", vk - 0x6F)),
        0xBB | 0x6B => "=",
        0xBD | 0x6D => "-",
        0xDB => "[",
        0xDD => "]",
        0xBC => ",",
        0xBE => ".",
        0xBF => "/",
        0xBA => ";",
        0xC0 => "`",
        0xDE => "'",
        0xDC => "\\",
        0x25 => "arrowleft",
        0x26 => "arrowup",
        0x27 => "arrowright",
        0x28 => "arrowdown",
        0x1B => "escape",
        0x0D => "enter",
        0x09 => "tab",
        0x08 => "backspace",
        0x2E => "delete",
        0x20 => "space",
        0x21 => "pageup",
        0x22 => "pagedown",
        0x23 => "end",
        0x24 => "home",
        _ => return None,
    };
    Some(name.to_string())
}

pub fn eval(webview: &wry::WebView, script: &str, _world: World) {
    let _ = webview.evaluate_script(script);
}

pub fn set_frame(webview: &wry::WebView, (x, y, w, h, radius): (f64, f64, f64, f64, f64), window: &crate::window::BrowserWindow) {
    let (w, h) = (w.round().max(1.0), h.round().max(1.0));
    let _ = webview.set_bounds(wry::Rect {
        position: wry::dpi::LogicalPosition::new(x.round(), y.round()).into(),
        size: wry::dpi::LogicalSize::new(w, h).into(),
    });
    // Round the page's corners to match its card: a child window can't be
    // transparent, so clip it to a rounded region (not antialiased; at card
    // radii the steps are a pixel or two).
    let scale = window.window.scale_factor();
    let (pw, ph) = ((w * scale).round() as i32, (h * scale).round() as i32);
    let diameter = (radius * scale * 2.0).round() as i32;
    unsafe {
        use windows::Win32::Graphics::Gdi::{CreateRoundRectRgn, SetWindowRgn};
        let region = if diameter > 0 { Some(CreateRoundRectRgn(0, 0, pw + 1, ph + 1, diameter, diameter)) } else { None };
        // The window owns the region from here on.
        SetWindowRgn(webview.hwnd(), region, true);
    }
}

fn add_dev_script(core: &ICoreWebView2, state: &PageState) {
    let slot = state.dev_script.clone();
    let script = CoTaskMemPWSTR::from(scripts::dev_hooks_script().as_str());
    unsafe {
        let _ = core.AddScriptToExecuteOnDocumentCreated(
            *script.as_ref().as_pcwstr(),
            &AddScriptToExecuteOnDocumentCreatedCompletedHandler::create(Box::new(move |result, id| {
                if result.is_ok() {
                    *slot.borrow_mut() = Some(id);
                }
                Ok(())
            })),
        );
    }
}

pub fn set_dev_hooks(webview: &wry::WebView, state: &PageState, on: bool) {
    let core = webview.webview();
    if on {
        add_dev_script(&core, state);
    } else if let Some(id) = state.dev_script.borrow_mut().take() {
        let id = CoTaskMemPWSTR::from(id.as_str());
        unsafe {
            let _ = core.RemoveScriptToExecuteOnDocumentCreated(*id.as_ref().as_pcwstr());
        }
    }
}

pub fn set_user_agent(webview: &wry::WebView, agent: Option<&str>) {
    unsafe {
        if let Ok(settings) = webview.webview().Settings().and_then(|s| s.cast::<ICoreWebView2Settings2>()) {
            // An empty string restores the default agent.
            let agent = CoTaskMemPWSTR::from(agent.unwrap_or(""));
            let _ = settings.SetUserAgent(*agent.as_ref().as_pcwstr());
        }
    }
}

pub fn set_javascript_enabled(webview: &wry::WebView, on: bool) {
    unsafe {
        if let Ok(settings) = webview.webview().Settings() {
            let _ = settings.SetIsScriptEnabled(on);
        }
    }
}

pub fn reload_bypassing_cache(webview: &wry::WebView) {
    let method = CoTaskMemPWSTR::from("Page.reload");
    let params = CoTaskMemPWSTR::from(r#"{"ignoreCache":true}"#);
    unsafe {
        let _ = webview.webview().CallDevToolsProtocolMethod(
            *method.as_ref().as_pcwstr(),
            *params.as_ref().as_pcwstr(),
            &CallDevToolsProtocolMethodCompletedHandler::create(Box::new(|_, _| Ok(()))),
        );
    }
}

pub fn stop(webview: &wry::WebView) {
    unsafe {
        let _ = webview.webview().Stop();
    }
}

/// The visible part of the page, as JPEG, scaled to `max_width`.
pub fn snapshot(webview: &wry::WebView, max_width: u32, done: SnapshotDone) {
    let core = webview.webview();
    let Some(stream) = (unsafe { SHCreateMemStream(None) }) else { return done(Err("no stream".into())) };
    let target = stream.clone();
    let done = RefCell::new(Some(done));
    let result = unsafe {
        core.CapturePreview(
            COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_JPEG,
            &stream,
            &CapturePreviewCompletedHandler::create(Box::new(move |result| {
                let Some(done) = done.borrow_mut().take() else { return Ok(()) };
                if let Err(error) = result {
                    done(Err(error.to_string()));
                    return Ok(());
                }
                let bytes = read_stream(&target);
                std::thread::spawn(move || {
                    let decoded = image::load_from_memory(&bytes).map_err(|e| e.to_string());
                    done(decoded.and_then(|image| super::encode_jpeg(image.to_rgb8(), max_width)));
                });
                Ok(())
            })),
        )
    };
    if let Err(error) = result {
        eprintln!("CapturePreview failed: {error}");
    }
}

fn read_stream(stream: &IStream) -> Vec<u8> {
    let mut bytes = Vec::new();
    unsafe {
        if stream.Seek(0, STREAM_SEEK_SET, None).is_err() {
            return bytes;
        }
        let mut chunk = vec![0u8; 64 * 1024];
        loop {
            let mut read = 0u32;
            let hr = stream.Read(chunk.as_mut_ptr() as *mut _, chunk.len() as u32, Some(&mut read));
            if hr.is_err() || read == 0 {
                break;
            }
            bytes.extend_from_slice(&chunk[..read as usize]);
        }
    }
    bytes
}

pub fn open_inspector(webview: &wry::WebView) {
    unsafe {
        let _ = webview.webview().OpenDevToolsWindow();
    }
}

/// Empties the engine's caches (`cache_only`), or every kind of website data.
pub fn clear_data(webview: &wry::WebView, cache_only: bool, done: super::DataDone) {
    let profile = webview
        .webview()
        .cast::<ICoreWebView2_13>()
        .and_then(|core| unsafe { core.Profile() })
        .and_then(|profile| profile.cast::<ICoreWebView2Profile2>());
    let profile = match profile {
        Ok(profile) => profile,
        Err(error) => return done(Err(error.to_string())),
    };
    let kinds = if cache_only {
        COREWEBVIEW2_BROWSING_DATA_KINDS(COREWEBVIEW2_BROWSING_DATA_KINDS_DISK_CACHE.0 | COREWEBVIEW2_BROWSING_DATA_KINDS_CACHE_STORAGE.0)
    } else {
        COREWEBVIEW2_BROWSING_DATA_KINDS_ALL_PROFILE
    };
    let done = RefCell::new(Some(done));
    let result = unsafe {
        profile.ClearBrowsingData(
            kinds,
            &ClearBrowsingDataCompletedHandler::create(Box::new(move |result| {
                if let Some(done) = done.borrow_mut().take() {
                    done(result.map_err(|e| e.to_string()));
                }
                Ok(())
            })),
        )
    };
    if let Err(error) = result {
        eprintln!("ClearBrowsingData failed: {error}");
    }
}

fn devtools_protocol(webview: &wry::WebView, method: &str, params: &str) {
    let method = CoTaskMemPWSTR::from(method);
    let params = CoTaskMemPWSTR::from(params);
    unsafe {
        let _ = webview.webview().CallDevToolsProtocolMethod(
            *method.as_ref().as_pcwstr(),
            *params.as_ref().as_pcwstr(),
            &CallDevToolsProtocolMethodCompletedHandler::create(Box::new(|_, _| Ok(()))),
        );
    }
}

/// Cookies, storage, caches and databases for one site (DevTools ▸ Clear Site Data).
pub fn clear_site_data(webview: &wry::WebView, host: &str, done: super::DataDone) {
    for scheme in ["https", "http"] {
        let params = serde_json::json!({ "origin": format!("{scheme}://{host}"), "storageTypes": "all" }).to_string();
        devtools_protocol(webview, "Storage.clearDataForOrigin", &params);
    }
    done(Ok(()));
}

/// `prefers-color-scheme` for one page, through the DevTools protocol's media emulation.
pub fn set_color_scheme(webview: &wry::WebView, scheme: &str) -> std::result::Result<(), String> {
    let value = match scheme {
        "light" | "dark" => scheme,
        _ => "",
    };
    let params = serde_json::json!({ "features": [{ "name": "prefers-color-scheme", "value": value }] }).to_string();
    devtools_protocol(webview, "Emulation.setEmulatedMedia", &params);
    Ok(())
}

/// Loads `html` as if it were `url`: the request is answered locally, so the
/// document runs with the site's origin and storage without reaching the site.
pub fn load_as_origin(webview: &wry::WebView, url: &str, html: &str) {
    let core = webview.webview();
    let environment = webview.environment();
    let filter = CoTaskMemPWSTR::from(url);
    let target = url.to_string();
    let body = html.as_bytes().to_vec();
    let mut token = 0i64;
    unsafe {
        let _ = core.AddWebResourceRequestedFilter(*filter.as_ref().as_pcwstr(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT);
        let _ = core.add_WebResourceRequested(
            &WebResourceRequestedEventHandler::create(Box::new(move |_, args| {
                let Some(args) = args else { return Ok(()) };
                let request = args.Request()?;
                let mut uri = PWSTR::null();
                request.Uri(&mut uri)?;
                if take_pwstr(uri) != target {
                    return Ok(());
                }
                let stream = SHCreateMemStream(Some(&body));
                let reason = CoTaskMemPWSTR::from("OK");
                let headers = CoTaskMemPWSTR::from("Content-Type: text/html; charset=utf-8");
                let response = environment.CreateWebResourceResponse(stream.as_ref(), 200, *reason.as_ref().as_pcwstr(), *headers.as_ref().as_pcwstr())?;
                args.SetResponse(&response)?;
                Ok(())
            })),
            &mut token,
        );
        let navigate = CoTaskMemPWSTR::from(url);
        let _ = core.Navigate(*navigate.as_ref().as_pcwstr());
    }
}
