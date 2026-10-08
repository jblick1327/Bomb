using UnityEngine;

// Frames the arena and optionally follows the active player.
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
    [SerializeField, Min(0f), InspectorName("Follow smoothing (units/s)")]
    private float followSmoothing = 12f;
    [SerializeField, Min(0f), InspectorName("Follow dead zone (units)")]
    private float followDeadZone = 0.25f;
    [SerializeField, Min(1f), InspectorName("Follow viewport height (units)")]
    private float followViewportHeight = 12f;
    [SerializeField, Min(0.01f), InspectorName("Follow smooth time (seconds)")]
    private float followSmoothTime = 0.12f;
    [SerializeField, Min(0f), InspectorName("Player edge margin (units)")]
    private float playerEdgeMargin = 0.35f;
    [SerializeField, InspectorName("Follow player")]
    private bool followPlayer;

    [Header("Scene references")]
    [SerializeField, Tooltip("Shared dimensions used to frame the entire arena.")]
    private ArenaLayout layout;
    [SerializeField] private ArenaPlayerController player;

    private Vector3 targetCenter;
    private Vector3 followVelocity;

    private void OnEnable()
    {
        targetCenter = transform.position;
        FitArena(true);
    }

    private void OnValidate() => FitArena(true);
    private void LateUpdate() => FitArena(false);

    private void FitArena(bool instant)
    {
        Camera view = GetComponent<Camera>();
        if (view == null || layout == null) return;
        if (player == null)
            player = FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);

        Bounds bounds = layout.CameraBounds;

        Quaternion rotation = Quaternion.Euler(tilt, 0f, 0f);
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

        float fullArenaSize = Mathf.Max(halfHeight + padding,
            (halfWidth + padding) / Mathf.Max(view.aspect, 0.01f));
        view.orthographicSize = followPlayer
            ? Mathf.Min(fullArenaSize, followViewportHeight * 0.5f)
            : fullArenaSize;

        Vector3 desiredCenter = player != null && player.gameObject.activeInHierarchy
            ? player.transform.position
            : bounds.center;
        Vector2 playerPadding = GetPlayerPadding();
        float horizontalLimit = Mathf.Max(0f, bounds.extents.x - view.orthographicSize * view.aspect + playerPadding.x);
        float verticalLimit = Mathf.Max(0f, bounds.extents.y - view.orthographicSize + playerPadding.y);
        desiredCenter.x = Mathf.Clamp(desiredCenter.x, bounds.center.x - horizontalLimit, bounds.center.x + horizontalLimit);
        desiredCenter.y = Mathf.Clamp(desiredCenter.y, bounds.center.y - verticalLimit, bounds.center.y + verticalLimit);
        if (!instant)
        {
            Vector3 delta = desiredCenter - targetCenter;
            delta.x = Mathf.Abs(delta.x) <= followDeadZone ? 0f : delta.x;
            delta.y = Mathf.Abs(delta.y) <= followDeadZone ? 0f : delta.y;
            desiredCenter = Vector3.SmoothDamp(targetCenter, targetCenter + delta, ref followVelocity,
                followSmoothTime, followSmoothing, Time.deltaTime);
        }
        else followVelocity = Vector3.zero;
        targetCenter = desiredCenter;
        transform.SetPositionAndRotation(targetCenter - rotation * Vector3.forward * 30f, rotation);
    }

    private Vector2 GetPlayerPadding()
    {
        if (player == null) return Vector2.one * playerEdgeMargin;
        CharacterController controller = player.GetComponent<CharacterController>();
        if (controller == null) return Vector2.one * playerEdgeMargin;
        float horizontal = controller.radius * Mathf.Max(player.transform.lossyScale.x, player.transform.lossyScale.z);
        float vertical = controller.height * player.transform.lossyScale.y * 0.5f;
        return new Vector2(horizontal + playerEdgeMargin, vertical + playerEdgeMargin);
    }
}
