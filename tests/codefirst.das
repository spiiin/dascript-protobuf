options gen2
require ../src/annotations.das
require daslib/fio
[pb_message(package="example")]
struct Person {
    @pb_id=1
    name:string
    @pb_id=2
    age:Option<int>
    @pb_id=3
    scores:array<int>
    @pb_unknown
    unknown_fields:array<uint8>
}
[export]
def main {
    let args <- get_command_line_arguments()
    let folder=args[length(args)-1]
    var person=Person(name="Ada")
    person.age <- some(0)
    person.scores <- [1,2,3]
    pb_save(folder+"/codefirst.bin",pb_pack_Person(person))
    let foreign_bytes <- pb_load(folder+"/foreign.bin")
    verify(pb_verify_Person(foreign_bytes))
    verify(!pb_verify_Person([10u8,5u8,65u8]))
    verify(!pb_verify_Person([10u8,1u8,255u8]))
    let foreign <- pb_unpack_Person(foreign_bytes)
    assert(foreign.name=="Bob" && foreign.age is some && (foreign.age as some)==0)
    assert(length(foreign.scores)==3 && foreign.scores[2]==6)
    assert(length(foreign.unknown_fields)==9)
    verify(!pb_verify_Person([163u8,6u8,8u8,1u8,172u8,6u8]))
    pb_save(folder+"/codefirst_foreign_repacked.bin",pb_pack_Person(foreign))
    verify(fwrite(folder+"/codefirst.proto",pb_schema_Person()))
}
