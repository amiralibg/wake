//! Preferences: the keys of `shared/schema/settings.json` (the macOS app's
//! UserDefaults keys), kept in `settings.json` in the data folder. Every window
//! hears about every change.

use serde_json::{Map, Value};
use std::path::PathBuf;

const SCHEMA: &str = include_str!("../../../shared/schema/settings.json");

pub struct Settings {
    path: PathBuf,
    values: Map<String, Value>,
    defaults: Map<String, Value>,
}

impl Settings {
    pub fn load(path: PathBuf) -> Self {
        let values = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok())
            .and_then(|value| value.as_object().cloned())
            .unwrap_or_default();
        let mut defaults = Map::new();
        if let Ok(Value::Object(schema)) = serde_json::from_str::<Value>(SCHEMA) {
            for (key, spec) in schema {
                if let Some(default) = spec.get("default") {
                    defaults.insert(key, default.clone());
                }
            }
        }
        Self { path, values, defaults }
    }

    /// Every known key with its value (saved, or the default), plus any extra keys
    /// the UI stored (pinned layout choices and the like).
    pub fn all(&self) -> Value {
        let mut merged = self.defaults.clone();
        for (key, value) in &self.values {
            merged.insert(key.clone(), value.clone());
        }
        Value::Object(merged)
    }

    pub fn get(&self, key: &str) -> Value {
        self.values.get(key).or_else(|| self.defaults.get(key)).cloned().unwrap_or(Value::Null)
    }

    pub fn set(&mut self, key: &str, value: Value) {
        if value.is_null() {
            self.values.remove(key);
        } else {
            self.values.insert(key.to_string(), value);
        }
        self.save();
    }

    fn save(&self) {
        let text = serde_json::to_string_pretty(&Value::Object(self.values.clone())).unwrap_or_default();
        let temp = self.path.with_extension("json.tmp");
        if std::fs::write(&temp, text).is_ok() {
            let _ = std::fs::rename(&temp, &self.path);
        }
    }
}
