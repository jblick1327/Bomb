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
            foreach (var argument in Environment.GetCommandLineArgs())
                if (argument.StartsWith("--bom-", StringComparison.Ordinal))
                    return;

            // Follow the active display's refresh rate, including display/mode changes.
            QualitySettings.vSyncCount = 1;
            Debug.Log("BOM FRAME CAP vSyncCount=1");
        }
    }
}
