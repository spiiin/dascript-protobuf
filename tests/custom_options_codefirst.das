options gen2
require ../src/annotations.das
[pb_message(package="example",schema_header="import \"custom_options.proto\"; option (example.file_code) = 7;",pb_options="option (example.message_code) = 8;")]
struct CustomOptions {
    @pb_id=1
    @pb_options="(example.field_code) = 9"
    value:int
}
[export]
def main {
    print(pb_schema_CustomOptions())
}
