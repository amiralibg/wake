//! A browser window: a borderless tao window whose whole area is the shell
//! webview (Wake's UI). Page webviews are added on top of it at the rectangles the
//! UI asks for; nothing draws over a page, so whenever the UI needs to (the Deck,
//! the palette, menus) it hides the pages and draws their snapshots instead.

use crate::{assets, App, Target, UserEvent};
use serde_json::{json, Value};
use tao::dpi::LogicalSize;
use tao::window::{Window, WindowBuilder};
use wry::{WebView, WebViewBuilder};

#[cfg(target_os = "linux")]
use gtk::prelude::*;

/// How a window is made: a browser window, or a Pop Out panel.
#[derive(Default, Clone)]
pub struct WindowOptions {
    pub popout: bool,
    pub size: Option<(f64, f64)>,
    /// Top-left, in logical screen coordinates.
    pub position: Option<(f64, f64)>,
}

pub struct BrowserWindow {
    pub id: u64,
    pub popout: bool,
    pub window: Window,
    pub shell: WebView,
    /// Page webviews live in a GtkFixed laid over the shell. As an overlay child it
    /// doesn't make the window grow to fit columns placed off to the side, and as
    /// a windowless widget it neither paints nor catches events where it's empty.
    #[cfg(target_os = "linux")]
    pub layout: gtk::Fixed,
    /// Bumped each time the window gains focus; the most recent is the "front" window.
    pub focus_order: u64,
}

impl BrowserWindow {
    pub fn new(id: u64, target: &Target, app: &mut App, query: &str, options: WindowOptions) -> Result<Self, String> {
        let (width, height) = options.size.unwrap_or((1320.0, 860.0));
        let mut builder = WindowBuilder::new()
            .with_title(if options.popout { "Pop Out" } else { "Wake" })
            .with_decorations(false)
            .with_window_icon(app_icon())
            .with_inner_size(LogicalSize::new(width, height));
        if options.popout {
            // A floating panel: above other windows, even while Wake is in the background.
            builder = builder.with_always_on_top(true).with_min_inner_size(LogicalSize::new(200.0, 80.0));
        } else {
            builder = builder.with_min_inner_size(LogicalSize::new(560.0, 420.0));
        }
        if let Some((x, y)) = options.position {
            builder = builder.with_position(tao::dpi::LogicalPosition::new(x, y));
        }
        #[cfg(windows)]
        let builder = {
            use tao::platform::windows::WindowBuilderExtWindows;
            builder.with_undecorated_shadow(true)
        };
        let window = builder.build(target).map_err(|e| e.to_string())?;

        let proxy = app.proxy.clone();
        let data_dir = app.data_dir.clone();
        let mut shell_builder = WebViewBuilder::new_with_web_context(&mut app.shell_context)
            .with_url(assets::ui_url(query))
            .with_ipc_handler(move |request| {
                let _ = proxy.send_event(UserEvent::Shell { window: id, message: request.into_body() });
            })
            .with_background_color((236, 238, 242, 255))
            .with_devtools(true)
            .with_hotkeys_zoom(false)
            .with_focused(true)
            .with_navigation_handler(|url| {
                // The UI never navigates away; links in it open through commands.
                url.starts_with("wake://") || url.starts_with("http://wake.localhost") || url == "about:blank"
            })
            .with_new_window_req_handler(|_, _| wry::NewWindowResponse::Deny);
        // WebKitGTK registers a scheme once per context; WebView2 per webview.
        if cfg!(windows) || !crate::protocol_registered() {
            shell_builder = shell_builder.with_custom_protocol("wake".into(), move |_id, request| assets::respond(&request, &data_dir));
            crate::set_protocol_registered();
        }

        #[cfg(target_os = "linux")]
        let (shell, layout) = {
            use tao::platform::unix::WindowExtUnix;
            use wry::WebViewBuilderExtUnix;
            // The shell is the overlay's main child, so it always fills the window; the
            // pages' layout floats above it and lets events through where it's empty.
            let vbox = window.default_vbox().ok_or("no GTK box")?;
            let overlay = gtk::Overlay::new();
            vbox.pack_start(&overlay, true, true, 0);
            let shell = shell_builder.build_gtk(&overlay).map_err(|e| e.to_string())?;
            let layout = gtk::Fixed::new();
            overlay.add_overlay(&layout);
            overlay.set_overlay_pass_through(&layout, true);
            overlay.show_all();
            (shell, layout)
        };

        #[cfg(not(target_os = "linux"))]
        let shell = {
            let size = window.inner_size().to_logical::<f64>(window.scale_factor());
            shell_builder
                .with_bounds(wry::Rect {
                    position: wry::dpi::LogicalPosition::new(0.0, 0.0).into(),
                    size: wry::dpi::LogicalSize::new(size.width, size.height).into(),
                })
                .build_as_child(&window)
                .map_err(|e| e.to_string())?
        };

        Ok(Self {
            id,
            popout: options.popout,
            window,
            shell,
            #[cfg(target_os = "linux")]
            layout,
            focus_order: 0,
        })
    }

    /// Keeps the shell covering the whole window (GTK does this itself).
    pub fn fit_shell(&self) {
        #[cfg(not(target_os = "linux"))]
        {
            let size = self.window.inner_size().to_logical::<f64>(self.window.scale_factor());
            let _ = self.shell.set_bounds(wry::Rect {
                position: wry::dpi::LogicalPosition::new(0.0, 0.0).into(),
                size: wry::dpi::LogicalSize::new(size.width, size.height).into(),
            });
        }
    }

    pub fn emit(&self, name: &str, payload: Value) {
        let script = format!(
            "window.__wakeHost && window.__wakeHost.event({}, {});",
            serde_json::to_string(name).unwrap(),
            payload
        );
        let _ = self.shell.evaluate_script(&script);
    }

    pub fn reply(&self, req: u64, result: Result<Value, String>) {
        let script = match result {
            Ok(value) => format!("window.__wakeHost && window.__wakeHost.reply({req}, true, {value});"),
            Err(error) => format!("window.__wakeHost && window.__wakeHost.reply({req}, false, {});", json!(error)),
        };
        let _ = self.shell.evaluate_script(&script);
    }

    pub fn state(&self) -> Value {
        json!({
            "maximized": self.window.is_maximized(),
            "fullscreen": self.window.fullscreen().is_some(),
            "focused": self.window.is_focused(),
            "scale": self.window.scale_factor(),
        })
    }

    pub fn emit_state(&self) {
        self.emit("window.state", self.state());
    }
}

/// The taskbar / window-switcher icon (the .exe's own icon comes from build.rs).
fn app_icon() -> Option<tao::window::Icon> {
    let image = image::load_from_memory(include_bytes!("../../packaging/icons/wake-256.png")).ok()?.into_rgba8();
    let (width, height) = image.dimensions();
    tao::window::Icon::from_rgba(image.into_raw(), width, height).ok()
}
