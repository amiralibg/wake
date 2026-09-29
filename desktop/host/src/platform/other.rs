//! Stubs so the host type-checks on macOS (`cargo check`). It doesn't run there:
//! the Mac app is the Swift one in `Wake/`.

use super::SnapshotDone;
use crate::page::World;
use crate::{Keymap, Proxy};

pub struct PageState;

pub fn native_view(_webview: &wry::WebView) {}
pub fn setup_downloads(_context: &wry::WebContext, _proxy: &Proxy) {}
pub fn setup_page(_webview: &wry::WebView, _id: &str, _proxy: &Proxy, _keys: &Keymap, _dev_hooks: bool) -> PageState {
    PageState
}
pub fn eval(webview: &wry::WebView, script: &str, _world: World) {
    let _ = webview.evaluate_script(script);
}
pub fn set_frame(_webview: &wry::WebView, _frame: (f64, f64, f64, f64), _window: &crate::window::BrowserWindow) {}
pub fn set_dev_hooks(_webview: &wry::WebView, _state: &PageState, _on: bool) {}
pub fn set_user_agent(_webview: &wry::WebView, _agent: Option<&str>) {}
pub fn set_javascript_enabled(_webview: &wry::WebView, _on: bool) {}
pub fn reload_bypassing_cache(webview: &wry::WebView) {
    let _ = webview.reload();
}
pub fn stop(_webview: &wry::WebView) {}
pub fn snapshot(_webview: &wry::WebView, _max_width: u32, done: SnapshotDone) {
    done(Err("unsupported".into()));
}
pub fn open_inspector(webview: &wry::WebView) {
    webview.open_devtools();
}
pub fn clear_data(_webview: &wry::WebView, _cache_only: bool, done: super::DataDone) {
    done(Err("unsupported".into()));
}
pub fn clear_site_data(_webview: &wry::WebView, _host: &str, done: super::DataDone) {
    done(Err("unsupported".into()));
}
pub fn set_color_scheme(_webview: &wry::WebView, _scheme: &str) -> Result<(), String> {
    Err("unsupported".into())
}
pub fn load_as_origin(webview: &wry::WebView, url: &str, _html: &str) {
    let _ = webview.load_url(url);
}
