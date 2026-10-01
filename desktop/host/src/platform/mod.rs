//! What wry doesn't cover, per engine: WebKitGTK on Linux, WebView2 on Windows.
//! Both modules export the same functions.

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub use linux::*;

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use self::windows::*;

/// Lets `cargo check` run on a Mac; the desktop host doesn't run there.
#[cfg(not(any(target_os = "linux", windows)))]
mod other;
#[cfg(not(any(target_os = "linux", windows)))]
pub use other::*;

/// Shortcut names shared with the UI: modifiers in the order ctrl, alt, shift,
/// meta, then the key as in `KeyboardEvent.code` terms ("k", "1", "=", "arrowleft",
/// "escape"…), always the unshifted key at its QWERTY position.
pub fn accelerator(ctrl: bool, alt: bool, shift: bool, meta: bool, key: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    if ctrl {
        parts.push("ctrl");
    }
    if alt {
        parts.push("alt");
    }
    if shift {
        parts.push("shift");
    }
    if meta {
        parts.push("meta");
    }
    parts.push(key);
    parts.join("+")
}

/// Scales a snapshot down to `max_width` and encodes it as JPEG.
pub fn encode_jpeg(rgb: image::RgbImage, max_width: u32) -> Result<Vec<u8>, String> {
    let image = if max_width > 0 && rgb.width() > max_width {
        let height = (rgb.height() as f64 * max_width as f64 / rgb.width() as f64).round().max(1.0) as u32;
        image::imageops::resize(&rgb, max_width, height, image::imageops::FilterType::Triangle)
    } else {
        rgb
    };
    let mut out = Vec::new();
    let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 82);
    encoder.encode_image(&image).map_err(|e| e.to_string())?;
    Ok(out)
}

pub type SnapshotDone = Box<dyn FnOnce(Result<Vec<u8>, String>) + Send + 'static>;

pub type DataDone = Box<dyn FnOnce(Result<(), String>) + Send + 'static>;
