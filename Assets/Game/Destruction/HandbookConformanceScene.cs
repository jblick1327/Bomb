using System;
using System.Collections;
using System.IO;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public sealed class HandbookConformanceScene : MonoBehaviour
    {
        [SerializeField] private bool runPrimaryDemonstration = true;
        [SerializeField] private bool paused;
        [SerializeField] private string phase;
        public CanonicalSimulationHost Host { get; private set; }
        public ConformanceIds Ids { get; private set; }
        private CanonicalWorldRuntime2D runtime;
        private void Awake()
        {
            var world = HandbookConformanceFixture.Create(out var ids); Ids = ids;
            runtime = new CanonicalWorldRuntime2D();
            if (!runtime.TryRebuild(world,out var error)) throw new InvalidOperationException(error);
            Host = new CanonicalSimulationHost(world,runtime); phase = "Bomb falling; W supports P, K holds P";
        }
        private void FixedUpdate()
        {
            if (paused || Host == null) return;
            if (!Host.Tick(out var error)) { paused = true; phase = "Verification stopped: " + error; Debug.LogError(phase); }
        }
        private IEnumerator Start()
        {
            if (!runPrimaryDemonstration) yield break;
            while (!Host.World.View.Body(Ids.Bomb).Countdown.Active) yield return null;
            paused = true;
            if (!Host.TryCapture(out var before,out var error)) throw new InvalidOperationException(error);
            Save("scene-before.json",before); runtime.Clear(); yield return null;
            if (!Host.TryRecover(before,out error)) throw new InvalidOperationException(error);
            var service = new CanonicalDestructionService(Host.World);
            if (!service.TryExecute(new DestructionRequest(Ids.Platform,HandbookConformanceFixture.Rectangle(-0.25f,2.4f,0.25f,3.6f),Vector2.zero,0),out var result,out error))
                throw new InvalidOperationException(error);
            if (result.Commit.NotificationErrors.Count != 0) throw new AggregateException(result.Commit.NotificationErrors);
            if (!Host.TryCapture(out var after,out error)) throw new InvalidOperationException(error);
            Save("scene-after.json",after); runtime.Clear(); yield return null;
            if (!Host.TryRecover(after,out error)) throw new InvalidOperationException(error);
            phase = "Recovered split: C on left child, L on right; active countdown paused for inspection";
            Debug.Log("Handbook conformance: primary split and both recoveries completed. Temp/ConformanceEvidence contains current-state bundles.");
        }
        [ContextMenu("Continue authoritative simulation")]
        public void ContinueSimulation() { paused = false; phase = "Authoritative simulation resumed"; }
        private static void Save(string filename,string contents)
        { var dir = Path.GetFullPath(Path.Combine(Application.dataPath,"../Temp/ConformanceEvidence")); Directory.CreateDirectory(dir); File.WriteAllText(Path.Combine(dir,filename),contents); }
        private void OnDestroy() { if (Host != null) Host.World.Projection = null; runtime?.Dispose(); }
    }
}
