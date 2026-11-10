using System.Collections.Generic;
using UnityEngine;

// Builds a small physical terrain fragment spawned by an explosion.
[AddComponentMenu("Arena/Ground Rubble")]
public sealed class GroundRubble : MonoBehaviour
{
    private const float Lifetime = 8f;
    private const float ShrinkTime = 0.6f;

    private static readonly List<GroundRubble> active = new List<GroundRubble>();

    // Rubble currently in the scene, so callers do not need to search for it.
    public static IReadOnlyList<GroundRubble> Active => active;
    public Collider Collider { get; private set; }

    private Mesh mesh;
    private float age;
    private Vector3 startScale;

    private static MaterialPropertyBlock tintProperties;

    // Spawns one chunk. The impulse can include Z, so pieces fly toward and away
    // from the camera, and they tumble freely for a sense of depth. A tint
    // recolours the material, for example to match a player's colour.
    public static GroundRubble Spawn(Vector3 position, float size, Vector3 impulse, Material material,
        Transform parent, Color? tint = null)
    {
        var rubble = new GameObject("Ground Rubble");
        rubble.transform.SetParent(parent, true);
        rubble.transform.position = position;

        int sides = Random.Range(5, 8);
        var outline = new List<Vector2>(sides);
        for (int index = 0; index < sides; index++)
        {
            float angle = index * Mathf.PI * 2f / sides + Random.Range(-0.2f, 0.2f);
            float radius = size * Random.Range(0.7f, 1.25f);
            outline.Add(new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius);
        }

        // Chunky rather than flat, since pieces now turn in all directions.
        float depth = size * Random.Range(0.9f, 1.4f);
        var vertices = new List<Vector3>(sides * 4);
        var triangles = new List<int>((sides - 2) * 6 + sides * 6);
        foreach (Vector2 point in outline) vertices.Add(new Vector3(point.x, point.y, -depth * 0.5f));
        foreach (Vector2 point in outline) vertices.Add(new Vector3(point.x, point.y, depth * 0.5f));
        for (int index = 1; index < sides - 1; index++)
        {
            triangles.Add(0); triangles.Add(index + 1); triangles.Add(index);
            triangles.Add(sides); triangles.Add(sides + index); triangles.Add(sides + index + 1);
        }
        for (int index = 0; index < sides; index++)
        {
            int next = (index + 1) % sides;
            int side = vertices.Count;
            vertices.Add(new Vector3(outline[index].x, outline[index].y, -depth * 0.5f));
            vertices.Add(new Vector3(outline[next].x, outline[next].y, -depth * 0.5f));
            vertices.Add(new Vector3(outline[next].x, outline[next].y, depth * 0.5f));
            vertices.Add(new Vector3(outline[index].x, outline[index].y, depth * 0.5f));
            triangles.Add(side); triangles.Add(side + 1); triangles.Add(side + 2);
            triangles.Add(side); triangles.Add(side + 2); triangles.Add(side + 3);
        }

        var mesh = new Mesh { name = "Ground Rubble Mesh" };
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        var filter = rubble.AddComponent<MeshFilter>();
        filter.sharedMesh = mesh;
        var renderer = rubble.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = material;
        if (tint.HasValue)
        {
            if (tintProperties == null) tintProperties = new MaterialPropertyBlock();
            tintProperties.SetColor("_BaseColor", tint.Value);
            tintProperties.SetColor("_Color", tint.Value);
            renderer.SetPropertyBlock(tintProperties);
        }
        var collider = rubble.AddComponent<MeshCollider>();
        collider.sharedMesh = mesh;
        collider.convex = true;
        var body = rubble.AddComponent<Rigidbody>();
        body.mass = Random.Range(0.4f, 1.2f);
        body.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        body.AddForce(impulse, ForceMode.Impulse);
        body.AddTorque(Random.insideUnitSphere * 2f, ForceMode.Impulse);
        // Bombs pass through rubble instead of bouncing off it.
        foreach (FallingBomb bomb in FallingBomb.Active)
            if (bomb.TryGetComponent(out Collider bombCollider)) Physics.IgnoreCollision(collider, bombCollider);

        GroundRubble component = rubble.AddComponent<GroundRubble>();
        component.mesh = mesh;
        component.Collider = collider;
        component.startScale = rubble.transform.localScale;
        return component;
    }

    // Removes all rubble, for a fresh round.
    public static void ClearAll()
    {
        for (int i = active.Count - 1; i >= 0; i--)
        {
            GroundRubble rubble = active[i];
            rubble.gameObject.SetActive(false);
            Destroy(rubble.gameObject);
        }
    }

    private void OnEnable() => active.Add(this);
    private void OnDisable() => active.Remove(this);

    // Shrink away after a while so rubble does not pile up over a long round.
    private void Update()
    {
        age += Time.deltaTime;
        float shrinkStart = Lifetime - ShrinkTime;
        if (age < shrinkStart) return;
        float t = Mathf.Clamp01((age - shrinkStart) / ShrinkTime);
        transform.localScale = startScale * (1f - t);
        if (t >= 1f) Destroy(gameObject);
    }

    private void OnDestroy()
    {
        // Generated meshes are not freed with their GameObject.
        if (mesh != null) Destroy(mesh);
    }
}
