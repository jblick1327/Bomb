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
[StructLayout(LayoutKind.Sequential)] public struct BomOwnerState {
 public uint struct_size;
 public uint version;
 public uint flags;
 public uint support_kind;
 public ulong connection_incarnation;
 public ulong input_generation;
 public ulong state_tick;
 public ulong topology_revision;
 public ulong finalized_through_tick;
 public ulong last_applied_sequence;
 public ulong last_jump_edge;
 public ulong teleport_serial;
 public ulong support_cell;
 public uint epoch;
 public uint missing_held_ticks;
 public float position_x;
 public float position_y;
 public float velocity_x;
 public float velocity_y;
 public float support_velocity_x;
 public float support_velocity_y;
 public float coyote;
 public float buffered_jump;
 public float held_move;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomPredictionStats {
 public uint struct_size;
 public uint version;
 public uint status;
 public uint reason;
 public ulong input_generation;
 public ulong owner_tick;
 public ulong predicted_tick;
 public ulong finalized_through_tick;
 public ulong last_applied_sequence;
 public double rtt_seconds;
 public double positive_jitter_p95_seconds;
 public double clock_error_ticks;
 public uint lead_ticks;
 public uint pending_commands;
 public ulong correction_count;
 public ulong snap_count;
 public ulong conservative_transitions;
 public ulong recoveries;
 public ulong reset_count;
 public float correction_p95;
 public float correction_p99;
 public float correction_max;
 public float visual_offset_x;
 public float visual_offset_y;
 public float reserved;
 public double conservative_seconds;
}
[StructLayout(LayoutKind.Sequential)] public struct BomRequestResult {
 public uint struct_size;
 public uint version;
 public uint flags;
 public uint kind;
 public ulong request_id;
 public ulong effect_tick;
 public ulong event_id;
 public uint status;
 public uint reason;
}
[StructLayout(LayoutKind.Sequential)] public struct BomLevelInfo {
 public uint flags;
 public uint config_version;
 public float simulation_lo_x;
 public float simulation_lo_y;
 public float simulation_hi_x;
 public float simulation_hi_y;
 public float kill_lo_x;
 public float kill_lo_y;
 public float kill_hi_x;
 public float kill_hi_y;
 public float camera_lo_x;
 public float camera_lo_y;
 public float camera_hi_x;
 public float camera_hi_y;
 public float aim_lo_x;
 public float aim_lo_y;
 public float aim_hi_x;
 public float aim_hi_y;
 public float fragment_cull_lo_x;
 public float fragment_cull_lo_y;
 public float fragment_cull_hi_x;
 public float fragment_cull_hi_y;
 public float bomb_cleanup_lo_x;
 public float bomb_cleanup_lo_y;
 public float bomb_cleanup_hi_x;
 public float bomb_cleanup_hi_y;
 public float spawn0_x;
 public float spawn0_y;
 public float spawn1_x;
 public float spawn1_y;
 public float spawn2_x;
 public float spawn2_y;
 public float spawn3_x;
 public float spawn3_y;
 public float bomb_spawn_lo;
 public float bomb_spawn_hi;
 public float bomb_spawn_height;
 public float gravity_x;
 public float gravity_y;
 public float move_speed;
 public float move_acceleration;
 public float jump_speed;
 public float coyote_time;
 public float jump_buffer;
 public float bomb_fuse;
 public float bomb_drop_min;
 public float bomb_drop_max;
}
[StructLayout(LayoutKind.Sequential)] public struct BomCellBinding {
 public ulong cell_id;
 public ulong source_identity;
 public ulong source_part_id;
 public uint policy_flags;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomSourceBinding {
 public ulong source_identity;
 public uint flags;
 public uint reserved;
 public ulong visual_hash0;
 public ulong visual_hash1;
 public ulong visual_hash2;
 public ulong visual_hash3;
 public float m00;
 public float m10;
 public float m20;
 public float m30;
 public float m01;
 public float m11;
 public float m21;
 public float m31;
 public float m02;
 public float m12;
 public float m22;
 public float m32;
 public float m03;
 public float m13;
 public float m23;
 public float m33;
 public float depth_lo;
 public float depth_hi;
 public IntPtr asset_key;
 public uint asset_key_length;
 public uint cap_key_length;
 public IntPtr cap_key;
}
[StructLayout(LayoutKind.Sequential)] public struct BomCatalogInfo {
 public uint struct_size;
 public uint version;
 public uint epoch;
 public uint flags;
 public ulong revision;
 public ulong catalog_hash0;
 public ulong catalog_hash1;
 public ulong catalog_hash2;
 public ulong catalog_hash3;
 public ulong gameplay_hash0;
 public ulong gameplay_hash1;
 public ulong gameplay_hash2;
 public ulong gameplay_hash3;
 public ulong config_hash0;
 public ulong config_hash1;
 public ulong config_hash2;
 public ulong config_hash3;
 public uint source_count;
 public uint binding_count;
 public IntPtr sources;
 public IntPtr bindings;
 public BomLevelInfo level;
}
[StructLayout(LayoutKind.Sequential)] public struct BomRoundPlayer {
 public ulong session_id;
 public ulong generation;
 public uint slot;
 public uint alive;
 public uint death;
 public uint reserved;
 public ulong death_tick;
 public ulong alive_ticks;
 public ulong bombs_faced;
 public ulong xp_gained;
}
[StructLayout(LayoutKind.Sequential)] public struct BomRoundConnection {
 public ulong session_id;
 public ulong generation;
 public ulong total_xp;
 public ulong wins;
 public ulong level;
 public ulong xp_in_level;
 public ulong xp_to_next;
 public uint flags;
 public uint reserved;
}
[StructLayout(LayoutKind.Sequential)] public struct BomRoundInfo {
 public uint struct_size;
 public uint version;
 public uint epoch;
 public uint rules_version;
 public ulong tick;
 public ulong round_id;
 public ulong countdown_tick;
 public ulong start_tick;
 public ulong end_tick;
 public ulong bombs_spawned;
 public ulong winner;
 public ulong local_session_id;
 public uint mode;
 public uint state;
 public uint draw;
 public uint reason;
 public float lethal_radius;
 public uint flags;
 public IntPtr players;
 public uint player_count;
 public uint connection_count;
 public IntPtr connections;
}
public static class BomNative {
 public const uint AbiVersion = 1;
 public const uint AbiMinorVersion = 4;
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
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_get_owner_state(ulong handle, ref BomOwnerState state);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_get_prediction_stats(ulong handle, ref BomPredictionStats stats);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_set_prediction(ulong handle, uint enabled);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_clear_intent(ulong handle);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_reset_prediction_metrics(ulong handle);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_next_request_result(ulong handle, ulong after_request_id, ref BomRequestResult result);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_expect_gameplay_manifest(ulong handle, IntPtr hash, uint length);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_acquire_catalog(ulong handle, ulong sample_sequence, ref BomCatalogInfo catalog);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_get_round(ulong handle, ulong sample_sequence, ref BomRoundInfo info);
 [DllImport("bomcore", CallingConvention=CallingConvention.Cdecl)] public static extern uint bom_client_set_join_options(ulong handle, uint flags);
}
}
