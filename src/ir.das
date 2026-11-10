options gen2
module ir public
require strings

struct PBField { name:string; number:int; kind:int; repeated:bool; optional:bool; required:bool; implicit_presence:bool; boxed:bool; map:bool; map_key_kind:int; map_value_kind:int; type_name:string; extendee:string; package_name:string; oneof_name:string; oneof_index:int; proto3_optional:bool; feature_presence:int; feature_utf8:int; feature_message_encoding:int; packed:int; utf8_none:bool; delimited:bool; default_value:string; raw_options:string; options_bytes:array<uint8> }
struct PBNumberRange { first:int; last:int }
struct PBMessage { name:string; parent_name:string; package_name:string; syntax:string; edition:string; schema_header:string; raw_options:string; imported:bool; options_bytes:array<uint8>; fields:array<PBField>; extensions:array<PBField>; extension_ranges:array<PBNumberRange>; reserved_ranges:array<PBNumberRange>; reserved_names:array<string> }
struct PBEnumValue { name:string; number:int }
struct PBEnum { name:string; parent_name:string; package_name:string; allow_alias:bool; closed:bool; imported:bool; options_bytes:array<uint8>; values:array<PBEnumValue>; reserved_ranges:array<PBNumberRange>; reserved_names:array<string> }
struct PBMethod { name:string; request:string; response:string; client_streaming:bool; server_streaming:bool }
struct PBService { name:string; package_name:string; imported:bool; methods:array<PBMethod> }
struct PBSchema { messages:array<PBMessage>; enums:array<PBEnum>; services:array<PBService>; extensions:array<PBField>; imports:array<string>; root_package:string; schema_header:string; file_options_bytes:array<uint8>; syntax:string="proto3"; edition:string }
def pb_kind_name(kind:int):string{
    if(kind==1){return "double"}
    if(kind==2){return "float"}
    if(kind==3){return "int64"}
    if(kind==4){return "uint64"}
    if(kind==5){return "int32"}
    if(kind==6){return "fixed64"}
    if(kind==7){return "fixed32"}
    if(kind==8){return "bool"}
    if(kind==9){return "string"}
    if(kind==20){return "string"}
    if(kind==11){return "message"}
    if(kind==12){return "bytes"}
    if(kind==13){return "uint32"}
    if(kind==14){return "enum"}
    if(kind==15){return "sfixed32"}
    if(kind==16){return "sfixed64"}
    if(kind==17){return "sint32"}
    if(kind==18){return "sint64"}
    panic("unsupported Protobuf field kind")
    return ""
}
def pb_schema_extension(field:PBField; syntax,indent:string):string{
    let prefix=field.repeated ? "repeated " : (field.required ? "required " : "optional ")
    let typ=field.kind==11 || field.kind==14 ? field.type_name : pb_kind_name(field.kind)
    var option_text=""
    if(!empty(field.default_value)){
        let value=field.kind==9 || field.kind==20 ? "\"{field.default_value}\"" : field.default_value
        option_text=" [default = {value}]"
    }
    if(field.packed!=0){
        let enabled=field.packed==1 ? "true" : "false"
        option_text=" [packed = {enabled}]"
    }
    return "{indent}{prefix}{typ} {field.name} = {field.number}{option_text};\n"
}
def pb_schema_message(schema:PBSchema; message:PBMessage; indent:string; header:string=""):string{
    let heading=empty(header) ? "message {message.name}" : header
    var output="{indent}{heading} \{\n"
    if(!empty(message.raw_options)){output+="{indent}  {message.raw_options}\n"}
    var emitted_oneofs:table<string;bool>
    for(field in message.fields){
        if(field.kind==10 && !field.delimited){
            var found=false
            for(child in schema.messages){
                let child_name=empty(child.parent_name) ? child.name : ".{child.parent_name}.{child.name}"
                let full_name=empty(child.package_name) ? child_name : ".{child.package_name}{child_name}"
                if(full_name==field.type_name){
                    let group_prefix=field.repeated ? "repeated" : (field.required ? "required" : "optional")
                    output+=pb_schema_message(schema,child,"{indent}  ","{group_prefix} group {child.name} = {field.number}")
                    found=true
                }
            }
            if(!found){panic("unresolved group type")}
            continue
        }
        if(!empty(field.oneof_name)){
            if(key_exists(emitted_oneofs,field.oneof_name)){continue}
            emitted_oneofs[field.oneof_name]=true
            output+="{indent}  oneof {field.oneof_name} \{\n"
            for(member in message.fields){
                if(member.oneof_name!=field.oneof_name){continue}
                let member_type=member.kind==11 || member.kind==14 ? member.type_name : pb_kind_name(member.kind)
                output+="{indent}    {member_type} {member.name} = {member.number};\n"
            }
            output+="{indent}  }\n"
            continue
        }
        let prefix=field.repeated && !field.map ? "repeated " : (schema.syntax=="editions" ? "" : (field.required ? "required " : (field.optional && !field.map && (schema.syntax=="proto2" || field.kind!=11) ? "optional " : "")))
        var typ=field.kind==11 || field.kind==10 || field.kind==14 ? field.type_name : (field.map ? "" : pb_kind_name(field.kind))
        if(field.map){
            let value_type=field.map_value_kind==11 || field.map_value_kind==14 ? field.type_name : pb_kind_name(field.map_value_kind)
            typ="map<{pb_kind_name(field.map_key_kind)}, {value_type}>"
        }
        var default_attr=""
        if(schema.syntax=="proto2" && !empty(field.default_value)){
            let value=field.kind==9 || field.kind==20 ? "\"{field.default_value}\"" : field.default_value
            default_attr=" [default = {value}]"
        }
        if(field.repeated && field.packed!=0 && field.kind!=9 && field.kind!=11 && field.kind!=12){
            let option=field.packed==1 ? "PACKED" : "EXPANDED"
            if(schema.syntax=="editions"){default_attr=" [features.repeated_field_encoding = {option}]"}
            else{let enabled=field.packed==1 ? "true" : "false";default_attr=" [packed = {enabled}]"}
        }
        var features=""
        if(schema.syntax=="editions" && field.implicit_presence){features=" [features.field_presence = IMPLICIT]"}
        elif(schema.syntax=="editions" && field.required){features=" [features.field_presence = LEGACY_REQUIRED]"}
        if(schema.syntax=="editions" && field.utf8_none){
            if(!empty(features)){features=replace(features,"]",", features.utf8_validation = NONE]")}
            else{features=" [features.utf8_validation = NONE]"}
        }
        if(schema.syntax=="editions" && field.delimited){
            if(!empty(features)){features=replace(features,"]",", features.message_encoding = DELIMITED]")}
            else{features=" [features.message_encoding = DELIMITED]"}
        }
        if(!empty(field.raw_options)){
            if(!empty(features)){features=replace(features,"]",", {field.raw_options}]")}
            elif(!empty(default_attr)){default_attr=replace(default_attr,"]",", {field.raw_options}]")}
            else{default_attr=" [{field.raw_options}]"}
        }
        output+="{indent}  {prefix}{typ} {field.name} = {field.number}{default_attr}{features};\n"
    }
    let full_name=empty(message.parent_name) ? message.name : "{message.parent_name}.{message.name}"
    for(enu in schema.enums){
        if(enu.imported || enu.parent_name!=full_name || enu.package_name!=message.package_name){continue}
        output+="{indent}  enum {enu.name} \{\n"
        if(enu.allow_alias){output+="{indent}    option allow_alias = true;\n"}
        if(schema.syntax=="editions" && enu.closed){output+="{indent}    option features.enum_type = CLOSED;\n"}
        for(value in enu.values){output+="{indent}    {value.name} = {value.number};\n"}
        for(span in enu.reserved_ranges){let last=span.first==span.last ? "" : " to {span.last}";output+="{indent}    reserved {span.first}{last};\n"}
        for(name in enu.reserved_names){output+="{indent}    reserved \"{name}\";\n"}
        output+="{indent}  }\n"
    }
    for(span in message.extension_ranges){let last=span.first==span.last-1 ? "" : " to {span.last-1}";output+="{indent}  extensions {span.first}{last};\n"}
    for(span in message.reserved_ranges){let last=span.first==span.last-1 ? "" : " to {span.last-1}";output+="{indent}  reserved {span.first}{last};\n"}
    for(name in message.reserved_names){output+="{indent}  reserved \"{name}\";\n"}
    for(extension in message.extensions){
        output+="{indent}  extend {extension.extendee} \{\n"
        output+=pb_schema_extension(extension,schema.syntax,"{indent}    ")
        output+="{indent}  }\n"
    }
    for(child in schema.messages){
        if(child.imported || child.parent_name!=full_name || child.package_name!=message.package_name){continue}
        var is_group=false
        for(field in message.fields){
            if(field.kind==10 && !field.delimited && slice(field.type_name,rfind(field.type_name,".")+1)==child.name){is_group=true}
        }
        if(!is_group){output+=pb_schema_message(schema,child,"{indent}  ")}
    }
    output+="{indent}}\n"
    return output
}
def pb_schema_text(schema:PBSchema):string{
    var output=schema.syntax=="editions" ? "edition = \"{schema.edition}\";\n" : "syntax = \"{schema.syntax}\";\n"
    for(path in schema.imports){output+="import \"{path}\";\n"}
    if(!empty(schema.root_package)){output+="package {schema.root_package};\n"}
    if(!empty(schema.schema_header)){output+="{schema.schema_header}\n"}
    var current_package=schema.root_package
    for(enu in schema.enums){
        if(enu.imported || !empty(enu.parent_name) || enu.package_name!=schema.root_package){continue}
        if(!empty(enu.package_name) && enu.package_name!=current_package){
            if(!empty(current_package)){panic("multiple packages require separate .proto files")}
            output+="package {enu.package_name};\n"
            current_package=enu.package_name
        }
        output+="enum {enu.name} \{\n"
        if(enu.allow_alias){output+="  option allow_alias = true;\n"}
        if(schema.syntax=="editions" && enu.closed){output+="  option features.enum_type = CLOSED;\n"}
        for(value in enu.values){output+="  {value.name} = {value.number};\n"}
        for(span in enu.reserved_ranges){let last=span.first==span.last ? "" : " to {span.last}";output+="  reserved {span.first}{last};\n"}
        for(name in enu.reserved_names){output+="  reserved \"{name}\";\n"}
        output+="}\n"
    }
    for(message in schema.messages){
        if(message.imported || !empty(message.parent_name) || message.package_name!=schema.root_package){continue}
        if(!empty(message.package_name) && message.package_name!=current_package){
            if(!empty(current_package)){panic("multiple packages require separate .proto files")}
            output+="package {message.package_name};\n"
            current_package=message.package_name
        }
        output+=pb_schema_message(schema,message,"")
    }
    for(service in schema.services){
        if(service.imported || service.package_name!=schema.root_package){continue}
        output+="service {service.name} \{\n"
        for(method in service.methods){
            let request=method.client_streaming ? "stream {method.request}" : method.request
            let response=method.server_streaming ? "stream {method.response}" : method.response
            output+="  rpc {method.name}({request}) returns ({response});\n"
        }
        output+="}\n"
    }
    for(extension in schema.extensions){
        if(extension.package_name!=schema.root_package){continue}
        output+="extend {extension.extendee} \{\n"
        output+=pb_schema_extension(extension,schema.syntax,"  ")
        output+="}\n"
    }
    return output
}
