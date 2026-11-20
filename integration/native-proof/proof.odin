package proof

import "base:runtime"

// M1 boundary proof only. No game/network client is implemented here.
Proof_Info :: struct {
    struct_size, abi_major, abi_minor, handle_capacity: u32,
    build_tag: u64,
}
generations: [16]u32
active: [16]bool

@(export)
bom_proof_info :: proc "c" (out: ^Proof_Info) -> u32 {
    if out == nil { return 3 }
    out^ = Proof_Info{u32(size_of(Proof_Info)), 1, 0, 16, 0x424f4d50524f4f46}
    return 0
}

@(export)
bom_proof_create :: proc "c" (out: ^u64) -> u32 {
    context = runtime.default_context()
    if out == nil { return 3 }
    out^ = 0
    for i in 0..<len(active) {
        if !active[i] {
            generations[i] += 1
            if generations[i] == 0 { generations[i] = 1 }
            active[i] = true
            out^ = (u64(generations[i]) << 32) | u64(i+1)
            return 0
        }
    }
    return 2
}

proof_index :: proc "contextless" (handle: u64) -> (int, bool) {
    index := u32(handle & 0xffffffff)
    generation := u32(handle >> 32)
    if index == 0 || index > u32(len(active)) || generation == 0 { return 0, false }
    i := int(index-1)
    return i, active[i] && generations[i] == generation
}

@(export)
bom_proof_status :: proc "c" (handle: u64) -> u32 {
    _, valid := proof_index(handle)
    if !valid { return 1 }
    return 0
}

@(export)
bom_proof_destroy :: proc "c" (handle: u64) -> u32 {
    i, valid := proof_index(handle)
    if !valid { return 1 }
    active[i] = false
    return 0
}

@(export)
bom_proof_layout :: proc "c" (field: u32) -> u32 {
    switch field {
    case 0: return u32(size_of(Proof_Info))
    case 1: return u32(align_of(Proof_Info))
    case 2: return u32(offset_of(Proof_Info, struct_size))
    case 3: return u32(offset_of(Proof_Info, abi_major))
    case 4: return u32(offset_of(Proof_Info, abi_minor))
    case 5: return u32(offset_of(Proof_Info, handle_capacity))
    case 6: return u32(offset_of(Proof_Info, build_tag))
    }
    return 0xffffffff
}
