using System;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Serialization;

// The two states that control player input and the HUD.
public enum ArenaRoundState { Playing, Dead }

// Owns round state, player death, and restoration of arena objects on restart.
[AddComponentMenu("Arena/Round Session")]
public sealed class ArenaSession : MonoBehaviour
{
    [Header("Scene references")]
    [SerializeField] private ArenaLayout layout;
    [FormerlySerializedAs("player")]
    [SerializeField] private ArenaPlayerController player1;
    [SerializeField] private ArenaPlayerController player2;
    [SerializeField, Tooltip("Owns the bombs and effects cleared on death or restart.")]
    private BombDropper bombs;

    [Header("Two Player Settings")]
    [SerializeField, Tooltip("How far apart the two players spawn from the original player spawn point.")]
    private float playerSpawnSpacing = 2f;
    [SerializeField] private TMP_Text winnerText;

    public ArenaRoundState State { get; private set; } = ArenaRoundState.Playing;
    public bool IsPlaying => State == ArenaRoundState.Playing;
    public float TimeSurvived { get; private set; }
    public int BombsDodged => bombs != null ? bombs.DroppedBombCount : 0;
    public event Action<ArenaRoundState> StateChanged;

    public ArenaPlayerController Player1 => player1;
    public ArenaPlayerController Player2 => player2;
    public string WinnerMessage { get; private set; } = "";

    private void Awake()
    {
        if (layout == null) layout = FindFirstObjectByType<ArenaLayout>();
        if (bombs == null) bombs = FindFirstObjectByType<BombDropper>();
        ArenaPlayerController[] players = FindObjectsByType<ArenaPlayerController>(FindObjectsInactive.Include, FindObjectsSortMode.InstanceID);
        if (player1 == null && players.Length > 0) player1 = players[0];
        if (player2 == null || player2 == player1)
        {
            player2 = null;
            foreach (ArenaPlayerController candidate in players)
                if (candidate != player1) { player2 = candidate; break; }
            if (player2 == null && player1 != null)
            {
                player2 = Instantiate(player1, player1.transform.parent);
                player2.gameObject.name = "Player 2";
            }
        }
        if (player1 != null) player1.SetPlayerNumber(1);
        if (player2 != null) player2.SetPlayerNumber(2);
    }

    private void Start()
    {
        // The scene's saved transform can become stale when imported terrain bounds change.
        // Place the capsules against the measured grass surface on every fresh launch.
        RestartRound();
    }

    private void Update()
    {
        if (IsPlaying) TimeSurvived += Time.deltaTime;
        if (Keyboard.current != null && Keyboard.current.rKey.wasPressedThisFrame) RestartRound();
    }

    public void KillPlayer(ArenaPlayerController deadPlayer)
    {
        if (!IsPlaying || deadPlayer == null || (deadPlayer != player1 && deadPlayer != player2)) return;

        State = ArenaRoundState.Dead;

        deadPlayer.gameObject.SetActive(false);
        if (bombs != null) bombs.ClearTransientObjects();

        ArenaPlayerController winner = deadPlayer == player1 ? player2 : player1;

        WinnerMessage = winner != null ? $"Player {winner.PlayerNumber} Wins!" : "Game Over";
        if (winnerText != null)
        {
            winnerText.text = WinnerMessage;
            winnerText.gameObject.SetActive(true);
        }

        StateChanged?.Invoke(State);
    }

    public void RestartRound()
    {
        if (bombs != null) bombs.ClearTransientObjects();
        if (bombs != null) bombs.ResetSpawnRamp();

        foreach (DestructibleGround terrain in FindObjectsByType<DestructibleGround>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            terrain.ResetGround();
        foreach (ArenaGameplayGround terrain in FindObjectsByType<ArenaGameplayGround>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            terrain.ResetGround();
        DestructibleObject.ResetAllObjects();
        foreach (DestructibleMultiMesh target in FindObjectsByType<DestructibleMultiMesh>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            target.ResetTarget();

        if (winnerText != null)
            winnerText.gameObject.SetActive(false);

        ResetPlayer(player1, -playerSpawnSpacing * 0.5f);
        ResetPlayer(player2, playerSpawnSpacing * 0.5f);

        State = ArenaRoundState.Playing;
        TimeSurvived = 0f;
        WinnerMessage = "";

        Physics.SyncTransforms();
        StateChanged?.Invoke(State);
    }

    private void ResetPlayer(ArenaPlayerController player, float xOffset)
    {
        if (player == null || layout == null) return;
        player.gameObject.SetActive(false);

        CharacterController controller = player.GetComponent<CharacterController>();
        controller.enabled = false;

        Vector3 spawn = layout.PlayerSpawn;
        spawn.x += xOffset;

        Collider gameplayGround = bombs != null ? bombs.GameplayGroundCollider : null;
        if (gameplayGround != null && gameplayGround.enabled)
        {
            Bounds bounds = gameplayGround.bounds;
            Vector3 rayOrigin = new Vector3(spawn.x, Mathf.Max(spawn.y, bounds.max.y) + 2f, spawn.z);
            Ray ray = new Ray(rayOrigin, Vector3.down);

            if (gameplayGround.Raycast(ray, out RaycastHit groundHit, bounds.size.y + 4f))
                spawn.y = groundHit.point.y + controller.height * 0.5f + controller.skinWidth;
        }

        player.transform.position = spawn;
        controller.enabled = true;
        player.gameObject.SetActive(true);
    }
}
