using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UIElements;
using UnityEngine.SceneManagement;

// Creates or repairs the arena scene and its serialized component references.
public static class SetupArena
{
    [MenuItem("Arena/Rebuild Scene References", false, 20)]
    private static void Rebuild() => Debug.Log(Main());

    [MenuItem("Arena/Rebuild Scene References", true)]
    private static bool CanRebuild() => !EditorApplication.isPlaying
        && UnityEngine.Object.FindFirstObjectByType<ArenaLayout>() != null;

    public static string Main()
    {
        if (EditorApplication.isPlaying) throw new Exception("Stop Play mode before setup.");
        var layout = UnityEngine.Object.FindFirstObjectByType<ArenaLayout>();
        if (layout == null) throw new Exception("Open a scene with an ArenaLayout first.");
        var arena = layout.gameObject;
        bool isYardLevel = SceneManager.GetActiveScene().name == "YardLevel";
        Transform yardVisual = isYardLevel ? FindYardLevelRoot() : null;
        if (isYardLevel)
        {
            foreach (Transform root in FindYardLevelRoots())
                CleanYardLevelRoot(root);
        }
        if (yardVisual != null)
        {
            var layoutSettings = new SerializedObject(layout);
            layoutSettings.FindProperty("boundsSource").objectReferenceValue = yardVisual;
            layoutSettings.FindProperty("deriveBoundsFromSource").boolValue = true;
            layoutSettings.ApplyModifiedPropertiesWithoutUndo();
        }
        layout.ApplyGeometry();
        Collider levelBounds = arena.transform.Find("Level Bounds")?.GetComponent<Collider>();
        if (levelBounds != null) SetReference(layout, "levelBoundsCollider", levelBounds);
        DestructibleGround terrain = null;
        DestructibleGround yardVisualGround = null;
        ArenaGameplayGround yardGameplayGround = null;
        if (isYardLevel)
        {
            DisableLegacyFloor(arena);
            foreach (Transform root in FindYardLevelRoots())
            {
                RepairYardMaterials(root);
                foreach (Transform child in root.GetComponentsInChildren<Transform>(true))
                {
                    if (child.name == "Ground_Mesh")
                    {
                        yardGameplayGround = child.GetComponent<ArenaGameplayGround>();
                        if (yardGameplayGround == null) yardGameplayGround = child.gameObject.AddComponent<ArenaGameplayGround>();
                        SetYardLayerPosition(child.gameObject, 0.08f);
                        MeshRenderer renderer = child.GetComponent<MeshRenderer>();
                        if (renderer != null) EnsureGroundMaterial(renderer, child.name, true);
                    }
                    else if (child.name == "Grass_Mesh")
                    {
                        yardVisualGround = child.GetComponent<DestructibleGround>();
                        if (yardVisualGround == null) yardVisualGround = child.gameObject.AddComponent<DestructibleGround>();
                        var visualSettings = new SerializedObject(yardVisualGround);
                        visualSettings.FindProperty("collisionEnabled").boolValue = false;
                        visualSettings.ApplyModifiedPropertiesWithoutUndo();
                        yardVisualGround.SetCollisionEnabled(false);
                        ConfigureYardLayer(yardVisualGround, child.gameObject);
                        MeshRenderer renderer = child.GetComponent<MeshRenderer>();
                        if (renderer != null) EnsureGroundMaterial(renderer, child.name, true);
                    }
                }
                if (root.GetComponent<DestructibleMultiMesh>() == null)
                    root.gameObject.AddComponent<DestructibleMultiMesh>();
            }
            terrain = yardVisualGround;
        }
        else
        {
            var floors = FindGroundObjects(arena);
            var floor = floors[0];
            terrain = floor.GetComponent<DestructibleGround>() ?? floor.AddComponent<DestructibleGround>();
            foreach (GameObject groundObject in floors)
            {
                var ground = groundObject.GetComponent<DestructibleGround>() ?? groundObject.AddComponent<DestructibleGround>();
                SetReference(ground, "layout", layout);
                ground.ResetGround();
                groundObject.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.On;
                EnsureGroundMaterial(groundObject.GetComponent<MeshRenderer>(), groundObject.name, false);
            }
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
        }

        GameObject rock = GameObject.Find("Rock");
        if (rock != null && rock.GetComponent<DestructibleObject>() == null)
            rock.AddComponent<DestructibleObject>();

        var player = GameObject.Find("Player").GetComponent<ArenaPlayerController>();
        player.transform.position = layout.PlayerSpawn;
        var bombs = GameObject.Find("Bomb System");
        var dropper = bombs.GetComponent<BombDropper>();
        var session = bombs.GetComponent<ArenaSession>() ?? bombs.AddComponent<ArenaSession>();
        SetReference(session, "layout", layout);
        SetReference(session, "player", player);
        SetReference(session, "ground", terrain);
        SetReference(session, "rock", rock != null ? rock.GetComponent<DestructibleObject>() : null);
        SetReference(session, "bombs", dropper);
        SetReference(dropper, "layout", layout);
        SetReference(dropper, "session", session);
        SetReference(dropper, "ground", terrain);
        SetReference(dropper, "gameplayGround", yardGameplayGround);
        SetReference(dropper, "gameplayGroundCollider", yardGameplayGround != null ? yardGameplayGround.GetComponent<Collider>() : null);
        if (isYardLevel)
        {
            SetReference(dropper, "yardGrassMaterial", AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/YardGrass.mat"));
            SetReference(dropper, "yardDirtMaterial", AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/YardDirt.mat"));
        }
        SetReference(dropper, "player", player);
        Transform upperBoundary = arena.transform.Find("Upper Boundary");
        SetReference(dropper, "upperBoundary", upperBoundary != null ? upperBoundary.GetComponent<Collider>() : null);
        SetReference(Camera.main.GetComponent<ArenaCamera>(), "layout", layout);
        if (SceneManager.GetActiveScene().name == "YardLevel")
        {
            var cameraSettings = new SerializedObject(Camera.main.GetComponent<ArenaCamera>());
            cameraSettings.FindProperty("followPlayer").boolValue = true;
            cameraSettings.FindProperty("player").objectReferenceValue = player;
            cameraSettings.FindProperty("followViewportHeight").floatValue = 12f;
            cameraSettings.FindProperty("followDeadZone").floatValue = 0.25f;
            cameraSettings.FindProperty("followSmoothTime").floatValue = 0.12f;
            cameraSettings.ApplyModifiedPropertiesWithoutUndo();
        }
        Camera.main.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
        if (Camera.main.GetComponent<UniversalAdditionalCameraData>() == null)
            Camera.main.gameObject.AddComponent<UniversalAdditionalCameraData>();

        var oldHud = GameObject.Find("Arena HUD");
        if (oldHud != null) UnityEngine.Object.DestroyImmediate(oldHud);
        var ui = GameObject.Find("Arena UI") ?? new GameObject("Arena UI");
        var document = ui.GetComponent<UIDocument>() ?? ui.AddComponent<UIDocument>();
        var display = ui.GetComponent<ArenaHudDocument>() ?? ui.AddComponent<ArenaHudDocument>();
        var visualTree = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>("Assets/Game/UI/ArenaHud.uxml");
        var styleSheet = AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/Game/UI/ArenaHud.uss");
        if (visualTree == null || styleSheet == null) throw new Exception("Arena UI Toolkit assets are missing.");
        document.visualTreeAsset = visualTree;
        document.panelSettings = LoadPanelSettings();
        SetReference(display, "session", session);
        SetReference(display, "styleSheet", styleSheet);
        EditorSceneManager.MarkSceneDirty(arena.scene);
        EditorSceneManager.SaveScene(arena.scene);
        AssetDatabase.SaveAssets();
        Selection.activeGameObject = bombs;
        return "Arena references rebuilt and scene saved. Initial ground and player spawn reset; gameplay tuning preserved.";
    }

    private static PanelSettings LoadPanelSettings()
    {
        const string path = "Assets/Game/UI/ArenaPanelSettings.asset";
        var settings = AssetDatabase.LoadAssetAtPath<PanelSettings>(path);
        if (settings != null) return settings;
        settings = ScriptableObject.CreateInstance<PanelSettings>();
        AssetDatabase.CreateAsset(settings, path);
        return settings;
    }

    private static Transform FindYardLevelRoot()
    {
        List<Transform> roots = FindYardLevelRoots();
        if (roots.Count == 0) throw new Exception("YardLevel root is missing.");
        return roots[0];
    }

    private static List<Transform> FindYardLevelRoots()
    {
        var roots = new List<Transform>();
        foreach (Transform candidate in UnityEngine.Object.FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (candidate.parent != null) continue;
            bool hasGroundMesh = false;
            bool hasGrassMesh = false;
            foreach (Transform child in candidate.GetComponentsInChildren<Transform>(true))
            {
                hasGroundMesh |= child.name == "Ground_Mesh";
                hasGrassMesh |= child.name == "Grass_Mesh";
            }
            if (hasGroundMesh && hasGrassMesh) roots.Add(candidate);
        }
        return roots;
    }

    private static void EnsureGroundMaterial(MeshRenderer renderer, string objectName, bool isYardLevel)
    {
        if (isYardLevel)
        {
            string materialName = objectName.ToLowerInvariant().Contains("grass") ? "YardGrass" : "YardDirt";
            string materialPath = $"Assets/Game/Materials/{materialName}.mat";
            Material source = AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Ground.mat");
            if (source == null) throw new Exception("Assets/Game/Materials/Ground.mat is missing.");
            Material material = AssetDatabase.LoadAssetAtPath<Material>(materialPath);
            if (material == null)
            {
                material = new Material(source) { name = materialName };
                AssetDatabase.CreateAsset(material, materialPath);
            }
            else EditorUtility.CopySerialized(source, material);
            Color color = materialName == "YardGrass"
                ? new Color(0.18f, 0.42f, 0.16f)
                : new Color(0.28f, 0.16f, 0.08f);
            material.SetColor("_BaseColor", color);
            material.SetColor("_Color", color);
            EditorUtility.SetDirty(material);
            renderer.sharedMaterial = material;
            return;
        }

        foreach (Material material in renderer.sharedMaterials)
        {
            if (material != null && material.shader != null && material.shader.isSupported) return;
        }

        Material fallback = AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Ground.mat");
        if (fallback != null) renderer.sharedMaterial = fallback;
    }

    private static void RepairYardMaterials(Transform root)
    {
        Material fallback = AssetDatabase.LoadAssetAtPath<Material>("Assets/Game/Materials/Ground.mat");
        if (fallback == null) throw new Exception("Assets/Game/Materials/Ground.mat is missing.");
        foreach (MeshRenderer renderer in root.GetComponentsInChildren<MeshRenderer>(true))
        {
            if (renderer.gameObject == root.gameObject) continue;
            bool valid = renderer.sharedMaterials.Length > 0;
            foreach (Material material in renderer.sharedMaterials)
                valid &= material != null && material.shader != null && material.shader.isSupported;
            if (!valid) renderer.sharedMaterial = fallback;
        }
    }

    private static void CleanYardLevelRoot(Transform root)
    {
        foreach (MeshFilter filter in root.GetComponentsInChildren<MeshFilter>(true))
        {
            MeshFilter source = PrefabUtility.GetCorrespondingObjectFromSource(filter);
            if (source != null) filter.sharedMesh = source.sharedMesh;
        }

        foreach (DestructibleGround ground in root.GetComponentsInChildren<DestructibleGround>(true))
            UnityEngine.Object.DestroyImmediate(ground);

        foreach (DestructibleObject rock in root.GetComponentsInChildren<DestructibleObject>(true))
            UnityEngine.Object.DestroyImmediate(rock);

        var components = new List<Component>();
        components.AddRange(root.GetComponentsInChildren<MeshFilter>(true));
        components.AddRange(root.GetComponentsInChildren<MeshRenderer>(true));
        components.AddRange(root.GetComponentsInChildren<MeshCollider>(true));
        foreach (Component component in components)
        {
            if (component != null && PrefabUtility.GetCorrespondingObjectFromSource(component) == null)
                PrefabUtility.RevertAddedComponent(component, InteractionMode.UserAction);
        }
    }

    private static void ConfigureYardLayer(DestructibleGround ground, GameObject groundObject)
    {
        var settings = new SerializedObject(ground);
        settings.FindProperty("extrusionDepth").floatValue = 0.12f;
        settings.ApplyModifiedPropertiesWithoutUndo();

        SetYardLayerPosition(groundObject, -0.08f);
    }

    private static void SetYardLayerPosition(GameObject layer, float offset)
    {
        Transform source = PrefabUtility.GetCorrespondingObjectFromSource(layer.transform);
        Vector3 position = layer.transform.localPosition;
        position.z = (source != null ? source.localPosition.z : position.z) + offset;
        layer.transform.localPosition = position;
    }

    private static List<GameObject> FindGroundObjects(GameObject arena)
    {
        if (SceneManager.GetActiveScene().name == "YardLevel")
        {
            GameObject visual = GameObject.Find("YardLevel Visual");
            if (visual != null)
            {
                var importedGrounds = new List<GameObject>();
                foreach (MeshFilter mesh in visual.GetComponentsInChildren<MeshFilter>(true))
                {
                    if (mesh.sharedMesh != null) importedGrounds.Add(mesh.gameObject);
                }
                if (importedGrounds.Count > 0) return importedGrounds;
            }
        }

        Transform floor = arena.transform.Find("Floor");
        if (floor != null) return new List<GameObject> { floor.gameObject };
        throw new Exception("Arena ground object is missing. Expected Floor or Ground_Mesh.");
    }

    private static void DisableLegacyFloor(GameObject arena)
    {
        Transform floor = arena.transform.Find("Floor");
        if (floor == null) return;
        MeshRenderer renderer = floor.GetComponent<MeshRenderer>();
        if (renderer != null) renderer.enabled = false;
        foreach (Collider collider in floor.GetComponentsInChildren<Collider>(true))
            collider.enabled = false;
    }

    private static void SetReference(UnityEngine.Object target, string property, UnityEngine.Object value)
    {
        var settings = new SerializedObject(target);
        settings.FindProperty(property).objectReferenceValue = value;
        settings.ApplyModifiedProperties();
    }
}
