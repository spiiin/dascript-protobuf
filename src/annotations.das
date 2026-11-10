options gen2
module annotations public
require strings
require daslib/strings_boost
require daslib/ast
require daslib/ast_boost
require daslib/templates_boost
require daslib/option public
require ./references.das public
require ./ir.das public
require ./runtime.das public

def pb_option(td:TypeDeclPtr):bool => td.baseType==Type.tVariant && length(td.argNames)==2 && td.argNames[0]=="none" && td.argNames[1]=="some"
def pb_is_ref(td:TypeDeclPtr):bool{
    if(td.baseType!=Type.tStructure || length(td.structType.fields)!=1){return false}
    for(a in td.structType.fields[0].annotation){if(a.name=="pb_reference"){return true}}
    return false
}
def pb_payload(td:TypeDeclPtr):TypeDeclPtr const{
    if(pb_is_ref(td)){return td.structType.fields[0]._type.firstType}
    return pb_option(td) ? td.argTypes[1] : td
}
def pb_wire_object_name(st:StructurePtr):string{
    var name=string(st.name)
    var parent=""
    var package_name=""
    for(annotation in st.annotations){
        if(annotation.annotation.name!="pb_message"){continue}
        for(arg in annotation.arguments){
            if(arg.name=="name"){name=string(arg.sValue)}
            elif(arg.name=="parent"){parent=string(arg.sValue)}
            elif(arg.name=="package"){package_name=string(arg.sValue)}
        }
    }
    if(empty(parent)){return empty(package_name) ? name : ".{package_name}.{name}"}
    return empty(package_name) ? ".{parent}.{name}" : ".{package_name}.{parent}.{name}"
}
def pb_wire_enum_name(enu:EnumerationPtr; package_name:string):string{
    var name=string(enu.name)
    var parent=""
    var enum_package=package_name
    for(annotation in enu.annotations){
        if(annotation.annotation.name!="pb_enum"){continue}
        for(arg in annotation.arguments){
            if(arg.name=="name"){name=string(arg.sValue)}
            elif(arg.name=="parent"){parent=string(arg.sValue)}
            elif(arg.name=="package"){enum_package=string(arg.sValue)}
        }
    }
    if(empty(parent)){return enum_package==package_name ? name : ".{enum_package}.{name}"}
    return empty(enum_package) ? ".{parent}.{name}" : ".{enum_package}.{parent}.{name}"
}
def pb_enum_value(e:ExpressionPtr):int{
    if(e is ExprConstInt){return (e as ExprConstInt).value}
    if(e is ExprConstInt8){return int((e as ExprConstInt8).value)}
    if(e is ExprConstInt16){return int((e as ExprConstInt16).value)}
    panic("Protobuf enum values must be integer constants")
    return 0
}
def pb_closed_enum_values(enu:EnumerationPtr; syntax:string):string{
    var closed=syntax=="proto2"
    for(annotation in enu.annotations){
        if(annotation.annotation.name!="pb_enum"){continue}
        for(arg in annotation.arguments){if(arg.name=="closed"){closed=arg.bValue}}
    }
    if(!closed){return ""}
    var values=""
    for(value in enu.list){values+="{pb_enum_value(value.value)},"}
    return values
}
def pb_collect_enum(enu:EnumerationPtr; package_name,syntax:string; var schema:PBSchema){
    for(existing in schema.enums){if(existing.name==enu.name){return}}
    var item=PBEnum(name=string(enu.name),package_name=package_name)
    var found=false
    for(annotation in enu.annotations){
        if(annotation.annotation.name=="pb_enum"){
            found=true
            for(arg in annotation.arguments){
                if(arg.name=="name"){item.name=string(arg.sValue)}
                elif(arg.name=="parent"){item.parent_name=string(arg.sValue)}
                elif(arg.name=="package"){item.package_name=string(arg.sValue)}
                elif(arg.name=="allow_alias"){item.allow_alias=arg.bValue}
                elif(arg.name=="closed"){item.closed=arg.bValue}
            }
        }
    }
    if(!found){panic("Protobuf enum requires [pb_enum]")}
    if(syntax=="proto2"){item.closed=true}
    if(item.package_name!=schema.root_package){return}
    for(value in enu.list){emplace(item.values,PBEnumValue(name=string(value.name),number=pb_enum_value(value.value)))}
    if(empty(item.values) || (syntax!="proto2" && item.values[0].number!=0)){panic("proto3/Edtions enum must begin with zero")}
    emplace(schema.enums,item)
}
def pb_variant(typ:TypeDeclPtr; member:string; value:ExpressionPtr):ExpressionPtr{
    var result=new ExprMakeVariant(makeType=clone_type(typ))
    var slot=new MakeFieldDecl(name:=member,value=clone_expression(value))
    slot.flags=MakeFieldDeclFlags.moveSemantics
    emplace(result.variants,slot)
    return result
}
def pb_kind(td:TypeDeclPtr):int{
    if(td.baseType==Type.tInt){return 5}
    if(td.baseType==Type.tUInt){return 13}
    if(td.baseType==Type.tInt64){return 3}
    if(td.baseType==Type.tUInt64){return 4}
    if(td.baseType==Type.tBool){return 8}
    if(td.baseType==Type.tString){return 9}
    if(td.baseType==Type.tFloat){return 2}
    if(td.baseType==Type.tDouble){return 1}
    if(td.baseType==Type.tArray && td.firstType.baseType==Type.tUInt8){return 12}
    if(td.baseType==Type.tStructure){return 11}
    return 0
}
def pb_describe(st:StructurePtr):PBMessage{
    var message=PBMessage(name=string(st.name),syntax="proto3")
    for(a in st.annotations){
        if(a.annotation.name=="pb_message"){
            for(arg in a.arguments){if(arg.name=="package"){message.package_name=string(arg.sValue)}elif(arg.name=="syntax"){message.syntax=string(arg.sValue)}elif(arg.name=="edition"){message.edition=string(arg.sValue)}elif(arg.name=="name"){message.name=string(arg.sValue)}elif(arg.name=="parent"){message.parent_name=string(arg.sValue)}elif(arg.name=="schema_header"){message.schema_header=string(arg.sValue)}elif(arg.name=="pb_options"){message.raw_options=string(arg.sValue)}}
        }
    }
    for(field in st.fields){
        var unknown=false
        for(a in field.annotation){if(a.name=="pb_unknown"){unknown=true}}
        if(unknown){continue}
        if(field._type.baseType==Type.tVariant && !pb_option(field._type)){
            var numbers=""
            for(a in field.annotation){if(a.name=="pb_oneof_numbers"){numbers=string(a.sValue)}}
            let tags <- split(numbers,",")
            if(length(tags)!=length(field._type.argTypes) || field._type.argNames[0]!="none"){panic("oneof requires matching @pb_oneof_numbers and first none member")}
            for(i in range(1,length(tags))){
                let typ=field._type.argTypes[i]
                var one=PBField(name=string(field._type.argNames[i]),number=int(tags[i]),oneof_name=string(field.name))
                one.kind=typ.isEnum ? 14 : pb_kind(typ)
                if(one.kind==11){one.type_name=pb_wire_object_name(typ.structType)}
                elif(one.kind==14){one.type_name=pb_wire_enum_name(typ.enumType,message.package_name)}
                emplace(message.fields,one)
            }
            continue
        }
        var f=PBField(name=string(field.name))
        for(a in field.annotation){
            if(a.name=="pb_id"){f.number=a.iValue}
            elif(a.name=="pb_name"){f.name=string(a.sValue)}
            elif(a.name=="pb_required"){f.required=a.bValue}
            elif(a.name=="pb_implicit"){f.implicit_presence=a.bValue}
            elif(a.name=="pb_default"){f.default_value=string(a.sValue)}
            elif(a.name=="pb_options"){f.raw_options=string(a.sValue)}
            elif(a.name=="pb_packed"){f.packed=a.bValue ? 1 : 2}
            elif(a.name=="pb_group"){f.kind=10}
            elif(a.name=="pb_delimited"){f.kind=10;f.delimited=true}
            elif(a.name=="pb_utf8_none"){f.kind=20;f.utf8_none=true}
            elif(a.name=="pb_sint32"){f.kind=17}
            elif(a.name=="pb_sint64"){f.kind=18}
            elif(a.name=="pb_fixed32"){f.kind=7}
            elif(a.name=="pb_fixed64"){f.kind=6}
            elif(a.name=="pb_sfixed32"){f.kind=15}
            elif(a.name=="pb_sfixed64"){f.kind=16}
        }
        f.boxed=pb_is_ref(field._type)
        f.optional=pb_option(field._type) || f.boxed
        if(f.required || f.implicit_presence){f.optional=false}
        let payload=pb_payload(field._type)
        if(payload.baseType==Type.tTable){
            f.map=true
            f.kind=19
            f.map_key_kind=pb_kind(payload.firstType)
            f.map_value_kind=payload.secondType.isEnum ? 14 : pb_kind(payload.secondType)
            if(f.map_value_kind==11){f.type_name=pb_wire_object_name(payload.secondType.structType)}
            elif(f.map_value_kind==14){f.type_name=string(payload.secondType.enumType.name)}
        }
        f.repeated=payload.baseType==Type.tArray && payload.firstType.baseType!=Type.tUInt8
        let elem=f.repeated ? payload.firstType : payload
        if(f.map){}
        elif(elem.isEnum){f.kind=14;f.type_name=pb_wire_enum_name(elem.enumType,message.package_name)}
        elif(f.kind==0){f.kind=pb_kind(elem)}
        if(f.kind==9 && message.syntax=="proto2"){f.kind=20;f.utf8_none=true}
        if(f.kind==11 || f.kind==10){f.type_name=pb_wire_object_name(elem.structType)}
        emplace(message.fields,f)
    }
    return <- message
}
def pb_collect(st:StructurePtr; var schema:PBSchema; var seen:table<string;bool>){
    let key="{st._module.name}::{st.name}"
    if(key_exists(seen,key)){return}
    seen[key]=true
    let own <- pb_describe(st)
    if(own.package_name!=schema.root_package){return}
    for(field in st.fields){
        let payload=pb_payload(field._type)
        if(payload.baseType==Type.tVariant){
            for(i in range(1,length(payload.argTypes))){
                let member=payload.argTypes[i]
                if(member.isEnum){pb_collect_enum(member.enumType,own.package_name,own.syntax,schema)}
                elif(member.baseType==Type.tStructure){pb_collect(member.structType,schema,seen)}
            }
            continue
        }
        let elem=payload.baseType==Type.tArray && payload.firstType.baseType!=Type.tUInt8 ? payload.firstType : (payload.baseType==Type.tTable ? payload.secondType : payload)
        if(elem.isEnum){pb_collect_enum(elem.enumType,own.package_name,own.syntax,schema)}
        elif(elem.baseType==Type.tStructure){pb_collect(elem.structType,schema,seen)}
    }
    var message <- pb_describe(st)
    emplace(schema.messages,message)
}
def pb_replace(st:StructurePtr; name:string; var source:FunctionPtr){
    var fn=st._module |> find_unique_function(name)
    fn.body=source.body
    fn.body |> force_at(st.at)
}
def pb_apply(var st:StructurePtr; var errors:das_string):bool{
    for(field in st.fields){
        var found=false
        for(a in field.annotation){if(a.name=="pb_id" || a.name=="pb_oneof_numbers" || a.name=="pb_unknown"){found=true}}
        if(!found){errors:="every protobuf field requires @pb_id: {field.name}";return false}
        if(field._type.baseType==Type.tVariant && !pb_option(field._type)){field.annotation |> add_annotation_argument("safe_when_uninitialized",true)}
    }
    var pack=qmacro_function("pb_pack_{st.name}") $(value:$t(st)):array<uint8>{var data:array<uint8>;return <- data}
    var unpack=qmacro_function("pb_unpack_{st.name}") $(data:array<uint8>):$t(st){return default<$t(st)>}
    var schema=qmacro_function("pb_schema_{st.name}") $():string{return ""}
    var descriptor=qmacro_function("pb_descriptor_{st.name}") $():PBMessage{return PBMessage()}
    var verify=qmacro_function("pb_verify_{st.name}") $(data:array<uint8>):bool{return false}
    for(fn in [pack,unpack,schema,descriptor,verify]){
        if(st._module |> find_unique_function(string(fn.name))!=null){errors:="duplicate function: {fn.name}";return false}
        fn.flags.generated=true
        fn.body |> force_at(st.at)
        add_function(st._module,fn)
    }
    return true
}
def pb_patch(var st:StructurePtr; var args:AnnotationArgumentList; var astChanged:bool&):bool{
    if(find_arg(args,"__pb_done") is tBool){return true}
    var message=PBMessage(name=string(st.name))
    for(arg in args){
        if(arg.name=="package" && arg.basicType==Type.tString){message.package_name=string(arg.sValue)}
        elif(arg.name=="name" && arg.basicType==Type.tString){message.name=string(arg.sValue)}
        elif(arg.name=="parent" && arg.basicType==Type.tString){message.parent_name=string(arg.sValue)}
        elif(arg.name=="syntax" && arg.basicType==Type.tString){message.syntax=string(arg.sValue)}
    }
    var writes:array<ExpressionPtr>
    var reads:array<ExpressionPtr>
    var unknown_name=""
    for(field in st.fields){
        for(a in field.annotation){if(a.name=="pb_unknown"){
            if(!empty(unknown_name) || field._type.baseType!=Type.tArray || field._type.firstType.baseType!=Type.tUInt8){panic("@pb_unknown requires one array<uint8> field")}
            unknown_name=string(field.name)
        }}
    }
    for(field in st.fields){
        var unknown=false
        for(a in field.annotation){if(a.name=="pb_unknown"){unknown=true}}
        if(unknown){continue}
        if(field._type.baseType==Type.tVariant && !pb_option(field._type)){
            var numbers=""
            for(a in field.annotation){if(a.name=="pb_oneof_numbers"){numbers=string(a.sValue)}}
            let tags <- split(numbers,",")
            if(length(tags)!=length(field._type.argTypes) || field._type.argNames[0]!="none"){panic("invalid oneof annotation")}
            let field_name=string(field.name)
            for(i in range(1,length(tags))){
                let member=string(field._type.argNames[i])
                let typ=field._type.argTypes[i]
                let number=int(tags[i])
                let kind=typ.isEnum ? 14 : pb_kind(typ)
                if(kind==0){panic("unsupported oneof member")}
                var desc=PBField(name=member,number=number,kind=kind,oneof_name=field_name)
                if(kind==11){desc.type_name=pb_wire_object_name(typ.structType)}
                elif(kind==14){desc.type_name=pb_wire_enum_name(typ.enumType,message.package_name)}
                for(previous in message.fields){if(previous.number==number){panic("duplicate Protobuf field number")}}
                emplace(message.fields,desc)
                if(kind==11){
                    let writer="pb_pack_{typ.structType.name}"
                    let reader="pb_unpack_{typ.structType.name}"
                    writes |> push <| qmacro_block(){if(value.$f(field_name) is $f(member)){pb_put_key(data,$v(number),2);let bytes <- $c(writer)(value.$f(field_name) as $f(member));pb_put_bytes(data,bytes)}}
                    let made=pb_variant(field._type,member,qmacro(oneof_item))
                    reads |> push <| qmacro_block(){if(field_number==$v(number)){
                        if(wire!=2){panic("wrong oneof wire type")}
                        let bytes <- pb_get_bytes(data,pos)
                        var oneof_item=default<$t(typ)>
                        if(result.$f(field_name) is $f(member)){
                            let joined <- pb_concat($c(writer)(result.$f(field_name) as $f(member)),bytes)
                            oneof_item <- $c(reader)(joined)
                        }else{oneof_item <- $c(reader)(bytes)}
                        result.$f(field_name) <- $e(made)
                        matched=true
                    }}
                }else{
                    let payload_expr=qmacro(value.$f(field_name) as $f(member))
                    var write_value=clone_expression(payload_expr)
                    if(kind==14){write_value=qmacro(int($e(payload_expr)))}
                    writes |> push <| qmacro_block(){if(value.$f(field_name) is $f(member)){pb_write(data,$v(number),$v(kind),$e(write_value))}}
                    let native=clone_type(typ)
                    let made=pb_variant(field._type,member,qmacro(oneof_item))
                    if(kind==14){
                        let closed_values=pb_closed_enum_values(typ.enumType,message.syntax)
                        var unknown_step=qmacro_block(){}
                        if(!empty(unknown_name)){let storage=unknown_name;unknown_step=qmacro_block(){pb_write(result.$f(storage),$v(number),14,number_value)}}
                        reads |> push <| qmacro_block(){if(field_number==$v(number)){
                            if(wire!=0){panic("wrong oneof wire type")}
                            var number_value=0
                            pb_read(data,pos,14,number_value)
                            if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){$e(unknown_step);known_value=false}
                            else{var oneof_item=unsafe(reinterpret<$t(native)>(number_value));result.$f(field_name) <- $e(made)}
                            matched=true
                        }}
                    }else{
                        reads |> push <| qmacro_block(){if(field_number==$v(number)){if(wire!=$v(pb_wire(kind))){panic("wrong oneof wire type")};var oneof_item=default<$t(native)>;pb_read(data,pos,$v(kind),oneof_item);result.$f(field_name) <- $e(made);matched=true}}
                    }
                }
            }
            continue
        }
        var f=PBField(name=string(field.name))
        for(a in field.annotation){
            if(a.name=="pb_id"){f.number=a.iValue}
            elif(a.name=="pb_name"){f.name=string(a.sValue)}
            elif(a.name=="pb_required"){f.required=a.bValue}
            elif(a.name=="pb_implicit"){f.implicit_presence=a.bValue}
            elif(a.name=="pb_default"){f.default_value=string(a.sValue)}
            elif(a.name=="pb_options"){f.raw_options=string(a.sValue)}
            elif(a.name=="pb_packed"){f.packed=a.bValue ? 1 : 2}
            elif(a.name=="pb_group"){f.kind=10}
            elif(a.name=="pb_delimited"){f.kind=10;f.delimited=true}
            elif(a.name=="pb_utf8_none"){f.kind=20;f.utf8_none=true}
            elif(a.name=="pb_sint32"){f.kind=17}
            elif(a.name=="pb_sint64"){f.kind=18}
            elif(a.name=="pb_fixed32"){f.kind=7}
            elif(a.name=="pb_fixed64"){f.kind=6}
            elif(a.name=="pb_sfixed32"){f.kind=15}
            elif(a.name=="pb_sfixed64"){f.kind=16}
        }
        f.boxed=pb_is_ref(field._type)
        f.optional=pb_option(field._type) || f.boxed
        if(f.required || f.implicit_presence){f.optional=false}
        let payload=pb_payload(field._type)
        if(payload.baseType==Type.tTable){
            f.map=true
            f.kind=19
            f.map_key_kind=pb_kind(payload.firstType)
            f.map_value_kind=payload.secondType.isEnum ? 14 : pb_kind(payload.secondType)
            if(f.map_value_kind==11){f.type_name=pb_wire_object_name(payload.secondType.structType)}
            elif(f.map_value_kind==14){f.type_name=string(payload.secondType.enumType.name)}
        }
        f.repeated=payload.baseType==Type.tArray && payload.firstType.baseType!=Type.tUInt8
        let elem=f.repeated ? payload.firstType : payload
        if(f.map){}
        elif(elem.isEnum){f.kind=14;f.type_name=pb_wire_enum_name(elem.enumType,message.package_name)}
        elif(f.kind==0){f.kind=pb_kind(elem)}
        if(f.kind==9 && message.syntax=="proto2"){f.kind=20;f.utf8_none=true}
        if(f.kind==0){panic("unsupported Protobuf type: {f.name}")}
        if(f.kind==11 || f.kind==10){f.type_name=pb_wire_object_name(elem.structType)}
        if(f.number<1 || f.number>536870911 || (f.number>=19000 && f.number<=19999)){panic("invalid Protobuf field number")}
        for(previous in message.fields){if(previous.number==f.number){panic("duplicate Protobuf field number")}}
        if(f.repeated && f.optional){panic("repeated fields cannot be optional")}
        let name=string(field.name)
        let number=f.number
        let kind=f.kind
        let expected=pb_wire(kind)
        let source=f.boxed ? qmacro(value.$f(name).value[0]) : (f.optional ? qmacro(value.$f(name) as some) : qmacro(value.$f(name)))
        if(f.map){
            if(f.map_key_kind!=9 && f.map_key_kind!=5 && f.map_key_kind!=13 && f.map_key_kind!=3 && f.map_key_kind!=4 && f.map_key_kind!=8){panic("unsupported Protobuf map key type")}
            if(f.map_value_kind==0){panic("unsupported Protobuf map value type")}
            let keykind=f.map_key_kind
            let valuekind=f.map_value_kind
            let keytype=clone_type(payload.firstType)
            let valuetype=clone_type(payload.secondType)
            var put_value=qmacro(pb_write(entry,2,$v(valuekind),map_value))
            var read_value=qmacro(pb_read(entry,entry_pos,$v(valuekind),map_value))
            if(valuekind==11){
                let writer="pb_pack_{payload.secondType.structType.name}"
                let reader="pb_unpack_{payload.secondType.structType.name}"
                put_value=qmacro_block(){pb_put_key(entry,2,2);let bytes <- $c(writer)(map_value);pb_put_bytes(entry,bytes)}
                read_value=qmacro_block(){let bytes <- pb_get_bytes(entry,entry_pos);map_value <- $c(reader)(bytes)}
            }elif(valuekind==14){
                put_value=qmacro(pb_write(entry,2,14,int(map_value)))
                let closed_values=pb_closed_enum_values(payload.secondType.enumType,message.syntax)
                read_value=qmacro_block(){
                    var number_value=0;pb_read(entry,entry_pos,14,number_value)
                    if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){map_known=false}
                    else{map_value=unsafe(reinterpret<$t(valuetype)>(number_value))}
                }
            }
            var unknown_map_step=qmacro_block(){}
            if(!empty(unknown_name)){let storage=unknown_name;unknown_map_step=qmacro_block(){pb_put_key(result.$f(storage),$v(number),2);pb_put_bytes(result.$f(storage),entry)}}
            writes |> push <| qmacro_block(){
                for(map_key,map_value in keys(value.$f(name)),values(value.$f(name))){
                    var entry:array<uint8>
                    pb_write(entry,1,$v(keykind),map_key)
                    $e(put_value)
                    pb_put_key(data,$v(number),2)
                    pb_put_bytes(data,entry)
                }
            }
            reads |> push <| qmacro_block(){if(field_number==$v(number)){
                if(wire!=2){panic("wrong Protobuf map wire type")}
                let entry <- pb_get_bytes(data,pos)
                var entry_pos=0
                var map_key=default<$t(keytype)>
                var map_value=default<$t(valuetype)>
                var map_known=true
                while(entry_pos<length(entry)){
                    let entry_tag=pb_get_varint(entry,entry_pos)
                    let entry_number=int(entry_tag>>3u)
                    let entry_wire=int(entry_tag&7ul)
                    if(entry_number==1){if(entry_wire!=$v(pb_wire(keykind))){panic("wrong map key wire type")};pb_read(entry,entry_pos,$v(keykind),map_key)}
                    elif(entry_number==2){if(entry_wire!=$v(pb_wire(valuekind))){panic("wrong map value wire type")};$e(read_value)}
                    else{pb_skip(entry,entry_pos,entry_number,entry_wire)}
                }
                if(map_known){result.$f(name)[map_key] <- map_value}
                else{$e(unknown_map_step)}
                matched=true
            }}
        }elif(kind==14){
            let native=clone_type(elem)
            let closed_values=pb_closed_enum_values(elem.enumType,message.syntax)
            var unknown_step=qmacro_block(){}
            if(!empty(unknown_name)){let storage=unknown_name;unknown_step=qmacro_block(){pb_write(result.$f(storage),$v(number),14,number_value)}}
            if(f.repeated){
                if(f.packed==1 || (f.packed==0 && message.syntax!="proto2")){
                    writes |> push <| qmacro_block(){
                        if(!empty(value.$f(name))){
                            var packed:array<uint8>
                            for(item in value.$f(name)){pb_encode(packed,14,int(item))}
                            pb_put_key(data,$v(number),2)
                            pb_put_bytes(data,packed)
                        }
                    }
                }else{writes |> push <| qmacro_block(){for(item in value.$f(name)){pb_write(data,$v(number),14,int(item))}}}
                reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire==2){
                        let packed <- pb_get_bytes(data,pos)
                        var packed_position=0
                        while(packed_position<length(packed)){
                            var number_value=0
                            pb_read(packed,packed_position,14,number_value)
                            if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){$e(unknown_step)}
                            else{emplace(result.$f(name),unsafe(reinterpret<$t(native)>(number_value)))}
                        }
                    }else{
                        if(wire!=0){panic("wrong Protobuf enum wire type")}
                        var number_value=0
                        pb_read(data,pos,14,number_value)
                        if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){$e(unknown_step)}
                        else{emplace(result.$f(name),unsafe(reinterpret<$t(native)>(number_value)))}
                    }
                    matched=true
                }}
            }else{
                if(f.optional){writes |> push <| qmacro_block(){if(value.$f(name) is some){pb_write(data,$v(number),14,int(value.$f(name) as some))}}}
                elif(f.required){writes |> push <| qmacro(pb_write(data,$v(number),14,int(value.$f(name))))}
                else{writes |> push <| qmacro_block(){if(int(value.$f(name))!=0){pb_write(data,$v(number),14,int(value.$f(name)))}}}
                if(f.optional){reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire!=0){panic("wrong Protobuf enum wire type")}
                    var number_value=0;pb_read(data,pos,14,number_value)
                    if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){$e(unknown_step);known_value=false}
                    else{result.$f(name) <- some(unsafe(reinterpret<$t(native)>(number_value)))}
                    matched=true
                }}}
                else{reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire!=0){panic("wrong Protobuf enum wire type")}
                    var number_value=0;pb_read(data,pos,14,number_value)
                    if(!empty($v(closed_values)) && !pb_enum_contains($v(closed_values),number_value)){$e(unknown_step);known_value=false}
                    else{result.$f(name)=unsafe(reinterpret<$t(native)>(number_value))}
                    matched=true
                }}}
            }
        }elif(kind==11 || kind==10){
            let child_name="pb_pack_{elem.structType.name}"
            let reader="pb_unpack_{elem.structType.name}"
            var get_payload=qmacro(pb_get_bytes(data,pos))
            if(kind==10){get_payload=qmacro(pb_get_group(data,pos,$v(number)))}
            if(f.repeated){
                if(kind==10){writes |> push <| qmacro_block(){for(item in value.$f(name)){let nested <- $c(child_name)(item);pb_put_group(data,$v(number),nested)}}}
                else{writes |> push <| qmacro_block(){for(item in value.$f(name)){pb_put_key(data,$v(number),2);let nested <- $c(child_name)(item);pb_put_bytes(data,nested)}}}
                reads |> push <| qmacro_block(){if(field_number==$v(number)){if(wire!=$v(expected)){panic("wrong Protobuf wire type")};let nested <- $e(get_payload);var child <- $c(reader)(nested);emplace(result.$f(name),child);matched=true}}
            }else{
                var step=qmacro_block(){pb_put_key(data,$v(number),2);let nested <- $c(child_name)($e(source));pb_put_bytes(data,nested)}
                if(kind==10){step=qmacro_block(){let nested <- $c(child_name)($e(source));pb_put_group(data,$v(number),nested)}}
                if(f.boxed){writes |> push <| qmacro_block(){if(length(value.$f(name).value)>1){panic("PBRef must hold at most one message")};if(pb_has_ref(value.$f(name))){$e(step)}}}
                elif(f.optional){writes |> push <| qmacro_block(){if(value.$f(name) is some){$e(step)}}}
                else{writes |> push <| step}
                if(f.boxed){reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire!=$v(expected)){panic("wrong Protobuf wire type")}
                    let nested <- $e(get_payload)
                    var child=default<$t(elem)>
                    if(pb_has_ref(result.$f(name))){child <- $c(reader)(pb_concat($c(child_name)(result.$f(name).value[0]),nested))}
                    else{child <- $c(reader)(nested)}
                    result.$f(name) <- pb_move_ref(child)
                    matched=true
                }}}
                elif(f.optional){reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire!=$v(expected)){panic("wrong Protobuf wire type")}
                    let nested <- $e(get_payload)
                    var child=default<$t(elem)>
                    if(result.$f(name) is some){child <- $c(reader)(pb_concat($c(child_name)(result.$f(name) as some),nested))}
                    else{child <- $c(reader)(nested)}
                    result.$f(name) <- move_some(child)
                    matched=true
                }}}
                else{reads |> push <| qmacro_block(){if(field_number==$v(number)){
                    if(wire!=$v(expected)){panic("wrong Protobuf wire type")}
                    let nested <- $e(get_payload)
                    if(key_exists(seen_fields,$v(number))){result.$f(name) <- $c(reader)(pb_concat($c(child_name)(result.$f(name)),nested))}
                    else{result.$f(name) <- $c(reader)(nested)}
                    matched=true
                }}}
            }
        }else{
            if(f.repeated){
                if(expected!=2 && (f.packed==1 || (f.packed==0 && message.syntax!="proto2"))){
                    writes |> push <| qmacro_block(){
                        if(!empty(value.$f(name))){
                            var packed:array<uint8>
                            for(item in value.$f(name)){pb_encode(packed,$v(kind),item)}
                            pb_put_key(data,$v(number),2)
                            pb_put_bytes(data,packed)
                        }
                    }
                }else{writes |> push <| qmacro_block(){for(item in value.$f(name)){pb_write(data,$v(number),$v(kind),item)}}}
                let element=clone_type(elem)
                if(expected!=2){
                    reads |> push <| qmacro_block(){if(field_number==$v(number)){
                        if(wire==2){
                            let packed <- pb_get_bytes(data,pos)
                            var packed_position=0
                            while(packed_position<length(packed)){
                                var item=default<$t(element)>
                                pb_read(packed,packed_position,$v(kind),item)
                                emplace(result.$f(name),item)
                            }
                        }else{
                            if(wire!=$v(expected)){panic("wrong Protobuf wire type")}
                            var item=default<$t(element)>
                            pb_read(data,pos,$v(kind),item)
                            emplace(result.$f(name),item)
                        }
                        matched=true
                    }}
                }else{
                    reads |> push <| qmacro_block(){if(field_number==$v(number)){if(wire!=$v(expected)){panic("wrong Protobuf wire type")};var item=default<$t(element)>;pb_read(data,pos,$v(kind),item);emplace(result.$f(name),item);matched=true}}
                }
            }else{
                let step=qmacro(pb_write(data,$v(number),$v(kind),$e(source)))
                if(f.optional){writes |> push <| qmacro_block(){if(value.$f(name) is some){$e(step)}}}
                elif(f.required){writes |> push <| clone_expression(step)}
                elif(kind==12){writes |> push <| qmacro_block(){if(!empty(value.$f(name))){$e(step)}}}
                else{writes |> push <| qmacro_block(){if(value.$f(name)!=default<$t(payload)>){$e(step)}}}
                let native=clone_type(payload)
                if(f.optional){
                    reads |> push <| qmacro_block(){if(field_number==$v(number)){if(wire!=$v(expected)){panic("wrong Protobuf wire type")};var item=default<$t(native)>;pb_read(data,pos,$v(kind),item);result.$f(name) <- move_some(item);matched=true}}
                }else{
                    reads |> push <| qmacro_block(){if(field_number==$v(number)){if(wire!=$v(expected)){panic("wrong Protobuf wire type")};pb_read(data,pos,$v(kind),result.$f(name));matched=true}}
                }
            }
        }
        emplace(message.fields,f)
    }
    var schema=PBSchema()
    let root_meta <- pb_describe(st)
    schema.syntax=root_meta.syntax
    schema.edition=root_meta.edition
    schema.root_package=root_meta.package_name
    schema.schema_header=root_meta.schema_header
    var seen:table<string;bool>
    pb_collect(st,schema,seen)
    let text=pb_schema_text(schema)
    var required_checks:array<ExpressionPtr>
    for(f in message.fields){
        if(f.required){let id=f.number;required_checks |> push <| qmacro_block(){if(!key_exists(seen_fields,$v(id))){panic("missing required Protobuf field")}}}
    }
    if(!empty(unknown_name)){
        let name=unknown_name
        writes |> push <| qmacro_block(){for(byte in value.$f(name)){push(data,byte)}}
    }
    var pack_fn=qmacro_function("unused") $(value:$t(st)):array<uint8>{var data:array<uint8>;$b(writes);return <- data}
    var read_fn=qmacro_function("unused") $(data:array<uint8>):$t(st){
        var result=default<$t(st)>
        var pos=0
        var seen_fields:table<int;bool>
        while(pos<length(data)){
            let key=pb_get_varint(data,pos)
            let field_number=int(key>>3u)
            let wire=int(key&7ul)
            if(field_number==0){panic("invalid Protobuf field number")}
            var matched=false
            var known_value=true
            $b(reads)
            if(matched && known_value){seen_fields[field_number]=true}
            if(!matched){pb_skip(data,pos,field_number,wire)}
        }
        $b(required_checks)
        return <- result
    }
    if(!empty(unknown_name)){
        let name=unknown_name
        read_fn=qmacro_function("unused") $(data:array<uint8>):$t(st){
            var result=default<$t(st)>
            var pos=0
            var seen_fields:table<int;bool>
            while(pos<length(data)){
                let start=pos
                let key=pb_get_varint(data,pos)
                let field_number=int(key>>3u)
                let wire=int(key&7ul)
                if(field_number==0){panic("invalid Protobuf field number")}
                var matched=false
                var known_value=true
                $b(reads)
                if(matched && known_value){seen_fields[field_number]=true}
                if(!matched){pb_skip(data,pos,field_number,wire);for(i in range(start,pos)){push(result.$f(name),data[i])}}
            }
            $b(required_checks)
            return <- result
        }
    }
    var schema_fn=qmacro_function("unused") $():string{return $v(text)}
    var descriptor_fn=qmacro_function("unused") $():PBMessage{return <- $v(message)}
    let read_name="pb_unpack_{st.name}"
    var verify_fn=qmacro_function("unused") $(data:array<uint8>):bool{
        var valid=false
        try{let decoded <- $c(read_name)(data);valid=true}recover{valid=false}
        return valid
    }
    pb_replace(st,"pb_pack_{st.name}",pack_fn)
    pb_replace(st,"pb_unpack_{st.name}",read_fn)
    pb_replace(st,"pb_schema_{st.name}",schema_fn)
    pb_replace(st,"pb_descriptor_{st.name}",descriptor_fn)
    pb_replace(st,"pb_verify_{st.name}",verify_fn)
    args |> add_annotation_argument("__pb_done",true)
    astChanged=true
    return true
}
[structure_macro(name="pb_message")]
class PBMessageMacro:AstStructureAnnotation{
    def override apply(var st:StructurePtr; var group:ModuleGroup; args:AnnotationArgumentList; var errors:das_string):bool{
        return pb_apply(st,errors)
    }
    def override patch(var st:StructurePtr; var group:ModuleGroup; var args:AnnotationArgumentList; var errors:das_string; var astChanged:bool&):bool{
        return pb_patch(st,args,astChanged)
    }
}
[enumeration_macro(name="pb_enum")]
class PBEnumMacro:AstEnumerationAnnotation{
    def override apply(var enu:EnumerationPtr; var group:ModuleGroup; args:AnnotationArgumentList; var errors:das_string):bool{return true}
}
