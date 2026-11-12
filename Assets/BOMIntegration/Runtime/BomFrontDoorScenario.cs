using System;
using System.Collections;
using System.IO;
using Bom.Native;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace Bom.Unity
{
    // C5 scripted run (opt-in: --bom-frontdoor-test <dir> --bom-frontdoor-role host|guest|crash). Starts at Darryn's
    // MainMenuScene and presses the same buttons a player would: ONLINE, HOST GAME / JOIN GAME, START / JOIN, RETURN.
    // The host starts BOM-server.exe itself (no launcher). Odin decides the round; this only waits for its snapshots.
    // Host: host -> wait for the guest -> Elimination (host command) -> round Finished -> RETURN (server must stop) ->
    //       host again -> quit (server must stop). Guest: bad address and port rejected -> join -> forfeit by LEAVE GAME at
    //       150 ticks (the Rounds gate's choreography) -> join again -> sees the Finished round -> RETURN -> quit.
    // Crash: host and wait; the tool kills this player and checks the job object took the server with it.
    public sealed class BomFrontDoorScenario : MonoBehaviour
    {
        const ulong GuestForfeitTicks = 150;
        string dir,
            role;
        uint port = BomFrontDoor.DefaultPort;
        string joinAddress = "127.0.0.1";

        void Start()
        {
            var args = Environment.GetCommandLineArgs();
            string Arg(string key, string value)
            {
                int i = Array.IndexOf(args, key);
                return i >= 0 && i + 1 < args.Length ? args[i + 1] : value;
            }
            dir = Arg("--bom-frontdoor-test", "");
            role = Arg("--bom-frontdoor-role", "host");
            port = uint.Parse(Arg("--bom-frontdoor-port", port.ToString()));
            joinAddress = Arg("--bom-frontdoor-address", joinAddress);
            QualitySettings.vSyncCount = 0;
            Application.targetFrameRate = 60;
            Directory.CreateDirectory(dir);
            Log("start port=" + port);
            StartCoroutine(Guard(role == "guest" ? Guest() : role == "crash" ? Crash() : Host()));
        }

        void Log(string text) => Debug.Log("BOM FRONTDOOR TEST role=" + role + " " + text);

        void Mark(string name, string body = "")
        {
            File.WriteAllText(Path.Combine(dir, role + "-" + name + ".signal"), name + "\n" + body);
            Log("signal " + name + " " + body.Replace("\n", " "));
        }

        bool Seen(string name) => File.Exists(Path.Combine(dir, name + ".signal"));

        // Runs nested steps itself (not as Unity sub-coroutines) so a failure anywhere ends the run with exit code 4.
        IEnumerator Guard(IEnumerator steps)
        {
            var stack = new System.Collections.Generic.Stack<IEnumerator>();
            stack.Push(steps);
            while (stack.Count > 0)
            {
                object current;
                try
                {
                    if (!stack.Peek().MoveNext())
                    {
                        stack.Pop();
                        continue;
                    }
                    current = stack.Peek().Current;
                }
                catch (Exception error)
                {
                    Debug.LogError("BOM FRONTDOOR TEST FAIL role=" + role + " " + error.Message);
                    Application.Quit(4);
                    yield break;
                }
                if (current is IEnumerator nested)
                {
                    stack.Push(nested);
                    continue;
                }
                yield return current;
            }
            Log("PASS");
            Mark("pass");
            yield return new WaitForSecondsRealtime(.5f);
            Application.Quit(0);
        }

        static IEnumerator Until(Func<bool> done, double seconds, string what)
        {
            float deadline = Time.realtimeSinceStartup + (float)seconds;
            while (!done())
            {
                if (Time.realtimeSinceStartup > deadline)
                    throw new TimeoutException("Timed out waiting for " + what);
                yield return null;
            }
        }

        static void Press(Button button, string what)
        {
            if (button == null || !button.isActiveAndEnabled || !button.interactable)
                throw new InvalidOperationException("Button not available: " + what);
            button.onClick.Invoke();
        }

        IEnumerator OpenOnline()
        {
            Button online = null;
            yield return Until(
                () =>
                {
                    if (SceneManager.GetActiveScene().name != BomFrontDoor.MainMenuScene)
                        return false;
                    var found = GameObject.Find("OnlineButton");
                    online = found != null ? found.GetComponent<Button>() : null;
                    return online != null && online.isActiveAndEnabled;
                },
                60,
                "the main menu ONLINE button"
            );
            yield return new WaitForSecondsRealtime(1f);
            Log("menu ONLINE");
            Press(online, "ONLINE");
            yield return Until(() => BomOnlineMenu.Current != null, 10, "the online menu");
        }

        IEnumerator HostFromMenu()
        {
            yield return OpenOnline();
            var menu = BomOnlineMenu.Current;
            Press(menu.HostButton, "HOST GAME");
            yield return null;
            menu.PortField.text = port.ToString();
            Press(menu.StartButton, "START");
            yield return Until(() => Client() != null && Connected(Client()), 90, "the hosted level to load and connect");
            if (!IsHost(Client()))
                throw new InvalidOperationException("Hosted, but the server did not grant host permission");
            if (!BomFrontDoor.ServerRunning)
                throw new InvalidOperationException("Connected, but no server process is tracked");
            Log("hosted port=" + BomFrontDoor.SessionPort + " pid=" + BomFrontDoor.LastServerPid);
        }

        IEnumerator JoinFromMenu(string address)
        {
            yield return OpenOnline();
            var menu = BomOnlineMenu.Current;
            Press(menu.JoinButton, "JOIN GAME");
            yield return null;
            menu.AddressField.text = address;
            menu.PortField.text = port.ToString();
            Press(menu.ConnectButton, "JOIN");
        }

        static BomClientBehaviour Client() => FindFirstObjectByType<BomClientBehaviour>();

        static bool Connected(BomClientBehaviour client) =>
            client.ConnectionRequested
            && client.Session != null
            && (client.Session.Sample.flags & 6) == 6
            && (client.Session.Round.flags & 1) != 0;

        static bool IsHost(BomClientBehaviour client)
        {
            var stats = new BomStats { struct_size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<BomStats>(), version = 1 };
            return BomNative.bom_client_get_stats(client.Session.Handle, ref stats) == 0 && (stats.flags & 4) != 0;
        }

        static bool ProcessGone(int pid)
        {
            try { return System.Diagnostics.Process.GetProcessById(pid).HasExited; }
            catch (ArgumentException) { return true; }
            catch (InvalidOperationException) { return true; }
        }

        void LogRound(BomClientBehaviour client)
        {
            var r = client.Session.Round;
            Log("round=" + r.round_id + " state=" + r.state + " mode=" + r.mode + " tick=" + r.tick + " winner=" + r.winner + " draw=" + r.draw + " local=" + r.local_session_id);
            if (r.state == 3)
                foreach (var p in client.Session.RoundPlayers)
                    if (p.session_id != 0)
                        Log("player round=" + r.round_id + " session=" + p.session_id + " slot=" + p.slot + " alive=" + p.alive + " death=" + p.death + " xp=" + p.xp_gained);
        }

        IEnumerator WaitForMainMenu()
        {
            yield return Until(() => SceneManager.GetActiveScene().name == BomFrontDoor.MainMenuScene, 30, "the main menu");
        }

        IEnumerator Host()
        {
            yield return HostFromMenu();
            int pid = BomFrontDoor.LastServerPid;
            Mark("hosted", "port=" + BomFrontDoor.SessionPort + "\npid=" + pid);
            yield return Until(() => Seen("guest-connected"), 120, "the guest to join");
            var client = Client();
            BomSession.Check(BomNative.bom_client_host_command(client.Session.Handle, 5, 1, 0));
            Log("applied Elimination");
            ulong lastKey = ulong.MaxValue;
            yield return Until(
                () =>
                {
                    var r = client.Session.Round;
                    ulong key = (r.round_id << 8) | r.state;
                    if (key != lastKey)
                    {
                        lastKey = key;
                        LogRound(client);
                    }
                    return r.mode == 1 && r.state == 3;
                },
                180,
                "the round to finish"
            );
            var finished = client.Session.Round;
            if (finished.draw == 0 && finished.winner != finished.local_session_id)
                throw new InvalidOperationException("The guest forfeited, so the host should have won");
            Mark("finished", "round=" + finished.round_id + "\nwinner=" + finished.winner + "\ndraw=" + finished.draw);
            yield return Until(() => Seen("guest-finished"), 120, "the guest to see the finished round");
            // The guest goes back to its menu first. (A guest still connected when the host leaves gets the existing
            // "The host left" error, which BomClientBehaviour logs as an exception; that path is left to the owner check.)
            yield return Until(() => Seen("guest-menu"), 60, "the guest to return to its menu");
            Log("RETURN");
            FindFirstObjectByType<BomNetworkHud>().Leave();
            yield return WaitForMainMenu();
            yield return Until(() => !BomFrontDoor.ServerRunning && ProcessGone(pid), 10, "the server to stop after returning to the menu");
            Mark("menu", "server_pid=" + pid + "\nserver_gone=1");
            yield return HostFromMenu();
            int second = BomFrontDoor.LastServerPid;
            Mark("rehosted", "port=" + BomFrontDoor.SessionPort + "\npid=" + second);
            yield return new WaitForSecondsRealtime(1f);
            // Quit while hosting: BomFrontDoor stops the server on Application.quitting (the tool checks the pid).
        }

        IEnumerator Guest()
        {
            yield return OpenOnline();
            var menu = BomOnlineMenu.Current;
            Press(menu.JoinButton, "JOIN GAME");
            yield return null;
            menu.AddressField.text = "999.1.1.1";
            menu.PortField.text = port.ToString();
            Press(menu.ConnectButton, "JOIN (bad address)");
            yield return null;
            if (!menu.StatusIsError || menu.Showing != BomOnlineMenu.MenuScreen.Join || BomFrontDoor.InSession)
                throw new InvalidOperationException("A bad address was not rejected");
            Log("bad address rejected: " + menu.Status);
            menu.AddressField.text = joinAddress;
            menu.PortField.text = "70000";
            Press(menu.ConnectButton, "JOIN (bad port)");
            yield return null;
            if (!menu.StatusIsError || BomFrontDoor.InSession)
                throw new InvalidOperationException("A bad port was not rejected");
            Log("bad port rejected: " + menu.Status);
            menu.PortField.text = port.ToString();
            Press(menu.ConnectButton, "JOIN");
            yield return Until(() => Client() != null && Connected(Client()), 90, "the joined level to load and connect");
            if (IsHost(Client()))
                throw new InvalidOperationException("A guest must not get host permission");
            Mark("connected");
            var client = Client();
            ulong forfeitRound = 0,
                lastKey = ulong.MaxValue;
            yield return Until(
                () =>
                {
                    var r = client.Session.Round;
                    ulong key = (r.round_id << 8) | r.state;
                    if (key != lastKey)
                    {
                        lastKey = key;
                        LogRound(client);
                    }
                    if (r.mode == 1 && r.state == 2 && r.tick >= r.start_tick + GuestForfeitTicks)
                        forfeitRound = r.round_id;
                    return forfeitRound != 0;
                },
                180,
                "the elimination round to play"
            );
            Log("LEAVE GAME (forfeit) round=" + forfeitRound);
            FindFirstObjectByType<BomNetworkHud>().Leave();
            yield return WaitForMainMenu();
            Mark("forfeit", "round=" + forfeitRound);
            yield return JoinFromMenu(joinAddress);
            yield return Until(() => Client() != null && Connected(Client()), 90, "rejoining");
            client = Client();
            yield return Until(() => client.Session.Round.round_id == forfeitRound && client.Session.Round.state == 3, 60, "the finished round after rejoining");
            LogRound(client);
            Mark("finished", "round=" + forfeitRound + "\nwinner=" + client.Session.Round.winner);
            yield return new WaitForSecondsRealtime(1f);
            Log("RETURN");
            FindFirstObjectByType<BomNetworkHud>().Leave();
            yield return WaitForMainMenu();
            Mark("menu");
        }

        IEnumerator Crash()
        {
            yield return HostFromMenu();
            Mark("hosted", "port=" + BomFrontDoor.SessionPort + "\npid=" + BomFrontDoor.LastServerPid);
            // Wait to be killed by the tool.
            yield return Until(() => false, 120, "the tool to kill this player");
        }
    }
}
