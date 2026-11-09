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
    private VisualElement root, deathPanel;
    private Label gameHeader, winner, controls, timer, bombCounter;
    private Label coinsResult, bombsResult, timeResult, totalCoinsResult;
    private Button replayButton, returnButton;
    private IVisualElementScheduledItem timerUpdate;

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
    }

    private void OnEnable()
    {
        if (session != null) session.StateChanged += Refresh;
        if (replayButton != null) replayButton.clicked += Replay;
        if (returnButton != null) returnButton.clicked += Return;
        timerUpdate = root?.schedule.Execute(UpdateLiveStats).Every(100);
        if (session != null) Refresh(session.State);
    }

    private void OnDisable()
    {
        if (session != null) session.StateChanged -= Refresh;
        if (replayButton != null) replayButton.clicked -= Replay;
        if (returnButton != null) returnButton.clicked -= Return;
        timerUpdate?.Pause();
    }

    private void UpdateLiveStats()
    {
        if (session == null) return;
        if (timer != null) timer.text = FormatTime(session.TimeSurvived);
        if (bombCounter != null) bombCounter.text = $"Bombs dropped: {session.BombsDodged}";
    }

    private void Refresh(ArenaRoundState state)
    {
        bool dead = state == ArenaRoundState.Dead;
        if (winner != null) winner.text = session != null ? session.WinnerMessage : "Game Over";
        if (controls != null) controls.text = dead ? "R: restart" : "P1: A/D + W/Space    P2: arrows + Up    R: restart";
        if (controls != null) controls.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (deathPanel != null) deathPanel.style.display = dead ? DisplayStyle.Flex : DisplayStyle.None;
        if (timer != null) timer.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (bombCounter != null) bombCounter.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
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

    private void Replay()
    {
        GameAudio.PlayButtonPopSound();
        if (session != null)
            session.RestartRound();
    }

    private void Return()
    {
        GameAudio.PlayButtonPopSound();
        SceneManager.LoadScene("MainMenuScene");
    }

    private static string FormatTime(float seconds)
    {
        int total = Mathf.FloorToInt(seconds);
        return $"{total / 60:00}:{total % 60:00}";
    }
}
