using System.Collections.Generic;
using UnityEngine;

// Builds a small physical terrain fragment spawned by an explosion.
[AddComponentMenu("Arena/Ground Rubble")]
public sealed class GroundRubble : MonoBehaviour
{
    public static GroundRubble Spawn(Vector2 center, float size, Vector2 impulse, Material material, Transform parent)
    {
        var rubble = new GameObject("Ground Rubble");
        rubble.transform.SetParent(parent, true);
        rubble.transform.position = new Vector3(center.x, center.y, parent.position.z);

        int sides = Random.Range(5, 8);
        var outline = new List<Vector2>(sides);
        for (int index = 0; index < sides; index++)
        {
            float angle = index * Mathf.PI * 2f / sides + Random.Range(-0.2f, 0.2f);
            float radius = size * Random.Range(0.7f, 1.25f);
            outline.Add(new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * radius);
        }

        float depth = 0.22f;
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
        var collider = rubble.AddComponent<MeshCollider>();
        collider.sharedMesh = mesh;
        collider.convex = true;
        var body = rubble.AddComponent<Rigidbody>();
        body.mass = Random.Range(0.4f, 1.2f);
        body.constraints = RigidbodyConstraints.FreezePositionZ
            | RigidbodyConstraints.FreezeRotationX
            | RigidbodyConstraints.FreezeRotationY;
        body.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        body.AddForce(new Vector3(impulse.x, impulse.y, 0f), ForceMode.Impulse);
        body.AddTorque(Vector3.forward * Random.Range(-2f, 2f), ForceMode.Impulse);
        return rubble.AddComponent<GroundRubble>();
    }
}
