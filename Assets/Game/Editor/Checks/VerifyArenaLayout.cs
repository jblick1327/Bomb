using System;
using UnityEditor;
using UnityEngine;

public static class VerifyArenaLayout
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Layout verification requires Play mode.");
        var layout = UnityEngine.Object.FindFirstObjectByType<ArenaLayout>();
        var session = UnityEngine.Object.FindFirstObjectByType<ArenaSession>();
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var bombs = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        var player = UnityEngine.Object.FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);
        var settings = new SerializedObject(layout);
        string[] names = { "width", "height", "depth", "groundFraction" };
        float[] original = new float[names.Length];
        for (int i = 0; i < names.Length; i++) original[i] = settings.FindProperty(names[i]).floatValue;
        try
        {
            float[] changed = { 24f, 14f, 6f, 0.45f };
            for (int i = 0; i < names.Length; i++) settings.FindProperty(names[i]).floatValue = changed[i];
            settings.ApplyModifiedPropertiesWithoutUndo();
            layout.ApplyGeometry();
            session.RestartRound();
            Camera.main.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
            Physics.SyncTransforms();
            Bounds floor = ground.GetComponent<MeshCollider>().bounds;
            Require(Mathf.Abs(floor.size.x - 24f) < 0.001f && Mathf.Abs(floor.size.z - 6f) < 0.001f
                && Mathf.Abs(floor.max.y - 6.3f) < 0.001f, "Terrain did not use the new arena dimensions.");
            Require(player.transform.position == layout.PlayerSpawn, "Player spawn uses stale dimensions.");
            Require(Mathf.Abs(layout.transform.Find("Right Wall").GetComponent<Collider>().bounds.min.x - 12f) < 0.001f,
                "Side wall uses stale dimensions.");
            Require(Mathf.Abs(layout.transform.Find("Upper Boundary").GetComponent<Collider>().bounds.min.y - 14f) < 0.001f,
                "Upper boundary uses stale dimensions.");
            for (int i = 0; i < 20; i++)
            {
                var bomb = bombs.DropBomb();
                Require(Mathf.Abs(bomb.transform.position.x) <= 11f && bomb.transform.position.y > 14f,
                    "Bomb spawn uses stale dimensions.");
            }
            Bounds bounds = layout.ViewBounds;
            for (int x = -1; x <= 1; x += 2)
            for (int y = -1; y <= 1; y += 2)
            for (int z = -1; z <= 1; z += 2)
            {
                Vector3 point = bounds.center + Vector3.Scale(bounds.extents, new Vector3(x, y, z));
                Vector3 viewport = Camera.main.WorldToViewportPoint(point);
                Require(viewport.x >= 0f && viewport.x <= 1f && viewport.y >= 0f && viewport.y <= 1f,
                    "Camera clips the resized arena.");
            }
            return "PASS: resized width/height/depth/ground fraction update walls, terrain, player spawn, bomb range, and camera framing.";
        }
        finally
        {
            settings.Update();
            for (int i = 0; i < names.Length; i++) settings.FindProperty(names[i]).floatValue = original[i];
            settings.ApplyModifiedPropertiesWithoutUndo();
            layout.ApplyGeometry();
            session.RestartRound();
            Camera.main.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
