using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

namespace Bomb.CanonicalDestruction
{
    public sealed class CanonicalMaterialProjectionIdentity : MonoBehaviour
    {
        [SerializeField] private string canonicalId;

        public MaterialEntityId CanonicalId => new MaterialEntityId(canonicalId);
        internal void Initialize(MaterialEntityId id) => canonicalId = id.Value;
    }

    internal sealed class GeneratedMaterialProjection : MonoBehaviour
    {
        private readonly List<Mesh> meshes = new List<Mesh>();

        public void Own(Mesh mesh)
        {
            if (mesh != null) meshes.Add(mesh);
        }

        private void OnDestroy()
        {
            foreach (Mesh mesh in meshes)
            {
                if (mesh == null) continue;
                if (Application.isPlaying) Destroy(mesh);
                else DestroyImmediate(mesh);
            }
            meshes.Clear();
        }
    }

    public sealed class CanonicalMaterialRuntimeProjector : IDisposable
    {
        private readonly Transform parent;
        private readonly Material material;
        private readonly Dictionary<MaterialEntityId, ProjectionRecord> projections =
            new Dictionary<MaterialEntityId, ProjectionRecord>();
        private GameObject projectionRoot;

        public CanonicalMaterialRuntimeProjector(Transform parent, Material material)
        {
            this.parent = parent;
            this.material = material;
        }

        public int ProjectionCount => projections.Count;

        public bool TryGetProjection(MaterialEntityId id, out GameObject projection)
        {
            if (projections.TryGetValue(id, out ProjectionRecord record))
            {
                projection = record.Root;
                return projection != null;
            }
            projection = null;
            return false;
        }

        public bool TryReconcile(CanonicalMaterialWorld world, out string error)
        {
            if (world == null)
            {
                error = "Cannot project a missing canonical world.";
                return false;
            }

            GameObject stagedRoot = null;
            var staged = new Dictionary<MaterialEntityId, ProjectionRecord>();
            try
            {
                stagedRoot = new GameObject("Canonical Material Projections (staged)");
                stagedRoot.SetActive(false);
                if (parent != null) stagedRoot.transform.SetParent(parent, true);
                foreach (CanonicalMaterialState state in world.Entities.OrderBy(entity => entity.Id))
                {
                    if (!state.TryValidate(out error)) throw new InvalidOperationException(error);
                    ProjectionRecord record = BuildProjection(stagedRoot.transform, state);
                    if (!staged.TryAdd(state.Id, record))
                        throw new InvalidOperationException("Duplicate runtime projection ID " + state.Id + ".");
                }
            }
            catch (Exception exception)
            {
                DestroyObject(stagedRoot);
                error = "Runtime reconstruction failed and the previous projection was retained: " + exception.Message;
                return false;
            }

            GameObject previousRoot = projectionRoot;
            projectionRoot = stagedRoot;
            projectionRoot.name = "Canonical Material Projections";
            projections.Clear();
            foreach (KeyValuePair<MaterialEntityId, ProjectionRecord> pair in staged) projections.Add(pair.Key, pair.Value);
            if (previousRoot != null) previousRoot.SetActive(false);
            projectionRoot.SetActive(true);
            DestroyObject(previousRoot);
            error = null;
            return true;
        }

        public bool TryCaptureMotion(CanonicalMaterialWorld world, out string error)
        {
            if (world == null)
            {
                error = "Cannot capture runtime motion into a missing canonical world.";
                return false;
            }

            foreach (KeyValuePair<MaterialEntityId, ProjectionRecord> pair in projections)
            {
                ProjectionRecord record = pair.Value;
                if (record.Root == null || record.Body == null)
                {
                    error = "A runtime projection is stale for canonical entity " + pair.Key + ".";
                    return false;
                }

                Vector3 euler = record.Body.rotation.eulerAngles;
                Vector3 velocity = record.Body.linearVelocity;
                Vector3 angular = record.Body.angularVelocity;
                float rotationRadians = Mathf.DeltaAngle(0f, euler.z) * Mathf.Deg2Rad;
                if (!world.TryUpdateMotion(pair.Key, record.Body.position, rotationRadians,
                        new Vector2(velocity.x, velocity.y), angular.z, out error))
                    return false;
            }
            error = null;
            return true;
        }

        public void Clear()
        {
            if (projectionRoot != null) projectionRoot.SetActive(false);
            DestroyObject(projectionRoot);
            projectionRoot = null;
            projections.Clear();
        }

        public void Dispose() => Clear();

        private ProjectionRecord BuildProjection(Transform root, CanonicalMaterialState state)
        {
            var entity = new GameObject("Material " + state.Id.Value);
            entity.transform.SetParent(root, false);
            entity.transform.position = new Vector3(state.Position.x, state.Position.y, 0f);
            entity.transform.rotation = Quaternion.Euler(0f, 0f, state.RotationRadians * Mathf.Rad2Deg);
            entity.AddComponent<CanonicalMaterialProjectionIdentity>().Initialize(state.Id);
            var generated = entity.AddComponent<GeneratedMaterialProjection>();

            Mesh renderMesh = CanonicalShapeMesh.Build(state.Shape.Cells, state.Depth, "Material " + state.Id.Value + " Render");
            generated.Own(renderMesh);
            entity.AddComponent<MeshFilter>().sharedMesh = renderMesh;
            entity.AddComponent<MeshRenderer>().sharedMaterial = material;

            for (int i = 0; i < state.Shape.Cells.Count; i++)
            {
                var colliderObject = new GameObject("Canonical Cell " + i);
                colliderObject.transform.SetParent(entity.transform, false);
                Mesh colliderMesh = CanonicalShapeMesh.Build(new[] { state.Shape.Cells[i] }, state.Depth,
                    "Material " + state.Id.Value + " Collider " + i);
                generated.Own(colliderMesh);
                var collider = colliderObject.AddComponent<MeshCollider>();
                collider.sharedMesh = colliderMesh;
                collider.convex = true;
            }

            var body = entity.AddComponent<Rigidbody>();
            body.useGravity = state.BodyMode == CanonicalBodyMode.Dynamic;
            body.isKinematic = state.BodyMode == CanonicalBodyMode.Static;
            body.mass = Mathf.Max(0.1f, state.Shape.Area * state.MassPerArea);
            body.constraints = RigidbodyConstraints.FreezePositionZ
                | RigidbodyConstraints.FreezeRotationX
                | RigidbodyConstraints.FreezeRotationY;
            body.collisionDetectionMode = state.BodyMode == CanonicalBodyMode.Dynamic
                ? CollisionDetectionMode.ContinuousDynamic
                : CollisionDetectionMode.Discrete;
            body.interpolation = RigidbodyInterpolation.Interpolate;
            if (state.BodyMode == CanonicalBodyMode.Dynamic)
            {
                body.linearVelocity = new Vector3(state.LinearVelocity.x, state.LinearVelocity.y, 0f);
                body.angularVelocity = new Vector3(0f, 0f, state.AngularVelocityRadians);
            }

            return new ProjectionRecord(entity, body);
        }

        private static void DestroyObject(UnityEngine.Object value)
        {
            if (value == null) return;
            if (Application.isPlaying) UnityEngine.Object.Destroy(value);
            else UnityEngine.Object.DestroyImmediate(value);
        }

        private sealed class ProjectionRecord
        {
            public ProjectionRecord(GameObject root, Rigidbody body)
            {
                Root = root;
                Body = body;
            }

            public GameObject Root { get; }
            public Rigidbody Body { get; }
        }
    }
}
