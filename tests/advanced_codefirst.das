options gen2
require ../src/annotations.das
require daslib/fio
[pb_message(package="example")]
struct Child { @pb_id=1
    value:int
}
[pb_message(package="example")]
struct Advanced {
    @pb_id=1
    @pb_sint32
    delta:int
    @pb_id=2
    @pb_sfixed64
    clock:int64
    @pb_id=3
    mask:uint64
    @pb_id=4
    ratio:float
    @pb_id=5
    precise:double
    @pb_id=6
    data:array<uint8>
    @pb_id=7
    labels:array<string>
    @pb_id=8
    child:Option<Child>
    @pb_id=9
    children:array<Child>
}
[export]
def main {
    let args <- get_command_line_arguments()
    let folder=args[length(args)-1]
    var item=Advanced(delta=-7,clock=-9l,mask=18446744073709551615ul,ratio=1.5,precise=2.25lf)
    item.data <- [1u8,0u8,255u8]
    item.labels <- ["x","こんにちは"]
    item.child <- some(Child(value=42))
    item.children <- [Child(value=3),Child(value=4)]
    let encoded <- pb_pack_Advanced(item)
    verify(pb_verify_Advanced(encoded))
    pb_save(folder+"/advanced_codefirst.bin",encoded)
    let decoded <- pb_unpack_Advanced(pb_load(folder+"/advanced_foreign.bin"))
    assert(decoded.delta==-7 && decoded.clock==-9l && decoded.mask==18446744073709551615ul)
    assert((decoded.child as some).value==42 && decoded.children[1].value==4)
    verify(fwrite(folder+"/advanced_codefirst.proto",pb_schema_Advanced()))
}
