"""Closed enum values follow protoc/Python unknown-field behavior."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--daslang", default="daslang")
parser.add_argument("--grpc-tools-root", type=Path)
args = parser.parse_args()
if args.grpc_tools_root:
    sys.path.insert(0, str(args.grpc_tools_root.resolve()))
from grpc_tools import protoc
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory


def run(*argv):
    result = subprocess.run([str(arg) for arg in argv], cwd=ROOT,
                            capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


with tempfile.TemporaryDirectory(prefix="closed-enum-", dir=ROOT) as directory:
    out = Path(directory)
    proto = ROOT / "tests/closed_enum.proto"
    descriptor = out / "closed_enum.desc"
    assert protoc.main(["protoc", f"-I{proto.parent}",
                        f"--descriptor_set_out={descriptor}", str(proto)]) == 0
    run(args.daslang, "-no-module-cache", "-no-dynamic-modules",
        ROOT / "tools/generate.das", "--", descriptor,
        out / "closed_enum_generated.das", out / "closed_enum_ir.proto")
    assert "features.enum_type = CLOSED" in (out / "closed_enum_ir.proto").read_text()
    assert protoc.main(["protoc", f"-I{out}",
                        f"--descriptor_set_out={out/'ir.desc'}",
                        str(out / "closed_enum_ir.proto")]) == 0

    pool = descriptor_pool.DescriptorPool()
    pool.Add(descriptor_pb2.FileDescriptorSet.FromString(descriptor.read_bytes()).file[0])
    cls = message_factory.GetMessageClass(pool.FindMessageTypeByName("example.ClosedEnums"))
    wire = bytes((8, 9, 18, 3, 1, 9, 1, 24, 9, 34, 4, 8, 1, 16, 9, 40, 9))
    foreign = cls.FromString(wire)
    assert not foreign.HasField("single")
    assert list(foreign.many) == [1, 1]
    assert foreign.WhichOneof("choice") is None
    assert dict(foreign.states) == {}
    assert foreign.open_state == 9
    (out / "foreign.bin").write_bytes(wire)
    client = out / "closed_enum_client.das"
    client.write_text('''options gen2
require ./closed_enum_generated.das
[export]
def main {
    let parsed <- pb_unpack_ClosedEnums(pb_load("'''+(out/'foreign.bin').as_posix()+'''"))
    assert(parsed.single is none && length(parsed.many)==2)
    assert(parsed.choice is none)
    assert(length(parsed.states)==0 && length(parsed.pb_unknown_fields)==12)
    assert(int(parsed.open_state as some)==9)
    pb_save("'''+(out/'native.bin').as_posix()+'''",pb_pack_ClosedEnums(parsed))
}
''', encoding="utf-8")
    run(args.daslang, "-no-module-cache", "-no-dynamic-modules", client)
    roundtrip = cls.FromString((out / "native.bin").read_bytes())
    assert not roundtrip.HasField("single")
    assert list(roundtrip.many) == [1, 1]
    assert roundtrip.WhichOneof("choice") is None
    assert dict(roundtrip.states) == {}
    assert roundtrip.open_state == 9
    assert roundtrip.SerializeToString() == foreign.SerializeToString()

    schema = run(args.daslang, "-no-module-cache", "-no-dynamic-modules",
                 ROOT / "tests/closed_enum_codefirst.das")
    (out / "codefirst.proto").write_text(schema, encoding="utf-8")
    assert "features.enum_type = CLOSED" in schema
    assert protoc.main(["protoc", f"-I{out}",
                        f"--descriptor_set_out={out/'codefirst.desc'}",
                        str(out / "codefirst.proto")]) == 0
    legacy = ROOT / "tests/proto2_closed_enum.proto"
    legacy_descriptor = out / "proto2.desc"
    assert protoc.main(["protoc", f"-I{legacy.parent}",
                        f"--descriptor_set_out={legacy_descriptor}", str(legacy)]) == 0
    run(args.daslang, "-no-module-cache", "-no-dynamic-modules",
        ROOT / "tools/generate.das", "--", legacy_descriptor,
        out / "proto2_generated.das")
    legacy_client = out / "proto2_client.das"
    legacy_client.write_text('''options gen2
require ./proto2_generated.das
[export]
def main {
    let parsed <- pb_unpack_LegacyEnums([8u8,9u8,18u8,3u8,1u8,9u8,1u8])
    assert(parsed.single is none && length(parsed.many)==2)
    assert(length(parsed.pb_unknown_fields)==4)
}
''', encoding="utf-8")
    run(args.daslang, "-no-module-cache", "-no-dynamic-modules", legacy_client)
print("Closed enums: schema-first and code-first compatibility OK")
