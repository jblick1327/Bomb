#include "proof.h"
/* No SDK headers needed; use the installed MSVC CRT and Windows exit function. */
__declspec(dllimport) void __stdcall ExitProcess(unsigned int code);
#define CHECK(condition, code) do { if (!(condition)) ExitProcess(code); } while (0)
#define OFFSET(field) ((bom_u32)(bom_u64)&(((BomProofInfo*)0)->field))
int main(void) {
    BomProofInfo info;
    bom_u64 a=0, b=0, stale=0;
    bom_u32 offsets[7] = {sizeof(info), __alignof(BomProofInfo), OFFSET(struct_size), OFFSET(abi_major), OFFSET(abi_minor), OFFSET(handle_capacity), OFFSET(build_tag)};
    unsigned int i;
    CHECK(sizeof(bom_u32)==4 && sizeof(bom_u64)==8, 10);
    for (i=0;i<7;i++) CHECK(offsets[i]==bom_proof_layout(i), 11);
    CHECK(bom_proof_info(&info)==0 && info.abi_major==1 && info.build_tag==0x424f4d50524f4f46ULL, 12);
    CHECK(bom_proof_create(0)==3 && bom_proof_info(0)==3, 13);
    CHECK(bom_proof_status(0)==1 && bom_proof_destroy(~0ULL)==1, 14);
    for(i=0;i<100;i++) {
        CHECK(bom_proof_create(&a)==0 && bom_proof_create(&b)==0 && a!=b, 15);
        stale=a;
        CHECK(bom_proof_destroy(a)==0 && bom_proof_status(stale)==1, 16);
        CHECK(bom_proof_status(b)==0 && bom_proof_destroy(b)==0, 17);
        CHECK(bom_proof_create(&a)==0 && a!=stale && bom_proof_status(stale)==1, 18);
        CHECK(bom_proof_destroy(a)==0 && bom_proof_destroy(a)==1, 19);
    }
    return 0;
}
