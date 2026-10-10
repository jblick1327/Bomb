using TMPro;
using UnityEngine;

// Updates the legacy text HUD to reflect the current round state.
[AddComponentMenu("Arena/Arena HUD")]
public sealed class ArenaHud : MonoBehaviour
{
    [Header("Scene references")]
    [SerializeField] private ArenaSession session;
    [SerializeField, Tooltip("Shown when the session enters the Dead state.")]
    private GameObject deathPanel;
    [SerializeField, Tooltip("Displays the current movement, bomb and restart controls.")]
    private TMP_Text controls;

    private void OnEnable()
    {
        if (session == null) return;
        session.StateChanged += Refresh;
        Refresh(session.State);
    }

    private void OnDisable()
    {
        if (session != null) session.StateChanged -= Refresh;
    }

    private void Refresh(ArenaRoundState state)
    {
        if (deathPanel != null) deathPanel.SetActive(state == ArenaRoundState.Dead);
        if (controls != null) controls.text = state == ArenaRoundState.Playing
            ? "P1: A/D + W/Space    P2: arrows + Up    R: restart"
            : "R: restart";
    }
}
