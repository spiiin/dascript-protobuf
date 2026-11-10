options gen2
require ../src/annotations.das

[pb_enum(package="example",closed=true)]
enum State:int { STATE_UNSPECIFIED=0
STATE_READY=1 }

[pb_message(package="example",syntax="editions",edition="2023")]
struct ClosedEnums {
    @pb_id=1
    single:Option<State>
    @pb_id=2
    many:array<State>
    @pb_id=3
    states:table<int;State>
    @pb_unknown
    pb_unknown_fields:array<uint8>
}

[export]
def main {
    print(pb_schema_ClosedEnums())
    let bytes <- [8u8,9u8,18u8,3u8,1u8,9u8,1u8,26u8,4u8,8u8,1u8,16u8,9u8]
    let parsed <- pb_unpack_ClosedEnums(bytes)
    assert(parsed.single is none && length(parsed.many)==2)
    assert(length(parsed.pb_unknown_fields)==10 && length(parsed.states)==0)
    let roundtrip <- pb_pack_ClosedEnums(parsed)
    let again <- pb_unpack_ClosedEnums(roundtrip)
    assert(again.single is none && length(again.many)==2 && length(again.pb_unknown_fields)==10)
}
