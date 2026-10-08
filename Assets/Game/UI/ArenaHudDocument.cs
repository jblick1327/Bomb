using UnityEngine;
using UnityEngine.UIElements;

// Keeps the UI Toolkit HUD in a fixed screen position and updates round state.
[RequireComponent(typeof(UIDocument))]
[AddComponentMenu("Arena/UI Toolkit HUD")]
public sealed class ArenaHudDocument : MonoBehaviour
{
    [SerializeField] private ArenaSession session;
    [SerializeField] private StyleSheet styleSheet;

    private UIDocument document;
    private VisualElement root;
    private VisualElement deathPanel;
    private Label controls;

    private void Awake()
    {
        document = GetComponent<UIDocument>();
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        root = document.rootVisualElement.Q<VisualElement>("hud-root");
        if (styleSheet != null) root.styleSheets.Add(styleSheet);
        deathPanel = root.Q<VisualElement>("death-panel");
        controls = root.Q<Label>("controls");
    }

    private void OnEnable()
    {
        if (session != null) session.StateChanged += Refresh;
        if (session != null) Refresh(session.State);
    }

    private void OnDisable()
    {
        if (session != null) session.StateChanged -= Refresh;
    }

    private void Refresh(ArenaRoundState state)
    {
        if (controls != null) controls.text = state == ArenaRoundState.Playing
            ? "A/D or arrows: move    Space: jump    B: drop bomb    R: restart"
            : "R: restart";
        if (deathPanel != null)
            deathPanel.style.display = state == ArenaRoundState.Dead ? DisplayStyle.Flex : DisplayStyle.None;
    }
}
