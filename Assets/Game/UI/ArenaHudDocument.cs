using System;
using System.Collections.Generic;
using UnityEngine;
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
    private Label winner, controls, timer, bombCounter, roundMessage, walletText, waitingText, pauseHint;
    private Button replayButton, returnButton, resumeButton, restartButton, leaveButton;
    private IVisualElementScheduledItem timerUpdate;
    private VisualElement menuCursor;
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
        deathPanel = root.Q<VisualElement>("death-panel");
        winner = root.Q<Label>("winner");
        controls = root.Q<Label>("controls");
        timer = root.Q<Label>("timer");
        bombCounter = root.Q<Label>("bomb-counter");
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
        AddCursorButton(replayButton, Replay);
        AddCursorButton(returnButton, Return);
        AddCursorButton(resumeButton, Resume);
        AddCursorButton(restartButton, Replay);
        AddCursorButton(leaveButton, Leave);
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
    }

    private void Refresh(ArenaRoundState state)
    {
        bool dead = state == ArenaRoundState.Dead;
        bool waiting = state == ArenaRoundState.Waiting;
        if (winner != null) winner.text = session != null && !string.IsNullOrEmpty(session.WinnerMessage) ? session.WinnerMessage : "Game Over";
        if (controls != null)
        {
            controls.text = OnlineMatch.IsRunning ? "A/D or arrows: move    W/Space: jump    P: pause"
                : "P1: A/D + W/Space    P2: arrows + Up    P: pause";
            controls.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        }
        if (roundMessage != null) roundMessage.style.display = waiting ? DisplayStyle.Flex : DisplayStyle.None;
        if (deathPanel != null) deathPanel.style.display = dead ? DisplayStyle.Flex : DisplayStyle.None;
        if (timer != null) timer.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (bombCounter != null) bombCounter.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (pausePanel != null && dead) pausePanel.style.display = DisplayStyle.None;
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
        if (pausePanel == null) return;
        pausePanel.style.display = paused ? DisplayStyle.Flex : DisplayStyle.None;
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
