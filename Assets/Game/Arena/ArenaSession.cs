using System;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Serialization;
using UnityEngine.SceneManagement;

// The two states that control player input and the HUD.
public enum ArenaRoundState { Playing, Dead }

// Owns round state, player death, and restoration of arena objects on restart.
[AddComponentMenu("Arena/Round Session")]
public sealed class ArenaSession : MonoBehaviour
{
    public const int CoinsPerBomb = 10;
    public const int CoinsPerSecond = 1;

    [Header("Scene references")]
    [SerializeField] private ArenaLayout layout;
    [FormerlySerializedAs("player")]
    [SerializeField] private ArenaPlayerController player1;
    [SerializeField] private ArenaPlayerController player2;
    [SerializeField, Tooltip("Owns the bombs and effects cleared on death or restart.")]
    private BombDropper bombs;

    [Header("Local Multiplayer")]
    [SerializeField, Tooltip("Spacing between players at the arena spawn point.")]
    private float playerSpawnSpacing = 2f;
    [SerializeField, Tooltip("Use the first scene player's saved height as the spawn height. Useful for elevated starting platforms.")]
    private bool useScenePlayerSpawnHeight;
    [SerializeField] private TMP_Text winnerText;

    public ArenaRoundState State { get; private set; } = ArenaRoundState.Playing;
    public bool IsPlaying => State == ArenaRoundState.Playing;
    public bool IsPaused { get; private set; }
    public event Action<bool> PausedChanged;
    public float TimeSurvived { get; private set; }
    public int BombsDodged => bombs != null ? bombs.DroppedBombCount : 0;
    public int CoinsCollected { get; private set; }
    public int BonusCoins { get; private set; }
    public int TotalCoinsEarned { get; private set; }
    public event Action<ArenaRoundState> StateChanged;

    public ArenaPlayerController Player1 => player1;
    public ArenaPlayerController Player2 => player2;
    public IReadOnlyList<ArenaPlayerController> Players => players;
    public string WinnerMessage { get; private set; } = "";
    private readonly List<ArenaPlayerController> players = new List<ArenaPlayerController>(4);
    private float scenePlayerSpawnHeight;

    private void Awake()
    {
        if (layout == null) layout = FindFirstObjectByType<ArenaLayout>();
        if (bombs == null) bombs = FindFirstObjectByType<BombDropper>();
        ArenaPlayerController[] foundPlayers = FindObjectsByType<ArenaPlayerController>(FindObjectsInactive.Include, FindObjectsSortMode.InstanceID);
        if (IsUsablePlayer(player1)) players.Add(player1);
        if (IsUsablePlayer(player2) && player2 != player1) players.Add(player2);
        foreach (ArenaPlayerController candidate in foundPlayers)
        {
            if (IsUsablePlayer(candidate) && !players.Contains(candidate))
                players.Add(candidate);
        }

        if (players.Count > 0)
            scenePlayerSpawnHeight = players[0].transform.position.y;

        int desiredPlayerCount = MatchMenuUI.HasConfiguredMatchRoster ? MatchMenuUI.MatchPlayerCount : 2;
        desiredPlayerCount = Mathf.Clamp(desiredPlayerCount, 1, 4);
        if (players.Count == 0)
            Debug.LogError("ArenaSession could not find an enabled arena player.");

        while (players.Count > desiredPlayerCount)
        {
            ArenaPlayerController extra = players[players.Count - 1];
            players.RemoveAt(players.Count - 1);
            extra.gameObject.SetActive(false);
        }

        while (players.Count > 0 && players.Count < desiredPlayerCount)
        {
            int playerNumber = players.Count + 1;
            ArenaPlayerController extra = Instantiate(players[0], players[0].transform.parent);
            extra.gameObject.name = "Player " + playerNumber;
            players.Add(extra);
        }

        player1 = players.Count > 0 ? players[0] : null;
        player2 = players.Count > 1 ? players[1] : null;
        for (int i = 0; i < players.Count; i++)
        {
            players[i].SetPlayerNumber(i + 1);
            players[i].gameObject.name = "Player " + (i + 1);
        }
    }

    private bool IsUsablePlayer(ArenaPlayerController candidate)
    {
        // Players can be saved inactive in the scene; RestartRound activates them after positioning.
        if (candidate == null || !candidate.enabled)
            return false;
        CharacterController controller = candidate.GetComponent<CharacterController>();
        return controller != null;
    }

    private void Start()
    {
        // Spawn from the level layout, with an optional saved height for raised levels.
        RestartRound();
        GameAudio.PlayWhistle();
    }

    private void Update()
    {
        if (IsPlaying)
            TimeSurvived += Time.deltaTime;

        // Only Player 1 controls pausing and restarting.
        Keyboard keyboard = MatchMenuUI.IsKeyboardEnabledForPlayer(1) ? Keyboard.current : null;
        if (IsPlaying && PausePressed(keyboard))
            SetPaused(!IsPaused);
        // R only restarts once the round is over, so it can't be hit by accident mid-match.
        if (!IsPlaying && keyboard != null && keyboard.rKey.wasPressedThisFrame)
            RestartRound();
    }

    private static bool PausePressed(Keyboard keyboard)
    {
        if (keyboard != null && keyboard.pKey.wasPressedThisFrame) return true;
        Gamepad gamepad = MenuCursor.PlayerOneGamepad();
        return gamepad != null && gamepad.startButton.wasPressedThisFrame;
    }

    // Freezes the round by stopping game time. Bombs, players and timers all
    // run on scaled time, so they stop with it.
    public void SetPaused(bool paused)
    {
        if (paused && !IsPlaying) paused = false;
        if (IsPaused == paused) return;
        IsPaused = paused;
        Time.timeScale = paused ? 0f : 1f;
        PausedChanged?.Invoke(paused);
    }

    // Leaves the match. Time must be restarted first or the menu would be frozen.
    public void LeaveMatch()
    {
        SetPaused(false);
        SceneManager.LoadScene("MainMenuScene");
    }

    private void OnDestroy()
    {
        // Never leave the game frozen if this scene unloads while paused.
        if (IsPaused) Time.timeScale = 1f;
    }

    public void KillPlayer(ArenaPlayerController deadPlayer)
    {
        KillPlayers(new[] { deadPlayer });
    }

    public void KillPlayers(IEnumerable<ArenaPlayerController> deadPlayers)
    {
        if (!IsPlaying || deadPlayers == null) return;
        bool anyPlayerDied = false;
        foreach (ArenaPlayerController deadPlayer in deadPlayers)
        {
            if (deadPlayer == null || !players.Contains(deadPlayer) || !deadPlayer.gameObject.activeSelf)
                continue;
            deadPlayer.gameObject.SetActive(false);
            anyPlayerDied = true;
        }
        if (!anyPlayerDied) return;

        ArenaPlayerController winner = null;
        int aliveCount = 0;
        foreach (ArenaPlayerController player in players)
        {
            if (player != null && player.gameObject.activeSelf)
            {
                winner = player;
                aliveCount++;
            }
        }
        if (aliveCount > 1)
            return;

        State = ArenaRoundState.Dead;
        if (bombs != null) bombs.ClearTransientObjects();

        WinnerMessage = aliveCount == 1 ? $"Player {winner.PlayerNumber} Wins!" : "Game Over";
        CoinsCollected = 0;
        foreach (ArenaPlayerController player in players)
        {
            if (player != null)
                CoinsCollected += player.Coins;
        }

        BonusCoins = BombsDodged * CoinsPerBomb + Mathf.FloorToInt(TimeSurvived) * CoinsPerSecond;
        TotalCoinsEarned = CoinsCollected + BonusCoins;
        MatchMenuUI.AddShopCoins(TotalCoinsEarned);
        if (winnerText != null)
        {
            winnerText.text = WinnerMessage;
            winnerText.gameObject.SetActive(true);
        }

        StateChanged?.Invoke(State);
        GameAudio.PlayWhistle();
    }

    public void RestartRound()
    {
        SetPaused(false);
        if (bombs != null) bombs.ClearTransientObjects();
        if (bombs != null) bombs.ResetSpawnRamp();

        DestructibleObject.ResetAllObjects();
        GroundRubble.ClearAll();

        if (winnerText != null)
            winnerText.gameObject.SetActive(false);

        for (int i = 0; i < players.Count; i++)
        {
            float xOffset = (i - (players.Count - 1) * 0.5f) * playerSpawnSpacing;
            players[i].ResetCollectibleEffects();
            players[i].ResetRoundStats();
            players[i].RestoreBody();
            ResetPlayer(players[i], xOffset);
        }

        State = ArenaRoundState.Playing;
        TimeSurvived = 0f;
        CoinsCollected = 0;
        BonusCoins = 0;
        TotalCoinsEarned = 0;
        WinnerMessage = "";

        Physics.SyncTransforms();
        StateChanged?.Invoke(State);
    }

    private void ResetPlayer(ArenaPlayerController player, float xOffset)
    {
        if (player == null || layout == null) return;
        player.gameObject.SetActive(false);

        CharacterController controller = player.GetComponent<CharacterController>();
        if (controller == null) return;
        controller.enabled = false;

        Vector3 spawn = layout.PlayerSpawn;
        spawn.x += xOffset;

        if (useScenePlayerSpawnHeight)
            spawn.y = scenePlayerSpawnHeight;
        else if (SceneManager.GetActiveScene().name == "YardLevel")
            spawn.y += 0.75f;

        player.transform.position = spawn;
        controller.enabled = true;
        player.gameObject.SetActive(true);
    }
}
