options gen2
require ./runtime.das
require fio_core

// Supply distinct scratch paths for concurrent calls. The Python helper uses grpcio
// for HTTP/2 framing, TLS, deadlines, and streaming.
struct PBGrpcTransport {
    python:string
    helper:string
    target:string
    request_path:string
    response_path:string
    timeout:float = 10.0
    tls:bool = false
    root_cert:string = ""
    server_name:string = ""
    metadata:array<string>
}

def pb_grpc_frames_save(path:string; frames:array<array<uint8>>){
    var bytes:array<uint8>
    for(frame in frames){
        pb_put_fixed(bytes,uint64(length(frame)),4)
        for(value in frame){push(bytes,value)}
    }
    pb_save(path,bytes)
}

def pb_grpc_frames_load(path:string):array<array<uint8>>{
    let bytes <- pb_load(path)
    var result:array<array<uint8>>
    var pos=0
    while(pos<length(bytes)){
        if(length(bytes)-pos<4){panic("gRPC transport: truncated frame length")}
        let size=pb_get_fixed(bytes,pos,4)
        if(size>uint64(length(bytes)-pos)){panic("gRPC transport: truncated frame body")}
        var frame:array<uint8>
        for(i in range(int(size))){push(frame,bytes[pos+i])}
        pos+=int(size)
        emplace(result,frame)
    }
    return <- result
}

def pb_grpc_call(config:PBGrpcTransport; shape,method:string; requests:array<array<uint8>>):array<array<uint8>>{
    pb_grpc_frames_save(config.request_path,requests)
    var args:array<string>
    push(args,config.python)
    push(args,config.helper)
    push(args,"--target");push(args,config.target)
    push(args,"--shape");push(args,shape)
    push(args,"--method");push(args,method)
    push(args,"--input");push(args,config.request_path)
    push(args,"--output");push(args,config.response_path)
    push(args,"--timeout");push(args,"{config.timeout}")
    if(config.tls){push(args,"--tls")}
    if(!empty(config.root_cert)){push(args,"--root-cert");push(args,config.root_cert)}
    if(!empty(config.server_name)){push(args,"--server-name");push(args,config.server_name)}
    for(item in config.metadata){push(args,"--metadata");push(args,item)}
    let exit_code=unsafe(popen_argv(args,config.timeout+5.0,$(f){
        while(!feof(f)){
            let line=fgets(f)
            if(!empty(line)){print(line)}
        }
    }))
    if(exit_code!=0){panic("gRPC transport failed: exit code {int(exit_code)}")}
    return <- pb_grpc_frames_load(config.response_path)
}

def pb_grpc_unary(config:PBGrpcTransport; method:string; payload:array<uint8>):array<uint8>{
    var requests:array<array<uint8>>
    emplace(requests,clone(payload))
    let responses <- pb_grpc_call(config,"unary",method,requests)
    if(length(responses)!=1){panic("gRPC unary RPC requires one response")}
    return <- clone(responses[0])
}

def pb_grpc_stream(config:PBGrpcTransport; shape,method:string; payloads:array<array<uint8>>):array<array<uint8>>{
    return <- pb_grpc_call(config,shape,method,payloads)
}
