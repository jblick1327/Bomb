using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Unity.Netcode;
using Unity.Netcode.Transports.UTP;
using Unity.Services.Authentication;
using Unity.Services.Core;
using Unity.Services.Multiplayer;
using UnityEngine;

// Hosts and joins online games through Unity's Multiplayer Services: one
// player hosts, friends join with a short code, and traffic goes through Unity
// Relay over secure WebSockets so the browser build can connect.
//
// Nothing here runs until the player picks Online. Offline play never signs in
// to Unity Services or creates a NetworkManager.
//
// All async work stays on Unity's main thread (no Task.Run or
// ConfigureAwait(false)), which WebGL requires.
public static class OnlineSession
{
    public const int MaxPlayers = 4;

    private static Task initializeTask;
    private static NetworkManager networkManager;

    // The current online game, or null when not connected.
    public static ISession Current { get; private set; }
    public static bool IsActive => Current != null;
    public static bool IsHost => Current != null && Current.IsHost;
    public static string JoinCode => Current?.Code ?? string.Empty;
    public static string LocalPlayerId =>
        UnityServices.State == ServicesInitializationState.Initialized && AuthenticationService.Instance.IsSignedIn
            ? AuthenticationService.Instance.PlayerId : string.Empty;

    // Raised when the player list or connection state changes.
    public static event Action Changed;
    // Raised when the game ends for this player, with a message to show
    // (for example "The host left the game.").
    public static event Action<string> Ended;

    // Players in the session, in join order. The host is always first.
    public static IReadOnlyList<IReadOnlyPlayer> Players =>
        Current != null ? Current.Players : (IReadOnlyList<IReadOnlyPlayer>)Array.Empty<IReadOnlyPlayer>();

    // True once the game connection (not just the session) is up.
    public static bool IsNetworkConnected =>
        networkManager != null && (networkManager.IsHost || networkManager.IsConnectedClient);

    public static Task InitializeAsync()
    {
        if (initializeTask == null || initializeTask.IsFaulted || initializeTask.IsCanceled)
            initializeTask = InitializeServicesAsync();
        return initializeTask;
    }

    private static async Task InitializeServicesAsync()
    {
        if (UnityServices.State != ServicesInitializationState.Initialized)
        {
            // A fresh profile per launch gives every browser tab its own
            // anonymous player, so two tabs on one computer can host and join.
            string profile = "p" + Guid.NewGuid().ToString("N").Substring(0, 12);
            await UnityServices.InitializeAsync(new InitializationOptions().SetProfile(profile));
        }
        if (!AuthenticationService.Instance.IsSignedIn)
            await AuthenticationService.Instance.SignInAnonymouslyAsync();
    }

    // Creates a game and returns its join code.
    public static async Task<string> HostAsync()
    {
        await InitializeAsync();
        EnsureNetworkManager();
        SessionOptions options = new SessionOptions { MaxPlayers = MaxPlayers, IsPrivate = true }
            .WithRelayNetwork()
            .WithNetworkOptions(new NetworkOptions { RelayProtocol = RelayProtocol.WSS });
        Attach(await MultiplayerService.Instance.CreateSessionAsync(options));
        return Current.Code;
    }

    public static async Task JoinAsync(string code)
    {
        await InitializeAsync();
        EnsureNetworkManager();
        JoinSessionOptions options = new JoinSessionOptions()
            .WithNetworkOptions(new NetworkOptions { RelayProtocol = RelayProtocol.WSS });
        Attach(await MultiplayerService.Instance.JoinSessionByCodeAsync(code.Trim().ToUpperInvariant(), options));
    }

    // Leaves the game. When the host leaves, the session closes for everyone.
    public static async Task LeaveAsync()
    {
        ISession session = Current;
        Detach();
        if (session != null)
        {
            try { await session.LeaveAsync(); }
            catch (Exception e) { Debug.LogWarning($"[Online] Leaving the session failed: {e.Message}"); }
        }
        ShutdownNetwork();
        Changed?.Invoke();
    }

    public static bool IsLocalPlayer(IReadOnlyPlayer player) => player != null && player.Id == LocalPlayerId;
    public static bool IsHostPlayer(IReadOnlyPlayer player) => player != null && Current != null && player.Id == Current.Host;

    // The NetworkManager is created from code the first time Online is used,
    // so offline scenes never contain one.
    private static void EnsureNetworkManager()
    {
        if (networkManager != null) return;
        if (NetworkManager.Singleton != null)
        {
            networkManager = NetworkManager.Singleton;
        }
        else
        {
            var root = new GameObject("Network Manager");
            // Inactive while setting up, so the manager wakes with its config in place.
            root.SetActive(false);
            var transport = root.AddComponent<UnityTransport>();
            // Relay's "wss" connection: required by browsers, and used
            // everywhere so an editor host can be joined from a browser.
            transport.UseWebSockets = true;
            networkManager = root.AddComponent<NetworkManager>();
            networkManager.NetworkConfig = new NetworkConfig
            {
                NetworkTransport = transport,
                EnableSceneManagement = true,
                ConnectionApproval = false,
            };
            // Keep the game running when the browser tab loses focus.
            networkManager.RunInBackground = true;
            root.SetActive(true);
        }
        networkManager.OnClientDisconnectCallback += OnClientDisconnect;
        networkManager.OnTransportFailure += OnTransportFailure;
        Application.runInBackground = true;
    }

    private static void Attach(ISession session)
    {
        Current = session;
        session.PlayerJoined += OnPlayerListChanged;
        session.PlayerHasLeft += OnPlayerListChanged;
        session.Changed += OnSessionChanged;
        session.RemovedFromSession += OnRemovedFromSession;
        session.Deleted += OnSessionDeleted;
        Changed?.Invoke();
    }

    private static void Detach()
    {
        ISession session = Current;
        if (session == null) return;
        session.PlayerJoined -= OnPlayerListChanged;
        session.PlayerHasLeft -= OnPlayerListChanged;
        session.Changed -= OnSessionChanged;
        session.RemovedFromSession -= OnRemovedFromSession;
        session.Deleted -= OnSessionDeleted;
        Current = null;
    }

    private static void ShutdownNetwork()
    {
        if (networkManager != null && networkManager.IsListening)
            networkManager.Shutdown();
    }

    private static void OnPlayerListChanged(string playerId) => Changed?.Invoke();
    private static void OnSessionChanged() => Changed?.Invoke();
    private static void OnRemovedFromSession() => End("You were removed from the game.");
    private static void OnSessionDeleted() => End("The host closed the game.");

    private static void OnClientDisconnect(ulong clientId)
    {
        // A client losing its own connection means the host is gone.
        if (networkManager == null || networkManager.IsServer || clientId != networkManager.LocalClientId) return;
        End("Lost connection to the host.");
    }

    private static void OnTransportFailure() => End("The network connection failed.");

    private static async void End(string reason)
    {
        if (Current == null) return;
        await LeaveAsync();
        Ended?.Invoke(reason);
    }
}
