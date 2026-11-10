using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;
using UnityEngine.SceneManagement;

[RequireComponent(typeof(UIDocument))]
[AddComponentMenu("Arena/UI Toolkit HUD")]
public sealed class ArenaHudDocument : MonoBehaviour
{
    [SerializeField] private ArenaSession session;
    [SerializeField] private StyleSheet styleSheet;

    private UIDocument document;
    private VisualElement root, deathPanel, pausePanel;
    private Label gameHeader, winner, controls, timer, bombCounter;
    private Label coinsResult, bombsResult, timeResult, totalCoinsResult;
    private Button replayButton, returnButton, resumeButton, restartButton, leaveButton;
    private IVisualElementScheduledItem timerUpdate;
    private VisualElement menuCursor;
    // Buttons Player 1 can press with the menu cursor, and what each one does.
    private readonly Dictionary<Button, Action> cursorButtons = new Dictionary<Button, Action>();

    private void Awake()
    {
        document = GetComponent<UIDocument>();
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        root = document.rootVisualElement.Q<VisualElement>("hud-root");
        if (styleSheet != null) root.styleSheets.Add(styleSheet);
        deathPanel = root.Q<VisualElement>("death-panel");
        gameHeader = root.Q<Label>("game-header");
        winner = root.Q<Label>("winner");
        controls = root.Q<Label>("controls");
        timer = root.Q<Label>("timer");
        bombCounter = root.Q<Label>("bomb-counter");
        coinsResult = root.Q<Label>("result-coins");
        bombsResult = root.Q<Label>("result-bombs");
        timeResult = root.Q<Label>("result-time");
        totalCoinsResult = root.Q<Label>("result-total-coins");
        replayButton = root.Q<Button>("replay-button");
        returnButton = root.Q<Button>("return-button");
        pausePanel = root.Q<VisualElement>("pause-panel");
        resumeButton = root.Q<Button>("resume-button");
        restartButton = root.Q<Button>("restart-button");
        leaveButton = root.Q<Button>("leave-button");
        cursorButtons[replayButton] = Replay;
        cursorButtons[returnButton] = Return;
        cursorButtons[resumeButton] = Resume;
        cursorButtons[restartButton] = Replay;
        cursorButtons[leaveButton] = Return;
        cursorButtons.Remove(null);
        menuCursor = CreateMenuCursor();
        root.Add(menuCursor);
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
        bool menuOpen = MenuCursor.Active && session != null && (session.IsPaused || !session.IsPlaying);
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
        if (root.panel == null || session == null || (session.IsPlaying && !session.IsPaused)) return;
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
        if (leaveButton != null) leaveButton.clicked += Return;
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
        if (leaveButton != null) leaveButton.clicked -= Return;
        MenuCursor.GamepadSubmit -= OnCursorSubmit;
        MenuCursor.DrawnByScreen = false;
        timerUpdate?.Pause();
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
        if (winner != null) winner.text = session != null ? session.WinnerMessage : "Game Over";
        if (controls != null) controls.text = dead ? "R: restart" : "P1: A/D + W/Space    P2: arrows + Up    P: pause";
        if (controls != null) controls.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (deathPanel != null) deathPanel.style.display = dead ? DisplayStyle.Flex : DisplayStyle.None;
        if (timer != null) timer.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (bombCounter != null) bombCounter.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (pausePanel != null && dead) pausePanel.style.display = DisplayStyle.None;
        if (dead) ShowResults();
        else
        {
            foreach (Label item in new[] { coinsResult, bombsResult, timeResult, totalCoinsResult })
                item?.RemoveFromClassList("shown");
            UpdateLiveStats();
        }
    }

    private void ShowResults()
    {
        if (session == null) return;
        gameHeader.text = "Game";
        coinsResult.text = $"Coins Collected: {session.CoinsCollected}";
        int seconds = Mathf.FloorToInt(session.TimeSurvived);
        bombsResult.text = $"Bombs Dodged: {session.BombsDodged} (+{session.BombsDodged * ArenaSession.CoinsPerBomb} coins)";
        timeResult.text = $"Time Survived: {FormatTime(seconds)} (+{seconds * ArenaSession.CoinsPerSecond} coins)";
        totalCoinsResult.text = $"Total Coins: {session.TotalCoinsEarned}";
        foreach (Label item in new[] { coinsResult, bombsResult, timeResult, totalCoinsResult })
            item?.AddToClassList("shown");
    }

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
        if (session != null)
            session.RestartRound();
    }

    private void Return()
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
}
