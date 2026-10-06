using UnityEngine;

// Stores arena dimensions and keeps its boundaries aligned with the selected level bounds.
[ExecuteAlways]
[AddComponentMenu("Arena/Arena Layout")]
public sealed class ArenaLayout : MonoBehaviour
{
    [Header("Arena size")]
    [SerializeField, Min(4f), InspectorName("Width (units)")]
    private float width = 20f;
    [Tooltip("Total height from the arena base to the invisible upper boundary.")]
    [SerializeField, Min(4f), InspectorName("Height (units)")]
    private float height = 12f;
    [Tooltip("Terrain is extruded along Z. Movement and blast distance use XY.")]
    [SerializeField, Min(0.5f), InspectorName("Depth (units)")]
    private float depth = 4.6f;

    [Header("Ground and boundaries")]
    [Tooltip("Portion of the arena height filled with ground. 0.5 fills the lower half.")]
    [SerializeField, Range(0.1f, 0.8f), InspectorName("Ground fill (fraction)")]
    private float groundFraction = 0.5f;
    [Tooltip("Thickness of the indestructible boundary colliders; also extends ground below the base.")]
    [SerializeField, Min(0.1f), InspectorName("Boundary thickness (units)")]
    private float wallThickness = 0.6f;

    [Header("Imported level bounds")]
    [Tooltip("Optional visual or collider hierarchy used to suggest the playable rectangle.")]
    [SerializeField] private Transform boundsSource;
    [Tooltip("Collider defining the exact playable level rectangle. A child named Level Bounds is discovered automatically.")]
    [SerializeField] private Collider levelBoundsCollider;
    [Tooltip("When enabled, dimensions are read from the bounds source before manual padding is applied.")]
    [SerializeField] private bool deriveBoundsFromSource;
    [SerializeField, Min(0f), InspectorName("Bounds padding (units)")]
    private float boundsPadding = 0f;

    public float Width => width;
    public float Height => height;
    public float Depth => depth;
    public float GroundTop => GetGroundTop();
    public float GroundBottom => -wallThickness;
    public Vector3 Origin
    {
        get
        {
            ResolveLevelBounds();
            if (levelBoundsCollider != null)
            {
                Bounds bounds = levelBoundsCollider.bounds;
                return new Vector3(bounds.center.x, bounds.min.y, bounds.center.z);
            }
            return transform.position;
        }
    }
    public Bounds CameraBounds => GetLevelBounds();
    public float LeftEdge => CameraBounds.min.x;
    public float RightEdge => CameraBounds.max.x;
    public Rect GroundRect => Rect.MinMaxRect(Origin.x - width * 0.5f, Origin.y + GroundBottom,
        Origin.x + width * 0.5f, Origin.y + GroundTop);
    public Bounds ViewBounds => new Bounds(Origin + Vector3.up * height * 0.5f,
        new Vector3(width + wallThickness * 2f, height + wallThickness * 2f, depth + 0.3f));
    public Vector3 PlayerSpawn => Origin + new Vector3(0f, GroundTop + (deriveBoundsFromSource ? 0.8f : 0.85f), 0f);

    private float GetGroundTop()
    {
        if (deriveBoundsFromSource && boundsSource != null)
        {
            foreach (Renderer renderer in boundsSource.GetComponentsInChildren<Renderer>(true))
            {
                if (renderer.name == "Grass_Mesh")
                    return renderer.bounds.max.y - Origin.y;
            }
        }
        return height * groundFraction;
    }

    private void OnEnable() => ApplyGeometry();
    private void OnValidate() => ApplyGeometry();

    public void ApplyGeometry()
    {
        ResolveLevelBounds();
        if (levelBoundsCollider != null) ApplyColliderBounds();
        else if (deriveBoundsFromSource) ApplySourceBounds();

        if (levelBoundsCollider != null)
        {
            levelBoundsCollider.isTrigger = true;
            Bounds bounds = levelBoundsCollider.bounds;
            SetWorldBoundary("Left Wall", new Vector3(bounds.min.x - wallThickness * 0.5f, bounds.center.y, Origin.z),
                new Vector3(wallThickness, bounds.size.y, depth));
            SetWorldBoundary("Right Wall", new Vector3(bounds.max.x + wallThickness * 0.5f, bounds.center.y, Origin.z),
                new Vector3(wallThickness, bounds.size.y, depth));
            DisableBoundary("Upper Boundary");
            SetWorldBox("Bottom Boundary", new Vector3(Origin.x, Origin.y + GroundBottom - wallThickness * 0.5f, Origin.z),
                new Vector3(width + wallThickness * 2f, wallThickness, depth));
            SetWorldBox("Back Wall", new Vector3(Origin.x, Origin.y + height * 0.5f, Origin.z + depth * 0.5f + 0.15f),
                new Vector3(width, height, 0.3f));
        }
        else
        {
            SetBox("Left Wall", new Vector3(-(width + wallThickness) * 0.5f, height * 0.5f, 0f),
                new Vector3(wallThickness, height, depth));
            SetBox("Right Wall", new Vector3((width + wallThickness) * 0.5f, height * 0.5f, 0f),
                new Vector3(wallThickness, height, depth));
            HideWall("Left Wall");
            HideWall("Right Wall");
            SetBox("Upper Boundary", new Vector3(0f, height + wallThickness * 0.5f, 0f),
                new Vector3(width + wallThickness * 2f, wallThickness, depth));
        }
        if (levelBoundsCollider == null)
        {
            SetBox("Bottom Boundary", new Vector3(0f, GroundBottom - wallThickness * 0.5f, 0f),
                new Vector3(width + wallThickness * 2f, wallThickness, depth));
            SetBox("Back Wall", new Vector3(0f, height * 0.5f, depth * 0.5f + 0.15f),
                new Vector3(width, height, 0.3f));
        }
        Transform grid = transform.Find("Background Grid");
        if (grid != null)
        {
            grid.localScale = new Vector3(width / 20f, height / 12f, 1f);
            foreach (Transform line in grid)
            {
                Vector3 position = line.localPosition;
                position.z = depth * 0.5f - 0.01f;
                line.localPosition = position;
            }
        }
    }

    private void ResolveLevelBounds()
    {
        if (levelBoundsCollider != null) return;
        Transform bounds = transform.Find("Level Bounds");
        if (bounds != null) levelBoundsCollider = bounds.GetComponent<Collider>();
    }

    private void ApplyColliderBounds()
    {
        Bounds sourceBounds = levelBoundsCollider.bounds;
        width = Mathf.Max(4f, sourceBounds.size.x + boundsPadding * 2f);
        height = Mathf.Max(4f, sourceBounds.size.y + boundsPadding * 2f);
        depth = Mathf.Max(0.5f, sourceBounds.size.z + boundsPadding * 2f);
    }

    private Bounds GetLevelBounds()
    {
        ResolveLevelBounds();
        if (levelBoundsCollider != null) return levelBoundsCollider.bounds;
        return new Bounds(Origin + Vector3.up * height * 0.5f,
            new Vector3(width + wallThickness * 2f, height + wallThickness * 2f, depth + 0.3f));
    }

    private void ApplySourceBounds()
    {
        if (boundsSource == null) return;
        Renderer[] renderers = boundsSource.GetComponentsInChildren<Renderer>(true);
        if (renderers.Length == 0) return;

        Bounds sourceBounds = renderers[0].bounds;
        for (int i = 1; i < renderers.Length; i++) sourceBounds.Encapsulate(renderers[i].bounds);
        width = Mathf.Max(4f, sourceBounds.size.x + boundsPadding * 2f);
        height = Mathf.Max(4f, sourceBounds.size.y + boundsPadding * 2f);
        depth = Mathf.Max(0.5f, sourceBounds.size.z + boundsPadding * 2f);
        transform.position = new Vector3(sourceBounds.center.x, sourceBounds.min.y, sourceBounds.center.z);
    }

    private void SetBox(string name, Vector3 position, Vector3 scale)
    {
        Transform box = transform.Find(name);
        if (box == null) return;
        box.localPosition = position;
        box.localScale = scale;
    }

    private void SetWorldBox(string name, Vector3 position, Vector3 scale)
    {
        Transform box = EnsureBoundary(name);
        box.position = position;
        box.localScale = scale;
    }

    private void SetWorldBoundary(string name, Vector3 position, Vector3 size)
    {
        Transform boundary = EnsureBoundary(name);
        boundary.position = position;
        boundary.localScale = Vector3.one;
        BoxCollider collider = boundary.GetComponent<BoxCollider>();
        collider.size = size;
        collider.enabled = true;
        foreach (Renderer renderer in boundary.GetComponentsInChildren<Renderer>()) renderer.enabled = false;
    }

    private Transform EnsureBoundary(string name)
    {
        Transform boundary = transform.Find(name);
        if (boundary != null)
        {
            if (boundary.GetComponent<BoxCollider>() == null) boundary.gameObject.AddComponent<BoxCollider>();
            return boundary;
        }

        GameObject created = new GameObject(name);
        created.transform.SetParent(transform, true);
        created.AddComponent<BoxCollider>();
        return created.transform;
    }

    private void DisableBoundary(string name)
    {
        Transform wall = transform.Find(name);
        if (wall == null) return;
        foreach (Collider collider in wall.GetComponentsInChildren<Collider>()) collider.enabled = false;
        foreach (Renderer renderer in wall.GetComponentsInChildren<Renderer>()) renderer.enabled = false;
    }

    private void HideWall(string name)
    {
        Transform wall = transform.Find(name);
        if (wall == null) return;
        foreach (Renderer renderer in wall.GetComponentsInChildren<Renderer>()) renderer.enabled = false;
    }
}
