using System;
using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Serialization;
using UnityEngine.SceneManagement;

// The round states that control player input and the HUD. Waiting is only
// used online, while everyone's level finishes loading.
public enum ArenaRoundState { Playing, Dead, Waiting }

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
    // True while the pause menu or the results panel is up.
    public bool IsMenuShowing => IsPaused || State == ArenaRoundState.Dead;
    public event Action<bool> PausedChanged;
    public float TimeSurvived { get; private set; }
    public int BombsDodged => bombs != null ? bombs.DroppedBombCount : 0;
    public int CoinsCollected { get; private set; }
    public int BonusCoins { get; private set; }
    public int TotalCoinsEarned { get; private set; }
    // Coins added to this computer's wallet when the round ended.
    public int WalletCoinsAwarded { get; private set; }
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

        int desiredPlayerCount = OnlineMatch.IsRunning ? OnlineMatch.PlayerCount
            : MatchMenuUI.HasConfiguredMatchRoster ? MatchMenuUI.MatchPlayerCount : 2;
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
            if (OnlineMatch.IsRunning) players[i].SetOnlineRole(i == OnlineMatch.LocalSlot);
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
        if (OnlineMatch.IsRunning)
        {
            // Online, the host starts the round once every player has loaded.
            SetState(ArenaRoundState.Waiting);
            OnlineMatch.ArenaLoaded(this);
            return;
        }
        GameAudio.PlayWhistle();
    }

    private void Update()
    {
        if (IsPlaying)
            TimeSurvived += Time.deltaTime;

        // Only Player 1 controls pausing and restarting. Online, the keyboard
        // always belongs to this computer's player.
        Keyboard keyboard = OnlineMatch.IsRunning || MatchMenuUI.IsKeyboardEnabledForPlayer(1) ? Keyboard.current : null;
        if (IsPlaying && PausePressed(keyboard))
            SetPaused(!IsPaused);
        // R only restarts once the round is over, so it can't be hit by accident
        // mid-match. Online, only the host restarts, from the results panel.
        if (State == ArenaRoundState.Dead && !OnlineMatch.IsRunning && keyboard != null && keyboard.rKey.wasPressedThisFrame)
            RestartRound();

        CheckOutOfBounds();
    }

    private void SetState(ArenaRoundState state)
    {
        State = state;
        StateChanged?.Invoke(State);
    }

    private static readonly Collider[] boundHits = new Collider[16];

    // Players normally die by walking into a Bound. This catches the cases a
    // collision can miss: a bound set as a trigger, or falling out of the level.
    private void CheckOutOfBounds()
    {
        if (!IsPlaying || layout == null) return;
        Bounds level = layout.CameraBounds;
        float killY = Mathf.Min(level.min.y, layout.Origin.y + layout.GroundBottom) - 3f;
        List<ArenaPlayerController> outPlayers = null;
        foreach (ArenaPlayerController player in players)
        {
            // Remote players are checked by their own computer.
            if (player == null || !player.gameObject.activeInHierarchy || player.IsRemote) continue;
            Vector3 position = player.transform.position;
            bool outside = position.y < killY || position.x < level.min.x - 3f || position.x > level.max.x + 3f;
            if (!outside && !TouchesEliminationBound(player)) continue;
            if (outPlayers == null) outPlayers = new List<ArenaPlayerController>();
            outPlayers.Add(player);
        }
        if (outPlayers != null) KillPlayers(outPlayers);
    }

    private static bool TouchesEliminationBound(ArenaPlayerController player)
    {
        CharacterController body = player.GetComponent<CharacterController>();
        if (body == null) return false;
        Vector3 scale = player.transform.lossyScale;
        // Slightly smaller than the body, so standing on ground just above a
        // Bound doesn't count as touching it.
        float radius = Mathf.Max(0.01f, body.radius * Mathf.Max(Mathf.Abs(scale.x), Mathf.Abs(scale.z)) - 0.03f);
        float half = Mathf.Max(0f, body.height * Mathf.Abs(scale.y) * 0.5f - radius);
        Vector3 center = player.transform.TransformPoint(body.center);
        int count = Physics.OverlapCapsuleNonAlloc(center + Vector3.up * half, center - Vector3.up * half,
            radius, boundHits, ~0, QueryTriggerInteraction.Collide);
        for (int i = 0; i < count; i++)
            if (boundHits[i].GetComponentInParent<EliminationBound>() != null) return true;
        return false;
    }

    private static bool PausePressed(Keyboard keyboard)
    {
        if (keyboard != null && keyboard.pKey.wasPressedThisFrame) return true;
        Gamepad gamepad = MenuCursor.PlayerOneGamepad();
        return gamepad != null && gamepad.startButton.wasPressedThisFrame;
    }

    // Freezes the round by stopping game time. Bombs, players and timers all
    // run on scaled time, so they stop with it.
    // Online the game can't stop for one player, so pausing only opens the menu.
    public void SetPaused(bool paused)
    {
        if (paused && !IsPlaying) paused = false;
        if (IsPaused == paused) return;
        IsPaused = paused;
        if (!OnlineMatch.IsRunning) Time.timeScale = paused ? 0f : 1f;
        PausedChanged?.Invoke(paused);
    }

    // Leaves the match. Time must be restarted first or the menu would be frozen.
    public void LeaveMatch()
    {
        SetPaused(false);
        if (OnlineMatch.IsRunning) OnlineMatch.LeaveMatch();
        else SceneManager.LoadScene("MainMenuScene");
    }

    // Player by slot (0 = Player 1), or null.
    public ArenaPlayerController GetPlayer(int slot) =>
        slot >= 0 && slot < players.Count ? players[slot] : null;

    // Online: another computer reported that its player was knocked out.
    public void ApplyNetworkDeath(int slot, Vector2? blastCenter)
    {
        ArenaPlayerController player = GetPlayer(slot);
        if (player == null || !player.gameObject.activeSelf || !IsPlaying) return;
        if (blastCenter.HasValue) player.Burst(blastCenter.Value);
        EliminatePlayers(new[] { player });
    }

    // Online: a player left the game. They count as knocked out.
    public void ApplyPlayerLeft(int slot)
    {
        ArenaPlayerController player = GetPlayer(slot);
        if (player == null) return;
        player.HasLeftGame = true;
        if (!IsPlaying)
        {
            player.gameObject.SetActive(false);
            return;
        }
        EliminatePlayers(new[] { player });
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

    // Knocks players out. blastCenter is where the bomb that got them went off,
    // if it was a bomb. Online, this computer's player is reported to the others.
    public void KillPlayers(IEnumerable<ArenaPlayerController> deadPlayers, Vector2? blastCenter = null)
    {
        if (!IsPlaying || deadPlayers == null) return;
        var knockedOut = new List<ArenaPlayerController>();
        foreach (ArenaPlayerController deadPlayer in deadPlayers)
        {
            if (deadPlayer == null || deadPlayer.IsRemote || knockedOut.Contains(deadPlayer)) continue;
            knockedOut.Add(deadPlayer);
            if (OnlineMatch.IsRunning && deadPlayer.gameObject.activeSelf)
                OnlineMatch.ReportDeath(deadPlayer.PlayerNumber - 1, blastCenter);
        }
        EliminatePlayers(knockedOut);
    }

    private void EliminatePlayers(IEnumerable<ArenaPlayerController> deadPlayers)
    {
        if (!IsPlaying) return;
        bool anyPlayerDied = false;
        foreach (ArenaPlayerController deadPlayer in deadPlayers)
        {
            if (deadPlayer == null || !players.Contains(deadPlayer) || !deadPlayer.gameObject.activeSelf)
                continue;
            deadPlayer.RecordRoundResult(TimeSurvived, BombsDodged);
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
        SetPaused(false);
        if (bombs != null) bombs.ClearTransientObjects();
        if (winner != null) winner.RecordRoundResult(TimeSurvived, BombsDodged);

        WinnerMessage = aliveCount == 1 && players.Count > 1 ? $"Player {winner.PlayerNumber} Wins!" : "Game Over";
        CoinsCollected = 0;
        TotalCoinsEarned = 0;
        foreach (ArenaPlayerController player in players)
        {
            if (player == null) continue;
            CoinsCollected += player.Coins;
            TotalCoinsEarned += player.RoundTotal;
        }
        BonusCoins = TotalCoinsEarned - CoinsCollected;

        // Offline, everyone shares this computer's wallet, so it gets the
        // grand total. Online, each computer keeps only its own player's total.
        ArenaPlayerController localPlayer = OnlineMatch.IsRunning ? GetPlayer(OnlineMatch.LocalSlot) : null;
        WalletCoinsAwarded = OnlineMatch.IsRunning ? (localPlayer != null ? localPlayer.RoundTotal : 0) : TotalCoinsEarned;
        MatchMenuUI.AddShopCoins(WalletCoinsAwarded);
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
            // Players who left an online game stay out.
            if (players[i].HasLeftGame)
            {
                players[i].gameObject.SetActive(false);
                continue;
            }
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
        WalletCoinsAwarded = 0;
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
