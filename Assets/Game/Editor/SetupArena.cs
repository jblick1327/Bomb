using System;
using TMPro;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public static class SetupArena
{
    [MenuItem("Arena/Rebuild Scene References", false, 20)]
    private static void Rebuild() => Debug.Log(Main());

    [MenuItem("Arena/Rebuild Scene References", true)]
    private static bool CanRebuild() => !EditorApplication.isPlaying && GameObject.Find("Arena") != null;

    public static string Main()
    {
        if (EditorApplication.isPlaying) throw new Exception("Stop Play mode before setup.");
        var arena = GameObject.Find("Arena");
        if (arena == null) throw new Exception("Open the Arena scene first.");
        var font = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>("Assets/TextMesh Pro/Resources/Fonts & Materials/LiberationSans SDF.asset");
        if (font == null) throw new Exception("Import the TMP essential font first.");
        var layout = arena.GetComponent<ArenaLayout>() ?? arena.AddComponent<ArenaLayout>();
        layout.ApplyGeometry();
        var floor = arena.transform.Find("Floor").gameObject;
        floor.transform.localPosition = Vector3.zero;
        floor.transform.localRotation = Quaternion.identity;
        floor.transform.localScale = Vector3.one;
        var terrain = floor.GetComponent<DestructibleGround>();
        SetReference(terrain, "layout", layout);
        terrain.ResetGround();
        floor.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.On;
        const string meshPath = "Assets/Game/Geometry/GroundMesh.asset";
        var mesh = floor.GetComponent<MeshFilter>().sharedMesh;
        var asset = AssetDatabase.LoadAssetAtPath<Mesh>(meshPath);
        if (asset == null)
        {
            mesh.name = "GroundMesh";
            AssetDatabase.CreateAsset(mesh, meshPath);
        }
        else
        {
            asset.Clear();
            asset.vertices = mesh.vertices;
            asset.triangles = mesh.triangles;
            asset.normals = mesh.normals;
            asset.RecalculateBounds();
            floor.GetComponent<MeshFilter>().sharedMesh = asset;
            floor.GetComponent<MeshCollider>().sharedMesh = null;
            floor.GetComponent<MeshCollider>().sharedMesh = asset;
            EditorUtility.SetDirty(asset);
        }

        var player = GameObject.Find("Player").GetComponent<ArenaPlayerController>();
        player.transform.position = layout.PlayerSpawn;
        var bombs = GameObject.Find("Bomb System");
        var dropper = bombs.GetComponent<BombDropper>();
        var session = bombs.GetComponent<ArenaSession>() ?? bombs.AddComponent<ArenaSession>();
        SetReference(session, "layout", layout);
        SetReference(session, "player", player);
        SetReference(session, "ground", terrain);
        SetReference(session, "bombs", dropper);
        SetReference(dropper, "layout", layout);
        SetReference(dropper, "session", session);
        SetReference(dropper, "ground", terrain);
        SetReference(dropper, "player", player);
        SetReference(dropper, "upperBoundary", arena.transform.Find("Upper Boundary").GetComponent<Collider>());
        SetReference(Camera.main.GetComponent<ArenaCamera>(), "layout", layout);
        Camera.main.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
        if (Camera.main.GetComponent<UniversalAdditionalCameraData>() == null)
            Camera.main.gameObject.AddComponent<UniversalAdditionalCameraData>();

        var hud = GameObject.Find("Arena HUD");
        if (hud == null)
        {
            hud = new GameObject("Arena HUD", typeof(RectTransform), typeof(Canvas), typeof(UnityEngine.UI.CanvasScaler));
            Canvas canvas = hud.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceCamera;
            canvas.worldCamera = Camera.main;
            canvas.planeDistance = 1f;
            canvas.sortingOrder = 100;
            var scaler = hud.GetComponent<UnityEngine.UI.CanvasScaler>();
            scaler.uiScaleMode = UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280f, 720f);
            scaler.matchWidthOrHeight = 0.5f;
            var controls = Text("Controls", hud.transform, font, 18f);
            controls.rectTransform.anchorMin = new Vector2(0f, 1f);
            controls.rectTransform.anchorMax = Vector2.one;
            controls.rectTransform.pivot = new Vector2(0.5f, 1f);
            controls.rectTransform.offsetMin = new Vector2(16f, -56f);
            controls.rectTransform.offsetMax = new Vector2(-16f, -8f);
            controls.alignment = TextAlignmentOptions.Top;
            controls.text = "A/D or arrows: move    Space: jump    B: drop bomb    R: restart";

            var panel = new GameObject("Death Panel", typeof(RectTransform), typeof(UnityEngine.UI.Image));
            panel.transform.SetParent(hud.transform, false);
            var rect = panel.GetComponent<RectTransform>();
            rect.anchorMin = new Vector2(0.15f, 0.5f);
            rect.anchorMax = new Vector2(0.85f, 0.5f);
            rect.sizeDelta = new Vector2(0f, 140f);
            panel.GetComponent<UnityEngine.UI.Image>().color = new Color(0.03f, 0.04f, 0.055f, 0.94f);
            panel.GetComponent<UnityEngine.UI.Image>().raycastTarget = false;
            var message = Text("Death Message", panel.transform, font, 32f);
            message.rectTransform.anchorMin = Vector2.zero;
            message.rectTransform.anchorMax = Vector2.one;
            message.rectTransform.offsetMin = new Vector2(16f, 12f);
            message.rectTransform.offsetMax = new Vector2(-16f, -12f);
            message.alignment = TextAlignmentOptions.Center;
            message.text = "YOU DIED\n<size=22>Press R to restart</size>";
            panel.SetActive(false);
            var display = hud.AddComponent<ArenaHud>();
            SetReference(display, "session", session);
            SetReference(display, "deathPanel", panel);
            SetReference(display, "controls", controls);
        }
        EditorSceneManager.MarkSceneDirty(arena.scene);
        EditorSceneManager.SaveScene(arena.scene);
        AssetDatabase.SaveAssets();
        Selection.activeGameObject = bombs;
        return "Arena references rebuilt and scene saved. Initial ground and player spawn reset; gameplay tuning preserved.";
    }

    private static TextMeshProUGUI Text(string name, Transform parent, TMP_FontAsset font, float size)
    {
        var obj = new GameObject(name, typeof(RectTransform));
        obj.transform.SetParent(parent, false);
        var text = obj.AddComponent<TextMeshProUGUI>();
        text.font = font;
        text.fontSize = size;
        text.enableAutoSizing = false;
        text.color = new Color(0.94f, 0.96f, 1f);
        text.raycastTarget = false;
        return text;
    }

    private static void SetReference(UnityEngine.Object target, string property, UnityEngine.Object value)
    {
        var settings = new SerializedObject(target);
        settings.FindProperty(property).objectReferenceValue = value;
        settings.ApplyModifiedProperties();
    }
}
