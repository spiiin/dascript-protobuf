options gen2
module descriptor public
require strings
require ./ir.das public
require ./runtime.das public

// Reader for the subset of google.protobuf.FileDescriptorSet used by proto3.
def pb_feature_value(option_bytes:array<uint8>; features_id,feature_id:int):int{
    var position=0
    var result=0
    while(position<length(option_bytes)){
        let key=pb_get_varint(option_bytes,position)
        if(int(key>>3u)==features_id && (key&7ul)==2ul){
            let feature_bytes <- pb_get_bytes(option_bytes,position)
            var at=0
            while(at<length(feature_bytes)){
                let feature_key=pb_get_varint(feature_bytes,at)
                if(feature_key==uint64(feature_id*8)){result=int(pb_get_varint(feature_bytes,at))}
                else{pb_skip(feature_bytes,at,int(feature_key&7ul))}
            }
        }else{pb_skip(option_bytes,position,int(key&7ul))}
    }
    return result
}
def pb_feature_presence(option_bytes:array<uint8>; features_id:int):int=>pb_feature_value(option_bytes,features_id,1)
def pb_field_packed_option(data:array<uint8>):int{
    var result=0
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        if(key==16ul){result=pb_get_varint(data,position)!=0ul ? 1 : 2}
        elif(key==170ul){
            let features <- pb_get_bytes(data,position)
            var at=0
            while(at<length(features)){
                let feature_key=pb_get_varint(features,at)
                if(feature_key==24ul){result=int(pb_get_varint(features,at))}
                else{pb_skip(features,at,int(feature_key&7ul))}
            }
        }else{pb_skip(data,position,int(key&7ul))}
    }
    return result
}
def pb_enum_value_descriptor(data:array<uint8>):PBEnumValue{
    var result=PBEnumValue()
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){result.name=pb_get_text(data,position)}
        elif(id==2 && wire==0){result.number=int(pb_get_varint(data,position))}
        else{pb_skip(data,position,wire)}
    }
    return <- result
}
def pb_range_descriptor(data:array<uint8>):PBNumberRange{
    var result=PBNumberRange()
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        if(key==8ul){result.first=int(pb_get_varint(data,position))}
        elif(key==16ul){result.last=int(pb_get_varint(data,position))}
        else{pb_skip(data,position,int(key&7ul))}
    }
    return result
}
def pb_enum_descriptor(data:array<uint8>; package_name,source_syntax,parent_name:string; file_enum_type:int):PBEnum{
    var result=PBEnum(package_name=package_name,parent_name=parent_name,closed=source_syntax=="proto2" || (source_syntax=="editions" && file_enum_type==2))
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){result.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){var value <- pb_enum_value_descriptor(pb_get_bytes(data,position));emplace(result.values,value)}
        elif(id==3 && wire==2){
            let option_bytes <- pb_get_bytes(data,position)
            result.options_bytes <- clone(option_bytes)
            let enum_type=pb_feature_value(option_bytes,7,2)
            if(enum_type!=0){result.closed=enum_type==2}
            var at=0
            while(at<length(option_bytes)){
                let option_key=pb_get_varint(option_bytes,at)
                if(option_key==16ul){result.allow_alias=pb_get_varint(option_bytes,at)!=0ul}
                else{pb_skip(option_bytes,at,int(option_key&7ul))}
            }
        }
        elif(id==4 && wire==2){var span <- pb_range_descriptor(pb_get_bytes(data,position));emplace(result.reserved_ranges,span)}
        elif(id==5 && wire==2){push(result.reserved_names,pb_get_text(data,position))}
        else{pb_skip(data,position,wire)}
    }
    if(empty(result.name) || empty(result.values) || (source_syntax!="proto2" && result.values[0].number!=0)){panic("invalid enum")}
    return <- result
}
def pb_method_descriptor(data:array<uint8>):PBMethod{
    var method=PBMethod()
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){method.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){method.request=pb_get_text(data,position)}
        elif(id==3 && wire==2){method.response=pb_get_text(data,position)}
        elif(id==5 && wire==0){method.client_streaming=pb_get_varint(data,position)!=0ul}
        elif(id==6 && wire==0){method.server_streaming=pb_get_varint(data,position)!=0ul}
        else{pb_skip(data,position,wire)}
    }
    return <- method
}
def pb_service_descriptor(data:array<uint8>; package_name:string):PBService{
    var service=PBService(package_name=package_name)
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){service.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){var method <- pb_method_descriptor(pb_get_bytes(data,position));emplace(service.methods,method)}
        else{pb_skip(data,position,wire)}
    }
    return <- service
}
def pb_map_entry(data:array<uint8>):PBMessage{
    var result=PBMessage()
    var option_bytes:array<uint8>
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){result.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){var field <- pb_field_descriptor(pb_get_bytes(data,position));emplace(result.fields,field)}
        elif(id==7 && wire==2){option_bytes <- pb_get_bytes(data,position)}
        else{pb_skip(data,position,wire)}
    }
    var option_position=0
    var is_map=false
    while(option_position<length(option_bytes)){
        let key=pb_get_varint(option_bytes,option_position)
        if(key>>3u==7ul && (key&7ul)==0ul){is_map=pb_get_varint(option_bytes,option_position)!=0ul}
        else{pb_skip(option_bytes,option_position,int(key&7ul))}
    }
    if(!is_map || length(result.fields)!=2){panic("nested message is not a supported map entry")}
    return <- result
}
def pb_is_map_entry(data:array<uint8>):bool{
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        if(key>>3u==7ul && (key&7ul)==2ul){
            let option_bytes <- pb_get_bytes(data,position)
            var at=0
            while(at<length(option_bytes)){
                let option_key=pb_get_varint(option_bytes,at)
                if(option_key==56ul){return pb_get_varint(option_bytes,at)!=0ul}
                pb_skip(option_bytes,at,int(option_key&7ul))
            }
        }else{pb_skip(data,position,int(key&7ul))}
    }
    return false
}
def pb_field_descriptor(data:array<uint8>):PBField{
    var field=PBField(oneof_index=-1)
    var cardinality=1
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){field.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){field.extendee=pb_get_text(data,position)}
        elif(id==3 && wire==0){field.number=int(pb_get_varint(data,position))}
        elif(id==4 && wire==0){cardinality=int(pb_get_varint(data,position))}
        elif(id==5 && wire==0){field.kind=int(pb_get_varint(data,position))}
        elif(id==6 && wire==2){field.type_name=pb_get_text(data,position)}
        elif(id==7 && wire==2){field.default_value=pb_get_text(data,position)}
        elif(id==8 && wire==2){
            let option_bytes <- pb_get_bytes(data,position)
            field.options_bytes <- clone(option_bytes)
            field.feature_presence=pb_feature_presence(option_bytes,21)
            field.feature_utf8=pb_feature_value(option_bytes,21,4)
            field.feature_message_encoding=pb_feature_value(option_bytes,21,5)
            field.packed=pb_field_packed_option(option_bytes)
        }
        elif(id==9 && wire==0){field.oneof_index=int(pb_get_varint(data,position))}
        elif(id==17 && wire==0){field.proto3_optional=pb_get_varint(data,position)!=0ul}
        else{pb_skip(data,position,wire)}
    }
    field.repeated=cardinality==3
    field.required=cardinality==2
    field.optional=field.proto3_optional
    if(field.kind==11){field.optional=true}
    if(field.required){field.optional=false}
    if(field.kind==0 || empty(field.name) || field.number==0){panic("invalid field descriptor")}
    return <- field
}
def pb_message_descriptor(data:array<uint8>; package_name,source_syntax,source_edition,parent_name:string; file_presence,file_packed,file_utf8,file_message_encoding:int; var child_chunks,enum_chunks:array<array<uint8>>):PBMessage{
    var message=PBMessage(package_name=package_name,syntax=source_syntax,edition=source_edition,parent_name=parent_name)
    var nested_chunks:array<array<uint8>>
    var oneof_names:array<string>
    var message_presence=0
    var message_packed=0
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==1 && wire==2){message.name=pb_get_text(data,position)}
        elif(id==2 && wire==2){var field <- pb_field_descriptor(pb_get_bytes(data,position));emplace(message.fields,field)}
        elif(id==3 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(nested_chunks,chunk)}
        elif(id==4 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(enum_chunks,chunk)}
        elif(id==5 && wire==2){var span <- pb_range_descriptor(pb_get_bytes(data,position));emplace(message.extension_ranges,span)}
        elif(id==6 && wire==2){
            var extension <- pb_field_descriptor(pb_get_bytes(data,position))
            extension.package_name=package_name
            if(extension.kind==9 && (source_syntax=="proto2" || extension.feature_utf8==3)){extension.kind=20;extension.utf8_none=true}
            emplace(message.extensions,extension)
        }
        elif(id==7 && wire==2){
            let option_bytes <- pb_get_bytes(data,position)
            message.options_bytes <- clone(option_bytes)
            message_presence=pb_feature_presence(option_bytes,12)
            message_packed=pb_feature_value(option_bytes,12,3)
        }
        elif(id==8 && wire==2){
            let declaration <- pb_get_bytes(data,position)
            var at=0
            var name=""
            while(at<length(declaration)){
                let tag=pb_get_varint(declaration,at)
                if(tag==10ul){name=pb_get_text(declaration,at)}else{pb_skip(declaration,at,int(tag&7ul))}
            }
            push(oneof_names,name)
        }
        elif(id==9 && wire==2){var span <- pb_range_descriptor(pb_get_bytes(data,position));emplace(message.reserved_ranges,span)}
        elif(id==10 && wire==2){push(message.reserved_names,pb_get_text(data,position))}
        else{pb_skip(data,position,wire)}
    }
    if(empty(message.name)){panic("invalid message descriptor")}
    for(fi in range(length(message.fields))){
        let index=message.fields[fi].oneof_index
        if(index>=0 && !message.fields[fi].proto3_optional){
            if(index>=length(oneof_names)){panic("invalid oneof index")}
            message.fields[fi].oneof_name=oneof_names[index]
        }
        if(message.fields[fi].required){message.fields[fi].optional=false}
        elif(source_syntax=="proto2" && !message.fields[fi].repeated && empty(message.fields[fi].oneof_name)){message.fields[fi].optional=true}
        elif(source_syntax=="editions" && !message.fields[fi].repeated && !message.fields[fi].map && empty(message.fields[fi].oneof_name)){
            let effective=message.fields[fi].feature_presence!=0 ? message.fields[fi].feature_presence : (message_presence!=0 ? message_presence : (file_presence!=0 ? file_presence : 1))
            message.fields[fi].optional=effective==1
            message.fields[fi].implicit_presence=effective==2
            message.fields[fi].required=effective==3
        }
        if(source_syntax=="editions" && message.fields[fi].repeated && message.fields[fi].packed==0){
            message.fields[fi].packed=message_packed!=0 ? message_packed : (file_packed!=0 ? file_packed : 1)
        }
        if(message.fields[fi].kind==9){
            let utf8=message.fields[fi].feature_utf8!=0 ? message.fields[fi].feature_utf8 : (file_utf8!=0 ? file_utf8 : (source_syntax=="proto2" ? 3 : 2))
            if(utf8==3){message.fields[fi].kind=20;message.fields[fi].utf8_none=true}
        }
        if(source_syntax=="editions" && message.fields[fi].kind==11){
            let encoding=message.fields[fi].feature_message_encoding!=0 ? message.fields[fi].feature_message_encoding : file_message_encoding
            if(encoding==2){message.fields[fi].kind=10;message.fields[fi].delimited=true}
        }
    }
    for(chunk in nested_chunks){
        if(!pb_is_map_entry(chunk)){emplace(child_chunks,clone(chunk));continue}
        let entry <- pb_map_entry(chunk)
        var found=false
        for(fi in range(length(message.fields))){
            let dot=rfind(message.fields[fi].type_name,".")
            if(slice(message.fields[fi].type_name,dot+1)==entry.name){
                message.fields[fi].map=true
                message.fields[fi].kind=19
                message.fields[fi].repeated=false
                message.fields[fi].optional=false
                message.fields[fi].map_key_kind=entry.fields[0].kind
                message.fields[fi].map_value_kind=entry.fields[1].kind
                message.fields[fi].type_name=entry.fields[1].type_name
                found=true
            }
        }
        if(!found){panic("unreferenced nested map entry")}
    }
    return <- message
}
def pb_collect_messages(data:array<uint8>; package_name,source_syntax,source_edition,parent_name:string; file_presence,file_packed,file_utf8,file_message_encoding,file_enum_type:int; var schema:PBSchema){
    var child_chunks:array<array<uint8>>
    var enum_chunks:array<array<uint8>>
    var message <- pb_message_descriptor(data,package_name,source_syntax,source_edition,parent_name,file_presence,file_packed,file_utf8,file_message_encoding,child_chunks,enum_chunks)
    let full_name=empty(parent_name) ? message.name : "{parent_name}.{message.name}"
    emplace(schema.messages,message)
    for(chunk in enum_chunks){var enu <- pb_enum_descriptor(chunk,package_name,source_syntax,full_name,file_enum_type);emplace(schema.enums,enu)}
    for(chunk in child_chunks){pb_collect_messages(chunk,package_name,source_syntax,source_edition,full_name,file_presence,file_packed,file_utf8,file_message_encoding,file_enum_type,schema)}
}
def pb_file_descriptor(data:array<uint8>):PBSchema{
    var schema=PBSchema()
    var package_name=""
    var source_syntax=""
    var source_edition=""
    var file_presence=0
    var file_packed=0
    var file_utf8=0
    var file_message_encoding=0
    var file_enum_type=0
    var chunks:array<array<uint8>>
    var enum_chunks:array<array<uint8>>
    var service_chunks:array<array<uint8>>
    var extension_chunks:array<array<uint8>>
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let id=int(key>>3u)
        let wire=int(key&7ul)
        if(id==2 && wire==2){package_name=pb_get_text(data,position)}
        elif(id==3 && wire==2){push(schema.imports,pb_get_text(data,position))}
        elif(id==4 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(chunks,chunk)}
        elif(id==5 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(enum_chunks,chunk)}
        elif(id==6 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(service_chunks,chunk)}
        elif(id==7 && wire==2){var chunk <- pb_get_bytes(data,position);emplace(extension_chunks,chunk)}
        elif(id==12 && wire==2){source_syntax=pb_get_text(data,position)}
        elif(id==14 && wire==0){let value=int(pb_get_varint(data,position));source_edition=value==1000 ? "2023" : (value==1001 ? "2024" : (value==1002 ? "2026" : ""))}
        elif(id==8 && wire==2){
            let option_bytes <- pb_get_bytes(data,position)
            schema.file_options_bytes <- clone(option_bytes)
            file_presence=pb_feature_presence(option_bytes,50)
            file_packed=pb_feature_value(option_bytes,50,3)
            file_utf8=pb_feature_value(option_bytes,50,4)
            file_message_encoding=pb_feature_value(option_bytes,50,5)
            file_enum_type=pb_feature_value(option_bytes,50,2)
        }
        else{pb_skip(data,position,wire)}
    }
    if(empty(source_syntax)){source_syntax="proto2"}
    if(source_syntax!="proto3" && source_syntax!="proto2" && source_syntax!="editions"){panic("unsupported schema syntax")}
    if(source_syntax=="editions" && empty(source_edition)){panic("unsupported Protobuf edition")}
    schema.syntax=source_syntax
    schema.edition=source_edition
    schema.root_package=package_name
    for(chunk in enum_chunks){var item <- pb_enum_descriptor(chunk,package_name,source_syntax,"",file_enum_type);emplace(schema.enums,item)}
    for(chunk in service_chunks){var item <- pb_service_descriptor(chunk,package_name);emplace(schema.services,item)}
    for(chunk in extension_chunks){
        var extension <- pb_field_descriptor(chunk)
        extension.package_name=package_name
        if(extension.kind==9 && (source_syntax=="proto2" || extension.feature_utf8==3)){extension.kind=20;extension.utf8_none=true}
        emplace(schema.extensions,extension)
    }
    for(chunk in chunks){pb_collect_messages(chunk,package_name,source_syntax,source_edition,"",file_presence,file_packed,file_utf8,file_message_encoding,file_enum_type,schema)}
    return <- schema
}
def pb_import_descriptor_set(data:array<uint8>):PBSchema{
    var result=PBSchema()
    var position=0
    while(position<length(data)){
        let key=pb_get_varint(data,position)
        let wire=int(key&7ul)
        if(key>>3u==1ul && wire==2){
            var file <- pb_file_descriptor(pb_get_bytes(data,position))
            for(i in range(length(result.enums))){result.enums[i].imported=true}
            for(i in range(length(result.services))){result.services[i].imported=true}
            for(i in range(length(result.messages))){result.messages[i].imported=true}
            result.syntax=file.syntax
            result.edition=file.edition
            result.root_package=file.root_package
            result.imports <- clone(file.imports)
            result.file_options_bytes <- clone(file.file_options_bytes)
            for(enu in file.enums){emplace(result.enums,clone(enu))}
            for(service in file.services){emplace(result.services,clone(service))}
            result.extensions <- clone(file.extensions)
            for(message in file.messages){emplace(result.messages,clone(message))}
        }else{pb_skip(data,position,wire)}
    }
    if(empty(result.messages)){panic("descriptor set has no supported messages")}
    return <- result
}
def pb_native_type(field:PBField):string{
    if(field.kind==1){return "double"}
    if(field.kind==2){return "float"}
    if(field.kind==3 || field.kind==16 || field.kind==18){return "int64"}
    if(field.kind==4 || field.kind==6){return "uint64"}
    if(field.kind==5 || field.kind==15 || field.kind==17){return "int"}
    if(field.kind==7 || field.kind==13){return "uint"}
    if(field.kind==8){return "bool"}
    if(field.kind==9 || field.kind==20){return "string"}
    if(field.kind==12){return "array<uint8>"}
    if(field.kind==14){let dot=rfind(field.type_name,".");return slice(field.type_name,dot+1)}
    if(field.kind==11 || field.kind==10){
        let dot=rfind(field.type_name,".")
        return slice(field.type_name,dot+1)
    }
    panic("unsupported field type in descriptor")
    return ""
}
def pb_native_qualified(type_name,package_name:string):string{
    var name=type_name
    let prefix=".{package_name}."
    if(!empty(package_name) && find(name,prefix)==0){name=slice(name,length(prefix))}
    elif(find(name,".")==0){name=slice(name,1)}
    return replace(name,".","_")
}
def pb_native_type_in(field:PBField; package_name:string):string{
    if(field.kind==11 || field.kind==10 || field.kind==14){return pb_native_qualified(field.type_name,package_name)}
    return pb_native_type(field)
}
def pb_native_message_name(message:PBMessage; root_package:string):string{
    let full_name=empty(message.parent_name) ? message.name : "{message.parent_name}.{message.name}"
    let qualified=empty(message.package_name) ? ".{full_name}" : ".{message.package_name}.{full_name}"
    return pb_native_qualified(qualified,root_package)
}
def pb_native_field_name(name:string):string{
    let reserved=";label;options;module;require;struct;enum;var;let;def;return;if;else;for;while;true;false;none;some;type;class;public;private;static;auto;unsafe;"
    return find(reserved,";{name};")>=0 ? "{name}_" : name
}
def pb_options_function(name:string; option_bytes:array<uint8>):string{
    if(empty(option_bytes)){return ""}
    var output="def {name}():array<uint8> \{\n    var data:array<uint8>\n"
    for(byte in option_bytes){output+="    push(data,{int(byte)}u8)\n"}
    output+="    return <- data\n}\n"
    return output
}
def pb_emit_extension(field:PBField; root_package:string):string{
    let target=pb_native_qualified(field.extendee,root_package)
    let native=pb_native_type_in(field,root_package)
    let name=pb_native_field_name(field.name)
    let number=field.number
    let kind=field.kind
    let wire=pb_wire(kind)
    let result_type=field.repeated ? "array<{native}>" : "Option<{native}>"
    var output="def pb_ext_get_{name}(value:{target}):{result_type} \{\n"
    output+="    let data <- clone(value.pb_unknown_fields)\n    var pos=0\n    var result:{result_type}\n"
    output+="    while(pos<length(data)) \{\n"
    output+="        let tag=pb_get_varint(data,pos)\n"
    output+="        let field_number=int(tag/8ul)\n        let field_wire=int(tag&7ul)\n"
    output+="        if(field_number=={number} && field_wire=={wire}) \{\n"
    output+="            var item=default<{native}>\n"
    if(kind==11 || kind==10){
        let read_nested=kind==10 ? "pb_get_group(data,pos,{number})" : "pb_get_bytes(data,pos)"
        output+="            let nested <- {read_nested}\n"
        if(!field.repeated){
            output+="            if(result is some) \{ item <- pb_unpack_{native}(pb_concat(pb_pack_{native}(result as some),nested)) }\n"
            output+="            else \{ item <- pb_unpack_{native}(nested) }\n"
        }else{output+="            item <- pb_unpack_{native}(nested)\n"}
    }elif(kind==14){
        output+="            var numeric=0\n            pb_read(data,pos,14,numeric)\n"
        output+="            item=unsafe(reinterpret<{native}>(numeric))\n"
    }else{output+="            pb_read(data,pos,{kind},item)\n"}
    output+=field.repeated ? "            emplace(result,item)\n" : "            result <- move_some(item)\n"
    output+="        }\n"
    if(field.repeated && wire!=2){
        output+="        elif(field_number=={number} && field_wire==2) \{\n"
        output+="            let packed <- pb_get_bytes(data,pos)\n            var at=0\n"
        output+="            while(at<length(packed)) \{\n"
        output+="                var item=default<{native}>\n"
        if(kind==14){output+="                var numeric=0\n                pb_read(packed,at,14,numeric)\n                item=unsafe(reinterpret<{native}>(numeric))\n"}
        else{output+="                pb_read(packed,at,{kind},item)\n"}
        output+="                emplace(result,item)\n            }\n        }\n"
    }
    output+="        else \{ pb_skip(data,pos,field_number,field_wire) }\n"
    output+="    }\n    return <- result\n}\n"
    let argument=field.repeated ? "items:array<{native}>" : "item:{native}"
    output+="def pb_ext_set_{name}(var value:{target}; {argument}) \{\n"
    if(field.repeated){output+="    for(item in items) \{\n"}
    let indent=field.repeated ? "        " : "    "
    if(kind==11){output+="{indent}pb_put_key(value.pb_unknown_fields,{number},2)\n{indent}let bytes <- pb_pack_{native}(item)\n{indent}pb_put_bytes(value.pb_unknown_fields,bytes)\n"}
    elif(kind==10){output+="{indent}let bytes <- pb_pack_{native}(item)\n{indent}pb_put_group(value.pb_unknown_fields,{number},bytes)\n"}
    elif(kind==14){output+="{indent}pb_write(value.pb_unknown_fields,{number},14,int(item))\n"}
    else{output+="{indent}pb_write(value.pb_unknown_fields,{number},{kind},item)\n"}
    if(field.repeated){output+="    }\n"}
    output+="}\n"
    return output
}
def pb_emit_message(var schema:PBSchema; index:int; var states:array<int>):string{
    if(states[index]==2){return ""}
    if(states[index]==1){panic("recursive messages require explicit native reference support")}
    states[index]=1
    var output=""
    for(fi in range(length(schema.messages[index].fields))){
        assume field=schema.messages[index].fields[fi]
        if(field.kind!=11 && field.kind!=10 && !(field.map && field.map_value_kind==11)){continue}
        let dot=rfind(field.type_name,".")
        let dependency=pb_native_qualified(field.type_name,schema.root_package)
        var found=-1
        for(i in range(length(schema.messages))){if(pb_native_message_name(schema.messages[i],schema.root_package)==dependency){found=i}}
        if(found<0){panic("unresolved message type: {field.type_name}")}
        if(states[found]==1){schema.messages[index].fields[fi].boxed=true}
        else{output+=pb_emit_message(schema,found,states)}
    }
    assume message=schema.messages[index]
    let native_message=pb_native_message_name(message,schema.root_package)
    output+="[pb_message(package=\"{message.package_name}\",syntax=\"{message.syntax}\",edition=\"{message.edition}\",name=\"{message.name}\",parent=\"{message.parent_name}\")]\nstruct {native_message} \{\n"
    var emitted_oneofs:table<string;bool>
    for(field in message.fields){
            if(!empty(field.oneof_name)){
                if(key_exists(emitted_oneofs,field.oneof_name)){continue}
                emitted_oneofs[field.oneof_name]=true
                var members="variant<none"
                var numbers="0"
                for(member in message.fields){
                    if(member.oneof_name!=field.oneof_name){continue}
                    let member_type=pb_native_type_in(member,schema.root_package)
                    members+=";{member.name}:{member_type}"
                    numbers+=",{member.number}"
                }
                members+=">"
                output+="    @pb_oneof_numbers=\"{numbers}\"\n    {field.oneof_name}:{members}\n"
                continue
            }
            var base=field.map ? "" : pb_native_type_in(field,schema.root_package)
            var typ=field.repeated ? "array<{base}>" : (field.boxed ? "PBRef<{base}>" : (field.optional ? "Option<{base}>" : base))
            if(field.map){
                let keytype=pb_native_type(PBField(kind=field.map_key_kind))
                let valuetype=pb_native_type_in(PBField(kind=field.map_value_kind,type_name=field.type_name),schema.root_package)
                typ="table<{keytype};{valuetype}>"
            }
            output+="    @pb_id={field.number}\n"
            if(field.required){output+="    @pb_required\n"}
            if(field.implicit_presence){output+="    @pb_implicit\n"}
            if(field.kind==10){output+=field.delimited ? "    @pb_delimited\n" : "    @pb_group\n"}
            if(field.utf8_none && message.syntax=="editions"){output+="    @pb_utf8_none\n"}
            if(field.packed!=0){let enabled=field.packed==1 ? "true" : "false";output+="    @pb_packed={enabled}\n"}
            if(!empty(field.default_value)){output+="    @pb_default=\"{field.default_value}\"\n"}
            if(field.kind==17){output+="    @pb_sint32\n"}
            elif(field.kind==18){output+="    @pb_sint64\n"}
            elif(field.kind==6){output+="    @pb_fixed64\n"}
            elif(field.kind==7){output+="    @pb_fixed32\n"}
            elif(field.kind==15){output+="    @pb_sfixed32\n"}
            elif(field.kind==16){output+="    @pb_sfixed64\n"}
            let native_field=pb_native_field_name(field.name)
            if(native_field!=field.name){output+="    @pb_name=\"{field.name}\"\n"}
            output+="    {native_field}:{typ}\n"
    }
    output+="    @pb_unknown\n    pb_unknown_fields:array<uint8>\n}\n"
    states[index]=2
    return output
}
def pb_emit_native(schema:PBSchema; module_name,annotation_import:string):string{
    var output="options gen2\nmodule {module_name} public\nrequire {annotation_import} public\nrequire ../src/grpc_transport.das public\n"
    var working <- clone(schema)
    for(enu in schema.enums){
        let full_name=empty(enu.parent_name) ? enu.name : "{enu.parent_name}.{enu.name}"
        let qualified=empty(enu.package_name) ? ".{full_name}" : ".{enu.package_name}.{full_name}"
        let native=pb_native_qualified(qualified,schema.root_package)
        let alias_text=enu.allow_alias ? ",allow_alias=true" : ""
        let closed_text=enu.closed ? ",closed=true" : ""
        output+="[pb_enum(name=\"{enu.name}\",parent=\"{enu.parent_name}\",package=\"{enu.package_name}\"{alias_text}{closed_text})]\nenum {native}:int \{\n"
        for(value in enu.values){output+="    {value.name}={value.number}\n"}
        output+="}\n"
    }
    var states:array<int>
    resize(states,length(working.messages))
    for(i in range(length(working.messages))){
        output+=pb_emit_message(working,i,states)
    }
    output+=pb_options_function("pb_file_options",schema.file_options_bytes)
    for(message in schema.messages){
        let native=pb_native_message_name(message,schema.root_package)
        output+=pb_options_function("pb_message_options_{native}",message.options_bytes)
        for(field in message.fields){
            let field_name=pb_native_field_name(field.name)
            output+=pb_options_function("pb_field_options_{native}_{field_name}",field.options_bytes)
        }
    }
    for(extension in schema.extensions){
        if(extension.package_name==schema.root_package){output+=pb_emit_extension(extension,schema.root_package)}
    }
    for(message in schema.messages){
        if(message.imported || message.package_name!=schema.root_package){continue}
        for(extension in message.extensions){output+=pb_emit_extension(extension,schema.root_package)}
    }
    for(service in schema.services){
        if(service.imported || service.package_name!=schema.root_package){continue}
        for(method in service.methods){
            let package_name=schema.root_package
            let request=pb_native_qualified(method.request,package_name)
            let response=pb_native_qualified(method.response,package_name)
            let service_name=empty(package_name) ? service.name : "{package_name}.{service.name}"
            let path="/{service_name}/{method.name}"
            if(method.client_streaming || method.server_streaming){
                output+="def pb_rpc_stream_{service.name}_{method.name}(requests:array<{request}>; transport:block<(method:string;payloads:array<array<uint8>>):array<array<uint8>>>):array<{response}> \{\n"
                if(!method.client_streaming){output+="    if(length(requests)!=1) \{ panic(\"server-streaming RPC requires one request\") }\n"}
                output+="    var request_bytes:array<array<uint8>>\n"
                output+="    for(item in requests) \{ var bytes <- pb_pack_{request}(item); emplace(request_bytes,bytes) }\n"
                output+="    let response_bytes <- invoke(transport,\"{path}\",request_bytes)\n"
                if(!method.server_streaming){output+="    if(length(response_bytes)!=1) \{ panic(\"client-streaming RPC requires one response\") }\n"}
                output+="    var responses:array<{response}>\n"
                output+="    for(bytes in response_bytes) \{\n"
                output+="        if(!pb_verify_{response}(bytes)) \{ panic(\"invalid Protobuf RPC response\") }\n"
                output+="        var value <- pb_unpack_{response}(bytes)\n"
                output+="        emplace(responses,value)\n"
                output+="    }\n"
                output+="    return <- responses\n}\n"
                let shape=method.client_streaming ? (method.server_streaming ? "bidi" : "client_stream") : "server_stream"
                output+="def pb_grpc_{service.name}_{method.name}(requests:array<{request}>; config:PBGrpcTransport):array<{response}> \{\n"
                output+="    return <- pb_rpc_stream_{service.name}_{method.name}(requests,$(method,payloads):array<array<uint8>> \{ return <- pb_grpc_stream(config,\"{shape}\",method,payloads) })\n}\n"
                continue
            }
            output+="def pb_rpc_{service.name}_{method.name}(request:{request}; transport:block<(method:string;payload:array<uint8>):array<uint8>>):{response} \{\n"
            output+="    let request_bytes <- pb_pack_{request}(request)\n"
            output+="    let response_bytes <- invoke(transport,\"{path}\",request_bytes)\n"
            output+="    if(!pb_verify_{response}(response_bytes)) \{ panic(\"invalid Protobuf RPC response\") }\n"
            output+="    return <- pb_unpack_{response}(response_bytes)\n}\n"
            output+="def pb_grpc_{service.name}_{method.name}(request:{request}; config:PBGrpcTransport):{response} \{\n"
            output+="    return <- pb_rpc_{service.name}_{method.name}(request,$(method,payload):array<uint8> \{ return <- pb_grpc_unary(config,method,payload) })\n}\n"
        }
    }
    return output
}
