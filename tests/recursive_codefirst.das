options gen2
require ../src/annotations.das
[pb_message(package="example")]
struct Node { @pb_id=1
    value:int
    @pb_id=2
    next:PBRef<Node>
}
[export]
def main {
    var node=Node(value=1)
    node.next <- pb_ref(Node(value=2))
    let restored <- pb_unpack_Node(pb_pack_Node(node))
    assert(restored.value==1 && restored.next.value[0].value==2)
    print(pb_schema_Node())
}
