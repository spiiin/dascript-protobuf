"""Edition 2026 compatibility using an external protoc >=36."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--protoc',type=Path,required=True)
parser.add_argument('--daslang',type=Path,required=True)
parser.add_argument('--grpc-tools-root',type=Path,required=True)
args=parser.parse_args()
env=os.environ.copy()
env['PYTHONPATH']=str(args.grpc_tools_root.resolve())+os.pathsep+env.get('PYTHONPATH','')

def run(*command):
    result=subprocess.run([str(item) for item in command],cwd=ROOT,env=env,
                          capture_output=True,text=True,timeout=90)
    if result.returncode: raise AssertionError(result.stdout+result.stderr)

with tempfile.TemporaryDirectory(prefix='test-edition2026-',dir=ROOT) as directory:
    out=Path(directory)
    run(sys.executable,ROOT/'tools/proto_to_dascript.py',ROOT/'tests/edition2026.proto',
        '--out',out,'--daslang',args.daslang,'--protoc',args.protoc)
    run(args.protoc,f'-I{out}',f'--descriptor_set_out={out / "normalized.desc"}',
        out/'edition2026_normalized.proto')
    (out/'edition2026_client.das').write_text(
        (ROOT/'tests/edition2026_client.template').read_text(encoding='utf-8'),encoding='utf-8')
    run(args.daslang,'-no-module-cache','-no-dynamic-modules',out/'edition2026_client.das')
print('Edition 2026: official protoc compatibility OK')
