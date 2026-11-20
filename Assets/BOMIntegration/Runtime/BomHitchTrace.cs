using System;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using UnityEngine;
using UnityEngine.InputSystem;
using Debug = UnityEngine.Debug;

namespace Bom.Unity
{
    // G2b opt-in timing (--bom-hitch-trace): laps inside the blast handler and the topology apply, input-system update
    // cost, and every frame over 25 ms, all stamped with the frame number. Off by default; when off every call is one
    // bool test and allocates nothing.
    [DefaultExecutionOrder(-30000)]
    public sealed class BomHitchTrace : MonoBehaviour
    {
        public static readonly bool On = Array.IndexOf(Environment.GetCommandLineArgs(), "--bom-hitch-trace") >= 0;
        static readonly StringBuilder line = new StringBuilder(256);
        static long lap, inputStart, inputEnd, inputSum, lastLate, updateAt, renderAt;
        static string scope;
        static bool listed;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Install()
        {
            if (!On)
                return;
            var obj = new GameObject("BOM hitch trace");
            DontDestroyOnLoad(obj);
            obj.AddComponent<BomHitchTrace>();
            Application.onBeforeRender += () => renderAt = Stopwatch.GetTimestamp();
            InputSystem.onBeforeUpdate += () => inputStart = Stopwatch.GetTimestamp();
            InputSystem.onAfterUpdate += () =>
            {
                inputEnd = Stopwatch.GetTimestamp();
                inputSum += inputEnd - inputStart;
                double ms = Ms(inputStart);
                if (ms > 2)
                    Debug.Log("BOM HITCH input frame=" + Time.frameCount + " ms=" + F(ms));
            };
            InstallLoopMarkers();
            Debug.Log("BOM HITCH ON");
        }

        void Update()
        {
            updateAt = Stopwatch.GetTimestamp();
            float dt = Time.unscaledDeltaTime * 1000;
            if (dt > 25)
                Debug.Log("BOM HITCH slow frame=" + Time.frameCount + " dt_ms=" + F(dt) + " t=" + F(Time.realtimeSinceStartupAsDouble));
        }

        // Last LateUpdate of the frame (the perf probe samples at order 1000): split the wall time since the previous
        // one into render/present wait, input, and script update, for frames over 25 ms.
        void LateUpdate()
        {
            long now = Stopwatch.GetTimestamp();
            if (lastLate != 0 && (now - lastLate) * 1000.0 / Stopwatch.Frequency > 25)
                Debug.Log(
                    "BOM HITCH wall frame=" + Time.frameCount + " total=" + F((now - lastLate) * 1000.0 / Stopwatch.Frequency)
                        + " to_render=" + F((renderAt - lastLate) * 1000.0 / Stopwatch.Frequency)
                        + " render_to_input=" + F((inputStart - renderAt) * 1000.0 / Stopwatch.Frequency)
                        + " input_sum=" + F(inputSum * 1000.0 / Stopwatch.Frequency)
                        + " input_to_update=" + F((updateAt - inputEnd) * 1000.0 / Stopwatch.Frequency)
                        + " update_to_late=" + F((now - updateAt) * 1000.0 / Stopwatch.Frequency)
                        + " slowest(prev frame tail + this frame):" + SlowestSteps()
                );
            if (!listed && inputSum * 1000.0 / Stopwatch.Frequency > 2 && Time.frameCount > 600)
            {
                listed = true;
                var names = new System.Collections.Generic.SortedSet<string>();
                foreach (var b in FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None))
                    if (b.isActiveAndEnabled)
                        names.Add(b.GetType().FullName);
                Debug.Log("BOM HITCH behaviours " + string.Join(",", names));
            }
            inputSum = 0;
            lastLate = Stopwatch.GetTimestamp();
        }

        void OnApplicationFocus(bool focus) => Debug.Log("BOM HITCH focus=" + focus + " frame=" + Time.frameCount);

        public static void Begin(string name)
        {
            if (!On)
                return;
            scope = name;
            line.Clear().Append("BOM HITCH ").Append(name).Append(" frame=").Append(Time.frameCount);
            lap = Stopwatch.GetTimestamp();
        }

        public static void Lap(string name)
        {
            if (!On || scope == null)
                return;
            long now = Stopwatch.GetTimestamp();
            line.Append(' ').Append(name).Append('=').Append(F((now - lap) * 1000.0 / Stopwatch.Frequency));
            lap = Stopwatch.GetTimestamp();
        }

        public static void End(string name)
        {
            if (!On || scope == null)
                return;
            Lap(name);
            scope = null;
            Debug.Log(line.ToString());
        }

        public static void Section(string name, long from)
        {
            if (On && Ms(from) > 2)
                Debug.Log("BOM HITCH section " + name + " frame=" + Time.frameCount + " ms=" + F(Ms(from)));
        }

        // A timestamp before every player-loop subsystem; on a slow frame the slowest gaps are logged by name.
        static string[] markNames = new string[0];
        static long[] markTimes = new long[0];
        static int[] markFrame = new int[0];

        static void InstallLoopMarkers()
        {
            var loop = UnityEngine.LowLevel.PlayerLoop.GetCurrentPlayerLoop();
            var names = new System.Collections.Generic.List<string>();
            var phases = loop.subSystemList;
            for (int p = 0; p < phases.Length; p++)
            {
                var subs = phases[p].subSystemList ?? new UnityEngine.LowLevel.PlayerLoopSystem[0];
                var next = new System.Collections.Generic.List<UnityEngine.LowLevel.PlayerLoopSystem>();
                foreach (var sub in subs)
                {
                    next.Add(Marker(names, phases[p].type.Name + "." + (sub.type != null ? sub.type.Name : "?")));
                    next.Add(sub);
                }
                next.Add(Marker(names, phases[p].type.Name + ".end"));
                phases[p].subSystemList = next.ToArray();
            }
            loop.subSystemList = phases;
            markNames = names.ToArray();
            markTimes = new long[markNames.Length];
            markFrame = new int[markNames.Length];
            UnityEngine.LowLevel.PlayerLoop.SetPlayerLoop(loop);
        }

        static UnityEngine.LowLevel.PlayerLoopSystem Marker(System.Collections.Generic.List<string> names, string name)
        {
            int index = names.Count;
            names.Add(name);
            return new UnityEngine.LowLevel.PlayerLoopSystem
            {
                type = typeof(BomHitchTrace),
                updateDelegate = () =>
                {
                    markTimes[index] = Stopwatch.GetTimestamp();
                    markFrame[index] = Time.frameCount;
                },
            };
        }

        // Called on a slow frame: the 4 largest gaps between consecutive markers (gap i = time spent in subsystem i).
        static string SlowestSteps()
        {
            var sb = new StringBuilder();
            var used = new bool[markNames.Length];
            for (int k = 0; k < 4; k++)
            {
                int best = -1;
                long bestGap = 0;
                for (int i = 0; i + 1 < markNames.Length; i++)
                {
                    long gap = markTimes[i + 1] - markTimes[i];
                    if (!used[i] && markFrame[i] == markFrame[i + 1] && gap > bestGap)
                    {
                        best = i;
                        bestGap = gap;
                    }
                }
                if (best < 0)
                    break;
                used[best] = true;
                sb.Append(' ').Append(markNames[best]).Append('=').Append(F(bestGap * 1000.0 / Stopwatch.Frequency));
            }
            return sb.ToString();
        }

        public static long BuildTicks;
        public static int NewBodies;

        public static void Note(string name, long ticks, int count)
        {
            if (!On || scope == null)
                return;
            line.Append(' ').Append(name).Append('=').Append(F(ticks * 1000.0 / Stopwatch.Frequency)).Append('/').Append(count);
        }

        static double Ms(long from) => (Stopwatch.GetTimestamp() - from) * 1000.0 / Stopwatch.Frequency;

        static string F(double v) => v.ToString("0.00", CultureInfo.InvariantCulture);
    }
}
