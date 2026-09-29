//! SQLite storage: the tables of `shared/schema`, reached by the UI through plain
//! SQL (`db.query`, `db.exec`, `db.batch`). Only the shell webview (Wake's own UI)
//! can send those commands; pages can't reach them.

use base64::Engine;
use rusqlite::types::{Value as SqlValue, ValueRef};
use rusqlite::{params_from_iter, Connection};
use serde_json::{json, Map, Value};
use std::path::Path;

const MIGRATIONS: &[(i64, &str)] = &[(1, include_str!("../../../shared/schema/001_initial.sql"))];

pub struct Db {
    conn: Connection,
}

impl Db {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        let db = Self { conn };
        db.migrate()?;
        db.conn.pragma_update(None, "foreign_keys", true)?;
        Ok(db)
    }

    fn migrate(&self) -> rusqlite::Result<()> {
        let version: i64 = self.conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
        for (number, sql) in MIGRATIONS {
            if *number > version {
                self.conn.execute_batch(&format!("BEGIN;\n{sql}\nCOMMIT;"))?;
            }
        }
        Ok(())
    }

    /// Rows as objects keyed by column name.
    pub fn query(&self, sql: &str, params: &[Value]) -> Result<Value, String> {
        let mut statement = self.conn.prepare_cached(sql).map_err(|e| e.to_string())?;
        let names: Vec<String> = statement.column_names().iter().map(|s| s.to_string()).collect();
        let mut rows = statement.query(params_from_iter(params.iter().map(to_sql))).map_err(|e| e.to_string())?;
        let mut out = Vec::new();
        while let Some(row) = rows.next().map_err(|e| e.to_string())? {
            let mut object = Map::new();
            for (index, name) in names.iter().enumerate() {
                let value = row.get_ref(index).map_err(|e| e.to_string())?;
                object.insert(name.clone(), from_sql(value));
            }
            out.push(Value::Object(object));
        }
        Ok(Value::Array(out))
    }

    pub fn exec(&self, sql: &str, params: &[Value]) -> Result<Value, String> {
        let mut statement = self.conn.prepare_cached(sql).map_err(|e| e.to_string())?;
        let changes = statement.execute(params_from_iter(params.iter().map(to_sql))).map_err(|e| e.to_string())?;
        Ok(json!({ "changes": changes, "lastId": self.conn.last_insert_rowid() }))
    }

    /// Several statements in one transaction: all or nothing.
    pub fn batch(&mut self, statements: &[(String, Vec<Value>)]) -> Result<Value, String> {
        let tx = self.conn.transaction().map_err(|e| e.to_string())?;
        for (sql, params) in statements {
            let mut statement = tx.prepare_cached(sql).map_err(|e| e.to_string())?;
            statement.execute(params_from_iter(params.iter().map(to_sql))).map_err(|e| format!("{e} in: {sql}"))?;
        }
        tx.commit().map_err(|e| e.to_string())?;
        Ok(Value::Null)
    }
}

fn to_sql(value: &Value) -> SqlValue {
    match value {
        Value::Null => SqlValue::Null,
        Value::Bool(b) => SqlValue::Integer(*b as i64),
        Value::Number(n) => match n.as_i64() {
            Some(i) => SqlValue::Integer(i),
            None => SqlValue::Real(n.as_f64().unwrap_or(0.0)),
        },
        Value::String(s) => SqlValue::Text(s.clone()),
        other => SqlValue::Text(other.to_string()),
    }
}

fn from_sql(value: ValueRef) -> Value {
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(i) => json!(i),
        ValueRef::Real(f) => json!(f),
        ValueRef::Text(t) => Value::String(String::from_utf8_lossy(t).into_owned()),
        ValueRef::Blob(b) => Value::String(base64::engine::general_purpose::STANDARD.encode(b)),
    }
}
