"""End-to-end native daScript wrappers over a local grpcio HTTP/2 server."""
import argparse
from concurrent import futures
import os
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
import grpc
from grpc_tools import protoc


def run(*argv):
    env = os.environ.copy()
    if args.grpc_tools_root:
        env["PYTHONPATH"] = str(args.grpc_tools_root.resolve()) + os.pathsep + env.get("PYTHONPATH", "")
    result = subprocess.run([str(item) for item in argv], cwd=ROOT,
                            capture_output=True, text=True, timeout=120, env=env)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)


def value(data):
    assert len(data) == 2 and data[0] == 8
    return data[1]


def encoded(n):
    assert 0 <= n < 128
    return bytes((8, n))


def unary(request, context):
    assert ("x-test", "from-dascript") in context.invocation_metadata()
    return encoded(value(request) + 1)


with tempfile.TemporaryDirectory(prefix="grpc-test-", dir=ROOT) as scratch:
    out = Path(scratch)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    server.add_generic_rpc_handlers((
        grpc.method_handlers_generic_handler("example.Echo", {
            "Call": grpc.unary_unary_rpc_method_handler(unary)
        }),
        grpc.method_handlers_generic_handler("example.StreamEcho", {
            "Upload": grpc.stream_unary_rpc_method_handler(
                lambda requests, context: encoded(sum(map(value, requests)))),
            "Subscribe": grpc.unary_stream_rpc_method_handler(
                lambda request, context: (encoded(value(request) + i) for i in range(3))),
            "Chat": grpc.stream_stream_rpc_method_handler(
                lambda requests, context: (encoded(value(item) + 2) for item in requests)),
        }),
    ))
    port = server.add_insecure_port("127.0.0.1:0")
    assert port > 0
    server.start()
    try:
        for stem in ("service", "service_stream"):
            fixture = ROOT / "tests" / f"{stem}.proto"
            descriptor = out / f"{stem}.desc"
            result = protoc.main(["protoc", f"-I{fixture.parent}",
                                  f"--descriptor_set_out={descriptor}", str(fixture)])
            assert result == 0
            run(args.daslang, "-no-module-cache", "-no-dynamic-modules",
                ROOT / "tools/generate.das", "--", descriptor,
                out / f"{stem}_generated.das")
        client = out / "grpc_client.das"
        client.write_text('''options gen2
require ./service_generated.das
require ./service_stream_generated.das
[export]
def main {
    var config=PBGrpcTransport(python="'''+sys.executable.replace('\\','/')+'''",
        helper="'''+(ROOT/'tools/grpc_transport.py').as_posix()+'''",
        target="127.0.0.1:'''+str(port)+'''",
        request_path="'''+(out/'request.frames').as_posix()+'''",
        response_path="'''+(out/'response.frames').as_posix()+'''")
    push(config.metadata,"x-test=from-dascript")
    let answer <- pb_grpc_Echo_Call(Request(value=3),config)
    assert(answer.value==4)
    let uploaded <- pb_grpc_StreamEcho_Upload([StreamRequest(value=2),StreamRequest(value=5)],config)
    assert(length(uploaded)==1 && uploaded[0].value==7)
    let streamed <- pb_grpc_StreamEcho_Subscribe([StreamRequest(value=6)],config)
    assert(length(streamed)==3 && streamed[0].value==6 && streamed[2].value==8)
    let echoed <- pb_grpc_StreamEcho_Chat([StreamRequest(value=1),StreamRequest(value=4)],config)
    assert(length(echoed)==2 && echoed[0].value==3 && echoed[1].value==6)
}
''', encoding="utf-8")
        run(args.daslang, "-no-module-cache", "-no-dynamic-modules", client)
    finally:
        server.stop(0).wait()
print("gRPC transport: unary, client/server streaming and bidirectional streaming OK")
