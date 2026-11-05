package main

import "base:runtime"
import "core:encoding/json"
import "core:reflect"
import "core:strconv"
import "core:strings"

// A local writer for snapshot wire records. No global JSON hooks, so legacy v2
// fixtures and concurrent test encoders retain their original representation.
exact_json_indent :: proc(b: ^strings.Builder,pretty: bool,depth: int) {
 if !pretty { return }
 strings.write_byte(b,'\n')
 for _ in 0..<depth { strings.write_byte(b,'\t') }
}
exact_json_array :: proc(b: ^strings.Builder,data: rawptr,count: int,elem: ^runtime.Type_Info,pretty: bool,depth: int) -> bool {
 strings.write_byte(b,'[')
 for i in 0..<count {
  if i>0 { strings.write_byte(b,',') }
  exact_json_indent(b,pretty,depth+1)
  if !exact_json_value(b,any{rawptr(uintptr(data)+uintptr(i*elem.size)),elem.id},pretty,depth+1) { return false }
 }
 if count>0 { exact_json_indent(b,pretty,depth) }
 strings.write_byte(b,']'); return true
}
exact_json_value :: proc(b: ^strings.Builder,v: any,pretty: bool,depth: int) -> bool {
 if v==nil { strings.write_string(b,"null"); return true }
 ti:=runtime.type_info_base(type_info_of(v.id))
 #partial switch info in ti.variant {
 case runtime.Type_Info_Float:
  if ti.id!=f32 { return false }
  f:=(^f32)(v.data)^
  if !finite(f) { return false }
  // JSON's integer -0 is parsed as integer zero by Odin; force a float token.
  if transmute(u32)f==0x80000000 { strings.write_string(b,"-0.0"); return true }
  buf:[64]byte
  number:=strconv.write_float(buf[:],f64(f),'g',-1,32)
  if len(number)>0 && number[0]=='+' { number=number[1:] }
  strings.write_string(b,number)
 case runtime.Type_Info_Struct:
  strings.write_byte(b,'{'); count:=0
  for name,i in info.names[:info.field_count] {
   tag:=reflect.struct_tag_get(reflect.Struct_Tag(info.tags[i]),"json")
   if tag=="-" { continue }
   key:=name; options:=string("")
   comma:=strings.index_byte(tag,',')
   if comma>=0 { if comma>0 { key=tag[:comma] }; options=tag[comma+1:] }
   else if tag!="" { key=tag }
   field:=any{rawptr(uintptr(v.data)+info.offsets[i]),info.types[i].id}
   if strings.contains(options,"omitempty") && reflect.is_nil(field) { continue }
   if count>0 { strings.write_byte(b,',') }; count+=1
   exact_json_indent(b,pretty,depth+1)
   encoded,err:=json.marshal(key)
   if err!=nil { delete(encoded); return false }
   strings.write_string(b,string(encoded)); delete(encoded)
   strings.write_byte(b,':'); if pretty { strings.write_byte(b,' ') }
   if !exact_json_value(b,field,pretty,depth+1) { return false }
  }
  if count>0 { exact_json_indent(b,pretty,depth) }
  strings.write_byte(b,'}')
 case runtime.Type_Info_Dynamic_Array:
  a:=(^runtime.Raw_Dynamic_Array)(v.data)
  return exact_json_array(b,a.data,a.len,info.elem,pretty,depth)
 case runtime.Type_Info_Slice:
  a:=(^runtime.Raw_Slice)(v.data)
  return exact_json_array(b,a.data,a.len,info.elem,pretty,depth)
 case runtime.Type_Info_Array: return exact_json_array(b,v.data,info.count,info.elem,pretty,depth)
 case runtime.Type_Info_Union: return exact_json_value(b,reflect.get_union_variant(v),pretty,depth)
 case:
  encoded,err:=json.marshal(v)
  defer delete(encoded)
  if err!=nil { return false }
  strings.write_string(b,string(encoded))
 }
 return true
}
exact_json_encode :: proc(v: any,pretty: bool = true) -> ([]byte,bool) {
 b:=strings.builder_make()
 if !exact_json_value(&b,v,pretty,0) { strings.builder_destroy(&b); return nil,false }
 return b.buf[:],true
}

