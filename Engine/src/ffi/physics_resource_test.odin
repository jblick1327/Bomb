package ffi
import t "core:testing"
import b2 "vendor:box2d"

@(test)
last_native_handle_detects_unreleased_physics_world_bytes :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 baseline:=b2.GetByteCount();world:=b2.CreateWorld(b2.DefaultWorldDef())
 t.expect(test,b2.GetByteCount()>baseline)
 // Inject an unowned world to prove that the final-handle guard can fail.
 t.expect(test,bom_client_destroy(handle)==IO_ERROR,"unreleased Box2D bytes must fail teardown")
 b2.DestroyWorld(world);t.expect(test,b2.GetByteCount()==baseline)
 t.expect(test,bom_client_create(&info,&handle)==OK&&bom_client_destroy(handle)==OK,"clean subsequent lifetime must return to its baseline")
}
