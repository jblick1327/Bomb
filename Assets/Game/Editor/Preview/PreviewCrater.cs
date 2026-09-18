using System;
using UnityEditor;
using UnityEngine;

public static class PreviewCrater
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Preview is only for Play mode.");
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var bombs = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        ground.Carve(bombs.CreateCraterOutline(new Vector2(-5f, 6f)));
        ground.Carve(bombs.CreateCraterOutline(new Vector2(4f, 6f)));
        ground.Carve(bombs.CreateCraterOutline(new Vector2(2.5f, 5.7f)));
        return "Preview circular and overlapping craters in Play mode; stop Play mode to restore ground.";
    }
}
