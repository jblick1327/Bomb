using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

public static class VerifyFoundation
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Verification needs Play mode.");
        var session = UnityEngine.Object.FindFirstObjectByType<ArenaSession>();
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var dropper = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        var layout = UnityEngine.Object.FindFirstObjectByType<ArenaLayout>();
        var player = UnityEngine.Object.FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);
        var inputBehavior = InputSystem.settings.editorInputBehaviorInPlayMode;
        var inputBackground = InputSystem.settings.backgroundBehavior;
        InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        var keyboard = InputSystem.AddDevice<Keyboard>();
        var settings = new SerializedObject(dropper);
        float originalRadius = settings.FindProperty("craterRadius").floatValue;
        float originalLethal = settings.FindProperty("lethalRadius").floatValue;
        int originalShape = settings.FindProperty("craterShape").enumValueIndex;
        try
        {
            session.RestartRound();
            Require(ground.BoundaryEdgeCount == 4, "Untouched ground must have exactly four exposed edges.");
            Set(settings, "craterRadius", 0.8f);
            settings.FindProperty("craterShape").enumValueIndex = 0;
            settings.ApplyModifiedPropertiesWithoutUndo();
            ground.Carve(dropper.CreateCraterOutline(new Vector2(0f, 3f)));
            Require(ground.BoundaryEdgeCount == settings.FindProperty("craterSegments").intValue + 4,
                "Enclosed contour edge count is wrong. Edges=" + ground.BoundaryEdgeCount + "; segments=" + settings.FindProperty("craterSegments").intValue);
            Require(!ground.ContainsSolid(new Vector2(0f, 3f)) && ground.ContainsSolid(new Vector2(0f, 4f)), "Enclosed hole altered the wrong region.");
            Require(!Physics.Raycast(new Vector3(0f, 3f, -10f), Vector3.forward, out var holeHit, 12f)
                || holeHit.collider != ground.GetComponent<MeshCollider>(), "Enclosed hole still has a solid collider front.");

            ground.ResetGround();
            var cuts = new List<(Vector2 center, float radius)>();
            var random = new System.Random(7319);
            double totalMs = 0f;
            double worstMs = 0f;
            int peakVertices = 0;
            int peakPieces = 0;
            var timer = new Stopwatch();
            const int stressCuts = 20;
            for (int i = 0; i < stressCuts; i++)
            {
                float radius = 0.35f + (float)random.NextDouble() * 0.85f;
                Vector2 center = new Vector2(-9.4f + (float)random.NextDouble() * 18.8f, 0f + (float)random.NextDouble() * 6.2f);
                Set(settings, "craterRadius", radius);
                Vector2[] outline = dropper.CreateCraterOutline(center);
                timer.Restart();
                ground.Carve(outline);
                timer.Stop();
                totalMs += timer.Elapsed.TotalMilliseconds;
                worstMs = Math.Max(worstMs, timer.Elapsed.TotalMilliseconds);
                peakVertices = Math.Max(peakVertices, ground.VertexCount);
                peakPieces = Math.Max(peakPieces, ground.SolidPieceCount);
                cuts.Add((center, radius));
                for (int sample = 0; sample < 8; sample++)
                {
                    Vector2 point = new Vector2(-9.9f + (float)random.NextDouble() * 19.8f, -0.5f + (float)random.NextDouble() * 6.4f);
                    bool safelyRemoved = false;
                    bool safelySolid = true;
                    foreach (var cut in cuts)
                    {
                        float distance = Vector2.Distance(point, cut.center);
                        if (distance < cut.radius * 0.98f) safelyRemoved = true;
                        if (distance < cut.radius + 0.08f) safelySolid = false;
                    }
                    if (safelyRemoved) Require(!ground.ContainsSolid(point), "Overlapping cuts restored previously removed terrain.");
                    if (safelySolid) Require(ground.ContainsSolid(point), "Stress cuts removed unrelated solid terrain.");
                }
            }

            session.RestartRound();
            Set(settings, "craterRadius", 4f);
            Set(settings, "lethalRadius", 1f);
            dropper.Explode(new Vector2(-7f, 6f));
            var blast = UnityEngine.Object.FindFirstObjectByType<BombBlastVisual>();
            float visualRadius = (float)typeof(BombBlastVisual).GetField("radius", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(blast);
            Require(Mathf.Abs(visualRadius - 1f) < 0.001f, "Blast visual must match lethal radius even when crater is larger.");
            Vector3 expectedScreen = Camera.main.WorldToViewportPoint(new Vector3(-7f, 6f, layout.Origin.z));
            Vector3 actualScreen = Camera.main.WorldToViewportPoint(blast.transform.position);
            Require(Vector2.Distance(expectedScreen, actualScreen) < 0.001f, "Tilted camera offsets blast ring from the actual explosion.");

            session.RestartRound();
            Set(settings, "lethalRadius", 2.2f);
            Vector2 playerCenter = player.transform.position;
            dropper.Explode(playerCenter + Vector2.right * 2.7f);
            Require(session.IsPlaying, "Player body outside lethal radius was killed.");
            dropper.Explode(playerCenter + Vector2.right * 2.5f);
            Require(!session.IsPlaying && !player.gameObject.activeSelf, "Blast touching the player's capsule must kill them.");
            Require(dropper.DropBomb() == null, "Dead round must reject bomb drops.");
            Require(GameObject.Find("Death Panel") != null, "Death message must be visible.");

            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.R));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            typeof(ArenaSession).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(session, null);
            Require(session.IsPlaying && player.gameObject.activeSelf && player.transform.position == layout.PlayerSpawn,
                "R must restart the round at the shared spawn position.");
            Require(ground.BoundaryEdgeCount == 4 && ground.ContainsSolid(new Vector2(0f, 5.9f)), "Restart must fully restore terrain.");
            Require(GameObject.Find("Death Panel") == null, "Restart must hide the death message.");
            Require(UnityEngine.Object.FindObjectsByType<FallingBomb>(FindObjectsSortMode.None).Length == 0
                && UnityEngine.Object.FindObjectsByType<BombBlastVisual>(FindObjectsSortMode.None).Length == 0,
                "Restart must immediately clear bombs and effects.");
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            for (int i = 0; i < 5; i++) dropper.DropBomb();
            session.RestartRound();
            Require(UnityEngine.Object.FindObjectsByType<FallingBomb>(FindObjectsSortMode.None).Length == 0, "Restart with bombs in flight left active bombs behind.");
            return "PASS: exposed contours only (including enclosed hole); 20-cut geometry checks (use StressTerrain for 200-cut batches); lethal ring size/alignment; whole-body blast damage; death input lock/message; R restores player/terrain and clears bombs/effects. Stress mean="
                + (totalMs / stressCuts).ToString("F2") + "ms, worst=" + worstMs.ToString("F2") + "ms; peak vertices=" + peakVertices + "; peak solid pieces=" + peakPieces + ".";
        }
        finally
        {
            InputSystem.RemoveDevice(keyboard);
            InputSystem.settings.editorInputBehaviorInPlayMode = inputBehavior;
            InputSystem.settings.backgroundBehavior = inputBackground;
            settings.Update();
            settings.FindProperty("craterRadius").floatValue = originalRadius;
            settings.FindProperty("lethalRadius").floatValue = originalLethal;
            settings.FindProperty("craterShape").enumValueIndex = originalShape;
            settings.ApplyModifiedPropertiesWithoutUndo();
            session.RestartRound();
        }
    }

    private static void Set(SerializedObject settings, string name, float value)
    {
        settings.Update();
        settings.FindProperty(name).floatValue = value;
        settings.ApplyModifiedPropertiesWithoutUndo();
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
