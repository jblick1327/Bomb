using System;
using System.Collections.Generic;
using System.Diagnostics;
using UnityEditor;
using UnityEngine;

// Runs repeatable terrain carving loads and reports mesh and timing statistics.
public static class StressTerrain
{
    // Run consecutive batches: Main(0,25), Main(25,25), ..., Main(175,25).
    // This keeps individual Editor commands below their execution timeout.
    public static string Main(int start = 0, int count = 25)
    {
        if (!EditorApplication.isPlaying) throw new Exception("Stress test requires Play mode.");
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var dropper = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        var settings = new SerializedObject(dropper);
        float originalRadius = settings.FindProperty("craterRadius").floatValue;
        int originalShape = settings.FindProperty("craterShape").enumValueIndex;
        var random = new System.Random(7319);
        var cuts = new List<(Vector2 center, float radius)>();
        double totalMs = 0f;
        double worstMs = 0f;
        int peakVertices = 0;
        int peakPieces = 0;
        try
        {
            if (start == 0) ground.ResetGround();
            settings.FindProperty("craterShape").enumValueIndex = 0;
            settings.ApplyModifiedPropertiesWithoutUndo();
            var timer = new Stopwatch();
            for (int i = 0; i < start + count; i++)
            {
                float radius = 0.35f + (float)random.NextDouble() * 0.85f;
                Vector2 center = new Vector2(-9.4f + (float)random.NextDouble() * 18.8f, (float)random.NextDouble() * 6.2f);
                cuts.Add((center, radius));
                if (i < start) continue;
                settings.Update();
                settings.FindProperty("craterRadius").floatValue = radius;
                settings.ApplyModifiedPropertiesWithoutUndo();
                Vector2[] outline = dropper.CreateCraterOutline(center);
                timer.Restart();
                ground.Carve(outline);
                timer.Stop();
                totalMs += timer.Elapsed.TotalMilliseconds;
                worstMs = Math.Max(worstMs, timer.Elapsed.TotalMilliseconds);
                peakVertices = Math.Max(peakVertices, ground.VertexCount);
                peakPieces = Math.Max(peakPieces, ground.SolidPieceCount);
                for (int sample = 0; sample < 8; sample++)
                {
                    float x = -9.9f + ((i * 17 + sample * 31) % 199) * 0.1f;
                    float y = -0.5f + ((i * 23 + sample * 7) % 64) * 0.1f;
                    Vector2 point = new Vector2(x, y);
                    bool removed = false;
                    bool solid = true;
                    foreach (var cut in cuts)
                    {
                        float distance = Vector2.Distance(point, cut.center);
                        if (distance < cut.radius * 0.98f) removed = true;
                        if (distance < cut.radius + 0.08f) solid = false;
                    }
                    if (removed && ground.ContainsSolid(point)) throw new Exception("Overlapping cuts restored terrain.");
                    if (solid && !ground.ContainsSolid(point)) throw new Exception("Cuts damaged distant terrain.");
                }
            }
            return "PASS: cuts " + start + " through " + (start + count - 1)
                + "; mean=" + (totalMs / count).ToString("F2") + "ms; worst=" + worstMs.ToString("F2")
                + "ms; peak vertices=" + peakVertices + "; peak pieces=" + peakPieces + ".";
        }
        finally
        {
            settings.Update();
            settings.FindProperty("craterRadius").floatValue = originalRadius;
            settings.FindProperty("craterShape").enumValueIndex = originalShape;
            settings.ApplyModifiedPropertiesWithoutUndo();
        }
    }
}
