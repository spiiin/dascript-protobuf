options gen2
require ../src/annotations.das
[pb_message(package="example")]
struct Counts { @pb_id=1
    by_name:table<string;int>
}
[export]
def main {
    var value=Counts()
    value.by_name["a"]=7
    var decoded <- pb_unpack_Counts(pb_pack_Counts(value))
    verify(decoded.by_name["a"]==7)
    print(pb_schema_Counts())
}
