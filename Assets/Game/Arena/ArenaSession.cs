using System;
using UnityEngine;
using UnityEngine.InputSystem;

public enum ArenaRoundState { Playing, Dead }

[AddComponentMenu("Arena/Round Session")]
public sealed class ArenaSession : MonoBehaviour
{
    [Header("Scene references")]
    [SerializeField] private ArenaLayout layout;
    [SerializeField] private ArenaPlayerController player;
    [SerializeField] private DestructibleGround ground;
    [SerializeField, Tooltip("Owns the bombs and effects cleared on death or restart.")]
    private BombDropper bombs;

    public ArenaRoundState State { get; private set; } = ArenaRoundState.Playing;
    public bool IsPlaying => State == ArenaRoundState.Playing;
    public event Action<ArenaRoundState> StateChanged;

    private void Update()
    {
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
        ground.ResetGround();
        player.gameObject.SetActive(false);
        CharacterController controller = player.GetComponent<CharacterController>();
        controller.enabled = false;
        player.transform.position = layout.PlayerSpawn;
        controller.enabled = true;
        State = ArenaRoundState.Playing;
        player.gameObject.SetActive(true);
        Physics.SyncTransforms();
        StateChanged?.Invoke(State);
    }
}
