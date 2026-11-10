options gen2
require ../src/annotations.das
typedef Choice=variant<none; count:int; text:string>
[pb_message(package="example")]
struct Message { @pb_oneof_numbers="0,1,2"
    choice:Choice
}
[export]
def main {
    var value=Message()
    value.choice <- Choice(text="hello")
    let decoded <- pb_unpack_Message(pb_pack_Message(value))
    assert(decoded.choice is text && (decoded.choice as text)=="hello")
    print(pb_schema_Message())
}
