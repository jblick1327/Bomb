using System;
using System.Collections.Generic;
using Unity.Collections;
using Unity.Netcode;
using UnityEngine;
using UnityEngine.SceneManagement;

// Runs an online match on top of OnlineSession. The host is in charge: it
// picks the level, starts each round, drops the bombs and items, and decides
// who picks an item up first. Each computer moves its own player and checks
// its own player against blasts, then tells everyone else what happened.
//
// Everything travels as small "named messages" through Netcode for
// GameObjects, so no networked prefabs are needed. Clients send to the host;
// the host passes messages on to the other clients.
public static class OnlineMatch
{
    private const string Channel = "bom";
    private const float StateSendInterval = 0.05f;
    private const float ReadyTimeout = 15f;

    private enum Message : byte
    {
        Lobby = 1,   // host -> all: lobby screen and chosen level
        Load,        // host -> all: load this level, with the player order
        Ready,       // client -> host: level loaded
        Start,       // host -> all: start (or restart) the round
        State,       // owner -> all: player position, facing, running
        Bomb,        // host -> all: a bomb was dropped
        Item,        // host -> all: an item was dropped
        Boom,        // host -> all: a bomb went off
        Take,        // client -> host: my player touched an item
        Took,        // host -> all: this player got the item
        Graze,       // owner -> all: my player lost a limb
        Death,       // owner -> all: my player was knocked out
        Left,        // host -> all: a player left the game
        ToLobby,     // host -> all: back to the lobby
    }

    public enum LobbyScreen : byte { Players, ChooseLevel }

    // Lobby state, shared by the host with everyone.
    public static LobbyScreen Screen { get; private set; }
    public static int SelectedLevel { get; private set; }
    public static event Action LobbyChanged;

    // True from the moment a level starts loading until the match ends.
    public static bool IsRunning { get; private set; }
    public static bool IsHost => Network != null && Network.IsServer;
    public static int PlayerCount { get; private set; }
    // This computer's player (0 = Player 1).
    public static int LocalSlot { get; private set; }
    public static int LevelIndex { get; private set; }

    // A message to show on the Online screen after being sent back to the
    // main menu, such as "The host closed the game."
    public static string PendingMenuMessage { get; set; }

    private static NetworkManager Network => OnlineSession.Network;

    private static readonly List<ulong> slotClients = new List<ulong>();
    private static readonly HashSet<ulong> readyClients = new HashSet<ulong>();
    private static ArenaSession arena;
    private static BombDropper bombs;
    private static byte round;
    private static bool startPending;
    private static byte pendingRound;
    private static float readyDeadline;
    private static Runner runner;

    // Called when a session starts. Creates the object that runs every frame.
    public static void EnsureRunner()
    {
        if (runner != null) return;
        var root = new GameObject("Online Match");
        UnityEngine.Object.DontDestroyOnLoad(root);
        runner = root.AddComponent<Runner>();
        OnlineSession.Ended += OnSessionEnded;
    }

    // ---------- Lobby ----------

    public static int ConnectedPlayerCount => Network != null && Network.IsServer ? Network.ConnectedClientsIds.Count : 0;

    public static void HostShowLobby(LobbyScreen screen, int level)
    {
        if (!IsHost) return;
        Screen = screen;
        SelectedLevel = Mathf.Clamp(level, 0, MatchMenuUI.LevelSceneNames.Length - 1);
        SendToClients(WriteLobby(), NetworkDelivery.ReliableSequenced);
        LobbyChanged?.Invoke();
    }

    private static FastBufferWriter WriteLobby()
    {
        FastBufferWriter writer = Begin(Message.Lobby);
        writer.WriteValueSafe((byte)Screen);
        writer.WriteValueSafe((byte)SelectedLevel);
        return writer;
    }

    // Host: loads the chosen level for everyone connected.
    public static void HostStartMatch()
    {
        if (!IsHost || IsRunning) return;
        slotClients.Clear();
        slotClients.Add(Network.LocalClientId);
        var others = new List<ulong>(Network.ConnectedClientsIds);
        others.Remove(Network.LocalClientId);
        others.Sort();
        foreach (ulong id in others)
            if (slotClients.Count < OnlineSession.MaxPlayers) slotClients.Add(id);

        FastBufferWriter writer = Begin(Message.Load);
        writer.WriteValueSafe((byte)SelectedLevel);
        writer.WriteValueSafe((byte)slotClients.Count);
        foreach (ulong id in slotClients) writer.WriteValueSafe(id);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);

        // Nobody can join a match in progress.
        _ = OnlineSession.SetLockedAsync(true);
        BeginLoading(SelectedLevel, slotClients.Count, 0);
    }

    private static void BeginLoading(int level, int playerCount, int localSlot)
    {
        IsRunning = true;
        LevelIndex = level;
        PlayerCount = playerCount;
        LocalSlot = localSlot;
        arena = null;
        bombs = null;
        round = 0;
        startPending = false;
        readyClients.Clear();
        readyDeadline = Time.unscaledTime + ReadyTimeout;
        Time.timeScale = 1f;
        SceneManager.LoadScene(MatchMenuUI.LevelSceneNames[level]);
    }

    // ---------- Match flow ----------

    // Called by ArenaSession once the level has loaded and players are placed.
    public static void ArenaLoaded(ArenaSession session)
    {
        arena = session;
        bombs = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        if (IsHost)
        {
            readyClients.Add(Network.LocalClientId);
            readyDeadline = Time.unscaledTime + ReadyTimeout;
            StartIfEveryoneReady();
        }
        else
        {
            SendToHost(Begin(Message.Ready), NetworkDelivery.ReliableSequenced);
            if (startPending) ApplyStart(pendingRound);
        }
    }

    private static void StartIfEveryoneReady()
    {
        if (!IsHost || arena == null || arena.State != ArenaRoundState.Waiting) return;
        foreach (ulong id in slotClients)
            if (!readyClients.Contains(id) && IsConnected(id)) return;
        HostRestartRound();
    }

    // Host: starts a new round for everyone.
    public static void HostRestartRound()
    {
        if (!IsHost || arena == null) return;
        byte next = (byte)(round + 1);
        FastBufferWriter writer = Begin(Message.Start);
        writer.WriteValueSafe(next);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
        ApplyStart(next);
    }

    private static void ApplyStart(byte newRound)
    {
        if (arena == null)
        {
            // Still loading: start as soon as the level is ready.
            startPending = true;
            pendingRound = newRound;
            return;
        }
        startPending = false;
        round = newRound;
        arena.RestartRound();
        GameAudio.PlayWhistle();
    }

    // Results screen RETURN. The host takes everyone back to the lobby;
    // anyone else leaves the game.
    public static void ReturnFromResults()
    {
        if (IsHost) HostReturnToLobby();
        else LeaveMatch();
    }

    public static void HostReturnToLobby()
    {
        if (!IsHost) return;
        SendToClients(Begin(Message.ToLobby), NetworkDelivery.ReliableSequenced);
        _ = OnlineSession.SetLockedAsync(false);
        GoToLobby();
    }

    private static void GoToLobby()
    {
        EndMatchState();
        Screen = LobbyScreen.Players;
        SceneManager.LoadScene("MainMenuScene");
    }

    // Leaves the online game completely and returns to the main menu. If the
    // host leaves, the game closes for everyone.
    public static async void LeaveMatch()
    {
        EndMatchState();
        SceneManager.LoadScene("MainMenuScene");
        await OnlineSession.LeaveAsync();
    }

    private static void EndMatchState()
    {
        IsRunning = false;
        arena = null;
        bombs = null;
        startPending = false;
        Time.timeScale = 1f;
    }

    private static void OnSessionEnded(string reason)
    {
        Screen = LobbyScreen.Players;
        if (!IsRunning && SceneManager.GetActiveScene().name == "MainMenuScene") return;
        EndMatchState();
        PendingMenuMessage = reason;
        SceneManager.LoadScene("MainMenuScene");
    }

    // ---------- Game events ----------

    public static void SendBombSpawn(int id, float x)
    {
        if (!IsHost) return;
        FastBufferWriter writer = Begin(Message.Bomb);
        writer.WriteValueSafe(id);
        writer.WriteValueSafe(x);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
    }

    public static void SendItemSpawn(int id, float x, CollectibleItemType type)
    {
        if (!IsHost) return;
        FastBufferWriter writer = Begin(Message.Item);
        writer.WriteValueSafe(id);
        writer.WriteValueSafe(x);
        writer.WriteValueSafe((byte)type);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
    }

    public static void SendExplosion(int id, Vector2 center)
    {
        if (!IsHost) return;
        FastBufferWriter writer = Begin(Message.Boom);
        writer.WriteValueSafe(id);
        writer.WriteValueSafe(center);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
    }

    public static void RequestPickup(int itemId, int slot)
    {
        if (IsHost)
        {
            GrantPickup(itemId, slot);
            return;
        }
        FastBufferWriter writer = Begin(Message.Take);
        writer.WriteValueSafe(itemId);
        writer.WriteValueSafe((byte)slot);
        writer.WriteValueSafe(round);
        SendToHost(writer, NetworkDelivery.ReliableSequenced);
    }

    private static void GrantPickup(int itemId, int slot)
    {
        if (bombs == null || !bombs.TryClaimItem(itemId, out CollectibleItemType type)) return;
        FastBufferWriter writer = Begin(Message.Took);
        writer.WriteValueSafe(itemId);
        writer.WriteValueSafe((byte)type);
        writer.WriteValueSafe((byte)slot);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
        bombs.ApplyNetworkPickup(itemId, type, slot);
    }

    public static void ReportGraze(int slot, Vector2 center)
    {
        FastBufferWriter writer = Begin(Message.Graze);
        writer.WriteValueSafe((byte)slot);
        writer.WriteValueSafe(round);
        writer.WriteValueSafe(center);
        SendFromOwner(writer, NetworkDelivery.ReliableSequenced);
    }

    public static void ReportDeath(int slot, Vector2? center)
    {
        FastBufferWriter writer = Begin(Message.Death);
        writer.WriteValueSafe((byte)slot);
        writer.WriteValueSafe(round);
        writer.WriteValueSafe(center.HasValue);
        writer.WriteValueSafe(center ?? Vector2.zero);
        SendFromOwner(writer, NetworkDelivery.ReliableSequenced);
    }

    private static void SendLocalState()
    {
        ArenaPlayerController player = arena != null ? arena.GetPlayer(LocalSlot) : null;
        if (player == null || !player.gameObject.activeInHierarchy) return;
        FastBufferWriter writer = Begin(Message.State);
        writer.WriteValueSafe((byte)LocalSlot);
        Vector3 position = player.transform.position;
        writer.WriteValueSafe(new Vector2(position.x, position.y));
        byte flags = (byte)((player.FacingLeft ? 1 : 0) | (player.IsRunning ? 2 : 0));
        writer.WriteValueSafe(flags);
        SendFromOwner(writer, NetworkDelivery.UnreliableSequenced);
    }

    // ---------- Receiving ----------

    private static void OnMessage(ulong sender, FastBufferReader reader)
    {
        reader.ReadValueSafe(out byte kindByte);
        Message kind = (Message)kindByte;
        bool fromHost = sender == NetworkManager.ServerClientId;
        switch (kind)
        {
            case Message.Lobby:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out byte screen);
                reader.ReadValueSafe(out byte level);
                Screen = (LobbyScreen)screen;
                SelectedLevel = level;
                LobbyChanged?.Invoke();
                break;
            }
            case Message.Load:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out byte level);
                reader.ReadValueSafe(out byte count);
                int localSlot = -1;
                for (int i = 0; i < count; i++)
                {
                    reader.ReadValueSafe(out ulong id);
                    if (id == Network.LocalClientId) localSlot = i;
                }
                if (localSlot < 0) return;
                SelectedLevel = level;
                BeginLoading(level, count, localSlot);
                break;
            }
            case Message.Ready:
                if (!IsHost) return;
                readyClients.Add(sender);
                StartIfEveryoneReady();
                break;
            case Message.Start:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out byte newRound);
                ApplyStart(newRound);
                break;
            }
            case Message.State:
            {
                reader.ReadValueSafe(out byte slot);
                reader.ReadValueSafe(out Vector2 position);
                reader.ReadValueSafe(out byte flags);
                if (IsHost) Relay(sender, reader, NetworkDelivery.UnreliableSequenced);
                ArenaPlayerController player = arena != null ? arena.GetPlayer(slot) : null;
                if (player == null || !player.IsRemote || !player.gameObject.activeInHierarchy) return;
                RemotePlayerSmoother smoother = player.GetComponent<RemotePlayerSmoother>();
                if (smoother != null) smoother.AddState(position, (flags & 1) != 0, (flags & 2) != 0);
                break;
            }
            case Message.Bomb:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out int id);
                reader.ReadValueSafe(out float x);
                if (bombs != null) bombs.SpawnNetworkBomb(id, x);
                break;
            }
            case Message.Item:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out int id);
                reader.ReadValueSafe(out float x);
                reader.ReadValueSafe(out byte type);
                if (bombs != null) bombs.SpawnNetworkItem(id, x, (CollectibleItemType)type);
                break;
            }
            case Message.Boom:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out int id);
                reader.ReadValueSafe(out Vector2 center);
                if (bombs != null) bombs.ExplodeNetworkBomb(id, center);
                break;
            }
            case Message.Take:
            {
                if (!IsHost) return;
                reader.ReadValueSafe(out int id);
                reader.ReadValueSafe(out byte slot);
                reader.ReadValueSafe(out byte takeRound);
                if (takeRound == round && SlotOf(sender) == slot) GrantPickup(id, slot);
                break;
            }
            case Message.Took:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out int id);
                reader.ReadValueSafe(out byte type);
                reader.ReadValueSafe(out byte slot);
                if (bombs != null) bombs.ApplyNetworkPickup(id, (CollectibleItemType)type, slot);
                break;
            }
            case Message.Graze:
            {
                reader.ReadValueSafe(out byte slot);
                reader.ReadValueSafe(out byte grazeRound);
                reader.ReadValueSafe(out Vector2 center);
                if (IsHost) Relay(sender, reader, NetworkDelivery.ReliableSequenced);
                if (grazeRound != round || arena == null) return;
                ArenaPlayerController player = arena.GetPlayer(slot);
                if (player != null && player.IsRemote && player.gameObject.activeInHierarchy) player.TakeGraze(center);
                break;
            }
            case Message.Death:
            {
                reader.ReadValueSafe(out byte slot);
                reader.ReadValueSafe(out byte deathRound);
                reader.ReadValueSafe(out bool hasCenter);
                reader.ReadValueSafe(out Vector2 center);
                if (IsHost) Relay(sender, reader, NetworkDelivery.ReliableSequenced);
                if (deathRound != round || arena == null) return;
                ArenaPlayerController player = arena.GetPlayer(slot);
                if (player != null && player.IsRemote) arena.ApplyNetworkDeath(slot, hasCenter ? center : (Vector2?)null);
                break;
            }
            case Message.Left:
            {
                if (!fromHost || IsHost) return;
                reader.ReadValueSafe(out byte slot);
                if (arena != null) arena.ApplyPlayerLeft(slot);
                break;
            }
            case Message.ToLobby:
                if (!fromHost || IsHost) return;
                GoToLobby();
                break;
        }
    }

    // Host: someone dropped out. Their player is removed from the match.
    private static void OnClientDisconnected(ulong clientId)
    {
        if (!IsHost || clientId == Network.LocalClientId) return;
        LobbyChanged?.Invoke();
        if (!IsRunning) return;
        int slot = SlotOf(clientId);
        if (slot < 0) return;
        readyClients.Remove(clientId);
        FastBufferWriter writer = Begin(Message.Left);
        writer.WriteValueSafe((byte)slot);
        SendToClients(writer, NetworkDelivery.ReliableSequenced);
        if (arena != null) arena.ApplyPlayerLeft(slot);
        StartIfEveryoneReady();
    }

    // Host: tell a newly connected player what the lobby looks like.
    private static void OnClientConnected(ulong clientId)
    {
        if (!IsHost) return;
        LobbyChanged?.Invoke();
        if (clientId == Network.LocalClientId) return;
        FastBufferWriter writer = WriteLobby();
        try { Network.CustomMessagingManager.SendNamedMessage(Channel, clientId, writer, NetworkDelivery.ReliableSequenced); }
        finally { writer.Dispose(); }
    }

    // ---------- Sending helpers ----------

    private static int SlotOf(ulong clientId) => slotClients.IndexOf(clientId);

    private static bool IsConnected(ulong clientId)
    {
        if (Network == null) return false;
        foreach (ulong id in Network.ConnectedClientsIds)
            if (id == clientId) return true;
        return false;
    }

    private static FastBufferWriter Begin(Message kind)
    {
        var writer = new FastBufferWriter(64, Allocator.Temp, 1024);
        writer.WriteValueSafe((byte)kind);
        return writer;
    }

    private static bool CanSend => Network != null && Network.IsListening && Network.CustomMessagingManager != null;

    // Sends and disposes the writer.
    private static void SendToHost(FastBufferWriter writer, NetworkDelivery delivery)
    {
        try
        {
            if (CanSend && !Network.IsServer)
                Network.CustomMessagingManager.SendNamedMessage(Channel, NetworkManager.ServerClientId, writer, delivery);
        }
        finally { writer.Dispose(); }
    }

    // Host: sends to every client except the host itself (and except one
    // client, when passing on a message that client sent). Disposes the writer.
    private static void SendToClients(FastBufferWriter writer, NetworkDelivery delivery, ulong except = ulong.MaxValue)
    {
        try
        {
            if (!CanSend || !Network.IsServer) return;
            foreach (ulong id in Network.ConnectedClientsIds)
                if (id != Network.LocalClientId && id != except)
                    Network.CustomMessagingManager.SendNamedMessage(Channel, id, writer, delivery);
        }
        finally { writer.Dispose(); }
    }

    // News about this computer's own player: the host tells every client,
    // a client tells the host, who passes it on.
    private static void SendFromOwner(FastBufferWriter writer, NetworkDelivery delivery)
    {
        if (IsHost) SendToClients(writer, delivery);
        else SendToHost(writer, delivery);
    }

    // Host: passes a client's message on to the other clients unchanged.
    private static void Relay(ulong sender, FastBufferReader reader, NetworkDelivery delivery)
    {
        byte[] bytes = reader.ToArray();
        var writer = new FastBufferWriter(bytes.Length, Allocator.Temp);
        writer.WriteBytesSafe(bytes);
        SendToClients(writer, delivery, sender);
    }

    // ---------- Every frame ----------

    private sealed class Runner : MonoBehaviour
    {
        private NetworkManager hookedManager;
        private bool handlerRegistered;
        private float nextStateSend;

        private void Update()
        {
            NetworkManager network = Network;
            bool listening = network != null && network.IsListening && network.CustomMessagingManager != null;
            if (listening && (!handlerRegistered || hookedManager != network))
            {
                network.CustomMessagingManager.RegisterNamedMessageHandler(Channel, OnMessage);
                if (hookedManager != network)
                {
                    network.OnClientDisconnectCallback += OnClientDisconnected;
                    network.OnClientConnectedCallback += OnClientConnected;
                }
                hookedManager = network;
                handlerRegistered = true;
            }
            else if (!listening)
            {
                handlerRegistered = false;
            }

            if (!IsRunning || !listening || arena == null) return;

            // Start without anyone whose level never finished loading.
            if (IsHost && arena.State == ArenaRoundState.Waiting && Time.unscaledTime >= readyDeadline)
                HostRestartRound();

            if (arena.IsPlaying && Time.unscaledTime >= nextStateSend)
            {
                nextStateSend = Time.unscaledTime + StateSendInterval;
                SendLocalState();
            }
        }
    }
}
