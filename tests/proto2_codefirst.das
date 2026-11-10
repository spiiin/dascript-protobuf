options gen2
require ../src/annotations.das
[pb_message(package="example",syntax="proto2")]
struct Sample { @pb_id=1
    @pb_required
    id:int
    @pb_id=2
    name:Option<string>
}
[export]
def main {
    let bytes <- pb_pack_Sample(Sample(id=0))
    verify(pb_verify_Sample(bytes))
    verify(!pb_verify_Sample([]))
    verify(pb_verify_Sample([8u8,0u8,18u8,1u8,255u8]))
    print(pb_schema_Sample())
}
