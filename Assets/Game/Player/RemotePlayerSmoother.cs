using System.Collections.Generic;
using UnityEngine;

// Online: moves a player controlled from another computer. Positions arrive
// about 20 times a second; the player is drawn slightly in the past and
// slides between the two updates around that moment, so movement looks smooth.
[DisallowMultipleComponent]
public sealed class RemotePlayerSmoother : MonoBehaviour
{
    private const float DisplayDelay = 0.1f;
    private const int MaxSnapshots = 20;

    private struct Snapshot
    {
        public float Time;
        public Vector2 Position;
    }

    private readonly List<Snapshot> snapshots = new List<Snapshot>(MaxSnapshots);
    private ArenaPlayerController player;

    private void Awake() => player = GetComponent<ArenaPlayerController>();

    public void AddState(Vector2 position, bool facingLeft, bool running)
    {
        snapshots.Add(new Snapshot { Time = Time.unscaledTime, Position = position });
        if (snapshots.Count > MaxSnapshots) snapshots.RemoveAt(0);
        if (player != null) player.ApplyNetworkPose(facingLeft, running);
    }

    // Respawning teleports the player, so old positions no longer apply.
    private void OnDisable() => snapshots.Clear();

    private void Update()
    {
        if (snapshots.Count == 0) return;
        float displayTime = Time.unscaledTime - DisplayDelay;
        while (snapshots.Count >= 2 && snapshots[1].Time <= displayTime) snapshots.RemoveAt(0);

        Vector2 target = snapshots[0].Position;
        if (snapshots.Count >= 2 && snapshots[0].Time <= displayTime)
        {
            float t = Mathf.InverseLerp(snapshots[0].Time, snapshots[1].Time, displayTime);
            target = Vector2.Lerp(snapshots[0].Position, snapshots[1].Position, t);
        }
        transform.position = new Vector3(target.x, target.y, transform.position.z);
    }
}
