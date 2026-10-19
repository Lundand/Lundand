"""Writes vanta/src back into a Roblox place file (.rbxl, binary format).

    python3 tools/patch_place.py Vanta.rbxl Vanta-patched.rbxl [--src src] [--streaming]

* every script whose file changed gets its new Source
* scripts that exist as files but not in the place are added (as ModuleScript, Script or LocalScript under the
  instance their folder names; that parent must already exist in the place or be added in the same run)
* --streaming turns Workspace.StreamingEnabled on
Everything else in the place (meshes, animations, assets, properties) is copied chunk for chunk, so nothing the
script doesn't touch can change. Scripts deleted from src are left in the place (reported).
"""
import argparse, os, struct, sys, uuid
import zstandard, lz4.block

MAGIC = b"<roblox!\x89\xff\r\n\x1a\n"


# ---------------------------------------------------------------------------------------------------- chunks
def read_chunks(data):
    assert data[:14] == MAGIC, "not a binary place file"
    header = data[:32]
    pos, chunks = 32, []
    while pos < len(data):
        name = data[pos:pos + 4]
        clen, ulen, _ = struct.unpack("<III", data[pos + 4:pos + 16])
        pos += 16
        if clen == 0:
            body = data[pos:pos + ulen]
            pos += ulen
        else:
            raw = data[pos:pos + clen]
            pos += clen
            if raw[:4] == b"\x28\xb5\x2f\xfd":
                body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
            else:
                body = lz4.block.decompress(raw, uncompressed_size=ulen)
        chunks.append([name, bytes(body)])
        if name == b"END\0":
            break
    return header, chunks


def write_chunks(header, chunks):
    out = bytearray(header)
    for name, body in chunks:
        if name == b"END\0":
            out += name + struct.pack("<III", 0, len(body), 0) + body
        else:
            packed = lz4.block.compress(body, store_size=False)
            out += name + struct.pack("<III", len(packed), len(body), 0) + packed
    return bytes(out)


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def u8(self):
        v = self.d[self.p]
        self.p += 1
        return v

    def u32(self):
        v = struct.unpack("<I", self.d[self.p:self.p + 4])[0]
        self.p += 4
        return v

    def string(self):
        n = self.u32()
        v = self.d[self.p:self.p + n]
        self.p += n
        return v

    def raw(self, n):
        v = self.d[self.p:self.p + n]
        self.p += n
        return v

    def rest(self):
        return self.d[self.p:]


def deinterleave(blob, count, width):
    return [bytes(blob[j * count + i] for j in range(width)) for i in range(count)]


def interleave(items, width):
    count = len(items)
    out = bytearray(count * width)
    for i, item in enumerate(items):
        for j in range(width):
            out[j * count + i] = item[j]
    return bytes(out)


def decode_refs(blob, count):
    out, acc = [], 0
    for item in deinterleave(blob, count, 4):
        u = int.from_bytes(item, "big")
        acc += (u >> 1) ^ -(u & 1)
        out.append(acc)
    return out


def encode_refs(refs):
    items, prev = [], 0
    for r in refs:
        delta = r - prev
        prev = r
        z = (delta << 1) ^ (delta >> 31)
        items.append((z & 0xFFFFFFFF).to_bytes(4, "big"))
    return interleave(items, 4)


def pack_string(s):
    return struct.pack("<I", len(s)) + s


# property value layouts: "str" (length-prefixed, one after another), "bool" (one byte each),
# or an interleaved fixed width in bytes
WIDTH = {1: "str", 2: "bool", 12: 3, 18: 4, 27: 8, 28: 4, 31: 16, 33: 8}


def split_values(type_id, blob, count):
    kind = WIDTH.get(type_id)
    if kind is None:
        raise ValueError("unsupported property type %d" % type_id)
    if kind == "str":
        r, items = Reader(blob), []
        for _ in range(count):
            items.append(r.string())
        return items
    if kind == "bool":
        return [blob[i:i + 1] for i in range(count)]
    return deinterleave(blob, count, kind)


def join_values(type_id, items):
    kind = WIDTH[type_id]
    if kind == "str":
        return b"".join(pack_string(s) for s in items)
    if kind == "bool":
        return b"".join(items)
    return interleave(items, kind)


# ---------------------------------------------------------------------------------------------------- the place
class Place:
    def __init__(self, data):
        self.header, self.chunks = read_chunks(data)
        self.classes = {}  # class id -> {name, ids, inst_chunk, props: {name: chunk}}
        self.by_name = {}
        self.parent = {}
        self.sstr = []
        for chunk in self.chunks:
            name, body = chunk
            r = Reader(body)
            if name == b"INST":
                cid = r.u32()
                cname = r.string().decode()
                fmt = r.u8()
                n = r.u32()
                ids = decode_refs(r.raw(n * 4), n)
                info = {"name": cname, "ids": ids, "format": fmt, "chunk": chunk, "props": {}, "rest": r.rest(), "cid": cid}
                self.classes[cid] = info
                self.by_name[cname] = info
            elif name == b"PROP":
                cid = r.u32()
                pname = r.string().decode()
                self.classes[cid]["props"][pname] = chunk
            elif name == b"PRNT":
                r.u8()
                n = r.u32()
                children = decode_refs(r.raw(n * 4), n)
                parents = decode_refs(r.raw(n * 4), n)
                self.parent = dict(zip(children, parents))
                self.prnt_chunk = chunk
            elif name == b"SSTR":
                r.u32()
                n = r.u32()
                for _ in range(n):
                    r.raw(16)
                    self.sstr.append(r.string())
        self.class_of = {}
        for cid, info in self.classes.items():
            for i, ref in enumerate(info["ids"]):
                self.class_of[ref] = (cid, i)

    # property values of one class, decoded per instance
    def values(self, cid, pname):
        chunk = self.classes[cid]["props"][pname]
        r = Reader(chunk[1])
        r.u32()
        r.string()
        type_id = r.u8()
        return type_id, split_values(type_id, r.rest(), len(self.classes[cid]["ids"]))

    def set_values(self, cid, pname, type_id, items):
        chunk = self.classes[cid]["props"][pname]
        chunk[1] = struct.pack("<I", cid) + pack_string(pname.encode()) + bytes([type_id]) + join_values(type_id, items)

    def prop(self, ref, pname):
        cid, i = self.class_of[ref]
        if pname not in self.classes[cid]["props"]:
            return None
        type_id, items = self.values(cid, pname)
        return items[i]

    def children(self, ref):
        return [c for c, p in self.parent.items() if p == ref]

    def path_index(self):
        """Maps 'Service/Child/...' paths to referents (scripts and folders)."""
        names = {}
        for cid, info in self.classes.items():
            if "Name" in info["props"]:
                _, items = self.values(cid, "Name")
                for ref, n in zip(info["ids"], items):
                    names[ref] = n.decode("utf-8", "replace")
            else:
                for ref in info["ids"]:
                    names[ref] = info["name"]
        index = {}
        for ref in self.class_of:
            parts, cur = [], ref
            while cur in self.class_of:
                parts.append(names[cur])
                cur = self.parent.get(cur, -1)
            index["/".join(reversed(parts))] = ref
        return index

    def add_instance(self, class_name, parent_ref, overrides):
        """Adds one instance by copying another of the same class, then overriding some properties."""
        info = self.by_name[class_name]
        cid = info["cid"]
        template_index = 0
        # prefer a template whose tags are empty
        if "Tags" in info["props"]:
            _, tags = self.values(cid, "Tags")
            for i, t in enumerate(tags):
                idx = int.from_bytes(t, "big")
                if idx < len(self.sstr) and self.sstr[idx] == b"":
                    template_index = i
                    break
        new_ref = max(self.class_of) + 1
        for pname in list(info["props"]):
            type_id, items = self.values(cid, pname)
            item = items[template_index]
            if pname in overrides:
                item = overrides[pname]
            elif type_id == 31:
                item = item[:12] + os.urandom(4)  # UniqueId / HistoryId: keep it unique
            items.append(item)
            # the chunk's instance count comes from INST, so values and ids are updated together
            self.set_values_raw(cid, pname, type_id, items)
        info["ids"].append(new_ref)
        self.class_of[new_ref] = (cid, len(info["ids"]) - 1)
        self.parent[new_ref] = parent_ref
        self._rewrite_inst(cid)
        return new_ref

    def set_values_raw(self, cid, pname, type_id, items):
        chunk = self.classes[cid]["props"][pname]
        chunk[1] = struct.pack("<I", cid) + pack_string(pname.encode()) + bytes([type_id]) + join_values(type_id, items)

    def _rewrite_inst(self, cid):
        info = self.classes[cid]
        ids = info["ids"]
        body = struct.pack("<I", cid) + pack_string(info["name"].encode()) + bytes([info["format"]]) + struct.pack("<I", len(ids)) + encode_refs(ids)
        if info["format"] == 1:
            body += bytes([1]) * len(ids)
        info["chunk"][1] = body

    def finish(self):
        children = list(self.parent.keys())
        parents = [self.parent[c] for c in children]
        self.prnt_chunk[1] = bytes([0]) + struct.pack("<I", len(children)) + encode_refs(children) + encode_refs(parents)
        count = sum(len(info["ids"]) for info in self.classes.values())
        header = bytearray(self.header)
        header[16:20] = struct.pack("<i", len(self.classes))
        header[20:24] = struct.pack("<i", count)
        return write_chunks(bytes(header), self.chunks)


# ---------------------------------------------------------------------------------------------------- src files
SUFFIXES = [(".server.luau", "Script"), (".client.luau", "LocalScript"), (".luau", "ModuleScript")]


def source_files(root):
    """Yields (instance path, class, file) for every script file under src."""
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            for suffix, cls in SUFFIXES:
                if f.endswith(suffix):
                    base = f[: -len(suffix)]
                    rel = os.path.relpath(dirpath, root).replace(os.sep, "/")
                    path = rel if base == "init" else rel + "/" + base
                    yield path, cls, os.path.join(dirpath, f)
                    break


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--src", default="src")
    ap.add_argument("--streaming", action="store_true")
    args = ap.parse_args()
    place = Place(open(args.input, "rb").read())
    index = place.path_index()
    files = sorted(source_files(args.src), key=lambda t: t[0].count("/"))
    updated, added = [], []
    for path, cls, filename in files:
        source = open(filename, "rb").read()
        ref = index.get(path)
        if ref is not None:
            cid, i = place.class_of[ref]
            if place.classes[cid]["name"] != cls:
                sys.exit("%s is a %s in the place but a %s in src" % (path, place.classes[cid]["name"], cls))
            type_id, items = place.values(cid, "Source")
            if items[i] != source:
                items[i] = source
                place.set_values(cid, "Source", type_id, items)
                updated.append(path)
        else:
            parent_path, name = path.rsplit("/", 1)
            parent = index.get(parent_path)
            if parent is None:
                sys.exit("can't add %s: %s isn't in the place" % (path, parent_path))
            overrides = {
                "Name": name.encode(),
                "Source": source,
                "ScriptGuid": ("{%s}" % str(uuid.uuid4()).upper()).encode(),
            }
            ref = place.add_instance(cls, parent, overrides)
            index[path] = ref
            added.append(path)
    scripts = {p for p, _, _ in files}
    for path, ref in index.items():
        cid, _ = place.class_of[ref]
        if place.classes[cid]["name"] in ("Script", "LocalScript", "ModuleScript") and path not in scripts:
            print("in the place but not in src (left as is):", path)
    if args.streaming:
        ws = place.by_name["Workspace"]
        type_id, items = place.values(ws["cid"], "StreamingEnabled")
        place.set_values(ws["cid"], "StreamingEnabled", type_id, [b"\x01"] * len(items))
        print("Workspace.StreamingEnabled = true")
    open(args.output, "wb").write(place.finish())
    print("updated %d scripts, added %d:" % (len(updated), len(added)))
    for p in updated:
        print("  ~", p)
    for p in added:
        print("  +", p)


if __name__ == "__main__":
    main()
