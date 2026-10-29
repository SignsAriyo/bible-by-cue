"""Prebuilds the bundled Bible database so first launch only has to decompress it.

The database holds the verse text and cross references. The full-text index is not shipped: it
roughly doubles the download, and the app builds it on the device with a single native SQL
statement (see BibleRepository._installBundled), as is the small cross-reference index. The schema must match lib/core/bible_repository.dart.

usage: python tools/build_db.py tools/data/web.txt.gz tools/data/xref.bin.gz assets/bible/web.db.gz
"""
import gzip
import os
import sqlite3
import struct
import sys
import tempfile


def main(text_gz, xref_gz, out):
    rows = []
    with gzip.open(text_gz, 'rt', encoding='utf-8') as f:
        for line in f:
            i, t = line.rstrip('\n').split('\t', 1)
            rows.append((int(i), t))
    xref = gzip.open(xref_gz, 'rb').read()
    triples = [struct.unpack_from('<III', xref, k * 12) for k in range(len(xref) // 12)]

    fd, tmp = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    os.remove(tmp)
    db = sqlite3.connect(tmp)
    db.execute('PRAGMA page_size=4096')
    db.execute('CREATE TABLE verses(id INTEGER PRIMARY KEY, t TEXT NOT NULL)')
    db.execute('CREATE TABLE xref(f INTEGER NOT NULL, s INTEGER NOT NULL, e INTEGER NOT NULL)')
    db.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)')
    db.executemany('INSERT INTO verses(id, t) VALUES (?, ?)', rows)
    db.executemany('INSERT INTO xref VALUES (?, ?, ?)', triples)
    db.execute("INSERT INTO meta VALUES ('verses', ?)", (str(len(rows)),))
    db.commit()
    db.execute('VACUUM')
    db.close()
    raw = open(tmp, 'rb').read()
    os.remove(tmp)
    with gzip.open(out, 'wb', compresslevel=9) as g:
        g.write(raw)
    print(f'{len(rows)} verses, {len(triples)} cross references; db {len(raw):,} bytes -> {os.path.getsize(out):,} bytes gzipped')


if __name__ == '__main__':
    main(*sys.argv[1:4])
