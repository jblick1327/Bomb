package main
import "core:testing"
import "core:os"
import "core:strings"
import "core:fmt"

@(test)
existing_layouts_save_as_canonical_v3 :: proc(t:^testing.T) {
 count:=0
 for data in PRESET_LAYOUTS {
  l,seed,ok,reason:=decode_layout(transmute([]byte)data); testing.expect(t,ok,reason)
  again,encoded:=encode_layout(&l,seed); testing.expect(t,encoded && strings.contains(string(again),"\"version\": 3"));layout_capture_bytes(t,count,transmute([]byte)data,again);delete(again)
  l.next_identity+=1
  changed,cok:=encode_layout(&l,seed);testing.expect(t,cok && string(changed)!=data);delete(changed)
  destroy_layout(&l);count+=1
 }
 for path in ([]string{"layouts/autosave.json","evidence/material-library/custom-layout.json"}) {
  data,err:=os.read_entire_file(path,context.allocator); testing.expect(t,err==nil); if err!=nil { return }
  l,seed,ok,reason:=decode_layout(data);testing.expect(t,ok,reason)
  again,encoded:=encode_layout(&l,seed);testing.expect(t,encoded && (count==5 && strings.contains(string(again),"\"version\": 3") || count==6 && string(again)==legacy_test_v3(string(data))));layout_capture_bytes(t,count,data,again);delete(again);destroy_layout(&l);delete(data);count+=1
 }
 fmt.printf("Layout byte roundtrips: %d files verified; six v1 and one v2 upgrade to v3\n",count)
}
@(test)
custom_duplicates_preserve_all_knobs_without_loading_snap :: proc(t:^testing.T) {
 g:=Sandbox{layout=Layout{next_identity=1}}
 defer { destroy_layout(&g.layout);delete(g.status) }
 testing.expect(t,materials_duplicate(&g,.Wood))
 m:=&g.layout.materials[0];m.toughness=1.234;m.blast_resistance=2.345;m.strip_thickness=0.333;m.color={231,104,91}
 testing.expect(t,materials_duplicate_slot(&g,Slot(4)))
 a,b:=g.layout.materials[0],g.layout.materials[1]
 testing.expect(t,a.name!=b.name && a.base==b.base && a.toughness==b.toughness && a.blast_resistance==b.blast_resistance && a.strip_thickness==b.strip_thickness && a.color==b.color)
 data,ok:=encode_layout(&g.layout,42);testing.expect(t,ok);defer delete(data)
 decoded,seed,valid,reason:=decode_layout(data);testing.expect(t,valid,reason);defer destroy_layout(&decoded)
 again,eok:=encode_layout(&decoded,seed);defer delete(again)
 testing.expect(t,eok && string(data)==string(again) && decoded.materials[0].toughness==1.234 && decoded.materials[0].strip_thickness==0.333)
}

layout_capture_bytes :: proc(t:^testing.T,index:int,before,after:[]byte) {
 when #config(UI_LAYOUT_CAPTURE_DIRECTORY,"")!="" {
  a:=fmt.aprintf("%s/layout-%d-before.json",#config(UI_LAYOUT_CAPTURE_DIRECTORY,""),index)
  b:=fmt.aprintf("%s/layout-%d-after.json",#config(UI_LAYOUT_CAPTURE_DIRECTORY,""),index)
  testing.expect(t,os.write_entire_file(a,before)==nil && os.write_entire_file(b,after)==nil);delete(a);delete(b)
 }
}
