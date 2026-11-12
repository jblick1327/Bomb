using System;
using UnityEngine;

namespace Bom.Unity
{
    // Scripted runs (gates, soak, performance and prediction profiles) start players in the background while the
    // owner may be using the machine, so they are muted. Owner launches pass none of these flags and keep sound.
    // Presentation only: the listener volume is the only thing changed.
    public static class BomTestAudioMute
    {
        static readonly string[] ScriptedFlags =
        {
            "-batchmode",
            "--bom-mute",
            "--bom-round-test",
            "--bom-soak",
            "--bom-perf-out",
            "--bom-profile-out",
        };

        public static bool Muted { get; private set; }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Apply()
        {
            string reason = Environment.GetEnvironmentVariable("BOM_MUTE") is string env && env != "" && env != "0"
                ? "BOM_MUTE"
                : null;
            var args = Environment.GetCommandLineArgs();
            foreach (var flag in ScriptedFlags)
                if (reason == null && Array.IndexOf(args, flag) >= 0)
                    reason = flag;
            if (reason == null)
                return;
            Muted = true;
            AudioListener.volume = 0f;
            AudioListener.pause = true;
            Debug.Log("BOM AUDIO muted for scripted run (" + reason + ")");
        }
    }
}
