# daScript Protobuf

Protobuf serialization for [daScript](https://github.com/GaijinEntertainment/daScript). Define messages with daScript annotations or generate daScript types from a `.proto` schema. Both paths use the same schema IR and binary runtime.

## Quick start

Run commands from the repository root with `daslang` on `PATH`, or pass the full path to your daScript executable.

```powershell
python -m pip install -r requirements-dev.txt
python tools/proto_to_dascript.py tests/person.proto --out generated --daslang daslang
```

This creates `generated/person_generated.das`, a descriptor set, a verbatim schema copy, and an IR projection. The generated module exposes `pb_pack_Person`, `pb_unpack_Person`, and `pb_verify_Person`.

For code-first development, annotate a daScript type:

```das
options gen2
require ../src/annotations.das

[pb_message(package="example")]
struct Person {
    @pb_id=1
    name:string
    @pb_id=2
    age:Option<int>
    @pb_id=3
    scores:array<int>
}
```

The macro generates the binary functions plus `pb_schema_Person()` and `pb_descriptor_Person()`. `Option<T>` distinguishes an absent field from a present default value. See `examples/person.das` for a runnable example.

## Supported schemas

- Proto2, proto3, and Editions 2023, 2024, and 2026.
- Scalars, strings, bytes, enums, repeated fields, maps, oneofs, groups, nested and recursive messages, extensions, and services.
- Presence, required fields, schema defaults, packed encoding, UTF-8 validation, and delimited messages.
- Unknown-field retention, including groups and unknown closed-enum values.
- Imported descriptors and cross-package references.

Edition 2026 needs an external `protoc` 36 or newer. Pass its path with `--protoc`. Generated files import `../src/annotations.das` and `../src/grpc_transport.das`; place the output directory directly under the repository root or adjust the imports.

## JSON and gRPC

Binary encoding runs in daScript. The optional JSON bridge uses the official Python Protobuf runtime:

```powershell
python tools/json_bridge.py --descriptor generated/person.desc --type example.Person --input generated/person.bin --output generated/person.json --direction to-json
```

Use `--direction from-json` for the reverse conversion.

Generated `pb_rpc_*` functions accept a transport callback. Generated `pb_grpc_*` client functions use `grpcio` through `tools/grpc_transport.py`:

```das
var transport=PBGrpcTransport(
    python="python",
    helper="tools/grpc_transport.py",
    target="127.0.0.1:50051",
    request_path="request.frames",
    response_path="response.frames")
let reply <- pb_grpc_Echo_Call(Request(value=3),transport)
```

The adapter supports all four RPC shapes, TLS, deadlines, and metadata. Each call launches a Python process and buffers messages in files. Use distinct scratch paths for concurrent calls.

## Tests

Run from the repository root:

```powershell
python tests/run_tests.py --daslang daslang
python tests/test_closed_enum.py --daslang daslang
python tests/test_grpc_transport.py --daslang daslang
python tests/test_edition2026.py --protoc /path/to/protoc --daslang daslang
```

The tests compare schemas and messages with `protoc` and Python Protobuf. The gRPC test starts a local server. If dependencies are installed outside the active Python environment, add `--grpc-tools-root PATH`.

## Limitations

- A descriptor set does not contain the original comments or option syntax. `proto_to_dascript.py` preserves the input `.proto` byte for byte; the IR projection cannot restore that text.
- The bundled gRPC adapter is a client transport, not a gRPC server or persistent streaming connection.
- `PBRef<T>` serializes a tree; shared object identity and cycles are not preserved.
- Proto2 defaults appear in the schema, while native optional fields retain presence. Read an effective default with `or_value(field, declared_default)`.
- Some daScript identifier collisions may require manual renaming.

See the official [Protobuf encoding guide](https://protobuf.dev/programming-guides/encoding/) and [Editions feature guide](https://protobuf.dev/editions/features/).

## License

MIT. See [LICENSE](LICENSE).
