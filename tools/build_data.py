"""Builds the compact Bible assets bundled with Bible by Cue.

Inputs (downloaded once by the developer, not by the app):
  eng-web_vpl.txt        World English Bible (public domain) from https://ebible.org/Scriptures/eng-web_vpl.zip
  cross_references.txt   OpenBible.info cross references (CC-BY) from https://a.openbible.info/data/cross-references.zip

Outputs (inputs to tools/build_db.py, which produces the bundled assets/bible/web.db.gz):
  tools/data/web.txt.gz     one verse per line: "<id>\t<text>", id = book*1000000 + chapter*1000 + verse
  tools/data/xref.bin.gz    little-endian uint32 triples (from, toStart, toEnd), sorted by from
"""
import gzip, struct, sys, collections

WEB_CODES = ("GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SOL ISA JER LAM "
             "EZE DAN HOS JOE AMO OBA JON MIC NAH HAB ZEP HAG ZEC MAL MAT MAR LUK JOH ACT ROM 1CO 2CO GAL EPH PHI COL "
             "1TH 2TH 1TI 2TI TIT PHM HEB JAM 1PE 2PE 1JO 2JO 3JO JUD REV").split()
OSIS = ("Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth Job Ps Prov Eccl Song Isa Jer "
        "Lam Ezek Dan Hos Joel Amos Obad Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom 1Cor 2Cor Gal "
        "Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet 2Pet 1John 2John 3John Jude Rev").split()
assert len(WEB_CODES) == 66 and len(OSIS) == 66

def vid(b, c, v): return b * 1000000 + c * 1000 + v

def build_bible(src, out):
    book_of = {code: i + 1 for i, code in enumerate(WEB_CODES)}
    rows, seen = [], set()
    with open(src, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            code, cv, text = line.split(" ", 2)
            if code not in book_of:
                continue  # deuterocanonical books are not part of the 66-book canon shipped here
            c, v = map(int, cv.split(":"))
            text = " ".join(text.split())
            if not text:
                continue
            i = vid(book_of[code], c, v)
            assert i not in seen, line
            seen.add(i)
            rows.append((i, text))
    rows.sort()
    books = {r[0] // 1000000 for r in rows}
    assert books == set(range(1, 67)), sorted(set(range(1, 67)) - books)
    with gzip.open(out, "wt", encoding="utf-8", compresslevel=9) as g:
        for i, t in rows:
            g.write(f"{i}\t{t}\n")
    return {r[0] for r in rows}

def parse_osis(ref):
    b, c, v = ref.split(".")
    return vid(OSIS.index(b) + 1, int(c), int(v))

def build_xref(src, out, valid, min_votes, per_verse):
    by_from = collections.defaultdict(list)
    with open(src, encoding="utf-8") as f:
        next(f)
        for line in f:
            frm, to, votes = line.rstrip("\n").split("\t")
            votes = int(votes)
            if votes < min_votes:
                continue
            a = parse_osis(frm)
            parts = to.split("-")
            s = parse_osis(parts[0]); e = parse_osis(parts[1]) if len(parts) > 1 else s
            if a not in valid or s not in valid or e < s:
                continue
            by_from[a].append((votes, s, e))
    data = bytearray()
    n = 0
    for a in sorted(by_from):
        for votes, s, e in sorted(by_from[a], reverse=True)[:per_verse]:
            data += struct.pack("<III", a, s, e); n += 1
    with gzip.open(out, "wb", compresslevel=9) as g:
        g.write(data)
    return n

if __name__ == "__main__":
    web, xref, outdir = sys.argv[1:4]
    valid = build_bible(web, f"{outdir}/web.txt.gz")
    print("verses:", len(valid))
    print("xrefs:", build_xref(xref, f"{outdir}/xref.bin.gz", valid, min_votes=5, per_verse=12))
