using System;
using System.Collections.Generic;
using System.Text;
using Bomb.CanonicalDestruction;
using UnityEngine;

[AddComponentMenu("Arena/Destructible Rock")]
public sealed class DestructibleRock : MonoBehaviour, IBlastReceiver
{
    private const float MinimumAuthoringExtent = 0.0001f;
    private const int CutterSegments = 24;
    private const float DefaultMassPerArea = 0.2f;
    private static readonly HashSet<DestructibleRock> SourceRocks = new HashSet<DestructibleRock>();

    [SerializeField, Tooltip("Stable authoring identity. When empty, a deterministic scene/hierarchy ID is used without relying on a Unity instance ID.")]
    private string canonicalEntityId;

    private Collider rockCollider;
    private Renderer[] rockRenderers;
    private Bounds originalBounds;
    private Material rockMaterial;
    private MaterialEntityId sourceId;
    private CanonicalMaterialWorld canonicalWorld;
    private CanonicalDestructionService destructionService;
    private CanonicalMaterialRuntimeProjector runtimeProjector;
    private string initialSnapshot;

    public CanonicalMaterialWorld CanonicalWorld => canonicalWorld;
    public MaterialEntityId SourceId => sourceId;

    private void Awake()
    {
        rockRenderers = GetComponentsInChildren<Renderer>(true);
        Collider[] colliders = GetComponentsInChildren<Collider>(true);
        foreach (Collider candidate in colliders)
        {
            if (candidate is MeshCollider mesh && mesh.sharedMesh != null)
            {
                rockCollider = candidate;
                break;
            }
        }
        if (rockCollider == null && colliders.Length > 0) rockCollider = colliders[0];
        foreach (Collider candidate in colliders)
        {
            if (candidate != rockCollider && candidate is MeshCollider mesh && mesh.sharedMesh == null)
                candidate.enabled = false;
        }
        if (rockCollider == null)
        {
            Debug.LogError(name + " cannot initialize canonical destruction without a source collider.", this);
            return;
        }

        originalBounds = rockCollider.bounds;
        foreach (Renderer renderer in rockRenderers)
        {
            if (renderer.sharedMaterial == null) continue;
            rockMaterial = renderer.sharedMaterial;
            break;
        }

        if (originalBounds.size.x <= MinimumAuthoringExtent || originalBounds.size.y <= MinimumAuthoringExtent)
        {
            SourceRocks.Add(this);
            Debug.LogWarning(name + " has no usable XY collider bounds, so canonical destruction is disabled until its missing authoring mesh is restored.", this);
            return;
        }

        sourceId = new MaterialEntityId(string.IsNullOrWhiteSpace(canonicalEntityId)
            ? BuildDeterministicAuthoringId()
            : canonicalEntityId.Trim());
        runtimeProjector = new CanonicalMaterialRuntimeProjector(transform.parent, rockMaterial);
        SourceRocks.Add(this);
        ResetRock();
    }

    public void ReceiveBlast(Vector2 center, float radius)
    {
        ReceiveBlast(sourceId, center, radius);
    }

    internal void ReceiveBlast(MaterialEntityId targetId, Vector2 center, float radius)
    {
        if (canonicalWorld == null || destructionService == null || radius <= 0f) return;
        if (!runtimeProjector.TryCaptureMotion(canonicalWorld, out string captureError))
        {
            Debug.LogError(captureError, this);
            return;
        }

        var request = new DestructionRequest(targetId,
            new CanonicalPolygon2D(CreateCircle(center, radius, CutterSegments)),
            center,
            radius * 2f);
        if (!destructionService.TryExecute(request, out DestructionCommitOutcome outcome, out string error))
        {
            Debug.LogError("Canonical rock destruction rejected: " + error, this);
            return;
        }
        if (!outcome.Changed) return;

        SetSourcePresentation(false);
        if (!RebuildRuntimeFromCanonical())
            Debug.LogError("Canonical rock state committed, but its derived runtime projection could not be rebuilt. Retry RebuildRuntimeFromCanonical().", this);
    }

    public void ResetRock()
    {
        if (rockCollider == null) return;
        if (runtimeProjector == null)
        {
            SetSourcePresentation(true);
            return;
        }
        runtimeProjector.Clear();
        if (!string.IsNullOrEmpty(initialSnapshot))
        {
            if (!CanonicalMaterialSnapshotCodec.TryDeserialize(initialSnapshot, out canonicalWorld, out string restoreError))
                throw new InvalidOperationException("Could not restore the initial canonical rock state: " + restoreError);
        }
        else
        {
            string prefix = sourceId.Value + "-fragment-";
            canonicalWorld = new CanonicalMaterialWorld(new SequentialMaterialEntityIdAllocator(prefix));
            CanonicalMaterialState initial = BuildInitialCanonicalState();
            if (!canonicalWorld.TryAddInitial(initial, out string error))
                throw new InvalidOperationException("Could not initialize canonical rock state: " + error);
            initialSnapshot = CanonicalMaterialSnapshotCodec.Serialize(canonicalWorld);
        }
        destructionService = new CanonicalDestructionService(canonicalWorld);
        SetSourcePresentation(true);
    }

    public static void ResetAllRocks()
    {
        var stale = new List<DestructibleRock>();
        foreach (DestructibleRock rock in SourceRocks)
        {
            if (rock == null) stale.Add(rock);
            else rock.ResetRock();
        }
        foreach (DestructibleRock rock in stale) SourceRocks.Remove(rock);
    }

    public string SaveCanonicalState()
    {
        if (canonicalWorld == null) return string.Empty;
        if (!runtimeProjector.TryCaptureMotion(canonicalWorld, out string error)) Debug.LogError(error, this);
        return CanonicalMaterialSnapshotCodec.Serialize(canonicalWorld, true);
    }

    public bool LoadCanonicalState(string json)
    {
        if (!CanonicalMaterialSnapshotCodec.TryDeserialize(json, out CanonicalMaterialWorld restored, out string error))
        {
            Debug.LogError("Could not load canonical rock state: " + error, this);
            return false;
        }
        canonicalWorld = restored;
        destructionService = new CanonicalDestructionService(canonicalWorld);
        SetSourcePresentation(false);
        return RebuildRuntimeFromCanonical();
    }

    public bool RebuildRuntimeFromCanonical()
    {
        if (canonicalWorld == null || runtimeProjector == null) return false;
        if (!runtimeProjector.TryReconcile(canonicalWorld, out string error))
        {
            Debug.LogError(error, this);
            return false;
        }

        foreach (CanonicalMaterialState state in canonicalWorld.Entities)
        {
            if (!runtimeProjector.TryGetProjection(state.Id, out GameObject projection))
            {
                Debug.LogError("Missing derived runtime projection for canonical material " + state.Id + ".", this);
                return false;
            }
            var receiver = projection.AddComponent<DestructibleRockProjection>();
            receiver.Initialize(this, state.Id);
        }
        return true;
    }

    private CanonicalMaterialState BuildInitialCanonicalState()
    {
        Vector2 position = originalBounds.center;
        float left = originalBounds.min.x - position.x;
        float right = originalBounds.max.x - position.x;
        float bottom = originalBounds.min.y - position.y;
        float top = originalBounds.max.y - position.y;
        var polygon = new CanonicalPolygon2D(new[]
        {
            new Vector2(left, bottom),
            new Vector2(right, bottom),
            new Vector2(right, top),
            new Vector2(left, top)
        });
        return new CanonicalMaterialState(sourceId, new CanonicalMaterialShape(new[] { polygon }), 1,
            position, 0f, Vector2.zero, 0f, CanonicalBodyMode.Static,
            Mathf.Max(0.01f, originalBounds.size.z), DefaultMassPerArea);
    }

    private void SetSourcePresentation(bool visible)
    {
        if (rockCollider != null) rockCollider.enabled = visible;
        if (rockRenderers == null) return;
        foreach (Renderer renderer in rockRenderers)
        {
            if (renderer != null) renderer.enabled = visible;
        }
    }

    private string BuildDeterministicAuthoringId()
    {
        var path = new StringBuilder(gameObject.scene.path);
        var names = new Stack<string>();
        Transform current = transform;
        while (current != null)
        {
            names.Push(current.name);
            current = current.parent;
        }
        while (names.Count > 0) path.Append('/').Append(names.Pop());

        unchecked
        {
            const ulong offset = 14695981039346656037UL;
            const ulong prime = 1099511628211UL;
            ulong hash = offset;
            foreach (char character in path.ToString())
            {
                hash ^= character;
                hash *= prime;
            }
            return "material-rock-" + hash.ToString("X16");
        }
    }

    private static Vector2[] CreateCircle(Vector2 center, float radius, int segments)
    {
        var points = new Vector2[segments];
        for (int i = 0; i < segments; i++)
        {
            float angle = i * Mathf.PI * 2f / segments;
            points[i] = center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius;
        }
        return points;
    }

    private void OnDestroy()
    {
        SourceRocks.Remove(this);
        runtimeProjector?.Dispose();
    }
}

public sealed class DestructibleRockProjection : MonoBehaviour, IBlastReceiver
{
    private DestructibleRock owner;
    private MaterialEntityId entityId;

    public void Initialize(DestructibleRock owner, MaterialEntityId entityId)
    {
        this.owner = owner;
        this.entityId = entityId;
    }

    public void ReceiveBlast(Vector2 center, float radius)
    {
        if (owner != null) owner.ReceiveBlast(entityId, center, radius);
    }
}
