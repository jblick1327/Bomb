using System;
using UnityEngine;
using UnityEngine.InputSystem;

// The two states that control player input and the HUD.
public enum ArenaRoundState { Playing, Dead }

// Owns round state, player death, and restoration of arena objects on restart.
[AddComponentMenu("Arena/Round Session")]
public sealed class ArenaSession : MonoBehaviour
{
    [Header("Scene references")]
    [SerializeField] private ArenaLayout layout;
    [SerializeField] private ArenaPlayerController player;
    [SerializeField, Tooltip("Owns the bombs and effects cleared on death or restart.")]
    private BombDropper bombs;

    public ArenaRoundState State { get; private set; } = ArenaRoundState.Playing;
    public bool IsPlaying => State == ArenaRoundState.Playing;
    public float TimeSurvived { get; private set; }
    public int BombsDodged => bombs != null ? bombs.DroppedBombCount : 0;
    public event Action<ArenaRoundState> StateChanged;

    private void Start()
    {
        // The scene's saved transform can become stale when imported terrain bounds change.
        // Place the capsule against the measured grass surface on every fresh launch.
        RestartRound();
    }

    private void Update()
    {
        if (IsPlaying) TimeSurvived += Time.deltaTime;
        if (Keyboard.current != null && Keyboard.current.rKey.wasPressedThisFrame) RestartRound();
    }

    public void KillPlayer()
    {
        if (!IsPlaying) return;
        State = ArenaRoundState.Dead;
        player.gameObject.SetActive(false);
        bombs.ClearTransientObjects();
        StateChanged?.Invoke(State);
    }

    public void RestartRound()
    {
        bombs.ClearTransientObjects();
        bombs.ResetSpawnRamp();
        foreach (DestructibleGround terrain in FindObjectsByType<DestructibleGround>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            terrain.ResetGround();
        foreach (ArenaGameplayGround terrain in FindObjectsByType<ArenaGameplayGround>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            terrain.ResetGround();
        DestructibleObject.ResetAllObjects();
        foreach (DestructibleMultiMesh target in FindObjectsByType<DestructibleMultiMesh>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            target.ResetTarget();
        player.gameObject.SetActive(false);
        CharacterController controller = player.GetComponent<CharacterController>();
        controller.enabled = false;
        Vector3 spawn = layout.PlayerSpawn;
        Collider gameplayGround = bombs != null ? bombs.GameplayGroundCollider : null;
        if (gameplayGround != null && gameplayGround.enabled)
        {
            Bounds bounds = gameplayGround.bounds;
            Vector3 rayOrigin = new Vector3(spawn.x, Mathf.Max(spawn.y, bounds.max.y) + 2f, bounds.center.z);
            Ray ray = new Ray(rayOrigin, Vector3.down);
            if (gameplayGround.Raycast(ray, out RaycastHit groundHit, bounds.size.y + 4f))
                spawn.y = groundHit.point.y + controller.height * 0.5f + controller.skinWidth;
        }
        player.transform.position = spawn;
        controller.enabled = true;
        State = ArenaRoundState.Playing;
        TimeSurvived = 0f;
        player.gameObject.SetActive(true);
        Physics.SyncTransforms();
        StateChanged?.Invoke(State);
    }
}
