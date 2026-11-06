using Bom.Native;
using UnityEngine;
namespace Bom.Unity {
// Read-only pose presentation. No movement, collision or damage simulation.
public sealed class BomActorView : MonoBehaviour {
 public BomPose Pose {get;private set;}
 public void Apply(BomPose pose){Pose=pose;transform.SetPositionAndRotation(new Vector3(pose.x,pose.y,transform.position.z),BomUnityCoordinates.Rotation(pose.angle));}
}
}
