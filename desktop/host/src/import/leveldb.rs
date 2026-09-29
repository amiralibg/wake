//! Just enough LevelDB to read Chromium's "Local Storage/leveldb" folder (a port of
//! LevelDB.swift): every table file (`.ldb`/`.sst`) and write-ahead log (`.log`),
//! newest sequence number winning. The manifest is ignored; LevelDB deletes
//! obsolete files promptly, and sequence numbers order whatever is left. Plus raw
//! Snappy, which LevelDB and Firefox's storage both use.

use std::collections::HashMap;
use std::path::Path;

pub fn read(folder: &Path) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut latest: HashMap<Vec<u8>, (u64, Option<Vec<u8>>)> = HashMap::new();
    let mut apply = |key: Vec<u8>, sequence: u64, value: Option<Vec<u8>>| {
        if let Some((known, _)) = latest.get(&key) {
            if *known > sequence {
                return;
            }
        }
        latest.insert(key, (sequence, value));
    };
    let Ok(entries) = std::fs::read_dir(folder) else { return Vec::new() };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(bytes) = std::fs::read(&path) else { continue };
        match path.extension().and_then(|e| e.to_str()) {
            Some("ldb") | Some("sst") => table(&bytes, &mut apply),
            Some("log") => log(&bytes, &mut apply),
            _ => {}
        }
    }
    latest.into_iter().filter_map(|(k, (_, v))| v.map(|v| (k, v))).collect()
}

struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8], position: usize) -> Self {
        Self { bytes, position }
    }

    fn byte(&mut self) -> Option<u8> {
        let b = *self.bytes.get(self.position)?;
        self.position += 1;
        Some(b)
    }

    fn varint(&mut self) -> Option<u64> {
        let mut result = 0u64;
        let mut shift = 0;
        while shift < 64 {
            let b = self.byte()?;
            result |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Some(result);
            }
            shift += 7;
        }
        None
    }

    fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let end = self.position.checked_add(count)?;
        let slice = self.bytes.get(self.position..end)?;
        self.position = end;
        Some(slice)
    }
}

fn table(bytes: &[u8], emit: &mut dyn FnMut(Vec<u8>, u64, Option<Vec<u8>>)) {
    // Footer: metaindex and index handles, padding, 8-byte magic.
    if bytes.len() < 48 || bytes[bytes.len() - 8..] != [0x57, 0xFB, 0x80, 0x8B, 0x24, 0x75, 0x47, 0xDB] {
        return;
    }
    let mut footer = Reader::new(bytes, bytes.len() - 48);
    let (Some(_), Some(_), Some(offset), Some(size)) = (footer.varint(), footer.varint(), footer.varint(), footer.varint()) else { return };
    let Some(index) = block(bytes, offset as usize, size as usize) else { return };
    for (_, handle) in entries(&index) {
        let mut h = Reader::new(&handle, 0);
        let (Some(offset), Some(size)) = (h.varint(), h.varint()) else { continue };
        let Some(data) = block(bytes, offset as usize, size as usize) else { continue };
        for (internal, value) in entries(&data) {
            if internal.len() < 8 {
                continue;
            }
            // The last 8 bytes: sequence << 8 | type (1 = value, 0 = deletion).
            let tag = u64::from_le_bytes(internal[internal.len() - 8..].try_into().unwrap());
            let key = internal[..internal.len() - 8].to_vec();
            emit(key, tag >> 8, if tag & 0xff == 1 { Some(value) } else { None });
        }
    }
}

/// A block's contents, decompressed; a 5-byte trailer (type, CRC) follows it.
fn block(bytes: &[u8], offset: usize, size: usize) -> Option<Vec<u8>> {
    let end = offset.checked_add(size)?;
    if end + 5 > bytes.len() {
        return None;
    }
    let contents = &bytes[offset..end];
    match bytes[end] {
        0 => Some(contents.to_vec()),
        1 => snappy(contents),
        _ => None,
    }
}

/// Prefix-compressed entries, followed by restart offsets and their count.
fn entries(block: &[u8]) -> Vec<(Vec<u8>, Vec<u8>)> {
    if block.len() < 4 {
        return Vec::new();
    }
    let restarts = u32::from_le_bytes(block[block.len() - 4..].try_into().unwrap()) as usize;
    let Some(end) = block.len().checked_sub(4 + restarts * 4) else { return Vec::new() };
    let mut reader = Reader::new(block, 0);
    let mut key: Vec<u8> = Vec::new();
    let mut out = Vec::new();
    while reader.position < end {
        let (Some(shared), Some(unshared), Some(value_len)) = (reader.varint(), reader.varint(), reader.varint()) else { break };
        if shared as usize > key.len() {
            break;
        }
        let (Some(delta), Some(value)) = (reader.take(unshared as usize), reader.take(value_len as usize)) else { break };
        key.truncate(shared as usize);
        key.extend_from_slice(delta);
        out.push((key.clone(), value.to_vec()));
    }
    out
}

fn log(bytes: &[u8], emit: &mut dyn FnMut(Vec<u8>, u64, Option<Vec<u8>>)) {
    const BLOCK: usize = 32_768;
    let mut position = 0;
    let mut pending: Vec<u8> = Vec::new();
    while position + 7 <= bytes.len() {
        let left = BLOCK - position % BLOCK;
        if left < 7 {
            position += left;
            continue;
        }
        let length = bytes[position + 4] as usize | (bytes[position + 5] as usize) << 8;
        let kind = bytes[position + 6];
        let start = position + 7;
        if start + length > bytes.len() {
            break;
        }
        let fragment = &bytes[start..start + length];
        position = start + length;
        match kind {
            1 => batch(fragment, emit),
            2 => pending = fragment.to_vec(),
            3 => pending.extend_from_slice(fragment),
            4 => {
                pending.extend_from_slice(fragment);
                batch(&pending, emit);
                pending.clear();
            }
            _ => {}
        }
    }
}

/// A write batch: 8-byte sequence, 4-byte count, then tagged puts and deletes.
fn batch(record: &[u8], emit: &mut dyn FnMut(Vec<u8>, u64, Option<Vec<u8>>)) {
    if record.len() < 12 {
        return;
    }
    let sequence = u64::from_le_bytes(record[..8].try_into().unwrap());
    let mut reader = Reader::new(record, 12);
    let mut index = 0u64;
    while reader.position < record.len() {
        let Some(tag) = reader.byte() else { return };
        let Some(key_len) = reader.varint() else { return };
        let Some(key) = reader.take(key_len as usize) else { return };
        if tag == 1 {
            let Some(value_len) = reader.varint() else { return };
            let Some(value) = reader.take(value_len as usize) else { return };
            emit(key.to_vec(), sequence + index, Some(value.to_vec()));
        } else {
            emit(key.to_vec(), sequence + index, None);
        }
        index += 1;
    }
}

/// Raw (unframed) Snappy.
pub fn snappy(input: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(input, 0);
    let length = reader.varint()? as usize;
    if length > 256 * 1024 * 1024 {
        return None;
    }
    let mut out: Vec<u8> = Vec::with_capacity(length);
    while let Some(tag) = reader.byte() {
        match tag & 0x03 {
            0 => {
                let mut count = (tag >> 2) as usize;
                if count >= 60 {
                    let extra = count - 59;
                    let bytes = reader.take(extra)?;
                    count = bytes.iter().rev().fold(0usize, |acc, &b| acc << 8 | b as usize);
                }
                out.extend_from_slice(reader.take(count + 1)?);
            }
            1 => {
                let next = reader.byte()? as usize;
                let count = 4 + ((tag >> 2) & 0x07) as usize;
                let offset = ((tag >> 5) as usize) << 8 | next;
                copy(&mut out, offset, count)?;
            }
            2 => {
                let b = reader.take(2)?;
                copy(&mut out, b[0] as usize | (b[1] as usize) << 8, (tag >> 2) as usize + 1)?;
            }
            _ => {
                let b = reader.take(4)?;
                let offset = u32::from_le_bytes(b.try_into().ok()?) as usize;
                copy(&mut out, offset, (tag >> 2) as usize + 1)?;
            }
        }
    }
    (out.len() == length).then_some(out)
}

/// Byte by byte: the source may overlap what's being written (runs).
fn copy(out: &mut Vec<u8>, offset: usize, count: usize) -> Option<()> {
    if offset == 0 || offset > out.len() {
        return None;
    }
    let start = out.len() - offset;
    for i in 0..count {
        let b = out[start + i];
        out.push(b);
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::snappy;

    #[test]
    fn snappy_literal_and_copy() {
        // "abcabcabc": length 9, literal "abc", copy offset 3 length 6.
        let data = [9, 0b0000_1000, b'a', b'b', b'c', 0b0000_1001, 3];
        assert_eq!(snappy(&data).unwrap(), b"abcabcabc");
    }
}
