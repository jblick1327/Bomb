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
        deathPanel.SetActive(state == ArenaRoundState.Dead);
        controls.text = state == ArenaRoundState.Playing
            ? "A/D or arrows: move    Space: jump    B: drop bomb    R: restart"
            : "R: restart";
    }
}
