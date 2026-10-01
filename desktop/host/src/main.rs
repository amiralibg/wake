//! Wake for Windows and Linux: the host.
//!
//! The host owns windows and webviews and talks to the OS; the app itself (trail,
//! threads, Deck, palette…) is the TypeScript UI in `desktop/ui`, which runs in one
//! "shell" webview per window and drives everything through the commands in
//! `commands.rs`. See `desktop/README.md` for the protocol.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod assets;
mod commands;
mod db;
mod http;
mod import;
mod page;
mod platform;
mod scripts;
mod settings;
mod updater;
mod window;

use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::rc::Rc;
use tao::event::{Event, StartCause, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy, EventLoopWindowTarget};
use wry::WebContext;

pub type Proxy = EventLoopProxy<UserEvent>;
pub type Target = EventLoopWindowTarget<UserEvent>;
/// Accelerators the UI wants even while a page has keyboard focus ("ctrl+k", "alt+w"…).
pub type Keymap = Rc<RefCell<HashSet<String>>>;

/// Everything webview callbacks report goes through the event loop, so handlers
/// never run inside another handler's borrow of the app.
pub enum UserEvent {
    /// A command from a window's shell webview (JSON).
    Shell { window: u64, message: String },
    /// Something happened in a page: forwarded to its window's UI as `name`.
    Page { page: String, name: &'static str, payload: Value },
    /// A value a page evaluation posted back.
    PageReply { page: String, id: u64, result: Result<Value, String> },
    /// The answer to a command, computed off the main thread or asynchronously.
    Reply { window: u64, req: u64, result: Result<Value, String> },
    /// A shortcut pressed while a page had focus.
    Key { page: String, accel: String },
    /// Something for every window's UI.
    Broadcast { name: &'static str, payload: Value },
    /// Something for one window's UI.
    WindowEvent { window: u64, name: &'static str, payload: Value },
}

pub struct App {
    pub proxy: Proxy,
    pub data_dir: PathBuf,
    pub db: db::Db,
    pub settings: settings::Settings,
    /// Pages' web data (cookies, caches, storage).
    pub web_context: WebContext,
    /// The UI's own context, kept apart so pages can never load `wake://` files.
    pub shell_context: WebContext,
    pub windows: HashMap<u64, window::BrowserWindow>,
    pub pages: HashMap<String, page::Page>,
    /// Which window shows which thread, so one thread is never live twice.
    pub claims: HashMap<String, u64>,
    /// Every window's shortcuts; `keys` is their union (what pages give up).
    pub window_keys: HashMap<u64, HashSet<String>>,
    pub keys: Keymap,
    /// Page evaluations waiting for their reply: eval id → (window, command req).
    pub pending_evals: HashMap<u64, (u64, u64)>,
    pub next_eval: u64,
    next_window: u64,
    pub quitting: bool,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

/// Runs `f` with the app, unless it's already borrowed (a callback fired while a
/// command was running); then returns `None`.
pub fn with_app<R>(f: impl FnOnce(&mut App) -> R) -> Option<R> {
    APP.with(|cell| cell.try_borrow_mut().ok().and_then(|mut app| app.as_mut().map(f)))
}

thread_local! {
    static PROTOCOL_REGISTERED: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

pub fn protocol_registered() -> bool {
    PROTOCOL_REGISTERED.with(|c| c.get())
}

pub fn set_protocol_registered() {
    PROTOCOL_REGISTERED.with(|c| c.set(true));
}

pub fn data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("WAKE_DATA_DIR") {
        return PathBuf::from(dir);
    }
    dirs::data_dir().unwrap_or_else(|| PathBuf::from(".")).join("Wake")
}

impl App {
    fn new(proxy: Proxy) -> Self {
        let data_dir = data_dir();
        for sub in ["", "thumbs", "moments", "webdata", "uidata"] {
            let _ = std::fs::create_dir_all(data_dir.join(sub));
        }
        let db = db::Db::open(&data_dir.join("wake.sqlite")).expect("can't open the database");
        let settings = settings::Settings::load(data_dir.join("settings.json"));
        let web_context = WebContext::new(Some(data_dir.join("webdata")));
        let shell_context = WebContext::new(Some(data_dir.join("uidata")));
        platform::setup_downloads(&web_context, &proxy);
        Self {
            proxy,
            data_dir,
            db,
            settings,
            web_context,
            shell_context,
            windows: HashMap::new(),
            pages: HashMap::new(),
            claims: HashMap::new(),
            window_keys: HashMap::new(),
            keys: Rc::new(RefCell::new(HashSet::new())),
            pending_evals: HashMap::new(),
            next_eval: 1,
            next_window: 1,
            quitting: false,
        }
    }

    pub fn open_window(&mut self, target: &Target, query: &str, options: window::WindowOptions) -> u64 {
        let id = self.next_window;
        self.next_window += 1;
        match window::BrowserWindow::new(id, target, self, query, options) {
            Ok(window) => {
                self.windows.insert(id, window);
            }
            Err(error) => eprintln!("couldn't open a window: {error}"),
        }
        id
    }

    /// Sends an event to one window's UI.
    pub fn emit(&self, window: u64, name: &str, payload: Value) {
        if let Some(window) = self.windows.get(&window) {
            window.emit(name, payload);
        }
    }

    pub fn broadcast(&self, name: &str, payload: Value) {
        for window in self.windows.values() {
            window.emit(name, payload.clone());
        }
    }

    pub fn reply(&self, window: u64, req: u64, result: Result<Value, String>) {
        if let Some(window) = self.windows.get(&window) {
            window.reply(req, result);
        }
    }

    pub fn close_window(&mut self, id: u64) {
        let pages: Vec<String> = self.pages.iter().filter(|(_, p)| p.window == id).map(|(k, _)| k.clone()).collect();
        for page in pages {
            self.pages.remove(&page);
        }
        self.claims.retain(|_, owner| *owner != id);
        self.windows.remove(&id);
        self.window_keys.remove(&id);
        *self.keys.borrow_mut() = self.window_keys.values().flatten().cloned().collect();
        self.broadcast("threads.claims", json!(self.claims));
    }

    fn handle(&mut self, event: UserEvent, target: &Target, control_flow: &mut ControlFlow) {
        match event {
            UserEvent::Shell { window, message } => commands::handle(self, target, window, &message),
            UserEvent::Page { page, name, payload } => {
                if let Some(window) = self.pages.get(&page).map(|p| p.window) {
                    let mut payload = payload;
                    if let Value::Object(map) = &mut payload {
                        map.insert("page".into(), Value::String(page));
                    }
                    self.emit(window, name, payload);
                }
            }
            UserEvent::PageReply { page: _, id, result } => {
                if let Some((window, req)) = self.pending_evals.remove(&id) {
                    self.reply(window, req, result);
                }
            }
            UserEvent::Reply { window, req, result } => self.reply(window, req, result),
            UserEvent::Key { page, accel } => {
                if let Some(window) = self.pages.get(&page).map(|p| p.window) {
                    self.emit(window, "key", json!({ "accel": accel, "page": page }));
                }
            }
            UserEvent::Broadcast { name, payload } => self.broadcast(name, payload),
            UserEvent::WindowEvent { window, name, payload } => self.emit(window, name, payload),
        }
        // The last browser window closed (or Quit): the app ends with it, and takes
        // any Pop Outs along.
        if !self.windows.values().any(|w| !w.popout) {
            *control_flow = ControlFlow::Exit;
        }
    }

    fn window_event(&mut self, id: tao::window::WindowId, event: WindowEvent, control_flow: &mut ControlFlow) {
        let Some((&wid, window)) = self.windows.iter_mut().find(|(_, w)| w.window.id() == id) else { return };
        match event {
            WindowEvent::CloseRequested => {
                // The UI saves its threads, then closes the window itself.
                window.emit("window.closeRequested", json!({}));
            }
            WindowEvent::Resized(_) | WindowEvent::ScaleFactorChanged { .. } => {
                window.fit_shell();
                window.emit_state();
            }
            WindowEvent::Focused(focused) => {
                window.emit("window.focus", json!({ "focused": focused }));
                if focused {
                    window.focus_order = next_focus_order();
                }
            }
            WindowEvent::Destroyed => {
                self.close_window(wid);
            }
            _ => {}
        }
        if !self.windows.values().any(|w| !w.popout) {
            *control_flow = ControlFlow::Exit;
        }
    }
}

fn next_focus_order() -> u64 {
    thread_local!(static COUNTER: RefCell<u64> = const { RefCell::new(0) });
    COUNTER.with(|c| {
        *c.borrow_mut() += 1;
        *c.borrow()
    })
}

fn main() {
    #[cfg(target_os = "linux")]
    platform::prepare();

    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    let proxy = event_loop.create_proxy();
    APP.with(|cell| *cell.borrow_mut() = Some(App::new(proxy)));

    event_loop.run(move |event, target, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            Event::NewEvents(StartCause::Init) => {
                with_app(|app| app.open_window(target, "", Default::default()));
            }
            Event::UserEvent(event) => {
                with_app(|app| app.handle(event, target, control_flow));
            }
            Event::WindowEvent { window_id, event, .. } => {
                with_app(|app| app.window_event(window_id, event, control_flow));
            }
            _ => {}
        }
    });
}
