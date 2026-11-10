"""Integration tests with protoc and the official Python Protobuf runtime."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--daslang',default='daslang')
parser.add_argument('--grpc-tools-root',type=Path,help='Isolated grpcio-tools install')
args=parser.parse_args()
if args.grpc_tools_root:
    sys.path.insert(0,str(args.grpc_tools_root.resolve()))
from grpc_tools import protoc
from google.protobuf import descriptor_pb2,descriptor_pool,message_factory

def run(*cmd):
    result=subprocess.run([str(c) for c in cmd],cwd=ROOT,capture_output=True,text=True,timeout=60)
    if result.returncode: raise AssertionError(result.stdout+result.stderr)
    return result.stdout
def compile_schema(source,output):
    value=protoc.main(['protoc',f'-I{source.parent}',f'-I{ROOT / "tests"}',
                       f'-I{Path(protoc.__file__).resolve().parent / "_proto"}',
                       '--include_imports',f'--descriptor_set_out={output}',str(source)])
    if value: raise AssertionError(f'protoc failed: {source}')

with tempfile.TemporaryDirectory(prefix='test-output-',dir=ROOT) as folder:
    out=Path(folder)
    fixture=ROOT/'tests/person.proto'
    desc=out/'person.desc'
    compile_schema(fixture,desc)
    schema=descriptor_pb2.FileDescriptorSet.FromString(desc.read_bytes())
    pool=descriptor_pool.DescriptorPool()
    for file in schema.file: pool.Add(file)
    cls=message_factory.GetMessageClass(pool.FindMessageTypeByName('example.Person'))
    # Unknown varint and group fields exercise forward-compatible round trips.
    unknown_tail=b'\x98\x06\x07\xa3\x06\x08\x01\xa4\x06'
    (out/'foreign.bin').write_bytes(cls(name='Bob',age=0,scores=[4,5,6]).SerializeToString()+unknown_tail)

    run(args.daslang,'-no-module-cache','-no-dynamic-modules',ROOT/'tests/codefirst.das','--',out)
    compile_schema(out/'codefirst.proto',out/'codefirst.desc')
    message=cls.FromString((out/'codefirst.bin').read_bytes())
    assert message.name=='Ada' and message.HasField('age') and message.age==0
    assert list(message.scores)==[1,2,3]
    assert (out/'codefirst.bin').read_bytes()==cls(name='Ada',age=0,scores=[1,2,3]).SerializeToString()
    assert (out/'codefirst_foreign_repacked.bin').read_bytes().endswith(unknown_tail)

    run(args.daslang,'-no-module-cache','-no-dynamic-modules',ROOT/'tools/generate.das','--',desc,out/'person_generated.das')
    consumer=out/'consumer.das'
    consumer.write_text('''options gen2
require ./person_generated.das
[export]
def main {
    var person=Person(name="Ada")
    person.age <- some(0)
    person.scores <- [1,2,3]
    pb_save("'''+out.as_posix()+'''/schemafirst.bin",pb_pack_Person(person))
    let foreign <- pb_unpack_Person(pb_load("'''+out.as_posix()+'''/foreign.bin"))
    assert(foreign.name=="Bob" && foreign.age is some && length(foreign.scores)==3)
    pb_save("'''+out.as_posix()+'''/schemafirst_foreign_repacked.bin",pb_pack_Person(foreign))
}
''')
    run(args.daslang,'-no-module-cache','-no-dynamic-modules',consumer)
    message=cls.FromString((out/'schemafirst.bin').read_bytes())
    assert message.name=='Ada' and message.HasField('age') and list(message.scores)==[1,2,3]
    assert (out/'schemafirst_foreign_repacked.bin').read_bytes().endswith(unknown_tail)

    run(sys.executable,ROOT/'tools/json_bridge.py','--descriptor',desc,
        '--type','example.Person','--input',out/'schemafirst.bin',
        '--output',out/'person.json','--direction','to-json')
    payload=json.loads((out/'person.json').read_text(encoding='utf-8'))
    assert payload=={'name':'Ada','age':0,'scores':[1,2,3]}
    run(sys.executable,ROOT/'tools/json_bridge.py','--descriptor',desc,
        '--type','example.Person','--input',out/'person.json',
        '--output',out/'person_from_json.bin','--direction','from-json')
    assert cls.FromString((out/'person_from_json.bin').read_bytes())==message

    for stem in ('enum','map','map_message','oneof','recursive','proto2','group','custom_options'):
        emitted=run(args.daslang,'-no-module-cache','-no-dynamic-modules',
                    ROOT/'tests'/f'{stem}_codefirst.das')
        codefirst_schema=out/f'{stem}_codefirst.proto'
        codefirst_schema.write_text(emitted,encoding='utf-8')
        compile_schema(codefirst_schema,out/f'{stem}_codefirst.desc')

    advanced=ROOT/'tests/advanced.proto'
    advanced_desc=out/'advanced.desc'
    compile_schema(advanced,advanced_desc)
    advanced_set=descriptor_pb2.FileDescriptorSet.FromString(advanced_desc.read_bytes())
    advanced_pool=descriptor_pool.DescriptorPool()
    for file in advanced_set.file: advanced_pool.Add(file)
    advanced_cls=message_factory.GetMessageClass(advanced_pool.FindMessageTypeByName('example.Advanced'))
    foreign=advanced_cls(delta=-7,clock=-9,mask=2**64-1,ratio=1.5,precise=2.25,data=b'\x01\x00\xff',labels=['x','こんにちは'])
    foreign.child.value=42
    foreign.children.add(value=3)
    foreign.children.add(value=4)
    (out/'advanced_foreign.bin').write_bytes(foreign.SerializeToString())
    run(args.daslang,'-no-module-cache','-no-dynamic-modules',ROOT/'tests/advanced_codefirst.das','--',out)
    compile_schema(out/'advanced_codefirst.proto',out/'advanced_codefirst.desc')
    native=advanced_cls.FromString((out/'advanced_codefirst.bin').read_bytes())
    assert native==foreign
    run(args.daslang,'-no-module-cache','-no-dynamic-modules',ROOT/'tools/generate.das','--',advanced_desc,out/'advanced_generated.das')
    advanced_consumer=out/'advanced_consumer.das'
    advanced_consumer.write_text('''options gen2
require ./advanced_generated.das
[export]
def main {
    var item=Advanced(delta=-7,clock=-9l,mask=18446744073709551615ul,ratio=1.5,precise=2.25lf)
    item.data <- [1u8,0u8,255u8]
    item.labels <- ["x","こんにちは"]
    item.child <- some(Child(value=42))
    item.children <- [Child(value=3),Child(value=4)]
    pb_save("'''+out.as_posix()+'''/advanced_schemafirst.bin",pb_pack_Advanced(item))
    let decoded <- pb_unpack_Advanced(pb_load("'''+out.as_posix()+'''/advanced_foreign.bin"))
    assert(decoded.delta==-7 && decoded.mask==18446744073709551615ul && decoded.children[1].value==4)
}
''',encoding='utf-8')
    run(args.daslang,'-no-module-cache','-no-dynamic-modules',advanced_consumer)
    assert advanced_cls.FromString((out/'advanced_schemafirst.bin').read_bytes())==foreign

    # Descriptor import, normalized schema and binary interoperability for the
    # additional proto3/proto2/Edition constructs.
    roots={
        'enum':'Thing','map':'Counts','map_message':'Registry','oneof':'Message',
        'recursive':'Node','service':'Request','proto2':'Sample',
        'proto2_enum':'Paint','edition':'Sample',
        'nested_decl':'Outer','nested_enum':'Outer','proto2_default':'Defaults',
        'map_enum':'Palette','merge_message':'MergeHolder',
        'oneof_message':'ChoiceHolder','packed_options':'PackedOptions',
        'proto2_packed':'Proto2Packed','edition_expanded':'EditionExpanded',
        'enum_alias':'AliasPaint','service_nested':'Envelope','group':'GroupHolder',
        'import_main':'Imported','extensions':'Extendable',
        'service_stream':'StreamRequest','edition_file_expanded':'EditionFileExpanded',
        'edition_utf8_none':'Utf8Loose','custom_options_user':'CustomUser',
        'edition_delimited':'DelimitedHolder',
    }
    for stem,root_name in roots.items():
        source=ROOT/'tests'/f'{stem}.proto'
        descriptor=out/f'{stem}.desc'
        compile_schema(source,descriptor)
        descriptor_set=descriptor_pb2.FileDescriptorSet.FromString(descriptor.read_bytes())
        local_pool=descriptor_pool.DescriptorPool()
        for file in descriptor_set.file: local_pool.Add(file)
        package=descriptor_set.file[-1].package
        cls=message_factory.GetMessageClass(local_pool.FindMessageTypeByName((package+'.' if package else '')+root_name))
        item=cls()
        if stem=='enum': item.color=2;item.colors.extend([1,2])
        elif stem=='map': item.by_name['a']=7;item.by_name['b']=0
        elif stem=='map_message': item.items['a'].value=9
        elif stem=='oneof': item.text='hello'
        elif stem=='recursive': item.value=1;item.next.value=2
        elif stem=='service': item.value=4
        elif stem=='proto2': item.id=0;item.name='x'
        elif stem=='proto2_enum': item.color=2
        elif stem=='edition': item.explicit_value=0;item.implicit_value=0
        elif stem=='nested_decl': item.child.value=7
        elif stem=='nested_enum': item.color=1
        elif stem=='proto2_default': item.count=0;item.label='set'
        elif stem=='map_enum': item.colors['front']=2
        elif stem in ('merge_message','oneof_message'):
            item.child.a=1
            item.child.b=2
        elif stem in ('packed_options','proto2_packed'):
            item.unpacked.extend([1,2])
            item.packed.extend([3,4])
        elif stem in ('edition_expanded','edition_file_expanded'): item.values.extend([1,2])
        elif stem=='enum_alias': item.color=1
        elif stem=='group': item.detail.a=7;item.detail.b='g';item.item.add(value=3)
        elif stem=='import_main': item.child.code=7;item.kind=1;item.items.add(code=8)
        elif stem=='extensions':
            item.id=3
            item.Extensions[local_pool.FindExtensionByName('example.note')]='hello'
            item.Extensions[local_pool.FindExtensionByName('example.tags')].extend([1,2])
        elif stem=='service_stream': item.value=9
        elif stem=='edition_utf8_none': item.value='ok'
        elif stem=='custom_options_user': item.value=5
        elif stem=='edition_delimited': item.child.value=6
        input_path=out/f'{stem}_foreign.bin'
        if stem in ('merge_message','oneof_message'):
            first=cls();first.child.a=1
            second=cls();second.child.b=2
            input_path.write_bytes(first.SerializeToString()+second.SerializeToString())
        else:
            input_path.write_bytes(item.SerializeToString())
        generated=out/f'{stem}_generated.das'
        normalized=out/f'{stem}_normalized.proto'
        run(args.daslang,'-no-module-cache','-no-dynamic-modules',ROOT/'tools/generate.das',
            '--',descriptor,generated,normalized)
        compile_schema(normalized,out/f'{stem}_normalized.desc')
        consumer=out/f'{stem}_consumer.das'
        consumer.write_text(f'''options gen2
require ./{stem}_generated.das
[export]
def main {{
    let foreign <- pb_load("{input_path.as_posix()}")
    verify(pb_verify_{root_name}(foreign))
    let value <- pb_unpack_{root_name}(foreign)
    pb_save("{(out/f'{stem}_repacked.bin').as_posix()}",pb_pack_{root_name}(value))
}}
''',encoding='utf-8')
        run(args.daslang,'-no-module-cache','-no-dynamic-modules',consumer)
        if stem=='service_stream':
            stream_client=out/'stream_client.das'
            stream_client.write_text((ROOT/'tests/stream_client.template').read_text(encoding='utf-8'),encoding='utf-8')
            run(args.daslang,'-no-module-cache','-no-dynamic-modules',stream_client)
        if stem=='custom_options_user':
            custom_client=out/'custom_options_client.das'
            custom_client.write_text((ROOT/'tests/custom_options_client.template').read_text(encoding='utf-8'),encoding='utf-8')
            run(args.daslang,'-no-module-cache','-no-dynamic-modules',custom_client)
        if stem=='edition_utf8_none':
            utf8_client=out/'utf8_client.das'
            utf8_client.write_text('''options gen2
require ./edition_utf8_none_generated.das
[export]
def main {
    let raw <- [10u8,1u8,255u8]
    verify(pb_verify_Utf8Loose(raw))
    let decoded <- pb_unpack_Utf8Loose(raw)
    let repacked <- pb_pack_Utf8Loose(decoded)
    verify(length(repacked)==length(raw))
    for(i in range(length(raw))){verify(repacked[i]==raw[i])}
}
''',encoding='utf-8')
            run(args.daslang,'-no-module-cache','-no-dynamic-modules',utf8_client)
        if stem=='extensions':
            extension_client=out/'extension_client.das'
            extension_client.write_text(f'''options gen2
require ./extensions_generated.das
[export]
def main {{
    let value <- pb_unpack_Extendable(pb_load("{input_path.as_posix()}"))
    let fields <- pb_scan_fields(value.pb_unknown_fields)
    verify(length(fields)==2 && fields[0].number==100 && fields[1].number==101)
    let note <- pb_ext_get_note(value)
    let tags <- pb_ext_get_tags(value)
    verify(note is some && (note as some)=="hello")
    verify(length(tags)==2 && tags[0]==1 && tags[1]==2)
    var created=Extendable()
    pb_ext_set_note(created,"new")
    pb_ext_set_tags(created,[3,4])
    let created_note <- pb_ext_get_note(created)
    let created_tags <- pb_ext_get_tags(created)
    verify(created_note is some && (created_note as some)=="new")
    verify(length(created_tags)==2 && created_tags[0]==3 && created_tags[1]==4)
}}
''',encoding='utf-8')
            run(args.daslang,'-no-module-cache','-no-dynamic-modules',extension_client)
        assert cls.FromString((out/f'{stem}_repacked.bin').read_bytes())==item,stem
        if stem in ('packed_options','proto2_packed','edition_expanded','edition_file_expanded','edition_delimited'):
            assert (out/f'{stem}_repacked.bin').read_bytes()==item.SerializeToString(),stem
    env=os.environ.copy()
    if args.grpc_tools_root:
        env['PYTHONPATH']=str(args.grpc_tools_root.resolve())+os.pathsep+env.get('PYTHONPATH','')
    wrapper=subprocess.run([sys.executable,str(ROOT/'tools/proto_to_dascript.py'),
                            str(ROOT/'tests/custom_options_user.proto'),'--out',str(out),
                            '--daslang',args.daslang],cwd=ROOT,env=env,capture_output=True,text=True,timeout=60)
    if wrapper.returncode: raise AssertionError(wrapper.stdout+wrapper.stderr)
    assert (out/'custom_options_user_source.proto').read_bytes()==(ROOT/'tests/custom_options_user.proto').read_bytes()
    assert (out/'custom_options_user_normalized.proto').read_bytes()==(ROOT/'tests/custom_options_user.proto').read_bytes()
    assert (out/'custom_options_user_ir.proto').is_file()
    assert (out/'custom_options.proto').is_file()
    assert (out/'google/protobuf/descriptor.proto').is_file()
    assert not protoc.main(['protoc',f'-I{out}',
                            f'--descriptor_set_out={out / "self_contained.desc"}',
                            str(out/'custom_options_user_normalized.proto')])

    print(f'{len(roots)+2} schemas and 8 extra code-first fixtures: protoc/Python compatibility, JSON, and normalized schema OK')
