"""One command for protoc descriptor emission and the daScript source generator."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
from grpc_tools import protoc
from google.protobuf import descriptor_pb2

PROJECT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('schema',type=Path)
    parser.add_argument('--out',type=Path,default=PROJECT/'generated')
    parser.add_argument('--daslang',default='daslang')
    parser.add_argument('--protoc',type=Path,help='External protoc binary (required for editions newer than the bundled compiler)')
    parser.add_argument('-I','--proto-path',action='append',type=Path,default=[],help='Additional protoc import directory')
    args=parser.parse_args()
    schema=args.schema.resolve()
    if not schema.is_file():raise SystemExit(f'No schema: {schema}')
    out=args.out.resolve()
    if out.parent!=PROJECT:
        raise SystemExit('Output directory must be a direct child of the project for relative imports')
    out.mkdir(exist_ok=True)
    source_copy=out/(schema.stem+'_source.proto')
    if source_copy!=schema:
        shutil.copyfile(schema,source_copy)
    descriptor=out/(schema.stem+'.desc')
    compiler=args.protoc.resolve() if args.protoc else None
    bundled_include=compiler.parent.parent/'include' if compiler else Path(protoc.__file__).resolve().parent/'_proto'
    import_roots=[schema.parent,bundled_include]
    import_roots += [path.resolve() for path in args.proto_path]
    includes=[f'-I{path}' for path in import_roots]
    compiler_args=[*includes,'--include_imports',f'--descriptor_set_out={descriptor}',str(schema)]
    if compiler:
        subprocess.run([str(compiler),*compiler_args],check=True)
    elif protoc.main(['protoc',*compiler_args]):
        raise SystemExit('protoc failed')
    descriptor_set=descriptor_pb2.FileDescriptorSet.FromString(descriptor.read_bytes())
    for file in descriptor_set.file[:-1]:
        relative=Path(file.name)
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit(f'Unsafe import path: {file.name}')
        candidates=[root/relative for root in import_roots]
        source=next((path for path in candidates if path.is_file()),None)
        if source is None:
            raise SystemExit(f'Import source unavailable: {file.name}')
        dest=out/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists() and dest.read_bytes()!=source.read_bytes():
            raise SystemExit(f'Import destination differs: {dest}')
        if not dest.exists():
            shutil.copyfile(source,dest)
    normalized=out/(schema.stem+'_normalized.proto')
    subprocess.run([args.daslang,'-no-module-cache','-no-dynamic-modules',
                    str(PROJECT/'tools/generate.das'),'--',str(descriptor),
                    str(out/(schema.stem+'_generated.das')),
                    str(normalized)],cwd=PROJECT,check=True)
    (out/(schema.stem+'_ir.proto')).write_bytes(normalized.read_bytes())
    normalized.write_bytes(schema.read_bytes())
    print(out/(schema.stem+'_generated.das'))

if __name__=='__main__':main()
