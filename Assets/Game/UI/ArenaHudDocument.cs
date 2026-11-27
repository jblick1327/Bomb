using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UIElements;
using UnityEngine.SceneManagement;

[RequireComponent(typeof(UIDocument))]
[AddComponentMenu("Arena/UI Toolkit HUD")]
public sealed class ArenaHudDocument : MonoBehaviour
{
    // The stats along each result card, left to right.
    private enum Stat { Bombs, Slow, Speed, Shield, Coins }
    private static readonly int StatCount = Enum.GetValues(typeof(Stat)).Length;
    private static readonly int[] TimelineSteps = { 5, 10, 15, 30, 60, 120, 300, 600 };
    private const int MaxTimelineTicks = 6;

    [SerializeField] private ArenaSession session;
    [SerializeField] private StyleSheet styleSheet;

    private UIDocument document;
    private VisualElement root, deathPanel, pausePanel, resultCards, resultTimeline;
    private Label winner, pauseCorner, timer, bombCounter, roundMessage, walletText, waitingText, pauseHint;
    private VisualElement bombCounterGroup;
    private VisualElement controlsPanel, controlsTable;
    private Button controlsButton, controlsBackButton;
    private string shownPauseCorner;
    private Button replayButton, returnButton, resumeButton, restartButton, leaveButton;
    private IVisualElementScheduledItem timerUpdate;
    private VisualElement menuCursor;
    private VisualElement countdown;
    // The 3-2-1 picture, and a black copy of it behind as a drop shadow.
    private VisualElement countdownNumber, countdownShadow;
    private int shownCountdown = -1;
    // GO! takes this slot in place of a number, and shows for GoSeconds.
    private const int GoPicture = 4;
    private const float GoSeconds = .9f;
    private bool countdownWasRunning;
    private float goShownAt = -1f;
    // Buttons Player 1 can press with the menu cursor, and what each one does.
    private readonly Dictionary<Button, Action> cursorButtons = new Dictionary<Button, Action>();

    // Pictures for the result cards, rendered from the game's own models.
    private readonly RenderTexture[] statIcons = new RenderTexture[5];
    private readonly Dictionary<Color, RenderTexture> portraits = new Dictionary<Color, RenderTexture>();
    private bool iconsRendered;

    private void Awake()
    {
        document = GetComponent<UIDocument>();
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        root = document.rootVisualElement.Q<VisualElement>("hud-root");
        if (styleSheet != null) root.styleSheets.Add(styleSheet);
        // The main menu's chalk font, inherited by every label and button.
        Font font = BomUiSkin.HudFont;
        if (font != null) root.style.unityFontDefinition = FontDefinition.FromFont(font);
        countdown = root.Q<VisualElement>("countdown");
        if (countdown != null)
        {
            countdownShadow = new VisualElement { pickingMode = PickingMode.Ignore };
            countdownShadow.AddToClassList("countdown-shadow");
            countdown.Add(countdownShadow);
            countdownNumber = new VisualElement { pickingMode = PickingMode.Ignore };
            countdownNumber.AddToClassList("countdown-number");
            countdown.Add(countdownNumber);
        }
        deathPanel = root.Q<VisualElement>("death-panel");
        winner = root.Q<Label>("winner");
        pauseCorner = root.Q<Label>("pause-corner");
        timer = root.Q<Label>("timer");
        bombCounter = root.Q<Label>("bomb-counter");
        if (bombCounter != null)
        {
            // The chalk bomb from the menu art, over the counter's left end.
            // Both go in a wrapper: a Label with a child stops sizing to its
            // text, so the bomb can't be the label's own child.
            bombCounterGroup = new VisualElement { name = "bomb-counter-group", pickingMode = PickingMode.Ignore };
            bombCounterGroup.AddToClassList("bomb-counter-group");
            VisualElement parent = bombCounter.parent;
            parent.Insert(parent.IndexOf(bombCounter), bombCounterGroup);
            bombCounterGroup.Add(bombCounter);
            var bombIcon = new VisualElement { name = "bomb-icon", pickingMode = PickingMode.Ignore };
            bombIcon.AddToClassList("bomb-icon");
            bombCounterGroup.Add(bombIcon);
        }
        roundMessage = root.Q<Label>("round-message");
        resultCards = root.Q<VisualElement>("result-cards");
        resultTimeline = root.Q<VisualElement>("result-timeline");
        walletText = root.Q<Label>("result-wallet");
        waitingText = root.Q<Label>("result-waiting");
        replayButton = root.Q<Button>("replay-button");
        returnButton = root.Q<Button>("return-button");
        pausePanel = root.Q<VisualElement>("pause-panel");
        pauseHint = root.Q<Label>("pause-hint");
        resumeButton = root.Q<Button>("resume-button");
        restartButton = root.Q<Button>("restart-button");
        leaveButton = root.Q<Button>("leave-button");
        controlsButton = root.Q<Button>("controls-button");
        controlsPanel = root.Q<VisualElement>("controls-panel");
        controlsTable = root.Q<VisualElement>("controls-table");
        controlsBackButton = root.Q<Button>("controls-back-button");
        BuildControlsTable();
        AddCursorButton(replayButton, Replay);
        AddCursorButton(returnButton, Return);
        AddCursorButton(resumeButton, Resume);
        AddCursorButton(restartButton, Replay);
        AddCursorButton(leaveButton, Leave);
        AddCursorButton(controlsButton, OpenControls);
        AddCursorButton(controlsBackButton, CloseControls);
        menuCursor = CreateMenuCursor();
        root.Add(menuCursor);
        SetUpOnlineButtons();
    }

    // A dictionary can't hold a null key, so skip buttons missing from the layout.
    private void AddCursorButton(Button button, Action action)
    {
        if (button != null) cursorButtons[button] = action;
    }

    // Online, only the host restarts. The host's RETURN takes everyone back to
    // the lobby; anyone else leaves the game.
    private void SetUpOnlineButtons()
    {
        bool online = OnlineMatch.IsRunning;
        bool canRestart = !online || OnlineMatch.IsHost;
        if (replayButton != null) replayButton.style.display = canRestart ? DisplayStyle.Flex : DisplayStyle.None;
        if (waitingText != null) waitingText.style.display = canRestart ? DisplayStyle.None : DisplayStyle.Flex;
        if (restartButton != null) restartButton.style.display = canRestart ? DisplayStyle.Flex : DisplayStyle.None;
        if (returnButton != null) returnButton.text = !online ? "RETURN" : OnlineMatch.IsHost ? "LOBBY" : "LEAVE";
        if (pauseHint != null && online) pauseHint.text = "The game keeps going while paused online.";
    }

    // Player 1's "P1" ring, drawn inside the HUD so it sits above the panels.
    private static VisualElement CreateMenuCursor()
    {
        var ring = new VisualElement { name = "menu-cursor", pickingMode = PickingMode.Ignore };
        ring.AddToClassList("menu-cursor");
        Color color = MatchMenuUI.GetPlayerCursorColor(0);
        ring.style.borderTopColor = color;
        ring.style.borderBottomColor = color;
        ring.style.borderLeftColor = color;
        ring.style.borderRightColor = color;
        var label = new Label("P1") { pickingMode = PickingMode.Ignore };
        label.AddToClassList("menu-cursor-label");
        ring.Add(label);
        return ring;
    }

    private void Update()
    {
        UpdateCountdown();
        UpdateControlsBack();
        // Runs while paused too: Update ignores the frozen game time.
        bool menuOpen = MenuCursor.Active && session != null && session.IsMenuShowing;
        MenuCursor.DrawnByScreen = true;
        menuCursor.style.display = menuOpen ? DisplayStyle.Flex : DisplayStyle.None;
        if (!menuOpen || root.panel == null) return;

        Vector2 point = ToPanel(MenuCursor.Position);
        menuCursor.style.left = point.x;
        menuCursor.style.top = point.y;
        foreach (Button button in cursorButtons.Keys)
            button.EnableInClassList("cursor-hover", IsShown(button) && button.worldBound.Contains(point));
    }

    // Shows the 3, 2, 1 pictures before the round, then GO! as it starts.
    // Each one pops in large, settles, then fades just before the next.
    private void UpdateCountdown()
    {
        if (countdown == null) return;
        bool counting = session != null && session.State == ArenaRoundState.Countdown;
        int number = counting ? Mathf.Clamp(Mathf.CeilToInt(session.CountdownRemaining), 1, 3) : 0;
        float progress = counting ? Mathf.Clamp01(number - session.CountdownRemaining) : 0f;

        // The countdown has just run out into a live round: show GO! briefly.
        if (counting) countdownWasRunning = true;
        else if (countdownWasRunning)
        {
            countdownWasRunning = false;
            goShownAt = session != null && session.State == ArenaRoundState.Playing ? Time.unscaledTime : -1f;
        }
        if (!counting && goShownAt >= 0f)
        {
            float goTime = Time.unscaledTime - goShownAt;
            if (goTime < GoSeconds && session != null && session.State == ArenaRoundState.Playing)
            {
                number = GoPicture;
                progress = goTime / GoSeconds;
            }
            else goShownAt = -1f;
        }

        if (number != shownCountdown)
        {
            shownCountdown = number;
            Texture2D picture = number == GoPicture ? BomUiSkin.CountdownGo : BomUiSkin.CountdownNumber(number);
            if (picture != null)
            {
                countdownNumber.style.backgroundImage = new StyleBackground(picture);
                countdownShadow.style.backgroundImage = new StyleBackground(picture);
                // GO! is wide, so its box widens to keep it as tall as the numbers.
                countdown.EnableInClassList("countdown-go", number == GoPicture);
                countdown.style.display = DisplayStyle.Flex;
            }
            else
            {
                countdown.style.display = DisplayStyle.None;
            }
        }
        if (number == 0) return;

        float pop = 1f - Mathf.Pow(1f - Mathf.Clamp01(progress / .3f), 3f);
        float size = Mathf.Lerp(1.8f, 1f, pop);
        countdown.style.scale = new Scale(new Vector3(size, size, 1f));
        countdown.style.opacity = progress < .8f ? 1f : Mathf.Lerp(1f, .15f, (progress - .8f) / .2f);
    }

    // Player 1 pressed A on a controller: press the button under the cursor.
    // Mouse clicks reach the buttons directly, so they don't come through here.
    private void OnCursorSubmit(Vector2 screenPosition)
    {
        if (root.panel == null || session == null || !session.IsMenuShowing) return;
        Vector2 point = ToPanel(screenPosition);
        foreach (KeyValuePair<Button, Action> entry in cursorButtons)
        {
            if (!IsShown(entry.Key) || !entry.Key.worldBound.Contains(point)) continue;
            entry.Value();
            return;
        }
    }

    // Screen pixels (origin bottom-left) to panel coordinates (origin top-left).
    private Vector2 ToPanel(Vector2 screenPosition) =>
        RuntimePanelUtils.ScreenToPanel(root.panel, new Vector2(screenPosition.x, Screen.height - screenPosition.y));

    private static bool IsShown(VisualElement element)
    {
        for (VisualElement e = element; e != null; e = e.parent)
            if (e.resolvedStyle.display == DisplayStyle.None) return false;
        return true;
    }

    private void OnEnable()
    {
        if (session != null) session.StateChanged += Refresh;
        if (session != null) session.PausedChanged += ShowPause;
        if (replayButton != null) replayButton.clicked += Replay;
        if (returnButton != null) returnButton.clicked += Return;
        if (resumeButton != null) resumeButton.clicked += Resume;
        if (restartButton != null) restartButton.clicked += Replay;
        if (leaveButton != null) leaveButton.clicked += Leave;
        if (controlsButton != null) controlsButton.clicked += OpenControls;
        if (controlsBackButton != null) controlsBackButton.clicked += CloseControls;
        MenuCursor.GamepadSubmit += OnCursorSubmit;
        timerUpdate = root?.schedule.Execute(UpdateLiveStats).Every(100);
        if (session != null) Refresh(session.State);
    }

    private void OnDisable()
    {
        if (session != null) session.StateChanged -= Refresh;
        if (session != null) session.PausedChanged -= ShowPause;
        if (replayButton != null) replayButton.clicked -= Replay;
        if (returnButton != null) returnButton.clicked -= Return;
        if (resumeButton != null) resumeButton.clicked -= Resume;
        if (restartButton != null) restartButton.clicked -= Replay;
        if (leaveButton != null) leaveButton.clicked -= Leave;
        if (controlsButton != null) controlsButton.clicked -= OpenControls;
        if (controlsBackButton != null) controlsBackButton.clicked -= CloseControls;
        MenuCursor.GamepadSubmit -= OnCursorSubmit;
        MenuCursor.DrawnByScreen = false;
        timerUpdate?.Pause();
    }

    private void OnDestroy()
    {
        foreach (RenderTexture icon in statIcons) ModelSnapshot.Release(icon);
        foreach (RenderTexture portrait in portraits.Values) ModelSnapshot.Release(portrait);
        portraits.Clear();
    }

    private int shownSeconds = -1;
    private int shownBombs = -1;

    // Only rebuild the text when the number changes, to avoid string garbage.
    private void UpdateLiveStats()
    {
        if (session == null) return;
        int seconds = Mathf.FloorToInt(session.TimeSurvived);
        if (timer != null && seconds != shownSeconds)
        {
            shownSeconds = seconds;
            timer.text = FormatTime(seconds);
        }
        int bombs = session.BombsDodged;
        if (bombCounter != null && bombs != shownBombs)
        {
            shownBombs = bombs;
            bombCounter.text = $"Bombs dropped: {bombs}";
        }
        UpdatePauseCorner();
    }

    private void Refresh(ArenaRoundState state)
    {
        bool dead = state == ArenaRoundState.Dead;
        bool waiting = state == ArenaRoundState.Waiting;
        if (winner != null) winner.text = session != null && !string.IsNullOrEmpty(session.WinnerMessage) ? session.WinnerMessage : "Game Over";
        if (pauseCorner != null) pauseCorner.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        UpdatePauseCorner();
        if (roundMessage != null) roundMessage.style.display = waiting ? DisplayStyle.Flex : DisplayStyle.None;
        if (deathPanel != null) deathPanel.style.display = dead ? DisplayStyle.Flex : DisplayStyle.None;
        if (timer != null) timer.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (bombCounterGroup != null) bombCounterGroup.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (pausePanel != null && dead) pausePanel.style.display = DisplayStyle.None;
        if (controlsPanel != null && dead) controlsPanel.style.display = DisplayStyle.None;
        if (dead) ShowResults();
        else UpdateLiveStats();
    }

    // ---------- Game Over panel ----------

    private void ShowResults()
    {
        if (session == null || resultCards == null) return;
        RenderIcons();
        resultCards.Clear();
        resultTimeline?.Clear();

        IReadOnlyList<ArenaPlayerController> players = session.Players;
        float roundLength = Mathf.Max(session.TimeSurvived, 1f);
        float timelineEnd = TimelineEnd(roundLength, out int step);
        var cards = new List<(VisualElement card, VisualElement fill, float fraction)>();
        var sums = new int[StatCount];

        for (int i = 0; i < players.Count; i++)
        {
            ArenaPlayerController player = players[i];
            if (player == null) continue;
            int[] values = StatsFor(player);
            for (int s = 0; s < StatCount; s++) sums[s] += values[s];

            if (cards.Count > 0) resultCards.Add(CreateDottedLine());
            string name = "Player " + player.PlayerNumber;
            if (OnlineMatch.IsRunning && i == OnlineMatch.LocalSlot) name += " (you)";
            if (player.HasLeftGame) name += " (left)";
            VisualElement card = CreateCard(name, Portrait(player.CharacterColor), values, player.RoundTotal,
                player.CharacterColor, out VisualElement fill);
            if (player.gameObject.activeSelf && players.Count > 1) card.AddToClassList("winner");
            resultCards.Add(card);
            cards.Add((card, fill, player.TimeSurvived / timelineEnd));
        }

        // The last card adds everyone up.
        if (cards.Count > 1)
        {
            resultCards.Add(CreateDottedLine());
            VisualElement summary = CreateCard("ALL PLAYERS", null, sums, session.TotalCoinsEarned, Color.clear, out _);
            summary.AddToClassList("summary");
            resultCards.Add(summary);
            cards.Add((summary, null, 0f));
        }

        BuildTimeline(timelineEnd, step);
        if (walletText != null)
        {
            walletText.text = OnlineMatch.IsRunning
                ? $"+{session.WalletCoinsAwarded} coins added to your wallet"
                : $"+{session.WalletCoinsAwarded} coins added to the wallet";
        }

        // Slide the cards in one after another, then grow each time bar.
        for (int i = 0; i < cards.Count; i++)
        {
            var entry = cards[i];
            root.schedule.Execute(() =>
            {
                entry.card.AddToClassList("shown");
                if (entry.fill != null) entry.fill.style.width = Length.Percent(Mathf.Clamp01(entry.fraction) * 100f);
            }).StartingIn(120 + i * 140);
        }
    }

    private static int[] StatsFor(ArenaPlayerController player)
    {
        var values = new int[StatCount];
        values[(int)Stat.Bombs] = player.BombsDodged;
        values[(int)Stat.Slow] = player.ItemCount(CollectibleItemType.Slow);
        values[(int)Stat.Speed] = player.ItemCount(CollectibleItemType.SpeedBoost);
        values[(int)Stat.Shield] = player.ItemCount(CollectibleItemType.Invincibility);
        values[(int)Stat.Coins] = player.Coins;
        return values;
    }

    // One horizontal card: name above the portrait at the left, the stats
    // across the middle, and the total at the right. The tinted bar behind it
    // shows how long the player lasted, measured against the time line below.
    private VisualElement CreateCard(string name, Texture portrait, int[] values, int total, Color tint, out VisualElement fill)
    {
        var card = new VisualElement();
        card.AddToClassList("result-card");

        fill = new VisualElement { pickingMode = PickingMode.Ignore };
        fill.AddToClassList("result-fill");
        fill.style.backgroundColor = new Color(tint.r, tint.g, tint.b, .32f);
        card.Add(fill);

        var who = new VisualElement();
        who.AddToClassList("result-who");
        var nameLabel = new Label(name);
        nameLabel.AddToClassList("result-name");
        who.Add(nameLabel);
        if (portrait != null)
        {
            var image = new Image { image = portrait, scaleMode = ScaleMode.ScaleToFit };
            image.AddToClassList("result-portrait");
            who.Add(image);
        }
        card.Add(who);

        var stats = new VisualElement();
        stats.AddToClassList("result-stats");
        for (int s = 0; s < StatCount; s++)
        {
            var stat = new VisualElement();
            stat.AddToClassList("result-stat");
            stat.Add(CreateIcon(statIcons[s]));
            var value = new Label(values[s].ToString());
            value.AddToClassList("result-value");
            stat.Add(value);
            stats.Add(stat);
        }
        card.Add(stats);

        var totalBox = new VisualElement();
        totalBox.AddToClassList("result-total");
        var totalLabel = new Label("= " + total);
        totalLabel.AddToClassList("result-total-value");
        totalBox.Add(totalLabel);
        totalBox.Add(CreateIcon(statIcons[(int)Stat.Coins]));
        card.Add(totalBox);
        return card;
    }

    private static VisualElement CreateIcon(Texture texture)
    {
        var icon = new Image { image = texture, scaleMode = ScaleMode.ScaleToFit };
        icon.AddToClassList("result-icon");
        return icon;
    }

    private static VisualElement CreateDottedLine()
    {
        var line = new VisualElement();
        line.AddToClassList("result-dots");
        for (int i = 0; i < 70; i++)
        {
            var dot = new VisualElement();
            dot.AddToClassList("result-dot");
            line.Add(dot);
        }
        return line;
    }

    // Picks a tick spacing so the line has at most six ticks, and returns
    // the time at the right end of the line.
    private static float TimelineEnd(float roundLength, out int step)
    {
        step = TimelineSteps[TimelineSteps.Length - 1];
        foreach (int candidate in TimelineSteps)
        {
            if (roundLength / candidate <= MaxTimelineTicks)
            {
                step = candidate;
                break;
            }
        }
        return Mathf.Max(step, Mathf.Ceil(roundLength / step) * step);
    }

    private void BuildTimeline(float end, int step)
    {
        if (resultTimeline == null) return;
        var caption = new Label("SURVIVED TIME");
        caption.AddToClassList("timeline-caption");
        resultTimeline.Add(caption);

        var track = new VisualElement();
        track.AddToClassList("timeline-track");
        var line = new VisualElement();
        line.AddToClassList("timeline-line");
        track.Add(line);
        for (int seconds = 0; seconds <= end + 0.01f; seconds += step)
        {
            float percent = seconds / end * 100f;
            var tick = new VisualElement();
            tick.AddToClassList("timeline-tick");
            tick.style.left = Length.Percent(percent);
            track.Add(tick);
            var label = new Label(FormatClock(seconds));
            label.AddToClassList("timeline-label");
            label.style.left = Length.Percent(percent);
            track.Add(label);
        }
        resultTimeline.Add(track);
    }

    // Renders the stat icons from the bomb and item models the first time
    // results are shown.
    private void RenderIcons()
    {
        if (iconsRendered) return;
        iconsRendered = true;
        BombDropper dropper = FindFirstObjectByType<BombDropper>();
        if (dropper == null) return;
        statIcons[(int)Stat.Bombs] = ModelSnapshot.Render(dropper.BombPrefab, 96, null, ModelSnapshot.Framing.Whole);
        statIcons[(int)Stat.Slow] = ModelSnapshot.Render(dropper.GetItemVisualPrefab(CollectibleItemType.Slow), 96, null, ModelSnapshot.Framing.Whole);
        statIcons[(int)Stat.Speed] = ModelSnapshot.Render(dropper.GetItemVisualPrefab(CollectibleItemType.SpeedBoost), 96, null, ModelSnapshot.Framing.Whole);
        statIcons[(int)Stat.Shield] = ModelSnapshot.Render(dropper.GetItemVisualPrefab(CollectibleItemType.Invincibility), 96, null, ModelSnapshot.Framing.Whole);
        statIcons[(int)Stat.Coins] = ModelSnapshot.Render(dropper.GetItemVisualPrefab(CollectibleItemType.SilverCoin), 96, null, ModelSnapshot.Framing.Whole);
    }

    private RenderTexture Portrait(Color color)
    {
        if (portraits.TryGetValue(color, out RenderTexture existing) && existing != null) return existing;
        GameObject prefab = Resources.Load<GameObject>("PlayerPreview");
        RenderTexture texture = ModelSnapshot.Render(prefab, 128, color, ModelSnapshot.Framing.Head);
        portraits[color] = texture;
        return texture;
    }

    // ---------- Buttons ----------

    private void ShowPause(bool paused)
    {
        // Pausing opens the pause menu; unpausing closes it and Controls too.
        if (controlsPanel != null) controlsPanel.style.display = DisplayStyle.None;
        if (pausePanel == null) return;
        pausePanel.style.display = paused ? DisplayStyle.Flex : DisplayStyle.None;
    }

    // Pause menu CONTROLS: swaps the pause menu for the controls list.
    private void OpenControls()
    {
        if (controlsPanel == null) return;
        GameAudio.PlayButtonPopSound();
        if (pausePanel != null) pausePanel.style.display = DisplayStyle.None;
        controlsPanel.style.display = DisplayStyle.Flex;
    }

    // Controls BACK (or Esc / B): back to the pause menu.
    private void CloseControls()
    {
        if (controlsPanel == null || controlsPanel.resolvedStyle.display == DisplayStyle.None) return;
        GameAudio.PlayButtonPopSound();
        controlsPanel.style.display = DisplayStyle.None;
        if (pausePanel != null && session != null && session.IsPaused) pausePanel.style.display = DisplayStyle.Flex;
    }

    private void UpdateControlsBack()
    {
        if (controlsPanel == null || controlsPanel.resolvedStyle.display == DisplayStyle.None) return;
        Keyboard keyboard = Keyboard.current;
        Gamepad gamepad = MenuCursor.PlayerOneGamepad();
        if ((keyboard != null && keyboard.escapeKey.wasPressedThisFrame)
            || (gamepad != null && gamepad.buttonEast.wasPressedThisFrame))
            CloseControls();
    }

    // ---------- Controls ----------

    // Player 1 pauses with P on the keyboard (when they have it) and Start on
    // their controller (when they have one). Online, the keyboard is yours.
    private static bool PlayerOneHasKeyboard => OnlineMatch.IsRunning || MatchMenuUI.IsKeyboardEnabledForPlayer(1);

    // The lower-right "PAUSE  P / START" chip, naming only the keys that work.
    private void UpdatePauseCorner()
    {
        if (pauseCorner == null) return;
        bool keyboard = PlayerOneHasKeyboard;
        bool controller = MenuCursor.PlayerOneGamepad() != null || (OnlineMatch.IsRunning && Gamepad.current != null);
        string keys = keyboard && controller ? "P / START" : controller ? "START" : "P";
        string text = "PAUSE  " + keys;
        if (text == shownPauseCorner) return;
        shownPauseCorner = text;
        pauseCorner.text = text;
    }

    // Fills the Controls panel for how this match is being played: the keys
    // each player has, and the controller buttons.
    private void BuildControlsTable()
    {
        if (controlsTable == null) return;
        controlsTable.Clear();
        bool online = OnlineMatch.IsRunning;
        MatchInputMode mode = MatchMenuUI.CurrentInputMode;
        bool keyboardUsed = online || mode != MatchInputMode.AllControllers;
        bool sharedKeyboard = !online && mode == MatchInputMode.SharedKeyboard;

        AddControlsRow("", keyboardUsed ? "KEYBOARD" : null, "CONTROLLER", true);
        AddControlsRow("MOVE", !keyboardUsed ? null : sharedKeyboard ? "P1  A / D\nP2  LEFT / RIGHT" : "A / D", "LEFT STICK", false);
        AddControlsRow("JUMP", !keyboardUsed ? null : sharedKeyboard ? "P1  W / SPACE\nP2  UP" : "W / SPACE", "A  /  CROSS", false);
        AddControlsRow("PAUSE", keyboardUsed ? "P" : null, "START / OPTIONS", false);
        AddControlsRow("MENUS", keyboardUsed ? "MOUSE" : null, "LEFT STICK + A", false);

        var note = new Label(online ? "Pausing online doesn't stop the game for everyone else."
            : "Only Player 1 can pause and use the menus.");
        note.AddToClassList("controls-note");
        controlsTable.Add(note);
    }

    // One line of the controls list. keyboard null leaves that column out
    // (controller-only matches).
    private void AddControlsRow(string action, string keyboard, string controller, bool heading)
    {
        var row = new VisualElement();
        row.AddToClassList("controls-row");
        if (heading) row.AddToClassList("controls-heading");
        row.Add(ControlsCell(action, "controls-action"));
        if (keyboard != null) row.Add(ControlsCell(keyboard, "controls-key"));
        row.Add(ControlsCell(controller, "controls-key"));
        controlsTable.Add(row);
    }

    private static Label ControlsCell(string text, string className)
    {
        var cell = new Label(text) { pickingMode = PickingMode.Ignore };
        cell.AddToClassList(className);
        return cell;
    }

    private void Resume()
    {
        GameAudio.PlayButtonPopSound();
        if (session != null) session.SetPaused(false);
    }

    private void Replay()
    {
        GameAudio.PlayButtonPopSound();
        if (OnlineMatch.IsRunning)
        {
            if (session != null) session.SetPaused(false);
            OnlineMatch.HostRestartRound();
            return;
        }
        if (session != null)
            session.RestartRound();
    }

    // Results panel RETURN (LOBBY or LEAVE online).
    private void Return()
    {
        GameAudio.PlayButtonPopSound();
        if (OnlineMatch.IsRunning) OnlineMatch.ReturnFromResults();
        else if (session != null) session.LeaveMatch();
        else SceneManager.LoadScene("MainMenuScene");
    }

    // Pause menu LEAVE GAME.
    private void Leave()
    {
        GameAudio.PlayButtonPopSound();
        if (session != null) session.LeaveMatch();
        else SceneManager.LoadScene("MainMenuScene");
    }

    private static string FormatTime(float seconds)
    {
        int total = Mathf.FloorToInt(seconds);
        return $"{total / 60:00}:{total % 60:00}";
    }

    private static string FormatClock(int seconds) => $"{seconds / 60}:{seconds % 60:00}";
}
