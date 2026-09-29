#!/bin/sh
# Inside the container: a small fake Firefox profile (history, a search, cookies,
# localStorage) so Import has something to read. Run before app.sh.
set -e
P=$HOME/.mozilla/firefox/test.default
mkdir -p "$P/storage/default/https+++example.com/ls"
cat > "$HOME/.mozilla/firefox/profiles.ini" <<INI
[Profile0]
Name=default
IsRelative=1
Path=test.default
INI
NOW=$(date +%s)
sqlite3 "$P/places.sqlite" <<SQL
CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_date INTEGER, hidden INTEGER DEFAULT 0);
INSERT INTO moz_places (url, title, visit_count, last_visit_date) VALUES
 ('https://example.com/', 'Example Domain', 4, ${NOW}000000),
 ('https://www.rust-lang.org/', 'Rust Programming Language', 2, ${NOW}000000 - 3600000000),
 ('https://duckduckgo.com/?q=paper+boats', 'paper boats at DuckDuckGo', 1, ${NOW}000000 - 7200000000),
 ('https://www.google.com/search?q=kelvin+wake', 'kelvin wake - Google Search', 1, ${NOW}000000 - 9000000000);
SQL
sqlite3 "$P/cookies.sqlite" <<SQL
CREATE TABLE moz_cookies (id INTEGER PRIMARY KEY, originAttributes TEXT NOT NULL DEFAULT '', name TEXT, value TEXT, host TEXT, path TEXT, expiry INTEGER, isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER);
INSERT INTO moz_cookies (name, value, host, path, expiry, isSecure, isHttpOnly, sameSite) VALUES
 ('session', 'abc123', '.example.com', '/', $((NOW + 86400)), 1, 1, 1),
 ('theme', 'dark', 'example.com', '/', $((NOW + 86400)), 0, 0, 0);
SQL
sqlite3 "$P/storage/default/https+++example.com/ls/data.sqlite" <<SQL
CREATE TABLE data (key TEXT PRIMARY KEY, value BLOB, compression_type INTEGER, conversion_type INTEGER);
INSERT INTO data VALUES ('greeting', CAST('hello from firefox' AS BLOB), 0, 1);
SQL
echo "fixture at $P"
