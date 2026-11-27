using UnityEngine;

// Renders a 3D model once into a small texture, for menu portraits and
// result-screen icons. The model is built far from the level, photographed
// by its own camera, then removed.
public static class ModelSnapshot
{
    public enum Framing { Head, Whole }

    private const int SnapshotLayer = 31;
    private static int snapshotCount;

    // tint recolours the model; null keeps its own materials. faceCamera turns
    // a flat model (a coin) so its broad side faces the camera, whichever way
    // it was modelled.
    public static RenderTexture Render(Object prefab, int size, Color? tint, Framing framing, bool silhouette = false, bool faceCamera = false)
    {
        if (prefab == null) return null;

        var rig = new GameObject("Snapshot Rig");
        rig.transform.position = new Vector3(-10000f - (snapshotCount++ % 16) * 20f, -10000f, 0f);
        Object made = Object.Instantiate(prefab, rig.transform);
        GameObject model = made as GameObject;
        if (model == null && made is Component component) model = component.gameObject;
        if (model == null)
        {
            Object.Destroy(made);
            Object.Destroy(rig);
            return null;
        }
        model.transform.localPosition = Vector3.zero;

        // Only the look is needed: stop the model's scripts and physics.
        foreach (MonoBehaviour behaviour in model.GetComponentsInChildren<MonoBehaviour>(true)) behaviour.enabled = false;
        foreach (Collider collider in model.GetComponentsInChildren<Collider>(true)) collider.enabled = false;
        foreach (Rigidbody body in model.GetComponentsInChildren<Rigidbody>(true)) body.isKinematic = true;
        foreach (Light light in model.GetComponentsInChildren<Light>(true)) light.enabled = false;
        if (faceCamera) TurnFlatSideToCamera(model);

        Bounds bounds = default;
        bool hasBounds = false;
        var properties = new MaterialPropertyBlock();
        foreach (Renderer renderer in model.GetComponentsInChildren<Renderer>(true))
        {
            renderer.gameObject.layer = SnapshotLayer;
            if (renderer is ParticleSystemRenderer || renderer is LineRenderer || renderer is TrailRenderer) continue;
            if (hasBounds) bounds.Encapsulate(renderer.bounds);
            else { bounds = renderer.bounds; hasBounds = true; }
            if (tint == null) continue;
            renderer.GetPropertyBlock(properties);
            properties.SetColor("_BaseColor", tint.Value);
            properties.SetColor("_Color", tint.Value);
            if (silhouette)
            {
                properties.SetColor("_SpecColor", Color.black);
                properties.SetColor("_EmissionColor", Color.black);
            }
            renderer.SetPropertyBlock(properties);
        }
        if (!hasBounds) bounds = new Bounds(model.transform.position + Vector3.up, new Vector3(1f, 2f, 1f));

        var texture = new RenderTexture(size, size, 16, RenderTextureFormat.ARGB32);
        texture.Create();

        var cameraObject = new GameObject("Snapshot Camera");
        cameraObject.transform.SetParent(rig.transform, false);
        Camera camera = cameraObject.AddComponent<Camera>();
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0f, 0f, 0f, 0f);
        camera.cullingMask = 1 << SnapshotLayer;
        camera.orthographic = true;
        camera.aspect = 1f;
        camera.nearClipPlane = .01f;
        camera.farClipPlane = 20f + bounds.size.z;
        Vector3 focus;
        if (framing == Framing.Head)
        {
            // Head and shoulders, matching the character select portraits.
            camera.orthographicSize = Mathf.Max(bounds.extents.y * .48f, .1f);
            focus = bounds.center + Vector3.up * bounds.extents.y * .53f;
        }
        else
        {
            camera.orthographicSize = Mathf.Max(Mathf.Max(bounds.extents.x, bounds.extents.y) * 1.1f, .05f);
            focus = bounds.center;
        }
        camera.transform.position = focus + Vector3.back * (5f + bounds.extents.z);
        camera.transform.rotation = Quaternion.LookRotation(Vector3.forward, Vector3.up);
        camera.targetTexture = texture;
        camera.Render();
        camera.targetTexture = null;

        rig.SetActive(false);
        Object.Destroy(rig);
        return texture;
    }

    // The camera sits on -Z looking along +Z. Finds the model's thinnest
    // direction and turns the model so that direction points at the camera.
    private static void TurnFlatSideToCamera(GameObject model)
    {
        Bounds bounds = default;
        bool hasBounds = false;
        foreach (Renderer renderer in model.GetComponentsInChildren<Renderer>(true))
        {
            if (renderer is ParticleSystemRenderer || renderer is LineRenderer || renderer is TrailRenderer) continue;
            if (hasBounds) bounds.Encapsulate(renderer.bounds);
            else { bounds = renderer.bounds; hasBounds = true; }
        }
        if (!hasBounds) return;
        Vector3 size = bounds.size;
        if (size.x < size.z && size.x <= size.y)
            model.transform.rotation = Quaternion.Euler(0f, 90f, 0f) * model.transform.rotation;   // thin along X
        else if (size.y < size.z && size.y < size.x)
            model.transform.rotation = Quaternion.Euler(-90f, 0f, 0f) * model.transform.rotation;  // lying flat
    }

    public static void Release(RenderTexture texture)
    {
        if (texture == null) return;
        texture.Release();
        Object.Destroy(texture);
    }
}
