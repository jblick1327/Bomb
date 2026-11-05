#ifndef BOM_PROOF_H
#define BOM_PROOF_H
/* Windows x64 proof-only ABI. No network functionality. Natural alignment. */
typedef unsigned int bom_u32;
typedef unsigned long long bom_u64;
typedef struct BomProofInfo {
    bom_u32 struct_size, abi_major, abi_minor, handle_capacity;
    bom_u64 build_tag;
} BomProofInfo;
__declspec(dllimport) bom_u32 __cdecl bom_proof_info(BomProofInfo *out);
__declspec(dllimport) bom_u32 __cdecl bom_proof_create(bom_u64 *out);
__declspec(dllimport) bom_u32 __cdecl bom_proof_status(bom_u64 handle);
__declspec(dllimport) bom_u32 __cdecl bom_proof_destroy(bom_u64 handle);
__declspec(dllimport) bom_u32 __cdecl bom_proof_layout(bom_u32 field);
#endif
