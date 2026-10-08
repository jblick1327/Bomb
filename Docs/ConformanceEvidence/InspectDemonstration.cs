if (!UnityEditor.EditorApplication.isPlaying) throw new System.InvalidOperationException("The demonstration is not playing.");
var fixture = UnityEngine.Object.FindFirstObjectByType<Bomb.CanonicalDestruction.HandbookConformanceScene>();
if (fixture == null || fixture.Host == null) throw new System.InvalidOperationException("The fixture host was not created.");
var serialized = new UnityEditor.SerializedObject(fixture);
string phase = serialized.FindProperty("phase").stringValue;
bool paused = serialized.FindProperty("paused").boolValue;
var view = fixture.Host.World.View;
var ids = fixture.Ids;
var connector = System.Linq.Enumerable.Single(view.Connectors);
var hold = System.Linq.Enumerable.Single(view.Holds);
var bomb = view.Body(ids.Bomb);
var runtime = fixture.Host.World.Projection as Bomb.CanonicalDestruction.CanonicalWorldRuntime2D;
if (!paused || !phase.StartsWith("Recovered split:") || view.Body(ids.Platform) != null || view.Bodies.Count != 5
    || connector.Id != ids.Connector || hold.Id != ids.Hold || connector.B == hold.Target || !bomb.Countdown.Active
    || System.Linq.Enumerable.Single(view.Participants).ControlledBody != ids.Character || runtime == null)
    throw new System.InvalidOperationException("Incomplete demonstration: " + phase);
if (!runtime.TryGetBody(ids.Support,out var support) || support.bodyType != UnityEngine.RigidbodyType2D.Static
    || !runtime.TryGetBody(connector.A,out var a) || !runtime.TryGetBody(connector.B,out var b)
    || !runtime.TryGetBody(hold.Target,out var heldTarget))
    throw new System.InvalidOperationException("Missing derived bodies or fixed support.");
if (b.position.x >= heldTarget.position.x) throw new System.InvalidOperationException("Connector/hold children did not resolve left/right.");
int bodies3D = 0;
foreach (var root in runtime.Scene.GetRootGameObjects()) bodies3D += root.GetComponentsInChildren<UnityEngine.Rigidbody>().Length;
if (bodies3D != 0 || runtime.ProjectionCount != 5) throw new System.InvalidOperationException("Unexpected physics projection.");
return new { project = UnityEngine.Application.dataPath, version = UnityEngine.Application.unityVersion,
    scene = fixture.gameObject.scene.path, phase, paused, frame = UnityEngine.Time.frameCount, physicsSteps = runtime.Steps,
    bodies = view.Bodies.Count, projectedBodies2D = runtime.ProjectionCount, bodies3D,
    retiredPlatform = ids.Platform.Value, connectorId = connector.Id.Value, connectorChild = connector.B.Value,
    holdId = hold.Id.Value, holdChild = hold.Target.Value, controlledBody = ids.Character.Value,
    countdownActive = bomb.Countdown.Active, remainingSeconds = bomb.Countdown.RemainingSeconds,
    connectorFit = UnityEngine.Vector2.Distance(a.GetRelativePoint(connector.A0),b.GetRelativePoint(connector.B0)),
    connectorChildX = b.position.x, holdChildX = heldTarget.position.x,
    supportX = support.position.x, supportY = support.position.y,
    connectorChildMass = view.Body(connector.B).Mass(fixture.Host.World.Definitions),
    holdChildMass = view.Body(hold.Target).Mass(fixture.Host.World.Definitions) };
