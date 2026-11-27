using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

// Grows a menu button slightly while the mouse is on it or it is selected,
// and squashes it a touch while pressed, matching the in-game chalk buttons.
// CursorOver lets a screen's own cursor (the setup screen's P1 ring) light it
// up the same way, colour included.
[RequireComponent(typeof(Selectable))]
public sealed class BomButtonHover : MonoBehaviour,
    IPointerEnterHandler, IPointerExitHandler, IPointerDownHandler, IPointerUpHandler, ISelectHandler, IDeselectHandler
{
    private const float HoverScale = 1.05f;
    private const float PressScale = .98f;
    private const float Speed = 18f;

    private Selectable selectable;
    private Vector3 baseScale = Vector3.one;
    private bool pointerOver, selected, pressed, cursorOver;

    public bool CursorOver
    {
        get => cursorOver;
        set
        {
            if (cursorOver == value) return;
            cursorOver = value;
            // The button's own colour states only follow the pointer and
            // selection, so light it up by hand for the screen's cursor.
            if (!pointerOver && !selected && selectable != null && selectable.targetGraphic != null && selectable.interactable)
            {
                ColorBlock colors = selectable.colors;
                Color color = (value ? colors.highlightedColor : colors.normalColor) * colors.colorMultiplier;
                selectable.targetGraphic.CrossFadeColor(color, colors.fadeDuration, true, true);
            }
        }
    }

    private void Awake()
    {
        selectable = GetComponent<Selectable>();
        baseScale = transform.localScale;
    }

    private void OnDisable()
    {
        pointerOver = selected = pressed = cursorOver = false;
        transform.localScale = baseScale;
    }

    // Unscaled time, so it still works while the game is paused.
    private void Update()
    {
        bool lit = selectable == null || selectable.interactable;
        float target = !lit ? 1f : pressed ? PressScale : pointerOver || selected || cursorOver ? HoverScale : 1f;
        Vector3 goal = baseScale * target;
        if (transform.localScale != goal)
            transform.localScale = Vector3.Lerp(transform.localScale, goal, 1f - Mathf.Exp(-Speed * Time.unscaledDeltaTime));
    }

    public void OnPointerEnter(PointerEventData eventData) => pointerOver = true;
    public void OnPointerExit(PointerEventData eventData) { pointerOver = false; pressed = false; }
    public void OnPointerDown(PointerEventData eventData) => pressed = true;
    public void OnPointerUp(PointerEventData eventData) => pressed = false;
    public void OnSelect(BaseEventData eventData) => selected = true;
    public void OnDeselect(BaseEventData eventData) => selected = false;
}
