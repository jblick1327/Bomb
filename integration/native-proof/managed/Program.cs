using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
struct Info {
    public uint struct_size, abi_major, abi_minor, handle_capacity;
    public ulong build_tag;
}
[StructLayout(LayoutKind.Sequential)]
struct AlignmentProbe { public byte prefix; public Info value; }
static class Native {
    [DllImport("bomproof", CallingConvention=CallingConvention.Cdecl)] internal static extern uint bom_proof_info(out Info info);
    [DllImport("bomproof", CallingConvention=CallingConvention.Cdecl)] internal static extern uint bom_proof_create(out ulong handle);
    [DllImport("bomproof", CallingConvention=CallingConvention.Cdecl)] internal static extern uint bom_proof_status(ulong handle);
    [DllImport("bomproof", CallingConvention=CallingConvention.Cdecl)] internal static extern uint bom_proof_destroy(ulong handle);
    [DllImport("bomproof", CallingConvention=CallingConvention.Cdecl)] internal static extern uint bom_proof_layout(uint field);
}
static class Program {
    static void Check(bool condition) { if (!condition) throw new Exception("Native ABI proof failed"); }
    static void Main() {
        Check(Native.bom_proof_info(out var info)==0 && info.abi_major==1 && info.build_tag==0x424f4d50524f4f46UL);
        string[] fields={nameof(Info.struct_size),nameof(Info.abi_major),nameof(Info.abi_minor),nameof(Info.handle_capacity),nameof(Info.build_tag)};
        Check(Marshal.SizeOf<Info>()==Native.bom_proof_layout(0));
        Check((uint)Marshal.OffsetOf<AlignmentProbe>(nameof(AlignmentProbe.value))==Native.bom_proof_layout(1));
        for(uint i=0;i<fields.Length;i++) Check((uint)Marshal.OffsetOf<Info>(fields[i])==Native.bom_proof_layout(i+2));
        for(int i=0;i<100;i++) {
            Check(Native.bom_proof_create(out var a)==0);
            Check(Native.bom_proof_create(out var b)==0 && a!=b);
            Check(Native.bom_proof_destroy(a)==0 && Native.bom_proof_status(a)==1);
            Check(Native.bom_proof_status(b)==0 && Native.bom_proof_destroy(b)==0);
            Check(Native.bom_proof_create(out var replacement)==0 && replacement!=a && Native.bom_proof_status(a)==1);
            Check(Native.bom_proof_destroy(replacement)==0 && Native.bom_proof_destroy(replacement)==1);
        }
        Check(Native.bom_proof_status(0)==1 && Native.bom_proof_status(ulong.MaxValue)==1);
        Console.WriteLine("PASS: .NET x64 ABI layout, two handles, 100 lifecycle cycles, stale/invalid handles");
    }
}
