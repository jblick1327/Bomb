using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.Controls;
using UnityEngine.InputSystem.UI;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

// Player 1's menu cursor: a "P1" ring that replaces the system mouse pointer.
// It shows whenever a menu is open and only Player 1 can drive it, using the
// mouse or Player 1's controller (stick or d-pad to move, A to click). The
// setup screen draws its own P1-P4 cursors, so this one hides there.
[DefaultExecutionOrder(-50)]
public sealed class MenuCursor : MonoBehaviour
{
    private const float GamepadSpeed = 900f; // screen pixels per second at full tilt
    private const string MainMenuScene = "MainMenuScene";

    private static MenuCursor instance;
    private static Sprite ringSprite;

    // Where the cursor is, in screen pixels.
    public static Vector2 Position => instance != null ? instance.position : Vector2.zero;
    // True while a menu is open and the cursor is in use.
    public static bool Active => instance != null && instance.active;
    // The controller that last clicked, so menus can tell which pad Player 1 is using.
    public static Gamepad LastSubmitGamepad { get; private set; }
    // Raised when Player 1 clicks with a controller. UI Toolkit screens, such as
    // the in-game pause menu, listen for it to press their own buttons.
    public static event Action<Vector2> GamepadSubmit;
    // Set by screens that draw the cursor themselves, such as the in-game HUD.
    public static bool DrawnByScreen { get; set; }

    private Vector2 position;
    private bool active;
    private RectTransform cursor;
    private ArenaSession session;
    private PointerEventData pressData;
    private GameObject hoveredSelectable;
    private readonly List<RaycastResult> raycastResults = new List<RaycastResult>();

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Create()
    {
        if (instance != null) return;
        var root = new GameObject("Menu Cursor");
        DontDestroyOnLoad(root);
        instance = root.AddComponent<MenuCursor>();
    }

    // A white ring, tinted per player by the caller.
    public static Sprite RingSprite
    {
        get
        {
            if (ringSprite != null) return ringSprite;
            var texture = new Texture2D(64, 64, TextureFormat.RGBA32, false);
            var pixels = new Color[64 * 64];
            for (int y = 0; y < 64; y++)
                for (int x = 0; x < 64; x++)
                {
                    float distance = Vector2.Distance(new Vector2(x, y), new Vector2(31.5f, 31.5f));
                    pixels[y * 64 + x] = distance <= 30f && distance >= 25f ? Color.white : Color.clear;
                }
            texture.SetPixels(pixels);
            texture.Apply();
            ringSprite = Sprite.Create(texture, new Rect(0f, 0f, 64f, 64f), new Vector2(.5f, .5f));
            return ringSprite;
        }
    }

    // Player 1's controller. Before a match roster exists, or if Player 1's pad
    // was unplugged in controller-only mode, the first connected pad stands in.
    public static Gamepad PlayerOneGamepad()
    {
        Gamepad gamepad = MatchMenuUI.GetGamepadForPlayer(1);
        if (gamepad != null) return gamepad;
        if (!MatchMenuUI.IsKeyboardEnabledForPlayer(1) && Gamepad.all.Count > 0) return Gamepad.all[0];
        return null;
    }

    private void Awake()
    {
        position = new Vector2(Screen.width * 0.5f, Screen.height * 0.5f);
        BuildCursor();
        SceneManager.sceneLoaded += OnSceneLoaded;
        OnSceneLoaded(SceneManager.GetActiveScene(), LoadSceneMode.Single);
    }

    private void OnDestroy()
    {
        SceneManager.sceneLoaded -= OnSceneLoaded;
        if (instance == this) instance = null;
    }

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        session = FindFirstObjectByType<ArenaSession>();
        pressData = null;
        hoveredSelectable = null;
        DrawnByScreen = false;
        // Unity's UI module lets every controller move the selection and press
        // buttons. Turn that off so only Player 1, through this cursor, can.
        foreach (InputSystemUIInputModule module in FindObjectsByType<InputSystemUIInputModule>(FindObjectsSortMode.None))
        {
            module.move = null;
            module.submit = null;
            module.cancel = null;
        }
    }

    private void BuildCursor()
    {
        var canvasObject = new GameObject("Menu Cursor Canvas", typeof(Canvas), typeof(CanvasScaler));
        canvasObject.transform.SetParent(transform, false);
        Canvas canvas = canvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 32000;
        CanvasScaler scaler = canvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;

        var ring = new GameObject("P1 Cursor", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        cursor = ring.GetComponent<RectTransform>();
        cursor.SetParent(canvasObject.transform, false);
        cursor.sizeDelta = new Vector2(72f, 72f);
        Image image = ring.GetComponent<Image>();
        image.sprite = RingSprite;
        image.color = MatchMenuUI.GetPlayerCursorColor(0);
        image.raycastTarget = false;

        var labelObject = new GameObject("Label", typeof(RectTransform), typeof(CanvasRenderer), typeof(TMPro.TextMeshProUGUI));
        RectTransform labelRect = labelObject.GetComponent<RectTransform>();
        labelRect.SetParent(cursor, false);
        labelRect.anchorMin = Vector2.zero;
        labelRect.anchorMax = Vector2.one;
        labelRect.offsetMin = Vector2.zero;
        labelRect.offsetMax = Vector2.zero;
        var label = labelObject.GetComponent<TMPro.TextMeshProUGUI>();
        label.text = "P1";
        label.fontSize = 18f;
        label.fontStyle = TMPro.FontStyles.Bold;
        label.alignment = TMPro.TextAlignmentOptions.Center;
        label.color = Color.white;
        label.raycastTarget = false;
    }

    private void Update()
    {
        // The P1 ring replaces the system pointer everywhere, in menus and in play.
        Cursor.visible = false;

        active = IsMenuOpen();
        cursor.gameObject.SetActive(active && !DrawnByScreen);
        if (!active)
        {
            CancelPress();
            return;
        }

        bool movedByGamepad = MoveCursor();
        cursor.position = position;
        if (movedByGamepad) HighlightUnderCursor();
        HandleGamepadClick();
    }

    private bool IsMenuOpen()
    {
        if (MatchMenuUI.IsSetupScreenOpen) return false;
        if (SceneManager.GetActiveScene().name == MainMenuScene) return true;
        return session != null && session.IsMenuShowing;
    }

    // Returns true if a controller moved the cursor this frame.
    private bool MoveCursor()
    {
        Mouse mouse = Mouse.current;
        if (mouse != null && mouse.delta.ReadValue().sqrMagnitude > 0.01f)
            position = mouse.position.ReadValue();

        Gamepad gamepad = PlayerOneGamepad();
        if (gamepad == null) return false;
        Vector2 input = gamepad.leftStick.ReadValue();
        Vector2 dpad = gamepad.dpad.ReadValue();
        if (dpad.sqrMagnitude > input.sqrMagnitude) input = dpad;
        if (input.sqrMagnitude < 0.02f) return false;

        // Unscaled time, so the cursor still moves while the game is paused.
        position += input * (GamepadSpeed * Time.unscaledDeltaTime);
        position.x = Mathf.Clamp(position.x, 0f, Screen.width);
        position.y = Mathf.Clamp(position.y, 0f, Screen.height);
        return true;
    }

    // A controller can't hover, so select the button under the cursor instead.
    // That shows its highlight the same way a mouse hover would.
    private void HighlightUnderCursor()
    {
        EventSystem events = EventSystem.current;
        if (events == null) return;
        GameObject hit = RaycastUi(position);
        Selectable selectable = hit != null ? hit.GetComponentInParent<Selectable>() : null;
        GameObject target = selectable != null && selectable.IsInteractable() ? selectable.gameObject : null;
        if (target == hoveredSelectable) return;
        hoveredSelectable = target;
        events.SetSelectedGameObject(target);
    }

    private void HandleGamepadClick()
    {
        Gamepad gamepad = PlayerOneGamepad();
        if (gamepad == null) return;
        ButtonControl submit = gamepad.buttonSouth;

        if (submit.wasPressedThisFrame)
        {
            LastSubmitGamepad = gamepad;
            PressUi(position);
            GamepadSubmit?.Invoke(position);
        }
        else if (submit.isPressed && pressData != null)
        {
            DragUi(position);
        }
        if (submit.wasReleasedThisFrame) ReleaseUi(position);
    }

    // Clicks the Unity UI element at a screen position straight away. Used by
    // the setup screen, which moves its own cursors.
    public static void ClickAt(Vector2 screenPosition)
    {
        if (instance == null) return;
        instance.PressUi(screenPosition);
        instance.ReleaseUi(screenPosition);
    }

    private GameObject RaycastUi(Vector2 screenPosition)
    {
        EventSystem events = EventSystem.current;
        if (events == null) return null;
        var data = new PointerEventData(events) { position = screenPosition };
        raycastResults.Clear();
        events.RaycastAll(data, raycastResults);
        return raycastResults.Count > 0 ? raycastResults[0].gameObject : null;
    }

    // The same pointer down / drag / up / click sequence a mouse produces, so
    // buttons, toggles and sliders all respond as usual.
    private void PressUi(Vector2 screenPosition)
    {
        EventSystem events = EventSystem.current;
        if (events == null) return;
        var data = new PointerEventData(events) { position = screenPosition, button = PointerEventData.InputButton.Left };
        raycastResults.Clear();
        events.RaycastAll(data, raycastResults);
        if (raycastResults.Count == 0) return;

        RaycastResult result = raycastResults[0];
        GameObject hit = result.gameObject;
        data.pointerCurrentRaycast = result;
        data.pointerPressRaycast = result;
        data.pressPosition = screenPosition;
        data.eligibleForClick = true;
        GameObject pressed = ExecuteEvents.ExecuteHierarchy(hit, data, ExecuteEvents.pointerDownHandler);
        data.pointerPress = pressed != null ? pressed : ExecuteEvents.GetEventHandler<IPointerClickHandler>(hit);
        data.rawPointerPress = hit;
        data.pointerDrag = ExecuteEvents.GetEventHandler<IDragHandler>(hit);
        if (data.pointerDrag != null) ExecuteEvents.Execute(data.pointerDrag, data, ExecuteEvents.initializePotentialDrag);
        pressData = data;
    }

    private void DragUi(Vector2 screenPosition)
    {
        if (pressData.pointerDrag == null) return;
        pressData.delta = screenPosition - pressData.position;
        pressData.position = screenPosition;
        if (pressData.delta.sqrMagnitude > 0f) ExecuteEvents.Execute(pressData.pointerDrag, pressData, ExecuteEvents.dragHandler);
    }

    private void ReleaseUi(Vector2 screenPosition)
    {
        if (pressData == null) return;
        PointerEventData data = pressData;
        pressData = null;
        data.position = screenPosition;
        if (data.pointerPress != null) ExecuteEvents.Execute(data.pointerPress, data, ExecuteEvents.pointerUpHandler);
        GameObject hit = RaycastUi(screenPosition);
        GameObject clickTarget = hit != null ? ExecuteEvents.GetEventHandler<IPointerClickHandler>(hit) : null;
        if (data.eligibleForClick && clickTarget != null && clickTarget == data.pointerPress)
            ExecuteEvents.Execute(clickTarget, data, ExecuteEvents.pointerClickHandler);
    }

    private void CancelPress()
    {
        if (pressData == null) return;
        if (pressData.pointerPress != null) ExecuteEvents.Execute(pressData.pointerPress, pressData, ExecuteEvents.pointerUpHandler);
        pressData = null;
    }
}
