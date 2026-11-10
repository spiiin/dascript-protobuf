options gen2
module references public
require daslib/templates
require daslib/templates_boost
require daslib/typemacro_boost

// Owning nullable native message reference for recursive declarations.
[template_structure(T)]
struct template PBRef {
    @pb_reference
    value:array<T>
}
def pb_ref(v:auto(T)){
    var result:$PBRef<T -const>
    push_clone(result.value,v)
    return <- result
}
def pb_move_ref(var v:auto(T)){
    var result:$PBRef<T -const>
    emplace(result.value,v)
    return <- result
}
def pb_has_ref(v:$PBRef<auto(T)>):bool=>length(v.value)==1
