// Generated from bom-abi.json. No network codec exists in managed code.
using System;
using System.Runtime.InteropServices;
namespace Bom.Native {
[StructLayout(LayoutKind.Sequential)] public struct BomCreateInfo {
 public uint struct_size;
 public uint version;
 public uint flags;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomConnectInfo {
 public uint struct_size;
 public uint version;
 public uint ipv4;
 public uint port;
 public IntPtr token;
 public uint token_length;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomVertex {
 public float x;
 public float y;
}
[StructLayout(LayoutKind.Sequential)] public struct BomCell {
 public ulong id;
 public ulong piece_id;
 public uint material;
 public uint pose_kind;
 public float rest_x;
 public float rest_y;
 public float pivot_x;
 public float pivot_y;
 public uint vertex_start;
 public uint vertex_count;
 public uint color_rgba;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomPose {
 public ulong id;
 public uint kind;
 public uint flags;
 public float x;
 public float y;
 public float angle;
 public float fuse;
}
[StructLayout(LayoutKind.Sequential)] public struct BomEvent {
 public ulong id;
 public ulong tick;
 public uint kind;
 public uint reserved;
 public float x;
 public float y;
 public float radius;
 public uint padding;
}
[StructLayout(LayoutKind.Sequential)] public struct BomSample {
 public uint struct_size;
 public uint version;
 public ulong connection_generation;
 public uint epoch;
 public uint connection_state;
 public ulong revision;
 public ulong sample_sequence;
 public double presentation_tick;
 public ulong canonical_hash;
 public ulong input_count;
 public ulong stall_count;
 public uint local_player_id;
 public uint flags;
 public uint cell_count;
 public uint vertex_count;
 public uint pose_count;
 public uint event_count;
 public IntPtr cells;
 public IntPtr vertices;
 public IntPtr poses;
 public IntPtr events;
 public IntPtr error_text;
 public uint error_length;
 public uint reserved;
 public uint received_epoch;
 public uint received_flags;
 public ulong received_revision;
 public ulong transaction_id;
 public ulong effective_tick;
 public ulong from_revision;
 public ulong to_revision;
 public uint transaction_flags;
 public uint catalog_revision;
 public ulong catalog_hash;
 public uint owner_prediction_status;
 public uint round_state;
}
[StructLayout(LayoutKind.Sequential)] public struct BomBuildInfo {
 public uint struct_size;
 public uint version;
 public uint abi_major;
 public uint abi_minor;
 public uint game_protocol;
 public uint canonical_version;
 public ulong source_build_tag;
 public IntPtr game_build;
 public uint game_build_length;
 public uint reserved0;
 public IntPtr compiler_version;
 public uint compiler_version_length;
 public uint reserved1;
 public IntPtr compiler_hash;
 public uint compiler_hash_length;
 public uint reserved2;
}
[StructLayout(LayoutKind.Sequential)] public struct BomStats {
 public uint struct_size;
 public uint version;
 public ulong connection_generation;
 public ulong input_count;
 public ulong stall_count;
 public double presentation_tick;
 public double fixed_tick;
 public uint held_queued;
 public uint jumps_queued;
 public uint actions_queued;
 public uint events_queued;
 public uint reliable_queued;
 public uint structure_errors;
 public uint frames_complete;
 public uint flags;
 public ulong owned_bytes;
 public ulong peak_owned_bytes;
 public ulong live_allocations;
}
[StructLayout(LayoutKind.Sequential)] public struct BomError {
 public uint struct_size;
 public uint version;
 public IntPtr message;
 public uint message_length;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomHostCommand {
 public uint struct_size;
 public uint version;
 public uint op;
 public uint mode;
 public float radius;
 public uint reserved;
 public IntPtr layout;
 public uint layout_length;
 public uint reserved1;
}
[StructLayout(LayoutKind.Sequential)] public struct BomCommandResult {
 public uint struct_size;
 public uint version;
 public ulong command_id;
 public uint status;
 public uint reason_length;
 public IntPtr reason;
}
[StructLayout(LayoutKind.Sequential)] public struct BomActorShapeInfo {
 public uint struct_size;
 public uint version;
 public float player_radius;
 public float player_segment;
 public float bomb_radius;
 public uint reserved;
}
public static class BomNative {
 public const uint AbiVersion = 1;
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_abi_version();
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern ulong bom_build_tag();
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_create(ref BomCreateInfo info, ref ulong handle);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_destroy(ulong handle);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_connect(ulong handle, ref BomConnectInfo info);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_disconnect(ulong handle);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_set_held_input(ulong handle, double timestamp, float move);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_enqueue_jump(ulong handle, double timestamp);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_enqueue_action(ulong handle, double timestamp, float x, float y);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_update(ulong handle, double now);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_acquire_sample(ulong handle, ref BomSample sample);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_release_sample(ulong handle, ulong sequence);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_ack_sample(ulong handle, ulong sequence);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_host_command(ulong handle, uint op, uint mode, float radius);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_debug_layout(uint type_id, uint field_id);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_build_info(ref BomBuildInfo info);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_get_stats(ulong handle, ref BomStats stats);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_last_error(ulong handle, ref BomError error);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_request_host_command(ulong handle, ref BomHostCommand command, ref ulong command_id);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_get_command_result(ulong handle, ref BomCommandResult result);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_actor_shape_info(ref BomActorShapeInfo info);
}
}
