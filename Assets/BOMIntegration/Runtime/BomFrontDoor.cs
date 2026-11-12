using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Bom.Unity
{
    // C5: Darryn's main menu is the front door. "Online" (BomOnlineMenu) hosts or joins Odin play over LAN/direct IP (D3).
    // Host: start BOM-server.exe (BomHostServer), load the level's network scene and connect with the in-memory host
    // token. Join: load the scene and connect to the typed address. Leaving goes back to MainMenuScene and stops the
    // server. Unity decides nothing here: Odin runs the round; this only starts processes and calls ConnectTo.
    public sealed class BomFrontDoor : MonoBehaviour
    {
        public const string MainMenuScene = "MainMenuScene";
        public const uint DefaultPort = 47380;
        const int PortAttempts = 10;
        const double ServerStartSeconds = 60;

        public sealed class Level
        {
            public string Name,
                Scene,
                Layout;
        }

        // Host level picker. C6 adds Darryn's Yard, Bridge and Tower here; the old network yard stays as "Classic Yard".
        public static readonly IReadOnlyList<Level> Levels = new[]
        {
            new Level { Name = "CLASSIC YARD", Scene = "NetworkMenu", Layout = "yard.json" },
        };

        sealed class Pending
        {
            public string Address,
                Token;
            public uint Port;
            public bool Host;
        }

        static BomFrontDoor instance;
        static Pending pending;
        public static BomHostServer Server { get; private set; }
        // True from the moment the player leaves the main menu for Odin play until it returns.
        public static bool InSession { get; private set; }
        public static bool IsHost { get; private set; }
        public static bool LanHost { get; private set; }
        public static uint SessionPort { get; private set; }
        public static bool Busy { get; private set; }
        public static int LastServerPid { get; private set; }

        static BomFrontDoor Instance
        {
            get
            {
                if (instance == null)
                {
                    var root = new GameObject("BOM front door");
                    DontDestroyOnLoad(root);
                    instance = root.AddComponent<BomFrontDoor>();
                }
                return instance;
            }
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Initialize()
        {
            _ = Instance;
            if (Array.IndexOf(Environment.GetCommandLineArgs(), "--bom-frontdoor-test") >= 0)
                Instance.gameObject.AddComponent<BomFrontDoorScenario>();
        }

        void OnEnable()
        {
            SceneManager.sceneLoaded += OnSceneLoaded;
            Application.quitting += OnQuitting;
        }

        void OnDisable()
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;
            Application.quitting -= OnQuitting;
        }

        static void OnQuitting() => StopServer("quit", 0);

        void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            if (scene.name == MainMenuScene)
            {
                // Back at the front door: no server may outlive the session (a crash path or a scene change we did not start).
                if (Server != null)
                {
                    var server = Server;
                    Server = null;
                    server.Stop("menu", 0);
                }
                InSession = false;
                IsHost = false;
                pending = null;
                return;
            }
            if (pending == null)
                return;
            var client = FindFirstObjectByType<BomClientBehaviour>();
            var request = pending;
            pending = null;
            if (client == null)
            {
                Debug.LogError("BOM FRONTDOOR scene " + scene.name + " has no network client");
                ReturnToMainMenu("no-client");
                return;
            }
            try
            {
                client.ConnectTo(request.Address, request.Port, request.Token, false);
                Debug.Log(
                    "BOM FRONTDOOR CONNECT role=" + (request.Host ? "host" : "guest") + " scene=" + scene.name + " address="
                        + request.Address + " port=" + request.Port
                );
            }
            catch (Exception error)
            {
                Debug.LogError("BOM FRONTDOOR connect failed: " + error.Message);
            }
        }

        // Hosting. status(message, isError) reports progress to the menu; done(ok) runs once at the end.
        public static void Host(Level level, uint port, bool lan, Action<string, bool> status, Action<bool> done)
        {
            if (Busy || InSession)
            {
                done?.Invoke(false);
                return;
            }
            Instance.StartCoroutine(Instance.HostRoutine(level, port, lan, status, done));
        }

        public static void CancelHost()
        {
            if (!Busy)
                return;
            Instance.StopAllCoroutines();
            Busy = false;
            StopServer("cancel", 0);
        }

        IEnumerator HostRoutine(Level level, uint first, bool lan, Action<string, bool> status, Action<bool> done)
        {
            Busy = true;
            string exe = BomHostServer.FindServer(),
                layout = BomHostServer.FindLayout(level.Layout);
            if (exe == null || layout == null)
            {
                Busy = false;
                status(
                    exe == null
                        ? "BOM-server.exe was not found. Expected it in a \"Server\" folder next to the game."
                        : "Level file " + level.Layout + " was not found in Server\\levels next to the game.",
                    true
                );
                done?.Invoke(false);
                yield break;
            }
            string token = BomHostServer.NewHostToken();
            string bind = lan ? "0.0.0.0" : "127.0.0.1";
            string logFolder = LogFolder();
            var busyPorts = new List<uint>();
            BomHostServer started = null;
            for (int attempt = 0; attempt < PortAttempts && started == null; attempt++)
            {
                uint port = first + (uint)attempt;
                if (port > 65535)
                    break;
                if (!BomHostServer.UdpPortFree(port))
                {
                    busyPorts.Add(port);
                    Debug.Log("BOM FRONTDOOR PORT busy port=" + port + " (probe)");
                    continue;
                }
                status(
                    (busyPorts.Count > 0 ? "Port " + string.Join(", ", busyPorts) + " is in use. " : "")
                        + "Starting the server on port " + port + "…",
                    false
                );
                BomHostServer server = null;
                string startError = null;
                try
                {
                    server = BomHostServer.Start(
                        exe,
                        layout,
                        bind,
                        port,
                        token,
                        Path.Combine(logFolder, "bom-server-" + DateTime.UtcNow.ToString("yyyyMMddTHHmmssfffZ") + ".log")
                    );
                }
                catch (Exception error)
                {
                    startError = error.Message;
                }
                if (server == null)
                {
                    Busy = false;
                    status("The server could not start: " + startError, true);
                    done?.Invoke(false);
                    yield break;
                }
                Server = server;
                LastServerPid = server.Pid;
                Debug.Log("BOM FRONTDOOR SERVER started pid=" + server.Pid + " bind=" + bind + " port=" + port + " log=" + server.LogPath);
                float deadline = Time.realtimeSinceStartup + (float)ServerStartSeconds;
                while (!server.Listening && !server.Exited && Time.realtimeSinceStartup < deadline)
                    yield return null;
                if (server.Listening && !server.Exited)
                {
                    started = server;
                    break;
                }
                // Give the output reader a moment to deliver the last lines before deciding why it stopped.
                float settle = Time.realtimeSinceStartup + .5f;
                while (Time.realtimeSinceStartup < settle && !server.BindFailed)
                    yield return null;
                bool bindFailed = server.BindFailed;
                StopServer(bindFailed ? "port-busy" : "start-failed", 2000);
                if (bindFailed)
                {
                    busyPorts.Add(port);
                    Debug.Log("BOM FRONTDOOR PORT busy port=" + port + " (server bind)");
                    continue;
                }
                Busy = false;
                status("The server stopped while starting. Its log: " + server.LogPath, true);
                done?.Invoke(false);
                yield break;
            }
            if (started == null)
            {
                Busy = false;
                status(
                    "No free UDP port from " + first + " to " + Math.Min(65535, first + PortAttempts - 1)
                        + ". Close the other game or server, or pick another port.",
                    true
                );
                done?.Invoke(false);
                yield break;
            }
            if (busyPorts.Count > 0)
                Debug.Log("BOM FRONTDOOR PORT chosen=" + started.Port + " busy=" + string.Join(",", busyPorts));
            Busy = false;
            IsHost = true;
            LanHost = lan;
            Begin(level.Scene, "127.0.0.1", started.Port, token, true);
            done?.Invoke(true);
        }

        public static void Join(Level level, string address, uint port)
        {
            if (Busy || InSession)
                return;
            IsHost = false;
            LanHost = false;
            Begin(level.Scene, address, port, "", false);
        }

        static void Begin(string scene, string address, uint port, string token, bool host)
        {
            pending = new Pending { Address = address, Port = port, Token = token, Host = host };
            InSession = true;
            SessionPort = port;
            Debug.Log("BOM FRONTDOOR LOAD scene=" + scene + " role=" + (host ? "host" : "guest") + " port=" + port);
            SceneManager.LoadScene(scene);
        }

        // RETURN, LEAVE GAME and "Main menu" in the network HUD. The caller has already disconnected the client; the server
        // ends itself when its host leaves ("SERVER host-left shutdown"), which lets guests see a clean "host left". It is
        // killed if it is still running after a short grace.
        public static void ReturnToMainMenu(string reason)
        {
            Debug.Log("BOM FRONTDOOR RETURN reason=" + reason + " host=" + IsHost);
            var server = Server;
            Server = null;
            if (server != null)
            {
                stopping = server;
                Instance.StartCoroutine(Instance.StopAfterGrace(server, reason, 1.5f));
            }
            pending = null;
            SceneManager.LoadScene(MainMenuScene);
        }

        IEnumerator StopAfterGrace(BomHostServer server, string reason, float seconds)
        {
            float deadline = Time.realtimeSinceStartup + seconds;
            while (!server.Exited && Time.realtimeSinceStartup < deadline)
                yield return null;
            if (stopping == server)
            {
                stopping = null;
                server.Stop(reason, 3000);
            }
        }

        static void StopServer(string reason, int waitMs)
        {
            var server = Server;
            Server = null;
            server?.Stop(reason, waitMs);
            var graced = stopping;
            stopping = null;
            graced?.Stop(reason, waitMs);
        }

        // A server that is getting its grace period after its host left (see ReturnToMainMenu).
        static BomHostServer stopping;
        public static bool ServerRunning => Server != null || stopping != null;

        public static string LogFolder()
        {
            string player = Application.consoleLogPath;
            if (!string.IsNullOrEmpty(player))
                return Path.GetDirectoryName(Path.GetFullPath(player));
            return Path.Combine(Application.persistentDataPath, "Logs");
        }

        // IPv4 addresses other machines on the LAN can type into Join (up, non-loopback, non-link-local).
        public static List<string> LanAddresses()
        {
            var list = new List<string>();
            try
            {
                foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                        continue;
                    foreach (var unicast in nic.GetIPProperties().UnicastAddresses)
                    {
                        var ip = unicast.Address;
                        if (ip.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(ip))
                            continue;
                        string text = ip.ToString();
                        if (!text.StartsWith("169.254.") && !list.Contains(text))
                            list.Add(text);
                    }
                }
            }
            catch (Exception error)
            {
                Debug.LogWarning("BOM FRONTDOOR could not list LAN addresses: " + error.Message);
            }
            return list;
        }

        // Join validation: a dotted IPv4 address (the native client takes IPv4 only) and a port from 1 to 65535.
        public static string ValidateJoin(string address, string portText, out uint port)
        {
            port = 0;
            address = (address ?? "").Trim();
            var parts = address.Split('.');
            bool ok = parts.Length == 4;
            foreach (var part in parts)
                ok &= part.Length is > 0 and <= 3 && int.TryParse(part, out int value) && value >= 0 && value <= 255;
            if (!ok)
                return "Enter the host's IPv4 address, like 192.168.1.20 (127.0.0.1 for this PC).";
            if (address == "0.0.0.0")
                return "0.0.0.0 is not a host address. Use 127.0.0.1 for this PC.";
            return ValidatePort(portText, out port);
        }

        public static string ValidatePort(string portText, out uint port)
        {
            if (!uint.TryParse((portText ?? "").Trim(), out port) || port < 1 || port > 65535)
                return "Enter a port from 1 to 65535.";
            return null;
        }
    }
}
