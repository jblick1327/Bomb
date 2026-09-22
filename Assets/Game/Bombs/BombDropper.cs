using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

public enum CraterShape { Circle, Ellipse, Box }

[AddComponentMenu("Arena/Bomb Dropper")]
public sealed class BombDropper : MonoBehaviour
{
    [SerializeField] private CraterShape craterShape = CraterShape.Circle;
    [Tooltip("Size of the ground cut. For Box this is the base half-width and half-height, before shape scale.")]
    [SerializeField, Min(0.05f), InspectorName("Crater radius (units)")]
    private float craterRadius = 1.6f;
    [Tooltip("Width and height multipliers for Ellipse and Box. Circle ignores this setting.")]
    [SerializeField] private Vector2 craterShapeScale = Vector2.one;
    [Tooltip("Number of polygon edges for Circle and Ellipse. Box always uses four edges.")]
    [SerializeField, Range(8, 96)] private int craterSegments = 40;
    [SerializeField, InspectorName("Crater rotation (degrees)")]
    private float craterRotation;

    [Tooltip("Kills when the circle touches any part of the player's capsule. The blast ring grows to this radius.")]
    [SerializeField, Min(0f), InspectorName("Lethal radius (units)")]
    private float lethalRadius = 2.2f;

    [SerializeField, Min(0.05f), InspectorName("Bomb radius (units)")]
    private float bombRadius = 0.25f;
    [Tooltip("Extra distance from the side boundaries, in addition to the bomb radius.")]
    [SerializeField, Min(0f), InspectorName("Spawn edge padding (units)")]
    private float spawnEdgePadding = 0.75f;
    [SerializeField, Min(0.5f), InspectorName("Spawn height above arena (units)")]
    private float dropHeightAboveArena = 2f;
    [Tooltip("Positive downward acceleration. Bombs use this instead of Physics gravity.")]
    [SerializeField, Min(0.1f), InspectorName("Fall acceleration (units/s²)")]
    private float fallAcceleration = 18f;
    [SerializeField, Min(1f), InspectorName("Maximum lifetime (seconds)")]
    private float bombLifetime = 15f;

    [SerializeField] private Material bombMaterial;
    [SerializeField] private Material blastMaterial;
    [SerializeField, Min(0.05f), InspectorName("Blast duration (seconds)")]
    private float blastDuration = 0.35f;
    [Tooltip("Draw spawn range, crater outline and lethal radius when selected in the Scene view.")]
    [SerializeField] private bool showSizePreviews;

    [SerializeField] private ArenaLayout layout;
    [SerializeField] private ArenaSession session;
    [SerializeField] private DestructibleGround ground;
    [SerializeField] private ArenaPlayerController player;
    [SerializeField, Tooltip("Bombs ignore this collider so they can fall into the arena from above.")]
    private Collider upperBoundary;

    private Transform transientRoot;
    public bool CanRun => session == null || session.IsPlaying;

    private void Update()
    {
        if (CanRun && Keyboard.current != null && Keyboard.current.bKey.wasPressedThisFrame) DropBomb();
    }

    public FallingBomb DropBomb()
    {
        if (!CanRun || layout == null) return null;
        float halfRange = Mathf.Max(0f, layout.Width * 0.5f - bombRadius - spawnEdgePadding);
        float x = Random.Range(-halfRange, halfRange);
        var body = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        body.name = "Falling Bomb";
        body.transform.position = layout.Origin + new Vector3(x, layout.Height + dropHeightAboveArena, 0f);
        body.transform.SetParent(GetTransientRoot(), true);
        body.transform.localScale = Vector3.one * bombRadius * 2f;
        body.GetComponent<Renderer>().sharedMaterial = bombMaterial;
        var collider = body.GetComponent<SphereCollider>();
        var rigidbody = body.AddComponent<Rigidbody>();
        rigidbody.useGravity = false;
        rigidbody.constraints = RigidbodyConstraints.FreezePositionX | RigidbodyConstraints.FreezePositionZ | RigidbodyConstraints.FreezeRotation;
        rigidbody.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        rigidbody.interpolation = RigidbodyInterpolation.Interpolate;
        if (upperBoundary != null) Physics.IgnoreCollision(collider, upperBoundary);

        var fuse = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        fuse.name = "Fuse";
        fuse.transform.SetParent(body.transform, false);
        fuse.transform.localPosition = new Vector3(0.12f, 0.52f, 0f);
        fuse.transform.localRotation = Quaternion.Euler(0f, 0f, -20f);
        fuse.transform.localScale = new Vector3(0.1f, 0.15f, 0.1f);
        // Disable immediately: Destroy is deferred until the end of the frame.
        fuse.GetComponent<Collider>().enabled = false;
        Destroy(fuse.GetComponent<Collider>());
        fuse.GetComponent<Renderer>().sharedMaterial = blastMaterial;

        var bomb = body.AddComponent<FallingBomb>();
        bomb.Initialize(this, fallAcceleration, bombLifetime);
        return bomb;
    }

    public void Explode(Vector2 center)
    {
        if (!CanRun) return;
        if (ground != null) ground.Carve(CreateCraterOutline(center));
        AffectBlastReceivers(center);
        if (player != null && player.gameObject.activeInHierarchy
            && player.DistanceToBody(center) <= lethalRadius)
        {
            if (session != null) session.KillPlayer();
            else player.gameObject.SetActive(false);
        }

        var visual = new GameObject("Blast");
        visual.transform.SetParent(GetTransientRoot(), true);
        var ring = visual.AddComponent<LineRenderer>();
        ring.sharedMaterial = blastMaterial;
        ring.useWorldSpace = false;
        ring.loop = true;
        ring.positionCount = 64;
        ring.startWidth = ring.endWidth = 0.12f;
        ring.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        ring.receiveShadows = false;
        for (int i = 0; i < ring.positionCount; i++)
        {
            float angle = i * Mathf.PI * 2f / ring.positionCount;
            ring.SetPosition(i, new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0f));
        }
        Vector3 origin = new Vector3(center.x, center.y, layout != null ? layout.Origin.z : 0f);
        Vector3 forward = Camera.main != null ? Camera.main.transform.forward : Vector3.forward;
        float frontDistance = ((layout != null ? layout.Depth : 0f) * 0.5f + 0.1f) / Mathf.Max(Mathf.Abs(forward.z), 0.1f);
        visual.transform.position = origin - forward * frontDistance;
        visual.AddComponent<BombBlastVisual>().Initialize(lethalRadius, blastDuration);
    }

    private void AffectBlastReceivers(Vector2 center)
    {
        Vector3 queryCenter = new Vector3(center.x, center.y, layout != null ? layout.Origin.z : transform.position.z);
        float halfDepth = layout != null ? layout.Depth * 0.5f + 0.5f : 10f;
        Collider[] colliders = Physics.OverlapBox(queryCenter, new Vector3(lethalRadius, lethalRadius, halfDepth));
        var receivers = new HashSet<IBlastReceiver>();
        foreach (Collider collider in colliders)
        {
            foreach (MonoBehaviour component in collider.GetComponentsInParent<MonoBehaviour>(true))
            {
                if (component is IBlastReceiver receiver)
                    receivers.Add(receiver);
            }
        }

        foreach (IBlastReceiver receiver in receivers)
            receiver.ReceiveBlast(center, lethalRadius);
    }

    public void ClearTransientObjects()
    {
        if (transientRoot == null) return;
        transientRoot.gameObject.SetActive(false);
        Destroy(transientRoot.gameObject);
        transientRoot = null;
    }

    private Transform GetTransientRoot()
    {
        if (transientRoot == null)
        {
            transientRoot = new GameObject("Round Effects").transform;
            transientRoot.SetParent(transform, false);
        }
        return transientRoot;
    }

    public Vector2[] CreateCraterOutline(Vector2 center)
    {
        int count = craterShape == CraterShape.Box ? 4 : Mathf.Clamp(craterSegments, 8, 96);
        var outline = new Vector2[count];
        Vector2 scale = craterShape == CraterShape.Circle ? Vector2.one
            : new Vector2(Mathf.Max(0.05f, craterShapeScale.x), Mathf.Max(0.05f, craterShapeScale.y));
        Quaternion rotation = Quaternion.Euler(0f, 0f, craterRotation);
        for (int i = 0; i < count; i++)
        {
            Vector2 point;
            if (craterShape == CraterShape.Box)
                point = new Vector2(i == 0 || i == 3 ? -1f : 1f, i < 2 ? -1f : 1f);
            else
            {
                float angle = i * Mathf.PI * 2f / count;
                point = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
            }
            outline[i] = center + (Vector2)(rotation * (Vector3)(Vector2.Scale(point, scale) * Mathf.Max(0.05f, craterRadius)));
        }
        return outline;
    }

    private void OnDrawGizmosSelected()
    {
        if (!showSizePreviews || layout == null) return;
        Vector3 origin = layout.Origin;
        float halfRange = Mathf.Max(0f, layout.Width * 0.5f - bombRadius - spawnEdgePadding);
        Gizmos.color = Color.yellow;
        Gizmos.DrawLine(origin + new Vector3(-halfRange, layout.Height + dropHeightAboveArena, 0f),
            origin + new Vector3(halfRange, layout.Height + dropHeightAboveArena, 0f));
        Vector2 center = (Vector2)origin + Vector2.up * layout.GroundTop;
        Vector2[] outline = CreateCraterOutline(center);
        Gizmos.color = Color.cyan;
        for (int i = 0; i < outline.Length; i++)
            Gizmos.DrawLine(new Vector3(outline[i].x, outline[i].y, origin.z), new Vector3(outline[(i + 1) % outline.Length].x, outline[(i + 1) % outline.Length].y, origin.z));
        Gizmos.color = Color.red;
        for (int i = 0; i < 64; i++)
        {
            float a = i * Mathf.PI * 2f / 64f;
            float b = (i + 1) * Mathf.PI * 2f / 64f;
            Gizmos.DrawLine(new Vector3(center.x + Mathf.Cos(a) * lethalRadius, center.y + Mathf.Sin(a) * lethalRadius, origin.z),
                new Vector3(center.x + Mathf.Cos(b) * lethalRadius, center.y + Mathf.Sin(b) * lethalRadius, origin.z));
        }
    }
}
