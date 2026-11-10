options gen2
require ../src/annotations.das
[pb_message(package="example")]
struct Child { @pb_id=1
value:int }
[pb_message(package="example")]
struct Registry { @pb_id=1
items:table<string;Child> }
[export]
def main {
    var value=Registry()
    value.items["a"] <- Child(value=9)
    var decoded <- pb_unpack_Registry(pb_pack_Registry(value))
    verify(decoded.items["a"].value==9)
    print(pb_schema_Registry())
}
