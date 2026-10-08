using UnityEditor;
using UnityEngine;

// Applies sample overlapping craters to the live scene for visual inspection.
public static class PreviewCrater
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new System.InvalidOperationException("Preview is only for Play mode.");
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var bombs = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        ground.Carve(bombs.CreateCraterOutline(new Vector2(-5f, 6f)));
        ground.Carve(bombs.CreateCraterOutline(new Vector2(4f, 6f)));
        ground.Carve(bombs.CreateCraterOutline(new Vector2(2.5f, 5.7f)));
        return "Preview circular and overlapping craters in Play mode; stop Play mode to restore ground.";
    }
}
