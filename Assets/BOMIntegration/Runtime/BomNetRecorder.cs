using System;
using System.Globalization;
using System.IO;
using System.Text;
using Bom.Native;

namespace Bom.Unity
{
    // Opt-in network record for the pump-thread A/B (--bom-net-out <file.jsonl>): one JSON line every 100 ms with
    // the native client's stall, input, clock, prediction and pump counters. Read by integration/tools/Measure-BomPumpAB.ps1.
    // Off unless the switch is given; when off it is one bool test.
    public static class BomNetRecorder
    {
        static readonly string Path;
        public static readonly bool On;
        static StreamWriter writer;
        static double nextRow, lastFrame, maxFrame, origin = double.NaN;
        static uint lastStatus = uint.MaxValue;
        static ulong modeSwitches;
        static readonly StringBuilder line = new StringBuilder(512);

        static BomNetRecorder()
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, "--bom-net-out");
            Path = i >= 0 && i + 1 < args.Length ? args[i + 1] : "";
            On = Path.Length > 0;
        }

        public static void Record(BomSession session, double now)
        {
            if (!On || session == null || session.Handle == 0)
                return;
            if (lastFrame > 0)
                maxFrame = Math.Max(maxFrame, (now - lastFrame) * 1000);
            lastFrame = now;
            uint status = session.Prediction.status;
            if (lastStatus != uint.MaxValue && status != lastStatus)
                modeSwitches++;
            lastStatus = status;
            if (now < nextRow)
                return;
            nextRow = now + 0.1;
            var stats = new BomStats
            {
                struct_size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<BomStats>(),
                version = 1,
            };
            if (BomNative.bom_client_get_stats(session.Handle, ref stats) != 0)
                return;
            var p = session.Prediction;
            // Rate check between Unity's timebase and the native QPC clock: drift from the first row.
            double gap = BomSession.Now - BomNative.bom_clock_now();
            if (double.IsNaN(origin))
                origin = gap;
            line.Clear();
            line.Append('{');
            Field("t", now);
            Field("stall_count", stats.stall_count);
            Field("input_count", stats.input_count);
            Field("connection_state", session.Sample.connection_state);
            Field("lead_ticks", p.lead_ticks);
            Field("rtt_ms", p.rtt_seconds * 1000);
            Field("jitter95_ms", p.positive_jitter_p95_seconds * 1000);
            Field("interp_delay_ticks", stats.interp_delay_ticks);
            Field("prediction_status", status);
            Field("prediction_mode_switches", modeSwitches);
            Field("conservative_transitions", p.conservative_transitions);
            Field("recoveries", p.recoveries);
            Field("pump_running", stats.pump_running);
            Field("pump_ticks", stats.pump_ticks);
            Field("pump_late_count", stats.pump_late_count);
            Field("pump_max_gap_ms", stats.pump_max_gap_ms);
            Field("pump_lock_wait_max_ms", stats.pump_lock_wait_max_ms);
            Field("pump_lock_wait_p99_ms", stats.pump_lock_wait_p99_ms);
            Field("main_lock_wait_max_ms", stats.main_lock_wait_max_ms);
            Field("main_lock_wait_p99_ms", stats.main_lock_wait_p99_ms);
            Field("heartbeat_neutral_ticks", stats.heartbeat_neutral_ticks);
            Field("debug_hitches", BomDebugHitch.Count);
            Field("skipped_frames", session.SkippedFrames);
            Field("clock_drift_ms", (gap - origin) * 1000);
            Field("max_frame_ms", maxFrame, last: true);
            line.Append('}');
            maxFrame = 0;
            try
            {
                if (writer == null)
                {
                    Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(Path)));
                    writer = new StreamWriter(Path, false, new UTF8Encoding(false)) { AutoFlush = true };
                }
                writer.WriteLine(line.ToString());
            }
            catch (IOException) { }
        }

        static void Field(string name, double value, bool last = false)
        {
            line.Append('"').Append(name).Append("\":").Append(value.ToString("R", CultureInfo.InvariantCulture));
            if (!last)
                line.Append(',');
        }

        static void Field(string name, ulong value) => line.Append('"').Append(name).Append("\":").Append(value).Append(',');
    }
}
