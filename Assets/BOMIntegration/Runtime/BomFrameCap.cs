using System;
using UnityEngine;

namespace Bom.Unity
{
    public static class BomFrameCap
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        static void Initialize()
        {
            // Scripted launches own their pacing, regardless of initialization order.
            // Include future --bom-* scenarios/probes without maintaining a flag list.
            // --bom-frame-cap (Start-BomNetwork play sessions) keeps the cap: uncapped windows ran at ~200 fps each
            // and starved the local server of CPU (NPT, 2026-11-24).
            var args = Environment.GetCommandLineArgs();
            if (Array.IndexOf(args, "--bom-frame-cap") < 0)
                foreach (var argument in args)
                    if (argument.StartsWith("--bom-", StringComparison.Ordinal))
                        return;

            // Follow the active display's refresh rate, including display/mode changes.
            QualitySettings.vSyncCount = 1;
            Debug.Log("BOM FRAME CAP vSyncCount=1");
        }
    }
}
