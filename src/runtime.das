options gen2
module runtime public
require daslib/fio
require strings
require daslib/strings_boost

struct PBWireField { number:int; wire:int; raw:array<uint8> }

def pb_enum_contains(values:string; number:int):bool{
    for(value in split(values,",")){if(!empty(value) && int(value)==number){return true}}
    return false
}

def pb_put_varint(var out:array<uint8>; value:uint64) {
    var v=value
    while(v>=128ul){push(out,uint8((v&127ul)|128ul));v=v>>7u}
    push(out,uint8(v))
}
def pb_get_varint(data:array<uint8>; var pos:int&) : uint64 {
    var result=0ul
    for(i in range(10)){
        if(pos>=length(data)){panic("Protobuf: truncated varint")}
        let byte=uint64(data[pos]);pos++
        if(i==9 && byte>1ul){panic("Protobuf: varint overflow")}
        result=result|((byte&127ul)<<uint64(i*7))
        if((byte&128ul)==0ul){return result}
    }
    panic("Protobuf: varint overflow")
    return 0ul
}
def pb_put_key(var out:array<uint8>; number,wire:int){
    if(number<1 || number>536870911 || (number>=19000 && number<=19999)){panic("Protobuf: invalid field number")}
    pb_put_varint(out,uint64(number)*8ul+uint64(wire))
}
def pb_wire(kind:int):int=> kind==10 ? 3 : ((kind==1 || kind==6 || kind==16) ? 1 : ((kind==2 || kind==7 || kind==15) ? 5 : ((kind==9 || kind==11 || kind==12 || kind==19 || kind==20) ? 2 : 0)))
def pb_zig32(value:int):uint64=>uint64(uint((value<<1)^(value>>31)))
def pb_zig64(value:int64):uint64=>uint64((value<<1)^(value>>63))
def pb_encode(var out:array<uint8>; kind:int; value:int){
    if(kind==17){pb_put_varint(out,pb_zig32(value))}
    elif(kind==15){pb_put_fixed(out,uint64(uint(value)),4)}
    else{pb_put_varint(out,uint64(int64(value)))}
}
def pb_encode(var out:array<uint8>; kind:int; value:uint){
    if(kind==7){pb_put_fixed(out,uint64(value),4)}else{pb_put_varint(out,uint64(value))}
}
def pb_encode(var out:array<uint8>; kind:int; value:int64){
    if(kind==18){pb_put_varint(out,pb_zig64(value))}
    elif(kind==16){pb_put_fixed(out,uint64(value),8)}
    else{pb_put_varint(out,uint64(value))}
}
def pb_encode(var out:array<uint8>; kind:int; value:uint64){
    if(kind==6){pb_put_fixed(out,value,8)}else{pb_put_varint(out,value)}
}
def pb_encode(var out:array<uint8>; kind:int; value:bool){pb_put_varint(out,value ? 1ul : 0ul)}
def pb_encode(var out:array<uint8>; kind:int; value:float){pb_put_fixed(out,uint64(unsafe(reinterpret<uint>(value))),4)}
def pb_encode(var out:array<uint8>; kind:int; value:double){pb_put_fixed(out,unsafe(reinterpret<uint64>(value)),8)}
def pb_encode(var out:array<uint8>; kind:int; value:string){pb_put_text(out,value)}
def pb_encode(var out:array<uint8>; kind:int; value:array<uint8>){pb_put_bytes(out,value)}
def pb_write(var out:array<uint8>; number,kind:int; value:auto(T)){
    pb_put_key(out,number,pb_wire(kind));pb_encode(out,kind,value)
}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:int&){
    let raw=kind==15 ? pb_get_fixed(data,pos,4) : pb_get_varint(data,pos)
    value=kind==17 ? int((raw>>1u)^uint64(-int64(raw&1ul))) : int(raw)
}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:uint&){value=uint(kind==7 ? pb_get_fixed(data,pos,4) : pb_get_varint(data,pos))}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:int64&){
    let raw=kind==16 ? pb_get_fixed(data,pos,8) : pb_get_varint(data,pos)
    value=kind==18 ? int64((raw>>1u)^uint64(-int64(raw&1ul))) : int64(raw)
}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:uint64&){value=kind==6 ? pb_get_fixed(data,pos,8) : pb_get_varint(data,pos)}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:bool&){value=pb_get_varint(data,pos)!=0ul}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:float&){value=unsafe(reinterpret<float>(uint(pb_get_fixed(data,pos,4))))}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:double&){value=unsafe(reinterpret<double>(pb_get_fixed(data,pos,8)))}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:string&){value=kind==20 ? pb_get_text_unchecked(data,pos) : pb_get_text(data,pos)}
def pb_read(data:array<uint8>; var pos:int&; kind:int; var value:array<uint8>&){value <- pb_get_bytes(data,pos)}
def pb_put_fixed(var out:array<uint8>; value:uint64; width:int){
    for(i in range(width)){push(out,uint8((value>>uint64(i*8))&255ul))}
}
def pb_get_fixed(data:array<uint8>; var pos:int&; width:int):uint64{
    if(width<0 || pos<0 || width>length(data)-pos){panic("Protobuf: truncated fixed value")}
    var value=0ul
    for(i in range(width)){value=value|(uint64(data[pos+i])<<uint64(i*8))}
    pos+=width
    return value
}
def pb_put_bytes(var out:array<uint8>; data:array<uint8>){
    pb_put_varint(out,uint64(length(data)))
    for(byte in data){push(out,byte)}
}
def pb_concat(first,second:array<uint8>):array<uint8>{
    var result:array<uint8>
    for(byte in first){push(result,byte)}
    for(byte in second){push(result,byte)}
    return <- result
}
def pb_put_group(var out:array<uint8>; number:int; body:array<uint8>){
    pb_put_key(out,number,3)
    for(byte in body){push(out,byte)}
    pb_put_key(out,number,4)
}
def pb_get_group(data:array<uint8>; var pos:int&; number:int):array<uint8>{
    let begin=pos
    while(pos<length(data)){
        let field_begin=pos
        let tag=pb_get_varint(data,pos)
        let child_number=int(tag>>3u)
        let wire=int(tag&7ul)
        if(wire==4){
            if(child_number!=number){panic("Protobuf: mismatched end group")}
            var result:array<uint8>
            for(i in range(begin,field_begin)){push(result,data[i])}
            return <- result
        }
        pb_skip(data,pos,child_number,wire)
    }
    panic("Protobuf: unterminated group")
    var missing:array<uint8>
    return <- missing
}
def pb_put_text(var out:array<uint8>; value:string){
    pb_put_varint(out,uint64(length(value)))
    peek_data(value) $(bytes){for(byte in bytes){push(out,byte)}}
}
def pb_get_bytes(data:array<uint8>; var pos:int&):array<uint8>{
    let count=pb_get_varint(data,pos)
    if(count>uint64(length(data)-pos)){panic("Protobuf: truncated bytes")}
    var result:array<uint8>
    for(i in range(int(count))){push(result,data[pos+i])}
    pos+=int(count)
    return <- result
}
def pb_check_utf8(data:array<uint8>){
    var i=0
    while(i<length(data)){
        let first=uint(data[i]);i++
        if(first<128u){continue}
        var more=0
        var codepoint=0u
        var minimum=0u
        if(first>=194u && first<=223u){more=1;codepoint=first&31u;minimum=128u}
        elif(first>=224u && first<=239u){more=2;codepoint=first&15u;minimum=2048u}
        elif(first>=240u && first<=244u){more=3;codepoint=first&7u;minimum=65536u}
        else{panic("Protobuf: invalid UTF-8")}
        if(more>length(data)-i){panic("Protobuf: truncated UTF-8")}
        for(j in range(more)){
            let next=uint(data[i]);i++
            if((next&192u)!=128u){panic("Protobuf: invalid UTF-8")}
            codepoint=(codepoint<<6u)|(next&63u)
        }
        if(codepoint<minimum || codepoint>1114111u || (codepoint>=55296u && codepoint<=57343u)){panic("Protobuf: invalid UTF-8")}
    }
}
def pb_get_text(data:array<uint8>; var pos:int&):string{
    let bytes <- pb_get_bytes(data,pos)
    pb_check_utf8(bytes)
    return string(bytes)
}
def pb_get_text_unchecked(data:array<uint8>; var pos:int&):string{
    let bytes <- pb_get_bytes(data,pos)
    return string(bytes)
}
def pb_skip(data:array<uint8>; var pos:int&; wire:int){
    if(wire==0){pb_get_varint(data,pos);return}
    if(wire==1){pb_get_fixed(data,pos,8);return}
    if(wire==2){let count=pb_get_varint(data,pos);if(count>uint64(length(data)-pos)){panic("Protobuf: truncated field")};pos+=int(count);return}
    if(wire==5){pb_get_fixed(data,pos,4);return}
    panic("Protobuf: unsupported wire type")
}
def pb_skip(data:array<uint8>; var pos:int&; number,wire:int; depth:int=0){
    if(wire==3){
        if(depth>=64){panic("Protobuf: group nesting limit")}
        while(pos<length(data)){
            let tag=pb_get_varint(data,pos)
            let child_number=int(tag>>3u)
            let child_wire=int(tag&7ul)
            if(child_number<1 || child_number>536870911){panic("Protobuf: invalid group field")}
            if(child_wire==4){
                if(child_number!=number){panic("Protobuf: mismatched end group")}
                return
            }
            pb_skip(data,pos,child_number,child_wire,depth+1)
        }
        panic("Protobuf: unterminated group")
    }
    if(wire==4){panic("Protobuf: unexpected end group")}
    pb_skip(data,pos,wire)
}
def pb_scan_fields(data:array<uint8>):array<PBWireField>{
    var fields:array<PBWireField>
    var pos=0
    while(pos<length(data)){
        let begin=pos
        let tag=pb_get_varint(data,pos)
        let number=int(tag>>3u)
        let wire=int(tag&7ul)
        if(number<1 || number>536870911){panic("Protobuf: invalid field number")}
        pb_skip(data,pos,number,wire)
        var field=PBWireField(number=number,wire=wire)
        for(i in range(begin,pos)){push(field.raw,data[i])}
        emplace(fields,field)
    }
    return <- fields
}
def pb_load(path:string):array<uint8>{
    var result:array<uint8>
    fopen(path,"rb") $(f){
        if(f==null){panic("cannot open {path}")}
        fseek(f,0l,2)
        let size=int(ftell(f))
        fseek(f,0l,0)
        resize(result,size)
        if(size>0 && fread(f,result)!=size){panic("short read")}
    }
    return <- result
}
def pb_save(path:string; data:array<uint8>){
    fopen(path,"wb") $(f){
        if(f==null || (!empty(data) && fwrite(f,data)!=length(data))){panic("cannot write {path}")}
    }
}
