"""Convert Protobuf binary and JSON using the official runtime and a descriptor set."""
import argparse
from pathlib import Path
from google.protobuf import descriptor_pb2, descriptor_pool, json_format, message_factory

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--descriptor',type=Path,required=True)
    parser.add_argument('--type',required=True,help='Fully qualified message name')
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--direction',choices=['to-json','from-json'],required=True)
    args=parser.parse_args()
    descriptor=descriptor_pb2.FileDescriptorSet.FromString(args.descriptor.read_bytes())
    pool=descriptor_pool.DescriptorPool()
    pending=list(descriptor.file)
    while pending:
        remaining=[]
        for file in pending:
            try: pool.Add(file)
            except Exception: remaining.append(file)
        if len(remaining)==len(pending):
            raise SystemExit('Descriptor set has unresolved imports; use protoc --include_imports')
        pending=remaining
    cls=message_factory.GetMessageClass(pool.FindMessageTypeByName(args.type.lstrip('.')))
    if args.direction=='to-json':
        message=cls.FromString(args.input.read_bytes())
        args.output.write_text(json_format.MessageToJson(message),encoding='utf-8')
    else:
        message=json_format.Parse(args.input.read_text(encoding='utf-8'),cls())
        args.output.write_bytes(message.SerializeToString())

if __name__=='__main__':main()
