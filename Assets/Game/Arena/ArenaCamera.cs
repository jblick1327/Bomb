using UnityEngine;

[ExecuteAlways, RequireComponent(typeof(Camera))]
[AddComponentMenu("Arena/Arena Camera")]
public sealed class ArenaCamera : MonoBehaviour
{
    [Header("Framing")]
    [Tooltip("Downward camera angle. 0 is a straight side view; the camera always frames the arena.")]
    [SerializeField, Range(0f, 90f), InspectorName("Downward tilt (degrees)")]
    private float tilt = 0f;
    [SerializeField, Min(0f), InspectorName("Frame padding (units)")]
    private float padding = 0.5f;

    [Header("Scene references")]
    [SerializeField, Tooltip("Shared dimensions used to frame the entire arena.")]
    private ArenaLayout layout;

    private void OnEnable() => FitArena();
    private void OnValidate() => FitArena();
    private void LateUpdate() => FitArena();

    private void FitArena()
    {
        Camera view = GetComponent<Camera>();
        if (view == null || layout == null) return;

        Bounds bounds = layout.ViewBounds;

        Quaternion rotation = Quaternion.Euler(tilt, 0f, 0f);
        transform.SetPositionAndRotation(bounds.center - rotation * Vector3.forward * 30f, rotation);
        view.orthographic = true;

        Vector3 half = bounds.extents;
        float halfWidth = 0f;
        float halfHeight = 0f;
        Quaternion inverse = Quaternion.Inverse(rotation);
        for (int x = -1; x <= 1; x += 2)
        for (int y = -1; y <= 1; y += 2)
        for (int z = -1; z <= 1; z += 2)
        {
            Vector3 corner = inverse * Vector3.Scale(half, new Vector3(x, y, z));
            halfWidth = Mathf.Max(halfWidth, Mathf.Abs(corner.x));
            halfHeight = Mathf.Max(halfHeight, Mathf.Abs(corner.y));
        }

        view.orthographicSize = Mathf.Max(halfHeight + padding,
            (halfWidth + padding) / Mathf.Max(view.aspect, 0.01f));
    }
}
