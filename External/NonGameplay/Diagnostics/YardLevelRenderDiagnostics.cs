using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.SceneManagement;

// Logs scene renderers, colliders, camera state, and player grounding after YardLevel loads.
[DefaultExecutionOrder(10000)]
public sealed class YardLevelRenderDiagnostics : MonoBehaviour
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Install()
    {
        if (SceneManager.GetActiveScene().name != "YardLevel") return;
        new GameObject("YardLevel Render Diagnostics").AddComponent<YardLevelRenderDiagnostics>();
    }

    private IEnumerator Start()
    {
        yield return new WaitForEndOfFrame();
        Report();
    }

    private static void Report()
    {
        Camera view = Camera.main;
        var report = new StringBuilder("[YardLevelRender] Runtime terrain report\n");
        report.AppendLine($"Scene={SceneManager.GetActiveScene().name}");
        if (view == null)
        {
            report.AppendLine("Camera.main=null");
        }
        else
        {
            report.AppendLine($"Camera path={GetPath(view.transform)} position={view.transform.position} rotation={view.transform.eulerAngles} "
                + $"orthographic={view.orthographic} size={view.orthographicSize} near={view.nearClipPlane} far={view.farClipPlane} "
                + $"cullingMask=0x{view.cullingMask:X8} occlusion={view.useOcclusionCulling}");
        }

        foreach (Transform root in FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (root.parent != null || !IsYardLevelRoot(root)) continue;
            report.AppendLine($"ROOT path={GetPath(root)} active={root.gameObject.activeInHierarchy} position={root.position} layer={root.gameObject.layer}");
            foreach (MeshRenderer renderer in root.GetComponentsInChildren<MeshRenderer>(true))
                AppendRenderer(report, renderer, view);
            foreach (Collider collider in root.GetComponentsInChildren<Collider>(true))
                AppendCollider(report, collider);
        }

        Transform floor = FindFirstObjectByType<ArenaLayout>(FindObjectsInactive.Include)?.transform.Find("Floor");
        if (floor == null)
            report.AppendLine("LEGACY FLOOR missing");
        else
        {
            MeshRenderer renderer = floor.GetComponent<MeshRenderer>();
            report.AppendLine($"LEGACY FLOOR path={GetPath(floor)} active={floor.gameObject.activeInHierarchy} "
                + $"renderer={(renderer != null ? renderer.enabled.ToString() : "missing")} colliders={floor.GetComponentsInChildren<Collider>(true).Length}");
        }
        ArenaPlayerController player = FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);
        if (player == null)
            report.AppendLine("PLAYER missing");
        else
        {
            CharacterController controller = player.GetComponent<CharacterController>();
            Vector3 bottom = player.transform.TransformPoint(controller.center + Vector3.down * controller.height * 0.5f);
            bool hit = Physics.Raycast(bottom + Vector3.up * 0.05f, Vector3.down, out RaycastHit groundHit, 2f);
            report.AppendLine($"PLAYER path={GetPath(player.transform)} active={player.gameObject.activeInHierarchy} enabled={player.enabled} "
                + $"position={player.transform.position} grounded={controller.isGrounded} bottom={bottom} "
                + $"rayHit={hit} hitObject={(hit ? GetPath(groundHit.collider.transform) : "none")} "
                + $"hitPoint={(hit ? groundHit.point.ToString() : "none")} distance={(hit ? groundHit.distance.ToString() : "none")}"
                + $" controllerHeight={controller.height} radius={controller.radius}");
        }
        Debug.Log(report.ToString());
    }

    private static bool IsYardLevelRoot(Transform candidate)
    {
        bool hasGroundMesh = false;
        bool hasGrassMesh = false;
        foreach (Transform child in candidate.GetComponentsInChildren<Transform>(true))
        {
            hasGroundMesh |= child.name == "Ground_Mesh";
            hasGrassMesh |= child.name == "Grass_Mesh";
        }
        return hasGroundMesh && hasGrassMesh;
    }

    private static void AppendRenderer(StringBuilder report, MeshRenderer renderer, Camera view)
    {
        MeshFilter filter = renderer.GetComponent<MeshFilter>();
        Mesh mesh = filter != null ? filter.sharedMesh : null;
        report.AppendLine($"MESH path={GetPath(renderer.transform)} active={renderer.gameObject.activeInHierarchy} enabled={renderer.enabled} "
            + $"layer={renderer.gameObject.layer} bounds={renderer.bounds} inFrustum={(view != null && GeometryUtility.TestPlanesAABB(GeometryUtility.CalculateFrustumPlanes(view), renderer.bounds))}");
        report.AppendLine($"  filter={(filter != null ? "present" : "missing")} mesh={(mesh != null ? mesh.name : "null")} "
            + $"vertices={(mesh != null ? mesh.vertexCount.ToString() : "0")} subMeshes={(mesh != null ? mesh.subMeshCount.ToString() : "0")}");
        Material[] materials = renderer.sharedMaterials;
        for (int i = 0; i < materials.Length; i++)
        {
            Material material = materials[i];
            report.AppendLine($"  material[{i}]={(material != null ? material.name : "null")} "
                + $"shader={(material != null && material.shader != null ? material.shader.name : "null")} "
                + $"supported={(material != null && material.shader != null && material.shader.isSupported)}");
        }
    }

    private static void AppendCollider(StringBuilder report, Collider collider)
    {
        MeshCollider mesh = collider as MeshCollider;
        report.AppendLine($"COLLIDER path={GetPath(collider.transform)} name={collider.name} type={collider.GetType().Name} "
            + $"enabled={collider.enabled} trigger={collider.isTrigger} convex={(mesh != null && mesh.convex)} "
            + $"mesh={(mesh != null && mesh.sharedMesh != null ? mesh.sharedMesh.name : "n/a")} "
            + $"position={collider.transform.position} rotation={collider.transform.eulerAngles} scale={collider.transform.lossyScale} "
            + $"layer={collider.gameObject.layer} bounds={collider.bounds}");
    }

    private static string GetPath(Transform current)
    {
        var path = current.name;
        while (current.parent != null)
        {
            current = current.parent;
            path = current.name + "/" + path;
        }
        return path;
    }
}
