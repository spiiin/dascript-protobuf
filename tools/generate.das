options gen2
require ../src/descriptor.das
require daslib/fio
require strings
[export]
def main {
    let all <- get_command_line_arguments()
    var args:array<string>
    var passing=false
    for(item in all){if(passing){push(args,item)};if(item=="--"){passing=true}}
    if(length(args)<2 || length(args)>3){panic("usage: generate.das -- descriptor.pb output.das [normalized.proto]")}
    let input=args[0]
    let output=args[1]
    let schema <- pb_import_descriptor_set(pb_load(input))
    let file=replace(output,"\\","/")
    let basename=slice(file,rfind(file,"/")+1)
    let module_name=slice(basename,0,rfind(basename,"."))
    verify(fwrite(output,pb_emit_native(schema,module_name,"../src/annotations.das")))
    if(length(args)==3){verify(fwrite(args[2],pb_schema_text(schema)))}
}
