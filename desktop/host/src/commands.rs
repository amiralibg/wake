//! Commands from the UI. Each message is `{ cmd, req?, ...args }`; when `req` is
//! set the UI waits for `window.__wakeHost.reply(req, ok, value)`.

use crate::page::{self, World};
use crate::{http, platform, scripts, App, Target, UserEvent};
use base64::Engine;
use serde_json::{json, Value};
use std::path::{Component, Path, PathBuf};

type Reply = Option<Result<Value, String>>;

pub fn handle(app: &mut App, target: &Target, window: u64, message: &str) {
    let Ok(msg) = serde_json::from_str::<Value>(message) else { return };
    let cmd = msg.get("cmd").and_then(Value::as_str).unwrap_or("");
    let req = msg.get("req").and_then(Value::as_u64);
    if std::env::var_os("WAKE_DEBUG").is_some() && cmd != "layout" {
        eprintln!("[wake] window {window}: {}", message.chars().take(300).collect::<String>());
    }
    let result = run(app, target, window, cmd, &msg, req);
    if let (Some(req), Some(result)) = (req, result) {
        app.reply(window, req, result);
    }
}

fn str_arg<'a>(msg: &'a Value, key: &str) -> Result<&'a str, String> {
    msg.get(key).and_then(Value::as_str).ok_or_else(|| format!("missing `{key}`"))
}

fn run(app: &mut App, target: &Target, window: u64, cmd: &str, msg: &Value, req: Option<u64>) -> Reply {
    match cmd {
        "ready" => {
            if let Some(w) = app.windows.get(&window) {
                w.emit_state();
            }
            Some(Ok(json!({
                "window": window,
                "platform": std::env::consts::OS,
                "version": env!("CARGO_PKG_VERSION"),
                "settings": app.settings.all(),
                "claims": app.claims,
                "downloads": page::downloads_dir(),
                "dataDir": app.data_dir,
                "firstWindow": app.windows.len() == 1,
            })))
        }

        // Pages
        "page.create" => Some((|| {
            let id = str_arg(msg, "page")?.to_string();
            if app.pages.contains_key(&id) {
                return Ok(Value::Null);
            }
            let (page, _) = page::create(app, window, id.clone(), page::Options::from_json(msg), None)?;
            app.pages.insert(id, page);
            Ok(Value::Null)
        })()),
        "page.load" => with_page(app, msg, |p| {
            p.load(str_arg(msg, "url")?);
            Ok(Value::Null)
        }),
        "page.nav" => with_page(app, msg, |p| {
            let _ = match str_arg(msg, "action")? {
                "back" => p.webview.go_back(),
                "forward" => p.webview.go_forward(),
                "reload" => p.webview.reload(),
                "reloadHard" => {
                    platform::reload_bypassing_cache(&p.webview);
                    Ok(())
                }
                "stop" => {
                    platform::stop(&p.webview);
                    Ok(())
                }
                other => return Err(format!("unknown action {other}")),
            };
            Ok(Value::Null)
        }),
        "page.close" => {
            if let Ok(id) = str_arg(msg, "page") {
                if let Some(page) = app.pages.remove(id) {
                    platform::stop(&page.webview);
                    let _ = page.webview.set_visible(false);
                    drop(page);
                }
            }
            Some(Ok(Value::Null))
        }
        "layout" => {
            layout(app, window, msg);
            None
        }
        "page.focus" => with_page(app, msg, |p| {
            let _ = p.webview.focus();
            Ok(Value::Null)
        }),
        "shell.focus" => {
            if let Some(w) = app.windows.get(&window) {
                let _ = w.shell.focus();
                w.window.set_focus();
            }
            Some(Ok(Value::Null))
        }
        "page.exec" => with_page(app, msg, |p| {
            p.eval(str_arg(msg, "js")?, World::parse(msg.get("world").and_then(Value::as_str)));
            Ok(Value::Null)
        }),
        "page.run" if req.is_none() => with_page(app, msg, |p| {
            let body = scripts::call_body(str_arg(msg, "script")?, msg.get("params").unwrap_or(&json!({})));
            p.eval(&format!("(async function () {{\n{body}\n}})();"), World::parse(msg.get("world").and_then(Value::as_str)));
            Ok(Value::Null)
        }),
        "page.eval" | "page.run" => {
            let Some(req) = req else { return None };
            let body = if cmd == "page.eval" {
                match str_arg(msg, "js") {
                    Ok(js) => js.to_string(),
                    Err(e) => return Some(Err(e)),
                }
            } else {
                match str_arg(msg, "script") {
                    Ok(name) => scripts::call_body(name, msg.get("params").unwrap_or(&json!({}))),
                    Err(e) => return Some(Err(e)),
                }
            };
            let world = World::parse(msg.get("world").and_then(Value::as_str));
            let id = app.next_eval;
            app.next_eval += 1;
            let Some(page) = str_arg(msg, "page").ok().and_then(|id| app.pages.get(id)) else {
                return Some(Err("no such page".into()));
            };
            app.pending_evals.insert(id, (window, req));
            page.eval_with_reply(&body, world, id);
            None
        }
        "page.snapshot" => {
            let Some(req) = req else { return None };
            let Some(page) = str_arg(msg, "page").ok().and_then(|id| app.pages.get(id)) else {
                return Some(Err("no such page".into()));
            };
            let width = msg.get("width").and_then(Value::as_u64).unwrap_or(640) as u32;
            let file = match msg.get("file").and_then(Value::as_str).map(|f| data_path(&app.data_dir, f)) {
                Some(Ok(path)) => Some(path),
                Some(Err(e)) => return Some(Err(e)),
                None => None,
            };
            let proxy = app.proxy.clone();
            platform::snapshot(
                &page.webview,
                width,
                Box::new(move |result| {
                    let result = result.and_then(|bytes| match &file {
                        Some(path) => std::fs::write(path, &bytes).map(|_| json!({ "bytes": bytes.len() })).map_err(|e| e.to_string()),
                        None => Ok(json!(format!(
                            "data:image/jpeg;base64,{}",
                            base64::engine::general_purpose::STANDARD.encode(&bytes)
                        ))),
                    });
                    let _ = proxy.send_event(UserEvent::Reply { window, req, result });
                }),
            );
            None
        }
        // DevTools: an expression against the page-side library (shared/scripts/devtools.js),
        // or one of its async scripts, in the page's world.
        "page.devtools" | "page.devtoolsRun" => {
            let Some(req) = req else { return None };
            let library = scripts::source("devtools", &json!({ "channel": scripts::DEVTOOLS_CHANNEL }));
            let (body, world) = if cmd == "page.devtools" {
                (format!("{library}\nreturn ({});", str_arg(msg, "expr").unwrap_or("undefined")), World::Page)
            } else {
                let name = str_arg(msg, "script").unwrap_or("");
                let params = msg.get("params").cloned().unwrap_or(json!({}));
                let world = World::parse(msg.get("world").and_then(Value::as_str));
                if name.starts_with("async-devtools") {
                    (format!("{library}\n{}", scripts::call_body(name, &params)), World::Page)
                } else {
                    (scripts::call_body(name, &params), world)
                }
            };
            let id = app.next_eval;
            app.next_eval += 1;
            let Some(page) = str_arg(msg, "page").ok().and_then(|id| app.pages.get(id)) else {
                return Some(Err("no such page".into()));
            };
            app.pending_evals.insert(id, (window, req));
            page.eval_with_reply(&body, world, id);
            None
        }
        "page.cookies" => with_page(app, msg, |p| {
            let url = p.webview.url().map_err(|e| e.to_string())?;
            let cookies = p.webview.cookies_for_url(&url).map_err(|e| e.to_string())?;
            Ok(Value::Array(cookies.iter().map(cookie_json).collect()))
        }),
        "page.setCookie" => with_page(app, msg, |p| {
            let url = p.webview.url().map_err(|e| e.to_string())?;
            let host = url::Url::parse(&url).ok().and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
            if let Some(old) = msg.get("old") {
                let _ = p.webview.delete_cookie(&cookie_from(old, &host));
            }
            p.webview.set_cookie(&cookie_from(msg.get("cookie").unwrap_or(&json!({})), &host)).map_err(|e| e.to_string())?;
            Ok(Value::Null)
        }),
        "page.deleteCookie" => with_page(app, msg, |p| {
            let url = p.webview.url().map_err(|e| e.to_string())?;
            let host = url::Url::parse(&url).ok().and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
            p.webview.delete_cookie(&cookie_from(msg.get("cookie").unwrap_or(&json!({})), &host)).map_err(|e| e.to_string())?;
            Ok(Value::Null)
        }),
        "page.clearSiteData" => {
            let Some(req) = req else { return None };
            let Some(page) = str_arg(msg, "page").ok().and_then(|id| app.pages.get(id)) else {
                return Some(Err("no such page".into()));
            };
            let host = page.webview.url().ok().and_then(|u| url::Url::parse(&u).ok()).and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
            let proxy = app.proxy.clone();
            platform::clear_site_data(
                &page.webview,
                &host,
                Box::new(move |result| {
                    let _ = proxy.send_event(UserEvent::Reply { window, req, result: result.map(|_| Value::Null) });
                }),
            );
            None
        }
        "page.colorScheme" => with_page(app, msg, |p| {
            platform::set_color_scheme(&p.webview, msg.get("scheme").and_then(Value::as_str).unwrap_or("system")).map(|_| Value::Null)
        }),
        "page.print" => with_page(app, msg, |p| p.webview.print().map(|_| Value::Null).map_err(|e| e.to_string())),
        "page.copySnapshot" => {
            let Some(req) = req else { return None };
            let Some(page) = str_arg(msg, "page").ok().and_then(|id| app.pages.get(id)) else {
                return Some(Err("no such page".into()));
            };
            let proxy = app.proxy.clone();
            platform::snapshot(
                &page.webview,
                0,
                Box::new(move |result| {
                    let result = result.and_then(|jpeg| {
                        let image = image::load_from_memory(&jpeg).map_err(|e| e.to_string())?.to_rgba8();
                        let (width, height) = image.dimensions();
                        arboard::Clipboard::new()
                            .and_then(|mut c| {
                                c.set_image(arboard::ImageData { width: width as usize, height: height as usize, bytes: image.into_raw().into() })
                            })
                            .map_err(|e| e.to_string())
                    });
                    let _ = proxy.send_event(UserEvent::Reply { window, req, result: result.map(|_| Value::Null) });
                }),
            );
            None
        }
        "page.zoom" => with_page(app, msg, |p| {
            let _ = p.webview.zoom(msg.get("zoom").and_then(Value::as_f64).unwrap_or(1.0));
            Ok(Value::Null)
        }),
        "page.userAgent" => with_page(app, msg, |p| {
            platform::set_user_agent(&p.webview, msg.get("userAgent").and_then(Value::as_str).filter(|s| !s.is_empty()));
            Ok(Value::Null)
        }),
        "page.devHooks" => with_page(app, msg, |p| {
            p.set_dev_hooks(msg.get("on").and_then(Value::as_bool).unwrap_or(false));
            Ok(Value::Null)
        }),
        "page.javascript" => with_page(app, msg, |p| {
            platform::set_javascript_enabled(&p.webview, msg.get("on").and_then(Value::as_bool).unwrap_or(true));
            Ok(Value::Null)
        }),
        "page.inspector" => with_page(app, msg, |p| {
            platform::open_inspector(&p.webview);
            Ok(Value::Null)
        }),

        // Storage
        "db.query" => Some(app.db.query(str_arg(msg, "sql").unwrap_or(""), &params(msg))),
        "db.exec" => Some(app.db.exec(str_arg(msg, "sql").unwrap_or(""), &params(msg))),
        "db.batch" => {
            let statements: Vec<(String, Vec<Value>)> = msg
                .get("statements")
                .and_then(Value::as_array)
                .map(|list| {
                    list.iter()
                        .filter_map(|s| Some((s.get("sql")?.as_str()?.to_string(), params(s))))
                        .collect()
                })
                .unwrap_or_default();
            Some(app.db.batch(&statements))
        }
        "settings.set" => {
            let key = str_arg(msg, "key").unwrap_or("").to_string();
            let value = msg.get("value").cloned().unwrap_or(Value::Null);
            app.settings.set(&key, value.clone());
            app.broadcast("settings.changed", json!({ "key": key, "value": app.settings.get(&key) }));
            Some(Ok(Value::Null))
        }

        // Threads shown in more than one window
        "threads.claim" => {
            let thread = str_arg(msg, "thread").unwrap_or("").to_string();
            let owner = app.claims.get(&thread).copied();
            let ok = owner.is_none() || owner == Some(window) || !app.windows.contains_key(&owner.unwrap());
            if ok {
                app.claims.insert(thread, window);
                app.broadcast("threads.claims", json!(app.claims));
            }
            Some(Ok(json!(ok)))
        }
        "threads.release" => {
            let thread = str_arg(msg, "thread").unwrap_or("");
            if app.claims.get(thread) == Some(&window) {
                app.claims.remove(thread);
                app.broadcast("threads.claims", json!(app.claims));
            }
            Some(Ok(Value::Null))
        }
        "threads.focusOwner" => {
            let thread = str_arg(msg, "thread").unwrap_or("");
            if let Some(owner) = app.claims.get(thread).and_then(|w| app.windows.get(w)) {
                owner.window.set_minimized(false);
                owner.window.set_focus();
            }
            Some(Ok(Value::Null))
        }
        "broadcast" => {
            // An event for every other window's UI (the sender already knows).
            let name = str_arg(msg, "name").unwrap_or("");
            let payload = msg.get("payload").cloned().unwrap_or(json!({}));
            for (id, w) in &app.windows {
                if *id != window {
                    w.emit(name, payload.clone());
                }
            }
            Some(Ok(Value::Null))
        }
        "threads.changed" => {
            // Another window's Deck or switcher should re-read the store.
            for (id, w) in &app.windows {
                if *id != window {
                    w.emit("threads.changed", json!({}));
                }
            }
            Some(Ok(Value::Null))
        }

        // The window
        "window.minimize" => window_do(app, window, |w| w.window.set_minimized(true)),
        "window.toggleMaximize" => window_do(app, window, |w| w.window.set_maximized(!w.window.is_maximized())),
        "window.fullscreen" => window_do(app, window, |w| {
            let on = msg.get("on").and_then(Value::as_bool).unwrap_or(w.window.fullscreen().is_none());
            w.window.set_fullscreen(on.then_some(tao::window::Fullscreen::Borderless(None)));
            w.emit_state();
        }),
        "window.drag" => window_do(app, window, |w| {
            let _ = w.window.drag_window();
        }),
        "window.resize" => window_do(app, window, |w| {
            use tao::window::ResizeDirection::*;
            let direction = match msg.get("edge").and_then(Value::as_str).unwrap_or("") {
                "n" => North,
                "s" => South,
                "e" => East,
                "w" => West,
                "ne" => NorthEast,
                "nw" => NorthWest,
                "se" => SouthEast,
                _ => SouthWest,
            };
            let _ = w.window.drag_resize_window(direction);
        }),
        "window.title" => window_do(app, window, |w| w.window.set_title(msg.get("title").and_then(Value::as_str).unwrap_or("Wake"))),
        "window.close" => {
            app.close_window(window);
            None
        }
        "window.new" => {
            let query = msg.get("query").and_then(Value::as_str).unwrap_or("").to_string();
            let popout = msg.get("popout").and_then(Value::as_bool).unwrap_or(false);
            let size = match (msg.get("width").and_then(Value::as_f64), msg.get("height").and_then(Value::as_f64)) {
                (Some(w), Some(h)) => Some((w, h)),
                _ => None,
            };
            // Pop Outs start beside the source window's top-right corner, cascading.
            let position = if popout {
                app.windows.get(&window).and_then(|w| {
                    let scale = w.window.scale_factor();
                    let origin = w.window.outer_position().ok()?.to_logical::<f64>(scale);
                    let outer = w.window.outer_size().to_logical::<f64>(scale);
                    let cascade = app.windows.values().filter(|w| w.popout).count() as f64 * 24.0;
                    let (width, _) = size.unwrap_or((320.0, 200.0));
                    Some((origin.x + outer.width - width - 24.0 - cascade, origin.y + 80.0 + cascade))
                })
            } else {
                None
            };
            let id = app.open_window(target, &query, crate::window::WindowOptions { popout, size, position });
            Some(Ok(json!(id)))
        }
        "window.setSize" => window_do(app, window, |w| {
            let width = msg.get("width").and_then(Value::as_f64).unwrap_or(320.0);
            let height = msg.get("height").and_then(Value::as_f64).unwrap_or(200.0);
            w.window.set_inner_size(tao::dpi::LogicalSize::new(width, height));
        }),
        "window.pin" => window_do(app, window, |w| {
            // Pinned: on every workspace, and over full-screen windows where the OS allows.
            let on = msg.get("on").and_then(Value::as_bool).unwrap_or(false);
            w.window.set_visible_on_all_workspaces(on);
            w.window.set_always_on_top(true);
        }),
        "window.focusID" => {
            if let Some(w) = msg.get("id").and_then(Value::as_u64).and_then(|id| app.windows.get(&id)) {
                w.window.set_minimized(false);
                w.window.set_focus();
            }
            Some(Ok(Value::Null))
        }
        "window.emit" => {
            // An event for one specific window (a Pop Out telling its source window to open a link).
            if let Some(w) = msg.get("id").and_then(Value::as_u64).and_then(|id| app.windows.get(&id)) {
                w.emit(str_arg(msg, "name").unwrap_or(""), msg.get("payload").cloned().unwrap_or(json!({})));
            }
            Some(Ok(Value::Null))
        }
        "app.quit" => {
            app.quitting = true;
            for w in app.windows.values() {
                w.emit("window.closeRequested", json!({ "quit": true }));
            }
            Some(Ok(Value::Null))
        }
        "shell.inspector" => window_do(app, window, |w| w.shell.open_devtools()),

        "keys.set" => {
            let keys: Vec<String> = msg
                .get("keys")
                .and_then(Value::as_array)
                .map(|list| list.iter().filter_map(|k| k.as_str().map(str::to_string)).collect())
                .unwrap_or_default();
            app.window_keys.insert(window, keys.into_iter().collect());
            let union = app.window_keys.values().flatten().cloned().collect();
            *app.keys.borrow_mut() = union;
            Some(Ok(Value::Null))
        }

        // The OS
        "open.external" => Some(open::that_detached(str_arg(msg, "url").unwrap_or("")).map(|_| Value::Null).map_err(|e| e.to_string())),
        "open.reveal" => {
            let path = PathBuf::from(str_arg(msg, "path").unwrap_or(""));
            let folder = if path.is_dir() { path } else { path.parent().map(Path::to_path_buf).unwrap_or_default() };
            Some(open::that_detached(folder).map(|_| Value::Null).map_err(|e| e.to_string()))
        }
        "clipboard.write" => Some(
            arboard::Clipboard::new()
                .and_then(|mut c| c.set_text(str_arg(msg, "text").unwrap_or("").to_string()))
                .map(|_| Value::Null)
                .map_err(|e| e.to_string()),
        ),
        "clipboard.read" => Some(arboard::Clipboard::new().and_then(|mut c| c.get_text()).map(Value::String).map_err(|e| e.to_string())),
        "http.fetch" => {
            if let Some(req) = req {
                http::fetch(app.proxy.clone(), window, req, msg.clone());
            }
            None
        }

        "dialog.folder" => {
            let mut dialog = rfd::FileDialog::new();
            if let Some(title) = msg.get("title").and_then(Value::as_str) {
                dialog = dialog.set_title(title);
            }
            Some(Ok(dialog.pick_folder().map(|p| json!(p.to_string_lossy())).unwrap_or(Value::Null)))
        }
        "dialog.save" => {
            // Saves text the UI made (a HAR, a copied response) where the user picks.
            let mut dialog = rfd::FileDialog::new().set_file_name(msg.get("name").and_then(Value::as_str).unwrap_or("download.txt"));
            if let Some(dir) = dirs::download_dir() {
                dialog = dialog.set_directory(dir);
            }
            Some(match dialog.save_file() {
                Some(path) => std::fs::write(&path, msg.get("text").and_then(Value::as_str).unwrap_or(""))
                    .map(|_| json!(path.to_string_lossy()))
                    .map_err(|e| e.to_string()),
                None => Ok(Value::Null),
            })
        }
        "git.branch" => Some(Ok(git_branch(Path::new(str_arg(msg, "folder").unwrap_or(""))).map(Value::String).unwrap_or(Value::Null))),
        "fs.exists" => Some(Ok(json!(Path::new(str_arg(msg, "path").unwrap_or("")).exists()))),
        "data.clearCache" | "data.clearAll" => {
            let Some(req) = req else { return None };
            // Any page will do: every page shares the one website data store.
            let page = app.pages.values().find(|p| p.window == window).or_else(|| app.pages.values().next());
            let Some(page) = page else {
                // No page has opened the store yet this session.
                return Some(Err("Open a page first, then try again.".into()));
            };
            let proxy = app.proxy.clone();
            platform::clear_data(
                &page.webview,
                cmd == "data.clearCache",
                Box::new(move |result| {
                    let _ = proxy.send_event(UserEvent::Reply { window, req, result: result.map(|_| Value::Null) });
                }),
            );
            None
        }
        "update.info" => Some(Ok(crate::updater::info())),
        "update.check" => {
            let Some(req) = req else { return None };
            let proxy = app.proxy.clone();
            std::thread::spawn(move || {
                let result = crate::updater::check().map(|found| {
                    let value = found.as_ref().map(|u| json!({ "version": u.version, "notes": u.notes, "url": u.page }));
                    *crate::updater::FOUND.lock().unwrap() = found;
                    value.unwrap_or(Value::Null)
                });
                let _ = proxy.send_event(UserEvent::Reply { window, req, result });
            });
            None
        }
        "update.install" => {
            let Some(req) = req else { return None };
            let proxy = app.proxy.clone();
            let data_dir = app.data_dir.clone();
            std::thread::spawn(move || {
                let result = match crate::updater::FOUND.lock().unwrap().as_ref() {
                    Some(update) => crate::updater::install(update, &data_dir),
                    None => Err("No update to install.".into()),
                };
                let restarts = result.as_ref().is_ok_and(|r| *r);
                let _ = proxy.send_event(UserEvent::Reply { window, req, result: result.map(|r| json!({ "restarts": r })) });
                // The new version is starting: every window saves and closes.
                if restarts {
                    let _ = proxy.send_event(UserEvent::Broadcast { name: "window.closeRequested", payload: json!({ "quit": true }) });
                }
            });
            None
        }
        // Import from another browser: the host reads, the UI merges.
        "import.profiles" => Some(Ok(Value::Array(crate::import::profiles().iter().map(|p| p.json()).collect()))),
        "import.read" => {
            let Some(req) = req else { return None };
            let id = str_arg(msg, "id").unwrap_or("").to_string();
            let Some(profile) = crate::import::profiles().into_iter().find(|p| p.dir.to_string_lossy() == id) else {
                return Some(Err("That profile is gone.".into()));
            };
            let flag = |k: &str| msg.get(k).and_then(Value::as_bool).unwrap_or(true);
            let options = crate::import::Options { history: flag("history"), searches: flag("searches"), cookies: flag("cookies"), site_data: flag("siteData") };
            let proxy = app.proxy.clone();
            std::thread::spawn(move || {
                let progress = {
                    let proxy = proxy.clone();
                    move |text: String| {
                        let _ = proxy.send_event(UserEvent::WindowEvent { window, name: "import.progress", payload: json!({ "text": text }) });
                    }
                };
                let result = crate::import::read(&profile, &options, &progress);
                let _ = proxy.send_event(UserEvent::Reply { window, req, result: Ok(result) });
            });
            None
        }
        "cookies.add" => {
            // Adds cookies Wake doesn't have yet (same name, domain and path), so an
            // import never signs you out of something you're signed into in Wake.
            let Some(page) = app.pages.values().find(|p| p.window == window).or_else(|| app.pages.values().next()) else {
                return Some(Err("Open a page first, then try again.".into()));
            };
            let existing: std::collections::HashSet<String> = page
                .webview
                .cookies()
                .unwrap_or_default()
                .iter()
                .map(|c| format!("{}|{}|{}", c.name(), c.domain().unwrap_or(""), c.path().unwrap_or("/")))
                .collect();
            let mut added = 0;
            for value in msg.get("cookies").and_then(Value::as_array).cloned().unwrap_or_default() {
                let cookie = cookie_from(&value, "");
                let key = format!("{}|{}|{}", cookie.name(), cookie.domain().unwrap_or(""), cookie.path().unwrap_or("/"));
                if existing.contains(&key) {
                    continue;
                }
                let mut cookie = cookie;
                if let Some(expires) = value.get("expires").and_then(Value::as_f64) {
                    if let Ok(time) = wry::cookie::time::OffsetDateTime::from_unix_timestamp(expires as i64) {
                        cookie.set_expires(time);
                    }
                }
                if let Some(same_site) = value.get("sameSite").and_then(Value::as_str) {
                    cookie.set_same_site(match same_site {
                        "strict" => wry::cookie::SameSite::Strict,
                        "lax" => wry::cookie::SameSite::Lax,
                        _ => wry::cookie::SameSite::None,
                    });
                }
                if page.webview.set_cookie(&cookie).is_ok() {
                    added += 1;
                }
            }
            Some(Ok(json!(added)))
        }
        "page.loadAsOrigin" => with_page(app, msg, |p| {
            platform::load_as_origin(&p.webview, str_arg(msg, "url")?, msg.get("html").and_then(Value::as_str).unwrap_or("<!doctype html><meta charset=utf-8>"));
            Ok(Value::Null)
        }),
        "hash.sha256" => {
            use sha2::Digest;
            let digest = sha2::Sha256::digest(str_arg(msg, "text").unwrap_or("").as_bytes());
            Some(Ok(json!(digest.iter().map(|b| format!("{b:02x}")).collect::<String>())))
        }

        // Files in the data folder (thumbnails, snapshots)
        "file.write" => Some((|| {
            let path = data_path(&app.data_dir, str_arg(msg, "path")?)?;
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            let bytes = match msg.get("base64").and_then(Value::as_str) {
                Some(b64) => base64::engine::general_purpose::STANDARD.decode(b64).map_err(|e| e.to_string())?,
                None => msg.get("text").and_then(Value::as_str).unwrap_or("").as_bytes().to_vec(),
            };
            std::fs::write(path, bytes).map(|_| Value::Null).map_err(|e| e.to_string())
        })()),
        "file.read" => Some((|| {
            let path = data_path(&app.data_dir, str_arg(msg, "path")?)?;
            std::fs::read_to_string(path).map(Value::String).map_err(|e| e.to_string())
        })()),
        "file.copy" => Some((|| {
            let from = data_path(&app.data_dir, str_arg(msg, "from")?)?;
            let to = data_path(&app.data_dir, str_arg(msg, "to")?)?;
            std::fs::copy(from, to).map(|_| Value::Null).map_err(|e| e.to_string())
        })()),
        "file.remove" => Some((|| {
            let path = data_path(&app.data_dir, str_arg(msg, "path")?)?;
            let _ = std::fs::remove_file(path);
            Ok(Value::Null)
        })()),
        "file.exists" => Some((|| {
            let path = data_path(&app.data_dir, str_arg(msg, "path")?)?;
            Ok(json!(path.exists()))
        })()),

        other => Some(Err(format!("unknown command {other}"))),
    }
}

fn cookie_json(cookie: &wry::cookie::Cookie) -> Value {
    json!({
        "name": cookie.name(),
        "value": cookie.value(),
        "domain": cookie.domain().unwrap_or(""),
        "path": cookie.path().unwrap_or("/"),
        "secure": cookie.secure().unwrap_or(false),
        "httpOnly": cookie.http_only().unwrap_or(false),
        "sameSite": cookie.same_site().map(|s| s.to_string()),
        "expires": cookie.expires_datetime().map(|d| d.unix_timestamp()),
    })
}

fn cookie_from(value: &Value, host: &str) -> wry::cookie::Cookie<'static> {
    let s = |k: &str| value.get(k).and_then(Value::as_str).map(str::to_string);
    let mut builder = wry::cookie::Cookie::build((s("name").unwrap_or_default(), s("value").unwrap_or_default()))
        .domain(s("domain").filter(|d| !d.is_empty()).unwrap_or_else(|| host.to_string()))
        .path(s("path").unwrap_or_else(|| "/".into()));
    if value.get("secure").and_then(Value::as_bool).unwrap_or(false) {
        builder = builder.secure(true);
    }
    if value.get("httpOnly").and_then(Value::as_bool).unwrap_or(false) {
        builder = builder.http_only(true);
    }
    builder.build()
}

/// The checked-out branch, read from `.git/HEAD` (or the commit, when detached).
fn git_branch(folder: &Path) -> Option<String> {
    let mut git = folder.join(".git");
    // Worktrees and submodules have a ".git" file pointing at the real directory.
    if let Ok(pointer) = std::fs::read_to_string(&git) {
        if let Some(path) = pointer.trim().strip_prefix("gitdir:") {
            git = folder.join(path.trim());
        }
    }
    let head = std::fs::read_to_string(git.join("HEAD")).ok()?;
    let head = head.trim();
    Some(match head.strip_prefix("ref: refs/heads/") {
        Some(branch) => branch.to_string(),
        None => head.chars().take(7).collect(),
    })
}

fn params(msg: &Value) -> Vec<Value> {
    msg.get("params").and_then(Value::as_array).cloned().unwrap_or_default()
}

fn with_page(app: &mut App, msg: &Value, f: impl FnOnce(&mut page::Page) -> Result<Value, String>) -> Reply {
    let id = match str_arg(msg, "page") {
        Ok(id) => id.to_string(),
        Err(e) => return Some(Err(e)),
    };
    Some(match app.pages.get_mut(&id) {
        Some(page) => f(page),
        None => Err(format!("no page {id}")),
    })
}

fn window_do(app: &App, window: u64, f: impl FnOnce(&crate::window::BrowserWindow)) -> Reply {
    if let Some(w) = app.windows.get(&window) {
        f(w);
    }
    Some(Ok(Value::Null))
}

/// A path inside the data folder, from a relative one the UI gave.
fn data_path(data_dir: &Path, relative: &str) -> Result<PathBuf, String> {
    let path = Path::new(relative);
    if path.components().all(|c| matches!(c, Component::Normal(_))) {
        Ok(data_dir.join(path))
    } else {
        Err("not a data path".into())
    }
}

/// Places the window's pages: those in `frames` at their rectangles, every other
/// page of the window hidden (off the stage, or covered by the UI).
fn layout(app: &mut App, window: u64, msg: &Value) {
    let Some(host) = app.windows.get(&window) else { return };
    let mut shown = std::collections::HashSet::new();
    if let Some(frames) = msg.get("frames").and_then(Value::as_array) {
        for frame in frames {
            let Some(id) = frame.get("page").and_then(Value::as_str) else { continue };
            let n = |k: &str| frame.get(k).and_then(Value::as_f64).unwrap_or(0.0);
            if let Some(page) = app.pages.get_mut(id) {
                if page.window == window {
                    page.set_frame(Some((n("x"), n("y"), n("w"), n("h"), n("r"))), host);
                    shown.insert(id.to_string());
                }
            }
        }
    }
    for page in app.pages.values_mut() {
        if page.window == window && !shown.contains(&page.id) {
            page.set_frame(None, host);
        }
    }
}
