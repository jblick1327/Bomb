using System;
using System.Linq;
using Bomb.CanonicalDestruction;
using UnityEditor;
using UnityEngine;

public static class VerifyCanonicalDestruction
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new InvalidOperationException("Canonical destruction verification needs Play mode.");

        var fixture = GameObject.CreatePrimitive(PrimitiveType.Cube);
        fixture.name = "Canonical Destruction Integration Fixture";
        fixture.transform.position = new Vector3(1000f, 1000f, 0f);
        fixture.transform.localScale = new Vector3(6f, 2f, 1f);
        Physics.SyncTransforms();
        DestructibleRock rock = fixture.AddComponent<DestructibleRock>();
        var bombObject = new GameObject("Canonical Destruction Bomb Fixture");
        BombDropper dropper = bombObject.AddComponent<BombDropper>();
        try
        {
            MaterialEntityId sourceId = rock.SourceId;
            dropper.Explode(fixture.transform.position);

            Require(rock.CanonicalWorld != null, "The gameplay blast did not initialize a canonical material world.");
            Require(!rock.CanonicalWorld.Contains(sourceId), "A split gameplay blast left the parent material ID alive.");
            Require(rock.CanonicalWorld.Count == 2, "The reachable gameplay cut must produce two canonical connected results.");
            Require(rock.CanonicalWorld.Entities.Select(entity => entity.Id).Distinct().Count() == 2,
                "Every gameplay split result must have a distinct canonical ID.");

            foreach (CanonicalMaterialState state in rock.CanonicalWorld.Entities)
            {
                CanonicalMaterialProjectionIdentity projection = UnityEngine.Object
                    .FindObjectsByType<CanonicalMaterialProjectionIdentity>(FindObjectsSortMode.None)
                    .FirstOrDefault(candidate => candidate.CanonicalId == state.Id);
                Require(projection != null, "A committed material result has no derived runtime projection.");
                Require(projection.GetComponent<Rigidbody>() != null, "A material projection has no derived rigidbody.");
                Require(projection.GetComponentsInChildren<MeshCollider>().Length == state.Shape.Cells.Count,
                    "A material projection does not match its canonical collision cells.");
            }

            string snapshot = rock.SaveCanonicalState();
            string lower = snapshot.ToLowerInvariant();
            Require(!lower.Contains("instanceid") && !lower.Contains("gameobject") && !lower.Contains("rigidbody")
                && !lower.Contains("collider") && !lower.Contains("unityengine"),
                "Canonical gameplay serialization contains a Unity runtime reference.");
            Require(rock.LoadCanonicalState(snapshot), "The gameplay material snapshot could not rebuild a clean runtime world.");
            Require(rock.CanonicalWorld.Count == 2 && !rock.CanonicalWorld.Contains(sourceId),
                "Loading the committed snapshot changed material identity or topology.");

            return "PASS: BombDropper -> canonical polygon evaluation -> atomic split commit -> runtime rebuild -> snapshot reload.";
        }
        finally
        {
            rock.ResetRock();
            dropper.ClearTransientObjects();
            fixture.SetActive(false);
            bombObject.SetActive(false);
            UnityEngine.Object.Destroy(fixture);
            UnityEngine.Object.Destroy(bombObject);
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
