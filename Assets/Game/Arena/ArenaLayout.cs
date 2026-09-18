using UnityEngine;

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

    public float Width => width;
    public float Height => height;
    public float Depth => depth;
    public float GroundTop => height * groundFraction;
    public float GroundBottom => -wallThickness;
    public Vector3 Origin => transform.position;
    public Rect GroundRect => Rect.MinMaxRect(-width * 0.5f, GroundBottom, width * 0.5f, GroundTop);
    public Bounds ViewBounds => new Bounds(Origin + Vector3.up * height * 0.5f,
        new Vector3(width + wallThickness * 2f, height + wallThickness * 2f, depth + 0.3f));
    public Vector3 PlayerSpawn => Origin + new Vector3(0f, GroundTop + 0.85f, 0f);

    private void OnEnable() => ApplyGeometry();
    private void OnValidate() => ApplyGeometry();

    public void ApplyGeometry()
    {
        SetBox("Left Wall", new Vector3(-(width + wallThickness) * 0.5f, height * 0.5f, 0f),
            new Vector3(wallThickness, height, depth));
        SetBox("Right Wall", new Vector3((width + wallThickness) * 0.5f, height * 0.5f, 0f),
            new Vector3(wallThickness, height, depth));
        HideWall("Left Wall");
        HideWall("Right Wall");
        SetBox("Upper Boundary", new Vector3(0f, height + wallThickness * 0.5f, 0f),
            new Vector3(width + wallThickness * 2f, wallThickness, depth));
        SetBox("Bottom Boundary", new Vector3(0f, GroundBottom - wallThickness * 0.5f, 0f),
            new Vector3(width + wallThickness * 2f, wallThickness, depth));
        SetBox("Back Wall", new Vector3(0f, height * 0.5f, depth * 0.5f + 0.15f),
            new Vector3(width, height, 0.3f));
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

    private void SetBox(string name, Vector3 position, Vector3 scale)
    {
        Transform box = transform.Find(name);
        if (box == null) return;
        box.localPosition = position;
        box.localScale = scale;
    }

    private void HideWall(string name)
    {
        Transform wall = transform.Find(name);
        if (wall == null) return;
        foreach (Renderer renderer in wall.GetComponentsInChildren<Renderer>())
            renderer.enabled = false;
    }
}
