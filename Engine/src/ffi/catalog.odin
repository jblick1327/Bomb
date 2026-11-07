package ffi
@(export)
bom_client_expect_gameplay_manifest :: proc "c" (handle:u64,hash:[^]u8,length:u32) -> u32 {
 s,status:=get_slot(handle);if status!=OK {return status}
 if s.acquired||s.live {return BUSY}
 if length!=0&&(length!=32||hash==nil) {return BAD_ARGUMENT}
 s.has_expected_manifest=length==32;s.expected_manifest={}
 if length==32 {copy(s.expected_manifest[:],hash[:32])};return OK
}
