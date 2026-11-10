options gen2
require ../src/annotations.das
[pb_message(package="example",syntax="proto2",name="Detail",parent="GroupHolder")]
struct GroupDetail {
    @pb_id=2
    @pb_required
    a:int
}
[pb_message(package="example",syntax="proto2")]
struct GroupHolder {
    @pb_id=1
    @pb_group
    detail:Option<GroupDetail>
}
[export]
def main {
    var item=GroupHolder()
    item.detail <- some(GroupDetail(a=7))
    let encoded <- pb_pack_GroupHolder(item)
    let decoded <- pb_unpack_GroupHolder(encoded)
    verify(decoded.detail is some && (decoded.detail as some).a==7)
    print(pb_schema_GroupHolder())
}
