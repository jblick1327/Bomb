using UnityEngine;
using UnityEngine.UIElements;

[RequireComponent(typeof(UIDocument))]
[AddComponentMenu("Arena/UI Toolkit HUD")]
public sealed class ArenaHudDocument : MonoBehaviour
{
    private const int XpPerBomb = 10;
    private const int XpPerSecond = 1;
    private const int FirstLevelXp = 100;
    private const int AdditionalXpPerLevel = 50;

    [SerializeField] private ArenaSession session;
    [SerializeField] private StyleSheet styleSheet;

    private UIDocument document;
    private VisualElement root, deathPanel, levelFill, levelTrack;
    private Label controls, timer, bombCounter, bombResult, timeResult, xpResult, currentLevel, nextLevel;
    private IVisualElementScheduledItem timerUpdate;

    private void Awake()
    {
        document = GetComponent<UIDocument>();
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        root = document.rootVisualElement.Q<VisualElement>("hud-root");
        if (styleSheet != null) root.styleSheets.Add(styleSheet);
        deathPanel = root.Q<VisualElement>("death-panel");
        controls = root.Q<Label>("controls");
        timer = root.Q<Label>("timer");
        bombCounter = root.Q<Label>("bomb-counter");
        bombResult = root.Q<Label>("result-bombs");
        timeResult = root.Q<Label>("result-time");
        xpResult = root.Q<Label>("result-xp");
        levelTrack = root.Q<VisualElement>("level-track");
        currentLevel = root.Q<Label>("current-level");
        nextLevel = root.Q<Label>("next-level");
        levelFill = root.Q<VisualElement>("level-fill");
    }

    private void OnEnable()
    {
        if (session != null) session.StateChanged += Refresh;
        timerUpdate = root?.schedule.Execute(UpdateLiveStats).Every(100);
        if (session != null) Refresh(session.State);
    }

    private void OnDisable()
    {
        if (session != null) session.StateChanged -= Refresh;
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
        if (controls != null) controls.text = dead ? "R: restart" : "A/D or arrows: move    Space: jump    R: restart";
        if (controls != null) controls.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (deathPanel != null) deathPanel.style.display = dead ? DisplayStyle.Flex : DisplayStyle.None;
        if (timer != null) timer.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (bombCounter != null) bombCounter.style.display = dead ? DisplayStyle.None : DisplayStyle.Flex;
        if (dead) ShowResults();
        else
        {
            root.schedule.Execute(() =>
            {
                foreach (Label item in new[] { bombResult, timeResult, xpResult }) item?.RemoveFromClassList("shown");
                levelTrack?.RemoveFromClassList("shown");
            });
            UpdateLiveStats();
        }
    }

    private void ShowResults()
    {
        if (session == null) return;
        int bombs = session.BombsDodged;
        int seconds = Mathf.FloorToInt(session.TimeSurvived);
        int xp = bombs * XpPerBomb + seconds * XpPerSecond;
        bombResult.text = "Bombs Dodged: 0";
        timeResult.text = "Time Survived: 00:00";
        xpResult.text = "XP Gained: 0";
        currentLevel.text = "Lvl 1";
        nextLevel.text = "Lvl 2";
        levelFill.style.width = Length.Percent(0);
        AnimateCount(bombResult, "Bombs Dodged: ", bombs, "", () =>
            AnimateCount(timeResult, "Time Survived: ", seconds, "", () =>
                AnimateCount(xpResult, "XP Gained: ", xp, "", () =>
                {
                    levelTrack?.AddToClassList("shown");
                    AnimateLevelProgress(xp, 1, FirstLevelXp);
                })));
    }

    private void AnimateLevelProgress(int remainingXp, int level, int xpNeeded, long startDelay = 60)
    {
        currentLevel.text = $"Lvl {level}";
        nextLevel.text = $"Lvl {level + 1}";
        levelFill.style.width = Length.Percent(0);

        if (remainingXp < xpNeeded)
        {
            float progress = xpNeeded > 0 ? (float)remainingXp / xpNeeded * 100f : 0f;
            levelTrack.schedule.Execute(() => levelFill.style.width = Length.Percent(progress)).StartingIn(startDelay);
            return;
        }

        // Let the bar visibly reach the threshold before advancing the level labels.
        levelTrack.schedule.Execute(() => levelFill.style.width = Length.Percent(100)).StartingIn(startDelay);
        levelTrack.schedule.Execute(() =>
        {
            levelTrack.AddToClassList("level-up");
            currentLevel.text = $"Lvl {level + 1}";
            nextLevel.text = $"Lvl {level + 2}";
        }).StartingIn(startDelay + 500);
        levelTrack.schedule.Execute(() =>
        {
            levelTrack.RemoveFromClassList("level-up");
            AnimateLevelProgress(remainingXp - xpNeeded, level + 1,
                xpNeeded + AdditionalXpPerLevel, 520);
        }).StartingIn(startDelay + 780);
    }

    private void AnimateCount(Label label, string prefix, int target, string suffix, System.Action finished)
    {
        if (label == null) { finished?.Invoke(); return; }
        label.AddToClassList("shown");
        int current = 0;
        int step = Mathf.Max(1, target / 30);
        label.schedule.Execute(() => { }).Every(35).Until(() =>
        {
            current = Mathf.Min(target, current + step);
            label.text = prefix + (label == timeResult ? FormatTime(current) : current.ToString()) + suffix;
            if (current < target) return false;
            label.schedule.Execute(() => finished?.Invoke()).StartingIn(350);
            return true;
        });
    }

    private static string FormatTime(float seconds)
    {
        int total = Mathf.FloorToInt(seconds);
        return $"{total / 60:00}:{total % 60:00}";
    }
}
