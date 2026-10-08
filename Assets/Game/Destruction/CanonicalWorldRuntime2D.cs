using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Bomb.CanonicalDestruction
{
    public readonly struct ConnectorLoad
    {
        public ConnectorLoad(Vector2 force, float torque) { Force = force; Torque = torque; }
        public Vector2 Force { get; }
        public float Torque { get; }
    }

    public sealed class CanonicalWorldRuntime2D : ICanonicalWorldProjection, IDisposable
    {
        private readonly Scene scene;
        private Dictionary<MaterialEntityId, Rigidbody2D> bodies = new Dictionary<MaterialEntityId, Rigidbody2D>();
        private Dictionary<MaterialEntityId, HingeJoint2D[]> connectors = new Dictionary<MaterialEntityId, HingeJoint2D[]>();
        private Dictionary<MaterialEntityId, DistanceJoint2D> holds = new Dictionary<MaterialEntityId, DistanceJoint2D>();
        private Prepared active;
        private CanonicalWorldView view;
        private bool disposed;
        private readonly HashSet<MaterialEntityId> landed = new HashSet<MaterialEntityId>();
        public const float StepSeconds = 0.02f;
        public static readonly Vector2 Gravity = new Vector2(0, -9.81f);
        public Scene Scene => scene;
        public int ProjectionCount => bodies.Count;
        public float PresentationDepthMultiplier { get; set; } = 1;
        public int Steps { get; private set; }
        public CanonicalWorldRuntime2D()
        {
            if (!Application.isPlaying) throw new InvalidOperationException("The authoritative 2D adapter runs in Play mode.");
            scene = SceneManager.CreateScene("Canonical2D-" + Guid.NewGuid().ToString("N"), new CreateSceneParameters(LocalPhysicsMode.Physics2D));
        }
        public bool TryGetBody(MaterialEntityId id, out Rigidbody2D body) => bodies.TryGetValue(id, out body);
        public DistanceJoint2D HoldJoint(MaterialEntityId id) => holds.TryGetValue(id, out var joint) ? joint : null;
        public HingeJoint2D[] ConnectorJoints(MaterialEntityId id) => connectors.TryGetValue(id, out var joints) ? (HingeJoint2D[])joints.Clone() : Array.Empty<HingeJoint2D>();
        public bool TryPrepare(CanonicalWorldView next, DefinitionSet definitions, out IPreparedCanonicalProjection prepared, out string error)
        {
            prepared = null; error = null;
            if (disposed || !next.TryValidate(definitions, out error)) { error = error ?? "Runtime adapter is disposed."; return false; }
            var staged = new Prepared(this, next);
            try
            {
                staged.Root = new GameObject("Canonical world (derived 2D bodies / 3D appearance)");
                staged.Root.SetActive(false);
                SceneManager.MoveGameObjectToScene(staged.Root, scene);
                foreach (var state in next.Bodies.OrderBy(b => b.Id))
                {
                    if (state.Selection == null) throw new InvalidOperationException("The conformance 2D adapter requires explicit resolved definitions.");
                    var material = definitions.Resolve(state.Selection.Material);
                    var appearance = definitions.Resolve(state.Selection.Appearance);
                    var entity = new GameObject(state.Id.Value);
                    entity.transform.SetParent(staged.Root.transform, false);
                    entity.transform.SetPositionAndRotation(new Vector3(state.Position.x, state.Position.y, 0), Quaternion.Euler(0, 0, state.RotationRadians * Mathf.Rad2Deg));
                    entity.AddComponent<CanonicalMaterialProjectionIdentity>().Initialize(state.Id);
                    var mesh = CanonicalShapeMesh.Build(state.Shape.Cells, appearance.depth * PresentationDepthMultiplier, "Current shape " + state.Id);
                    entity.AddComponent<MeshFilter>().sharedMesh = mesh;
                    staged.Owned.Add(mesh);
                    var shader = Shader.Find("Universal Render Pipeline/Unlit");
                    if (shader == null) throw new InvalidOperationException("Required URP Unlit shader is unavailable.");
                    var visual = new Material(shader);
                    visual.SetColor("_BaseColor", appearance.tint);
                    staged.Owned.Add(visual);
                    entity.AddComponent<MeshRenderer>().sharedMaterial = visual;
                    var physical = new PhysicsMaterial2D("Resolved material " + state.Selection.Material.id) { friction = material.friction, bounciness = material.restitution };
                    staged.Owned.Add(physical);
                    // Multiple touching paths can be unified into an unintended hull by PolygonCollider2D.
                    // One convex cell per collider preserves the declared union on one shared Rigidbody2D.
                    foreach (var cell in state.Shape.Cells)
                    {
                        var collider = entity.AddComponent<PolygonCollider2D>();
                        collider.sharedMaterial = physical;
                        collider.SetPath(0, cell.Vertices.ToArray());
                    }
                    var body = entity.AddComponent<Rigidbody2D>();
                    body.bodyType = state.BodyMode == CanonicalBodyMode.Static ? RigidbodyType2D.Static : RigidbodyType2D.Dynamic;
                    body.gravityScale = 0; // Local host gravity; no mutation of the project's global physics settings.
                    body.useAutoMass = false;
                    body.mass = state.Mass(definitions);
                    body.centerOfMass = state.Shape.Centroid;
                    body.linearDamping = material.linearDamping;
                    body.angularDamping = material.angularDamping;
                    body.collisionDetectionMode = CollisionDetectionMode2D.Continuous;
                    body.interpolation = RigidbodyInterpolation2D.None;
                    if (state.BodyMode == CanonicalBodyMode.Dynamic)
                    {
                        if (Mathf.Abs(body.mass - state.Mass(definitions)) > Mathf.Max(0.000001f, state.Mass(definitions) * 0.00001f))
                            throw new InvalidOperationException("Engine mass limit differs from resolved density × area for " + state.Id);
                        body.linearVelocity = state.LinearVelocity;
                        body.angularVelocity = state.AngularVelocityRadians * Mathf.Rad2Deg;
                    }
                    staged.Bodies.Add(state.Id, body);
                    if (state.IsBomb) entity.AddComponent<CanonicalBombContactSensor>().Initialize(this, state.Id);
                }
                foreach (var connector in next.Connectors)
                {
                    var joints = new[] {
                        Pin(staged.Bodies[connector.A], staged.Bodies[connector.B], connector.A0, connector.B0),
                        Pin(staged.Bodies[connector.A], staged.Bodies[connector.B], connector.A1, connector.B1) };
                    staged.Connectors.Add(connector.Id, joints);
                }
                foreach (var hold in next.Holds)
                {
                    var character = next.Body(hold.Character);
                    var role = definitions.Resolve(character.Selection.Role);
                    var joint = staged.Bodies[hold.Character].gameObject.AddComponent<DistanceJoint2D>();
                    joint.connectedBody = staged.Bodies[hold.Target];
                    joint.autoConfigureConnectedAnchor = false; joint.autoConfigureDistance = false;
                    joint.anchor = role.Root(hold.Slot); joint.connectedAnchor = hold.HeldLocal;
                    joint.distance = role.Reach(hold.Slot); joint.maxDistanceOnly = true;
                    joint.enableCollision = true; joint.breakForce = float.PositiveInfinity; joint.breakTorque = float.PositiveInfinity;
                    staged.Holds.Add(hold.Id, joint);
                }
                prepared = staged; return true;
            }
            catch (Exception exception) { staged.Dispose(); error = "2D projection preparation failed: " + exception.Message; return false; }
        }
        private static HingeJoint2D Pin(Rigidbody2D a, Rigidbody2D b, Vector2 anchor, Vector2 connectedAnchor)
        {
            var pin = a.gameObject.AddComponent<HingeJoint2D>();
            pin.connectedBody = b; pin.autoConfigureConnectedAnchor = false;
            pin.anchor = anchor; pin.connectedAnchor = connectedAnchor;
            pin.useLimits = false; pin.useMotor = false; pin.enableCollision = false;
            pin.breakForce = float.PositiveInfinity; pin.breakTorque = float.PositiveInfinity;
            return pin;
        }
        public bool TryRebuild(CanonicalMaterialWorld world, out string error)
        {
            if (!TryPrepare(world.View, world.Definitions, out var prepared, out error)) return false;
            prepared.Publish(); world.Projection = this; return true;
        }
        public bool TryCaptureMotion(CanonicalMaterialWorld world, out string error)
        {
            var updates = new List<CanonicalMaterialState>();
            foreach (var state in world.View.Bodies)
            {
                if (!bodies.TryGetValue(state.Id, out var body) || body == null) { error = "Missing derived body " + state.Id; return false; }
                updates.Add(state.WithMotion(body.position, body.rotation * Mathf.Deg2Rad, body.linearVelocity, body.angularVelocity * Mathf.Deg2Rad));
            }
            return world.TryUpdateBodyBatch(updates, out error);
        }
        public IReadOnlyCollection<MaterialEntityId> Step(float seconds = StepSeconds)
        {
            if (disposed || active == null || seconds != StepSeconds) throw new InvalidOperationException("The fixture uses one authoritative fixed 0.02-second step.");
            landed.Clear();
            foreach (var body in bodies.Values)
                if (body.bodyType == RigidbodyType2D.Dynamic) body.AddForce(body.mass * Gravity, ForceMode2D.Force);
            Physics2D.SyncTransforms();
            if (!scene.GetPhysicsScene2D().Simulate(seconds)) throw new InvalidOperationException("Local PhysicsScene2D refused simulation.");
            Steps++; return landed.ToArray();
        }
        internal void ObserveLanding(MaterialEntityId bomb, Collision2D collision)
        {
            foreach (var contact in collision.contacts)
            {
                if (contact.normal.y < 0.5f || Vector2.Dot(collision.relativeVelocity, contact.normal) > 0.01f) continue;
                var candidates = new[] { contact.collider, contact.otherCollider };
                foreach (var collider in candidates)
                {
                    var identity = collider.GetComponent<CanonicalMaterialProjectionIdentity>();
                    if (identity == null || identity.CanonicalId == bomb) continue;
                    var support = view.Body(identity.CanonicalId);
                    if (support != null && !support.IsCharacter && !support.IsBomb) landed.Add(bomb);
                }
            }
        }
        public ConnectorLoad Measure(CanonicalConnector connector)
        {
            Vector2 force = Vector2.zero; float torque = 0;
            if (!connectors.TryGetValue(connector.Id, out var pins)) throw new InvalidOperationException("Missing connector projection.");
            Vector2 midpoint = bodies[connector.A].GetRelativePoint((connector.A0 + connector.A1) * 0.5f);
            foreach (var pin in pins)
            {
                Vector2 reaction = pin.GetReactionForce(StepSeconds);
                force += reaction;
                torque += pin.GetReactionTorque(StepSeconds) + CanonicalPolygon2D.Cross(bodies[connector.A].GetRelativePoint(pin.anchor) - midpoint, reaction);
            }
            return new ConnectorLoad(force, torque);
        }
        public void Clear()
        {
            active?.Dispose(); active = null; bodies = new Dictionary<MaterialEntityId, Rigidbody2D>();
            connectors = new Dictionary<MaterialEntityId, HingeJoint2D[]>(); holds = new Dictionary<MaterialEntityId, DistanceJoint2D>(); view = null;
        }
        public void Dispose() { if (disposed) return; Clear(); disposed = true; if (scene.IsValid() && scene.isLoaded) SceneManager.UnloadSceneAsync(scene); }
        private static void Destroy(UnityEngine.Object value) { if (value == null) return; if (Application.isPlaying) UnityEngine.Object.Destroy(value); else UnityEngine.Object.DestroyImmediate(value); }
        private sealed class Prepared : IPreparedCanonicalProjection
        {
            private readonly CanonicalWorldRuntime2D owner;
            private readonly CanonicalWorldView next;
            public GameObject Root;
            public readonly List<UnityEngine.Object> Owned = new List<UnityEngine.Object>();
            public readonly Dictionary<MaterialEntityId, Rigidbody2D> Bodies = new Dictionary<MaterialEntityId, Rigidbody2D>();
            public readonly Dictionary<MaterialEntityId, HingeJoint2D[]> Connectors = new Dictionary<MaterialEntityId, HingeJoint2D[]>();
            public readonly Dictionary<MaterialEntityId, DistanceJoint2D> Holds = new Dictionary<MaterialEntityId, DistanceJoint2D>();
            public Prepared(CanonicalWorldRuntime2D owner, CanonicalWorldView next) { this.owner = owner; this.next = next; }
            public void Publish()
            {
                var previous = owner.active;
                if (previous != null) previous.Root.SetActive(false);
                owner.active = this; owner.bodies = Bodies; owner.connectors = Connectors; owner.holds = Holds; owner.view = next;
                Root.SetActive(true);
                // Unity creates/enables native bodies on activation and resets staged velocities.
                // Restore canonical COM motion after activation, before observers can see the publication.
                foreach (var state in next.Bodies.Where(b => b.BodyMode == CanonicalBodyMode.Dynamic))
                {
                    Bodies[state.Id].linearVelocity = state.LinearVelocity;
                    Bodies[state.Id].angularVelocity = state.AngularVelocityRadians * Mathf.Rad2Deg;
                }
                previous?.Dispose();
            }
            public void Dispose() { if (Root != null) Root.SetActive(false); Destroy(Root); Root = null; foreach (var item in Owned) Destroy(item); Owned.Clear(); }
        }
    }
}
