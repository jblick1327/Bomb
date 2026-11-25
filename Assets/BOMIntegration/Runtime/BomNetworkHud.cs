using System;
using Bom.Native;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;

namespace Bom.Unity
{
    // Read-only adapter for the preserved arena UXML/USS. All outcomes and XP are
    // supplied by the native server snapshot; buttons send intent through the C ABI.
    [RequireComponent(typeof(UIDocument))]
    public sealed class BomNetworkHud : MonoBehaviour
    {
        public BomClientBehaviour Client;
        public VisualTreeAsset ArenaHudTemplate;
        public StyleSheet ArenaHudStyle;
        public StyleSheet NetworkMenuStyle;
        VisualElement root,
            hud,
            menu,
            death;
        Label status,
            roundState,
            timer,
            bombs,
            winner,
            resultBombs,
            resultTime,
            resultCoins,
            resultTotal;
        VisualElement pausePanel;
        Button pauseResume,
            pauseRestart,
            pauseLeave;
        TextField address,
            port,
            token;
        Toggle spectator;
        DropdownField mode;
        Button connect,
            disconnect,
            reconnect,
            restart,
            setMode;
        Button replay, leave, mainMenu;
        ulong lastHudKey = ulong.MaxValue,
            menuRound = ulong.MaxValue;
        uint menuState = uint.MaxValue;
        bool sawElimination; // P2: "Preparing the round…" only until the menu's Elimination request first takes effect
        string message = "Connect to a local or LAN server.";
        ulong displayedRound,
            displayedTick;
        double receivedAt;
        bool wasBlocked;
        ulong menuConnection;
        uint serverMode = uint.MaxValue;

        public void SetMenuVisible(bool visible)
        {
            if (menu == null)
                return;
            menu.style.display = visible ? DisplayStyle.Flex : DisplayStyle.None;
            // C4: Darryn's pause-panel is our Esc menu. The game does not pause; it only shows next to the connection menu.
            if (pausePanel != null)
                pausePanel.style.display =
                    visible && Client != null && Client.ConnectionRequested ? DisplayStyle.Flex : DisplayStyle.None;
            if (!visible)
                (root.panel?.focusController?.focusedElement as VisualElement)?.Blur();
        }

        void Start()
        {
            DisableDuplicateArenaHud(GetComponent<UIDocument>());
            if (!TryGetComponent<BomCursorGuard>(out _))
                gameObject.AddComponent<BomCursorGuard>();
            if (!TryGetComponent<BomFocusGuard>(out _))
                gameObject.AddComponent<BomFocusGuard>();
            if (Client != null)
            {
                address.SetValueWithoutNotify(Client.Address);
                port.SetValueWithoutNotify(Client.Port.ToString());
            }
            ApplyFrontDoor();
        }

        // C5: started from the main menu. The connection was made for the player, so the manual connection fields are
        // hidden, leaving goes back to the main menu, and a LAN host is shown the addresses other PCs type into Join.
        void ApplyFrontDoor()
        {
            bool front = BomFrontDoor.InSession;
            foreach (VisualElement element in new VisualElement[] { address, port, token, spectator, connect })
                if (element != null)
                    element.style.display = front ? DisplayStyle.None : DisplayStyle.Flex;
            if (mainMenu != null)
                mainMenu.style.display = front ? DisplayStyle.Flex : DisplayStyle.None;
            if (!front)
                return;
            if (BomFrontDoor.IsHost && BomFrontDoor.LanHost)
            {
                var addresses = BomFrontDoor.LanAddresses();
                message =
                    "Hosting on port " + BomFrontDoor.SessionPort + ". Other PCs join "
                    + (addresses.Count > 0 ? string.Join(" or ", addresses) : "this PC's address") + " port " + BomFrontDoor.SessionPort + ".";
            }
            else if (BomFrontDoor.IsHost)
                message = "Hosting on port " + BomFrontDoor.SessionPort + " (this PC only). Others on this PC join 127.0.0.1.";
            else
                message = "Joined port " + BomFrontDoor.SessionPort + ".";
        }

        // The network scenes still hold a leftover "Arena UI" UIDocument that draws Darryn's ArenaHud.uxml with no
        // stylesheet, so his pause and game-over panels show over the game. Our HUD draws the same template, styled.
        void DisableDuplicateArenaHud(UIDocument own)
        {
            if (ArenaHudTemplate == null)
                return;
            foreach (
                var other in FindObjectsByType<UIDocument>(
                    FindObjectsInactive.Include,
                    FindObjectsSortMode.None
                )
            )
                if (other != own && other.visualTreeAsset == ArenaHudTemplate && other.enabled)
                    other.enabled = false;
        }

        void OnEnable()
        {
            var doc = GetComponent<UIDocument>();
            DisableDuplicateArenaHud(doc);
            SceneManager.sceneLoaded += OnSceneLoaded;
            root = doc.rootVisualElement;
            root.Clear();
            root.pickingMode = PickingMode.Ignore;
            if (ArenaHudTemplate != null)
            {
                hud = ArenaHudTemplate.CloneTree();
                if (ArenaHudStyle != null)
                    hud.styleSheets.Add(ArenaHudStyle);
                root.Add(hud);
                hud.pickingMode = PickingMode.Ignore;
            }
            else
            {
                hud = new VisualElement();
                root.Add(hud);
            }
            hud.style.position = Position.Absolute;
            hud.style.left = 0;
            hud.style.top = 0;
            hud.style.right = 0;
            hud.style.bottom = 0;
            Label L(string name) => hud.Q<Label>(name);
            timer = L("timer");
            bombs = L("bomb-counter");
            winner = L("winner");
            resultBombs = L("result-bombs");
            resultTime = L("result-time");
            resultCoins = L("result-coins");
            resultTotal = L("result-total-coins");
            death = hud.Q("death-panel");
            // Belt and braces: hide the pause and game-over panels inline too, even if the stylesheet fails to apply.
            // The death panel is shown again on a finished round. C4 maps the pause panel.
            pausePanel = hud.Q("pause-panel");
            if (pausePanel != null)
                pausePanel.style.display = DisplayStyle.None;
            if (death != null)
                death.style.display = DisplayStyle.None;
            if (L("controls") is Label controls)
                controls.text = "A/D or arrows: move    Space: jump    Esc: connection menu";
            // The legacy subtitle assumes local restart authority. Replace that text in
            // this instantiated tree without editing the original UXML asset.
            if (death != null)
                death
                    .Query<Label>()
                    .ForEach(label =>
                    {
                        if (label.text == "Press R to restart")
                            label.text = "The host starts the next round (REPLAY).";
                    });
            menu = new VisualElement();
            menu.name = "network-menu";
            menu.style.position = Position.Absolute;
            menu.style.right = 20;
            menu.style.top = 20;
            menu.style.width = 330;
            menu.style.maxHeight = Length.Percent(92);
            menu.style.paddingLeft = 18;
            menu.style.paddingRight = 18;
            menu.style.paddingTop = 16;
            menu.style.paddingBottom = 16;
            menu.style.backgroundColor = new Color(.035f, .055f, .075f, .96f);
            menu.style.color = Color.white;
            root.Add(menu);
            var title = new Label("BOM · NETWORK PLAY");
            title.style.fontSize = 21;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            menu.Add(title);
            menu.AddToClassList("network-menu");
            if (NetworkMenuStyle != null)
                menu.styleSheets.Add(NetworkMenuStyle);
            var body = new ScrollView(ScrollViewMode.Vertical);
            body.name = "network-menu-body";
            body.style.flexShrink = 1;
            body.style.flexGrow = 0;
            menu.Add(body);
            status = new Label("Connect to a local or LAN server.");
            status.style.whiteSpace = WhiteSpace.Normal;
            status.style.marginTop = 8;
            status.style.marginBottom = 8;
            body.Add(status);
            address = new TextField("Server")
            {
                value = Client != null ? Client.Address : "127.0.0.1",
            };
            port = new TextField("Port")
            {
                value = Client != null ? Client.Port.ToString() : "47380",
            };
            token = new TextField("Host key") { isPasswordField = true };
            spectator = new Toggle("Join as spectator");
            body.Add(address);
            body.Add(port);
            body.Add(token);
            body.Add(spectator);
            connect = new Button(() =>
                Click(() =>
                {
                    if (!uint.TryParse(port.value, out uint number) || number < 1 || number > 65535)
                        throw new ArgumentException("Enter a port from 1 to 65535.");
                    Client.ConnectTo(address.value.Trim(), number, token.value, spectator.value);
                    message = "Connecting…";
                })
            )
            {
                text = "Connect",
            };
            body.Add(connect);
            disconnect = new Button(() =>
                Click(() =>
                {
                    Client.Disconnect();
                    message = "Disconnected. You can reconnect to this session.";
                })
            )
            {
                text = "Disconnect",
            };
            body.Add(disconnect);
            reconnect = new Button(() =>
                Click(() =>
                {
                    Client.Reconnect();
                    message = "Reconnecting…";
                })
            )
            {
                text = "Reconnect",
            };
            body.Add(reconnect);
            mode = new DropdownField(
                "Mode",
                new System.Collections.Generic.List<string> { "Sandbox", "Elimination" },
                0
            );
            body.Add(mode);
            setMode = new Button(() => Intent(5, (uint)mode.index)) { text = "Apply mode (host)" };
            body.Add(setMode);
            restart = new Button(() => Intent(1, 0)) { text = "Start next round" };
            body.Add(restart);
            // Darryn's game-over panel buttons: REPLAY asks the host to start the next round (same command as the menu button),
            // RETURN leaves the server and shows the connection menu. Nothing was wired to them before.
            replay = hud.Q<Button>("replay-button");
            leave = hud.Q<Button>("return-button");
            if (replay != null)
                replay.clicked += () => Intent(1, 0);
            if (leave != null)
                leave.clicked += () => Click(LeaveServer);
            pauseResume = hud.Q<Button>("resume-button");
            pauseRestart = hud.Q<Button>("restart-button");
            pauseLeave = hud.Q<Button>("leave-button");
            if (pauseResume != null)
                pauseResume.clicked += () => Click(() => SetMenuVisible(false));
            if (pauseRestart != null)
                pauseRestart.clicked += () => Intent(1, 0);
            if (pauseLeave != null)
                pauseLeave.clicked += () => Click(LeaveServer);
            mainMenu = new Button(() => Click(LeaveServer)) { text = "Main menu" };
            mainMenu.style.display = DisplayStyle.None;
            body.Add(mainMenu);
            body.Add(new Button(() => Click(() => Application.Quit())) { text = "Quit" });
            roundState = new Label();
            roundState.style.position = Position.Absolute;
            roundState.style.left = 20;
            roundState.style.top = 20;
            roundState.style.fontSize = 22;
            roundState.style.color = Color.white;
            roundState.pickingMode = PickingMode.Ignore;
            root.Add(roundState);
        }

        // The same path as the RETURN button (used by the scripted front-door run).
        public void Leave() => Click(LeaveServer);

        // RETURN and LEAVE GAME: disconnect, forget paid rounds (another server may reuse round ids), show the menu.
        void LeaveServer()
        {
            Client.Disconnect();
            BomWallet.Forget();
            if (BomFrontDoor.InSession)
            {
                // C5: back to Darryn's main menu; a host's server stops there (BomFrontDoor).
                BomFrontDoor.ReturnToMainMenu("leave");
                return;
            }
            message = "Left the server. Connect to play again.";
            SetMenuVisible(true);
        }

        void Act(Action action)
        {
            try
            {
                if (Client == null)
                    throw new InvalidOperationException("Network scene is unavailable.");
                action();
            }
            catch (Exception error)
            {
                message = error.Message;
            }
        }

        void Click(Action action)
        {
            BomGameAudio.ButtonPop();
            Act(action);
        }

        void Intent(uint op, uint modeValue) =>
            Click(() =>
            {
                if (Client.Session == null)
                    throw new InvalidOperationException("Connect first.");
                BomSession.Check(
                    BomNative.bom_client_host_command(Client.Session.Handle, op, modeValue, 0)
                );
                message = "Request sent to the server.";
            });

        static void Text(Label label, string value)
        {
            if (label != null)
                label.text = value;
        }

        static string TimeText(ulong ticks)
        {
            ulong seconds = ticks / 60;
            return (seconds / 60).ToString("00") + ":" + (seconds % 60).ToString("00");
        }

        void Update()
        {
            long traced = BomHitchTrace.On ? System.Diagnostics.Stopwatch.GetTimestamp() : 0;
            UpdateCore();
            BomHitchTrace.Section("hud_update", traced);
        }

        void UpdateCore()
        {
            if (Client == null || root == null)
                return;
            if (Keyboard.current != null && Keyboard.current.escapeKey.wasPressedThisFrame)
                SetMenuVisible(menu.resolvedStyle.display == DisplayStyle.None);
            var session = Client.Session;
            bool requested = Client.ConnectionRequested;
            if (!requested)
                menu.style.display = DisplayStyle.Flex;
            var focus = root.panel?.focusController?.focusedElement as VisualElement;
            bool focused = focus is TextField || focus?.GetFirstAncestorOfType<TextField>() != null;
            bool pointer = false;
            if (
                menu.resolvedStyle.display != DisplayStyle.None
                && Mouse.current != null
                && root.panel != null
            )
            {
                Vector2 mouse = Mouse.current.position.ReadValue();
                pointer = menu.worldBound.Contains(
                    RuntimePanelUtils.ScreenToPanel(
                        root.panel,
                        new Vector2(mouse.x, Screen.height - mouse.y)
                    )
                );
            }
            Client.InputBlocked =
                menu.resolvedStyle.display != DisplayStyle.None || focused || pointer || !requested;
            if (Client.InputBlocked && !wasBlocked && requested && session != null)
                Act(() => BomSession.Check(BomNative.bom_client_clear_intent(session.Handle)));
            wasBlocked = Client.InputBlocked;
            connect.SetEnabled(!requested && session != null);
            disconnect.SetEnabled(requested);
            reconnect.SetEnabled(session != null);
            if (session == null)
            {
                status.text = Client.ConnectionError;
                return;
            }
            var r = session.Round;
            bool has = (r.flags & 1) != 0;
            if (has && serverMode != r.mode)
            {
                serverMode = r.mode;
                mode.SetValueWithoutNotify(r.mode == 1 ? "Elimination" : "Sandbox");
            }
            restart.text = has && r.mode == 0 ? "Reset sandbox" : "Start next round";
            // The connection menu sits on top of the game-over panel and hides its RETURN button, so put it away when an
            // Elimination round enters its countdown or finishes. Esc brings it back.
            if (has && (r.round_id != menuRound || r.state != menuState))
            {
                menuRound = r.round_id;
                menuState = r.state;
                if (r.mode == 1 && (r.state == 1 || r.state == 3))
                    SetMenuVisible(false);
            }
            if (
                requested
                && has
                && (session.Sample.flags & 6) == 6
                && session.Sample.connection_generation != menuConnection
            )
            {
                menuConnection = session.Sample.connection_generation;
                SetMenuVisible(false);
            }
            // Cached per sample by BomSession: a per-frame native call would wait on the pump thread.
            bool host = (session.Stats.flags & 4) != 0;
            Text(
                hud.Q<Label>("controls"),
                host && r.mode == 0
                    ? "A/D or arrows: move    Space: jump    Click: blast    Esc: menu"
                    : "A/D or arrows: move    Space: jump    Esc: connection menu"
            );
            setMode.SetEnabled(
                requested && host && (!has || r.mode == 0 || r.state == 0 || r.state == 3)
            );
            bool canRestart = requested && has && (r.flags & 2) != 0;
            restart.SetEnabled(canRestart);
            if (replay != null)
            {
                replay.SetEnabled(canRestart);
                // The host loses restart permission for a few seconds while the server rebuilds the world after the click,
                // so only a non-host should read "waiting for host".
                replay.text = canRestart ? "REPLAY" : "STARTING…";
                // C4: REPLAY is the host's command; guests see no button.
                replay.style.display = host ? DisplayStyle.Flex : DisplayStyle.None;
            }
            pauseRestart?.SetEnabled(canRestart);
            if (pauseRestart != null)
                pauseRestart.style.display = host ? DisplayStyle.Flex : DisplayStyle.None;
            leave?.SetEnabled(requested);
            ulong hudKey =
                ((ulong)r.state << 40)
                ^ ((ulong)r.mode << 32)
                ^ r.flags
                ^ (canRestart ? 1UL << 48 : 0)
                ^ (host ? 1UL << 49 : 0)
                ^ (requested ? 1UL << 50 : 0);
            if (hudKey != lastHudKey)
            {
                lastHudKey = hudKey;
                Debug.Log(
                    "BOM UNITY HUD round="
                        + r.round_id
                        + " state="
                        + r.state
                        + " mode="
                        + r.mode
                        + " flags="
                        + r.flags
                        + " host="
                        + host
                        + " requested="
                        + requested
                        + " can_restart="
                        + canRestart
                );
            }
            string error = !string.IsNullOrEmpty(Client.ConnectionError)
                ? Client.ConnectionError
                : session.Error;
            status.text =
                !string.IsNullOrEmpty(error) ? error
                : !requested ? message
                : !has ? "Connecting and loading the world…"
                : ((r.flags & 4) != 0 ? "Spectating" : "Connected")
                    + (host ? " · Host" : "")
                    + "\n"
                    + message;
            hud.style.display = has ? DisplayStyle.Flex : DisplayStyle.None;
            if (!has)
            {
                roundState.text = "";
                return;
            }
            if (displayedRound != r.round_id || displayedTick != r.tick)
            {
                displayedRound = r.round_id;
                displayedTick = r.tick;
                receivedAt = BomSession.Now;
            }
            double estimatedTick =
                r.tick + Math.Min(60, Math.Max(0, BomSession.Now - receivedAt) * 60);
            // P2: while the server rebuilds the level (a mode switch or REPLAY) and while everyone loads it, say so instead
            // of "SANDBOX" or "Waiting for two ready players" over the old level. Connection flags: 1 connected, 2 ready.
            int connected = 0,
                ready = 0;
            for (int i = 0; i < r.connection_count; i++)
            {
                uint f = session.RoundConnections[i].flags;
                if ((f & 1) != 0)
                    connected++;
                if ((f & 3) == 3)
                    ready++;
            }
            if (r.mode == 1)
                sawElimination = true;
            string state =
                r.mode == 0 && host && Client.EliminationRequested && !sawElimination ? "Preparing the round…"
                : r.mode == 0 ? "SANDBOX"
                : r.state == 0 && connected >= 2 ? "Loading the level… " + ready + "/" + connected + " ready"
                : r.state == 0 ? "Waiting for another player"
                : r.state == 3 && host && !canRestart ? "Preparing the next round…"
                : r.state == 1
                    ? "Starting in "
                        + Math.Max(0, Math.Ceiling((r.start_tick - estimatedTick) / 60))
                            .ToString("0")
                : r.state == 2 ? "Round " + r.round_id + ((r.flags & 4) != 0 ? " · Spectating" : "")
                : r.draw != 0 ? "DRAW"
                : "Round finished";
            roundState.text = state;
            BomRoundPlayer player = default;
            for (int i = 0; i < r.player_count; i++)
                if (session.RoundPlayers[i].session_id == r.local_session_id)
                    player = session.RoundPlayers[i];
            BomRoundConnection profile = default;
            for (int i = 0; i < r.connection_count; i++)
                if (session.RoundConnections[i].session_id == r.local_session_id)
                    profile = session.RoundConnections[i];
            Text(timer, TimeText(player.alive_ticks));
            Text(bombs, "Bombs faced: " + player.bombs_faced);
            if (death != null)
                death.style.display =
                    r.mode == 1 && r.state == 3 ? DisplayStyle.Flex : DisplayStyle.None;
            hud.Query<VisualElement>(className: "result-item")
                .ForEach(element =>
                    element.EnableInClassList("shown", r.mode == 1 && r.state == 3)
                );
            Text(
                winner,
                r.draw != 0 ? "DRAW"
                    : r.winner == r.local_session_id ? "YOU WIN"
                    : "ROUND OVER"
            );
            // D5: only a seated round player is paid (flag 4 is also set for a dead player, so it is not tested). The round award (xp_gained, which includes item coins) is paid into the local shop wallet once per round id.
            if (
                r.mode == 1
                && r.state == 3
                && player.session_id == r.local_session_id
                && r.local_session_id != 0
            )
                BomWallet.TryPay(r.round_id, player.xp_gained);
            Text(resultCoins, "Coins Collected: " + player.xp_gained);
            Text(resultBombs, "Bombs Dodged: " + player.bombs_faced);
            Text(resultTime, "Time Survived: " + TimeText(player.alive_ticks));
            Text(resultTotal, "Total Coins: " + BomWallet.Total);
            foreach (var result in session.RequestResults)
                if (result.kind != 1)
                    message =
                        result.status == 1
                            ? "Server accepted the request."
                            : "Server rejected the request.";
        }

        void OnSceneLoaded(Scene scene, LoadSceneMode mode) =>
            DisableDuplicateArenaHud(GetComponent<UIDocument>());

        void OnDisable()
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;
            if (Client != null)
                Client.InputBlocked = false;
            root?.Clear();
        }
    }
}
