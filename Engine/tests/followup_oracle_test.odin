package main
import "core:testing"
import "core:os"
import "core:fmt"
import "core:strings"
@(test)
followup_decode_oracle :: proc(t:^testing.T) {
 presets:=PRESET_LAYOUTS
 for i in 0..<6 {
  data:[]byte
  if i<5 { data=transmute([]byte)presets[i] } else { data,_=os.read_entire_file("layouts/autosave.json",context.allocator) }
  defer { if i==5 { delete(data) } }
  l,seed,ok,_:=decode_layout(data);testing.expect(t,ok)
  path:=fmt.aprintf("evidence/textures-ui-followup/decode-before/%d.json",i)
  expected,err:=os.read_entire_file(path,context.allocator);testing.expect(t,err==nil)
  actual,encoded:=encode_layout(&l,seed);testing.expect(t,encoded && string(actual)==legacy_test_v3(string(expected)))
  delete(actual);delete(expected);delete(path);destroy_layout(&l)
 }
}

legacy_test_v3 :: proc(data:string)->string { result,_:=strings.replace_all(data,"\"version\": 2","\"version\": 3",context.temp_allocator);return result }
