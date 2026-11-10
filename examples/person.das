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
}

[export]
def main {
    var person=Person(name="Ada")
    person.age <- some(0)
    person.scores <- [1,2,3]
    let data <- pb_pack_Person(person)
    verify(pb_verify_Person(data))
    let decoded <- pb_unpack_Person(data)
    assert(decoded.age is some && length(decoded.scores)==3)
    verify(fwrite("generated/person.proto",pb_schema_Person()))
}
