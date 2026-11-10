"""Binary gRPC transport for the generated daScript RPC wrappers.

The request and response files contain consecutive little-endian uint32 lengths
followed by opaque Protobuf messages. No generated Python stubs are required.
"""
import argparse
from pathlib import Path
import struct
import sys

import grpc


def read_frames(path):
    data = Path(path).read_bytes()
    frames = []
    offset = 0
    while offset < len(data):
        if len(data) - offset < 4:
            raise ValueError("truncated frame length")
        size = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        if size > len(data) - offset:
            raise ValueError("truncated frame body")
        frames.append(data[offset:offset + size])
        offset += size
    return frames


def write_frames(path, frames):
    with Path(path).open("wb") as output:
        for frame in frames:
            output.write(struct.pack("<I", len(frame)))
            output.write(frame)


def call(channel, shape, method, requests, timeout, metadata):
    options = dict(request_serializer=lambda data: data,
                   response_deserializer=lambda data: data)
    if shape == "unary":
        if len(requests) != 1:
            raise ValueError("unary RPC requires one request")
        return [channel.unary_unary(method, **options)(requests[0], timeout=timeout, metadata=metadata)]
    if shape == "client_stream":
        return [channel.stream_unary(method, **options)(iter(requests), timeout=timeout, metadata=metadata)]
    if shape == "server_stream":
        if len(requests) != 1:
            raise ValueError("server-streaming RPC requires one request")
        return list(channel.unary_stream(method, **options)(requests[0], timeout=timeout, metadata=metadata))
    if shape == "bidi":
        return list(channel.stream_stream(method, **options)(iter(requests), timeout=timeout, metadata=metadata))
    raise ValueError(f"unknown RPC shape: {shape}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True)
    parser.add_argument("--method", required=True)
    parser.add_argument("--shape", choices=("unary", "client_stream", "server_stream", "bidi"), required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--tls", action="store_true")
    parser.add_argument("--root-cert", type=Path)
    parser.add_argument("--server-name")
    parser.add_argument("--metadata", action="append", default=[], metavar="KEY=VALUE")
    args = parser.parse_args()
    if not args.method.startswith("/") or args.method.count("/") != 2:
        parser.error("method must be /package.Service/Method")
    metadata = []
    for item in args.metadata:
        key, sep, value = item.partition("=")
        if not sep or not key:
            parser.error("metadata must be KEY=VALUE")
        metadata.append((key, value))
    if args.root_cert and not args.tls:
        parser.error("--root-cert requires --tls")
    if args.server_name and not args.tls:
        parser.error("--server-name requires --tls")
    if args.tls:
        credentials = grpc.ssl_channel_credentials(
            root_certificates=args.root_cert.read_bytes() if args.root_cert else None)
        options = [("grpc.ssl_target_name_override", args.server_name)] if args.server_name else None
        channel = grpc.secure_channel(args.target, credentials, options=options)
    else:
        channel = grpc.insecure_channel(args.target)
    with channel:
        responses = call(channel, args.shape, args.method, read_frames(args.input),
                         args.timeout, metadata)
    write_frames(args.output, responses)


if __name__ == "__main__":
    try:
        main()
    except (grpc.RpcError, OSError, ValueError) as error:
        print(f"gRPC transport: {error}", file=sys.stderr)
        sys.exit(1)
