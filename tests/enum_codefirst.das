options gen2
require ../src/annotations.das
[pb_enum]
enum Color:int { UNKNOWN=0
RED=1
BLUE=2 }
[pb_message(package="example")]
struct Thing { @pb_id=1
color:Color
@pb_id=2
colors:array<Color>
}
[export]
def main {
    var thing=Thing(color=Color.RED)
    thing.colors <- [Color.BLUE]
    let result <- pb_unpack_Thing(pb_pack_Thing(thing))
    assert(result.color==Color.RED && result.colors[0]==Color.BLUE)
    print(pb_schema_Thing())
}
