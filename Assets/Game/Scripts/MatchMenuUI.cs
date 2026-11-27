using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using TMPro;
using UnityEngine.InputSystem;
#if UNITY_EDITOR
using UnityEditor;
#endif

public enum MatchInputMode
{
    KeyboardAndControllers,
    SharedKeyboard,
    AllControllers
}

/// <summary>Builds the match setup layout and owns the menu-to-setup transition.</summary>
public sealed class MatchMenuUI : MonoBehaviour
{
    private static MatchMenuUI instance;
    private Image fadeImage;
    private bool isTransitioning;
    private int selectedLevel;
    private int selectedCharacter;
    private const int MaxLocalPlayers = 4;
    private static readonly int[] playerCharacters = { 0, 1, 2, 3 };
    private static readonly int[] playerGamepadDeviceIds = { -1, -1, -1, -1 };
    private static int matchPlayerCount = 2;
    private static bool matchRosterConfigured;
    private static MatchInputMode inputMode = MatchInputMode.KeyboardAndControllers;
    private readonly int[] playerCharacterCursors = { 0, 1, 2, 3 };
    private readonly float[] nextPlayerNavigationTime = new float[MaxLocalPlayers];
    private int activeCharacterPlayer;
    private float nextControllerStatusRefresh;
    private string lastControllerStatus;
    private TextMeshProUGUI levelName;
    private TextMeshProUGUI[] playerSlotLabels;
    private RawImage[] playerSlotPortraits;
    private TextMeshProUGUI controllerStatusText;
    private Camera menuCamera;
    private Vector3 mainMenuCameraPosition;
    private Quaternion mainMenuCameraRotation;
    private Button mainMenuPlayButton;
    private Button onlineButton;
    private bool onlineMenuOpen;
    private Button startButton;
    private Button shopButton;
    private Button settingsButton;
    private GameObject splashscreen;
    private GameObject titleImage;
    private GameObject setupCanvasObject;
    private GameObject shopCanvasObject;
    private GameObject settingsCanvasObject;
    private bool secondaryMenuOpen;
    private bool shopMenuOpen;
    private bool settingsMenuOpen;
    private RectTransform playerOneSlot;
    private RawImage selectedPlayerPortrait;
    private RenderTexture[] unlockedCharacterPortraits;
    private readonly bool[] ownedCharacters = { true, true, true, true, true, false, false, false, false, false, false, false, false, false, false };
    private readonly string[] shopCharacterNames =
    {
        "Blue Claymate", "Red Claymate", "Yellow Claymate", "Green Claymate", "Orange Claymate",
        "Purple Claymate", "Cyan Claymate", "Pink Claymate", "Lime Claymate", "Brown Claymate",
        "Slate Claymate", "Gold Claymate", "Teal Claymate", "Violet Claymate", "Crimson Claymate"
    };
    private static readonly Color[] characterColors =
    {
        new Color(.16f, .48f, .98f), new Color(.92f, .19f, .22f), new Color(1f, .83f, .12f),
        new Color(.20f, .76f, .34f), new Color(1f, .45f, .10f), new Color(.55f, .28f, .86f),
        new Color(.15f, .75f, .85f), new Color(.95f, .40f, .67f), new Color(.62f, .78f, .22f),
        new Color(.70f, .43f, .26f), new Color(.52f, .58f, .72f), new Color(.90f, .66f, .26f),
        new Color(.36f, .68f, .60f), new Color(.75f, .39f, .88f), new Color(.90f, .36f, .38f)
    };
    private const int FirstRowCharacterPrice = 100;
    private const int SecondRowCharacterPrice = 500;
    private const int LastRowCharacterPrice = 1000;
    private const string ShopCoinsKey = "CharacterShop.Coins";
    private const string ShopOwnedKeyPrefix = "CharacterShop.Owned.";
    private int shopCoins = 250;
    private int shopSelectedCharacter;
    private TextMeshProUGUI shopBalanceText;
    private TextMeshProUGUI shopNameText;
    private TextMeshProUGUI shopPurchaseText;
    private RawImage shopDetailPortrait;
    private RawImage[] shopCardPortraits;
    private Outline[] shopCardOutlines;
    private Button shopPurchaseButton;
    private RenderTexture shopLockedPortrait;
    private TextMeshProUGUI[] shopCardLockedLabels;
    private Image[] shopCardBackgrounds;
    private readonly List<RenderTexture> portraitTextures = new List<RenderTexture>();
    private Button[] characterButtons;
    private Outline[] characterOutlines;
    private RectTransform[] playerCursors;
    private TextMeshProUGUI inputModeLabel;
    private RawImage levelPreviewImage;
    private Texture2D yardLevelPreviewTexture;
    private Texture2D bridgeLevelPreviewTexture;
    private Texture2D towerLevelPreviewTexture;
    private AspectRatioFitter levelPreviewAspect;

    internal static readonly string[] LevelNames = { "THE YARD", "THE BRIDGE", "THE TOWER" };
    internal static readonly string[] LevelSceneNames = { "YardLevel", "BridgeLevel", "TowerLevel" };
    private const int CharacterCount = 15;
    // Title bars: height, smallest width, and the room left either side of the words.
    private const float HeaderHeight = 76f;
    private const float HeaderMinWidth = 320f;
    private const float HeaderSidePadding = 70f;
    private const float HeaderFontSize = 44f;
    // Player slots: the name along the top, the portrait underneath.
    private const float SlotLabelSize = 26f;
    private static readonly Vector2 SlotLabelMin = new Vector2(.04f, .70f);
    private static readonly Vector2 SlotLabelMax = new Vector2(.96f, .98f);
    private static readonly Vector2 SlotPortraitMin = new Vector2(0f, 0f);
    private static readonly Vector2 SlotPortraitMax = new Vector2(1f, .72f);
    // Character portraits sit this far inside their card's chalk edge, and
    // their cut-off bottom fades out over the fade distance.
    private const float PortraitInset = 12f;
    private const int PortraitFade = 26;
    // How far in from the edges a level picture fades out.
    private const int PictureFadeSides = 48;
    private const int PictureFadeTopBottom = 30;
    // How dark chalk buttons sit when nothing is on them (1 = the art as drawn).
    private const float ButtonRestingShade = .66f;
    private static readonly string[] InputModeLabels =
    {
        "MODE A: P1 KEYBOARD / P2-P4 CONTROLLERS",
        "MODE B: SHARED KEYBOARD (P1 WASD / P2 ARROWS)",
        "MODE C: ALL CONTROLLERS (P1-P4)"
    };
    private static readonly Vector3 SettingsCameraPosition = new Vector3(148.1f, 32.99f, 85.5f);
    private static readonly Vector3 SetupCameraPosition = new Vector3(156.3213f, 32.04606f, 231.5275f);
    private static readonly Vector3 SetupCameraLookAt = new Vector3(0f, 0f, 0f);

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Initialize()
    {
        if (instance == null)
        {
            GameObject root = new GameObject("Match Menu UI");
            instance = root.AddComponent<MatchMenuUI>();
            DontDestroyOnLoad(root);
            instance.LoadShopProgress();
        }

        SceneManager.sceneLoaded -= instance.OnSceneLoaded;
        SceneManager.sceneLoaded += instance.OnSceneLoaded;
        instance.OnSceneLoaded(SceneManager.GetActiveScene(), LoadSceneMode.Single);
    }

    private void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        isTransitioning = false;
        ClearPortraits();
        setupCanvasObject = null;
        shopCanvasObject = null;
        secondaryMenuOpen = false;
        shopMenuOpen = false;
        settingsMenuOpen = false;
        onlineMenuOpen = false;
        settingsCanvasObject = null;
        controllerStatusText = null;
        lastControllerStatus = null;

        if (scene.name == "MainMenuScene")
        {
            menuCamera = Camera.main;
            if (menuCamera != null)
            {
                mainMenuCameraPosition = menuCamera.transform.position;
                mainMenuCameraRotation = menuCamera.transform.rotation;
            }
            splashscreen = GameObject.Find("splashscreen");
            titleImage = GameObject.Find("TitleImage");
            HookPlayButton();
            HookOnlineButton();
            HookShopButton();
            HookSettingsButton();
            HookQuitButton();
            // Back from an online match: reopen the lobby, or show why the game ended.
            if (OnlineSession.IsActive || !string.IsNullOrEmpty(OnlineMatch.PendingMenuMessage))
                ShowOnlineMenu();
        }

        if (scene.name == "LevelSetupScene")
        {
            if (!matchRosterConfigured)
                ResetMatchRoster();
            secondaryMenuOpen = true;
            BuildSetupScreen();
        }

        if (fadeImage != null)
            StartCoroutine(Fade(0f, 0.45f, false));
    }

    private void Update()
    {
        if (onlineButton != null && mainMenuPlayButton != null
            && onlineButton.gameObject.activeSelf != mainMenuPlayButton.gameObject.activeSelf)
            onlineButton.gameObject.SetActive(mainMenuPlayButton.gameObject.activeSelf);

        if ((secondaryMenuOpen || SceneManager.GetActiveScene().name == "LevelSetupScene")
            && setupCanvasObject != null && !isTransitioning)
        {
            RefreshRosterForInputMode();
            UpdateSetupInput();
            UpdateSetupButtonHover();
        }

        if (controllerStatusText != null && Time.unscaledTime >= nextControllerStatusRefresh)
        {
            nextControllerStatusRefresh = Time.unscaledTime + 0.25f;
            int connectedCount = Gamepad.all.Count;
            string status = connectedCount + " CONTROLLERS CONNECTED  |  X JOIN / SELECT  |  OPTIONS START";
            if (lastControllerStatus != status)
            {
                controllerStatusText.text = status;
                lastControllerStatus = status;
            }
        }
    }

    private void StartSetupMenu()
    {
        if (isTransitioning || secondaryMenuOpen)
            return;

        isTransitioning = true;
        if (splashscreen != null) splashscreen.SetActive(false);
        if (titleImage != null) titleImage.SetActive(false);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(false);
        StartCoroutine(MoveCameraToSetup());
    }

    private static void ResetMatchRoster()
    {
        matchRosterConfigured = true;
        matchPlayerCount = inputMode == MatchInputMode.AllControllers ? MaxLocalPlayers : inputMode == MatchInputMode.SharedKeyboard ? 2 : 1;
        for (int i = 0; i < MaxLocalPlayers; i++)
        {
            playerGamepadDeviceIds[i] = -1;
            playerCharacters[i] = i;
        }
        if (inputMode == MatchInputMode.AllControllers)
        {
            if (instance != null)
                instance.RefreshRosterForInputMode();
        }
    }

    public static int MatchPlayerCount => matchRosterConfigured ? matchPlayerCount : 2;
    // The setup screen draws its own P1-P4 cursors, so the shared menu cursor hides.
    public static bool IsSetupScreenOpen => instance != null && instance.setupCanvasObject != null;
    // Each player's cursor colour, by player index (0 = Player 1).
    public static Color GetPlayerCursorColor(int playerIndex) =>
        characterColors[Mathf.Clamp(playerIndex, 0, characterColors.Length - 1)];
    public static bool HasConfiguredMatchRoster => matchRosterConfigured;
    public static MatchInputMode CurrentInputMode => inputMode;

    public static bool IsKeyboardEnabledForPlayer(int playerNumber)
    {
        return inputMode != MatchInputMode.AllControllers
            && (playerNumber == 1 || inputMode == MatchInputMode.SharedKeyboard && playerNumber == 2);
    }

    public static int GetPlayerGamepadDeviceId(int playerNumber)
    {
        int index = playerNumber - 1;
        return index >= 0 && index < MaxLocalPlayers ? playerGamepadDeviceIds[index] : -1;
    }

    public static Gamepad GetGamepadForPlayer(int playerNumber)
    {
        if (matchRosterConfigured)
        {
            int deviceId = GetPlayerGamepadDeviceId(playerNumber);
            if (deviceId < 0) return null;
            foreach (Gamepad gamepad in Gamepad.all)
                if (gamepad.deviceId == deviceId) return gamepad;
            return null;
        }

        int fallbackIndex = playerNumber - 1;
        return fallbackIndex >= 0 && Gamepad.all.Count > fallbackIndex ? Gamepad.all[fallbackIndex] : null;
    }

    public static int GetCharacterForPlayer(int playerNumber)
    {
        int index = Mathf.Clamp(playerNumber - 1, 0, MaxLocalPlayers - 1);
        return playerCharacters[index];
    }

    public static Color GetCharacterColorForPlayer(int playerNumber)
    {
        int character = Mathf.Clamp(GetCharacterForPlayer(playerNumber), 0, CharacterCount - 1);
        return characterColors[character];
    }

    public static void AddShopCoins(int amount)
    {
        if (amount <= 0)
            return;
        if (instance == null)
        {
            Debug.LogError("Cannot award shop coins before the match menu has initialized.");
            return;
        }

        instance.shopCoins += amount;
        PlayerPrefs.SetInt(ShopCoinsKey, instance.shopCoins);
        PlayerPrefs.Save();
    }

    private void HookPlayButton()
    {
        Button[] buttons = FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (Button button in buttons)
        {
            if (button.gameObject.name != "PlayButton")
                continue;

            mainMenuPlayButton = button;
            button.onClick.RemoveListener(ShowSecondaryMenu);
            button.onClick.AddListener(ShowSecondaryMenu);
            // Offline covers single player and couch co-op, through the setup screen.
            TMP_Text label = button.GetComponentInChildren<TMP_Text>(true);
            if (label != null) label.text = "OFFLINE";
            StyleSceneButton(button);
            return;
        }
    }

    // The main menu's own buttons live in the scene: give their words the same
    // white, outlined look as the menus built in code. A label in some other
    // font keeps that font and only turns white.
    private static void StyleSceneButton(Button button)
    {
        if (button == null) return;
        foreach (TMP_Text label in button.GetComponentsInChildren<TMP_Text>(true))
        {
            if (label.font == BomUiSkin.MenuFont && BomUiSkin.MenuTextMaterial != null)
                label.fontSharedMaterial = BomUiSkin.MenuTextMaterial;
            label.color = BomUiSkin.TextColor;
        }
        if (button.transition == Selectable.Transition.ColorTint)
            SetChalkButtonColors(button);
        AddHover(button);
    }

    // The slight grow-on-hover the in-game buttons have.
    private static void AddHover(Button button)
    {
        if (button != null && button.GetComponent<BomButtonHover>() == null)
            button.gameObject.AddComponent<BomButtonHover>();
    }

    // Adds the ONLINE button under OFFLINE, styled the same.
    private void HookOnlineButton()
    {
        onlineButton = null;
        if (mainMenuPlayButton == null) return;
        GameObject onlineObject = Instantiate(mainMenuPlayButton.gameObject, mainMenuPlayButton.transform.parent, false);
        onlineObject.name = "OnlineButton";
        RectTransform onlineRect = onlineObject.GetComponent<RectTransform>();
        RectTransform playRect = mainMenuPlayButton.GetComponent<RectTransform>();
        onlineRect.anchoredPosition = playRect.anchoredPosition + new Vector2(0f, -110f);
        onlineButton = onlineObject.GetComponent<Button>();
        onlineButton.onClick.RemoveAllListeners();
        onlineButton.onClick.AddListener(ShowOnlineMenu);
        TMP_Text label = onlineObject.GetComponentInChildren<TMP_Text>(true);
        if (label != null) label.text = "ONLINE";
        GameAudio.RegisterButton(onlineButton);
    }

    private void ShowOnlineMenu()
    {
        if (isTransitioning || onlineMenuOpen || settingsMenuOpen || shopMenuOpen || secondaryMenuOpen)
            return;
        onlineMenuOpen = true;
        SetMainMenuButtonsVisible(false);
        OnlineMenuUI.Open(CloseOnlineMenu);
    }

    private void CloseOnlineMenu()
    {
        onlineMenuOpen = false;
        SetMainMenuButtonsVisible(true);
    }

    private void SetMainMenuButtonsVisible(bool visible)
    {
        if (splashscreen != null) splashscreen.SetActive(visible);
        if (titleImage != null) titleImage.SetActive(visible);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(visible);
        if (shopButton != null) shopButton.gameObject.SetActive(visible);
        if (settingsButton != null) settingsButton.gameObject.SetActive(visible);
    }

    private void HookShopButton()
    {
        if (shopButton == null)
        {
            Button[] buttons = FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None);
            foreach (Button button in buttons)
                if (button.gameObject.name == "ShopButton") { shopButton = button; break; }
        }

        if (shopButton == null && mainMenuPlayButton != null)
        {
            GameObject shopObject = Instantiate(mainMenuPlayButton.gameObject, mainMenuPlayButton.transform.parent, false);
            shopObject.name = "ShopButton";
            RectTransform shopRect = shopObject.GetComponent<RectTransform>();
            RectTransform playRect = mainMenuPlayButton.GetComponent<RectTransform>();
            shopRect.anchoredPosition = playRect.anchoredPosition + new Vector2(0f, -220f);
            shopButton = shopObject.GetComponent<Button>();
            TMP_Text buttonLabel = shopObject.GetComponentInChildren<TMP_Text>(true);
            if (buttonLabel != null) buttonLabel.text = "SHOP";
            GameAudio.RegisterButton(shopButton);
        }

        if (shopButton != null)
        {
            StyleSceneButton(shopButton);
            shopButton.onClick.RemoveListener(ShowSecondaryMenu);
            shopButton.onClick.RemoveListener(ShowShopMenu);
            shopButton.onClick.AddListener(ShowShopMenu);
        }
    }

    private void HookQuitButton()
    {
        Button[] buttons = FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (Button button in buttons)
        {
            if (button.gameObject.name != "QuitButton")
                continue;

            StyleSceneButton(button);
            button.onClick.RemoveListener(QuitGame);
            button.onClick.AddListener(QuitGame);
            GameAudio.RegisterButton(button);
            return;
        }
    }

    private void QuitGame()
    {
#if UNITY_EDITOR
        if (Application.isEditor)
        {
            EditorApplication.isPlaying = false;
            return;
        }
#endif
        Application.Quit();
    }

    private void HookSettingsButton()
    {
        Button[] buttons = FindObjectsByType<Button>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        foreach (Button button in buttons)
        {
            if (button.gameObject.name != "SettingsButton")
                continue;

            settingsButton = button;
            StyleSceneButton(button);
            button.onClick.RemoveListener(ShowSettingsMenu);
            button.onClick.AddListener(ShowSettingsMenu);
            return;
        }
    }

    private void ShowSettingsMenu()
    {
        if (isTransitioning || settingsMenuOpen || shopMenuOpen || secondaryMenuOpen)
            return;

        isTransitioning = true;
        if (splashscreen != null) splashscreen.SetActive(false);
        if (titleImage != null) titleImage.SetActive(false);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(false);
        if (shopButton != null) shopButton.gameObject.SetActive(false);
        if (settingsButton != null) settingsButton.gameObject.SetActive(false);
        StartCoroutine(MoveCameraToSettings());
    }

    private IEnumerator MoveCameraToSettings()
    {
        if (menuCamera != null)
        {
            Vector3 startPosition = menuCamera.transform.position;
            Quaternion startRotation = menuCamera.transform.rotation;
            Quaternion settingsRotation = Quaternion.AngleAxis(33f, Vector3.up) * startRotation;
            yield return MoveCamera(startPosition, startRotation, SettingsCameraPosition, settingsRotation, 2f);
        }

        settingsMenuOpen = true;
        isTransitioning = false;
        BuildSettingsScreen();
    }

    private void BuildSettingsScreen()
    {
        if (settingsCanvasObject != null) Destroy(settingsCanvasObject);
        settingsCanvasObject = new GameObject("Settings Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        Canvas canvas = settingsCanvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 60;
        CanvasScaler scaler = settingsCanvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = .5f;

        RectTransform root = settingsCanvasObject.GetComponent<RectTransform>();
        root.anchorMin = Vector2.zero;
        root.anchorMax = Vector2.one;
        root.offsetMin = Vector2.zero;
        root.offsetMax = Vector2.zero;

        RectTransform panel = AddPanel(root, "Settings Panel", new Vector2(.32f, .25f), new Vector2(.68f, .75f));
        AddHeaderBar(panel, "SETTINGS", BomButtonStyle.Blue);
        TextMeshProUGUI volumeLabel = AddText(panel, string.Empty, new Vector2(.10f, .57f), new Vector2(.90f, .69f), 34, Color.white, FontStyles.Bold);
        Slider volumeSlider = AddChalkSlider(panel, "Master Volume Slider", new Vector2(.12f, .42f), new Vector2(.88f, .53f));
        volumeSlider.minValue = 0f;
        volumeSlider.maxValue = 1f;
        volumeSlider.value = AudioListener.volume;
        void ShowVolume(float value) => volumeLabel.text = "MASTER VOLUME  " + Mathf.RoundToInt(value * 100f) + "%";
        ShowVolume(volumeSlider.value);
        volumeSlider.onValueChanged.AddListener(value =>
        {
            AudioListener.volume = value;
            ShowVolume(value);
        });
        AddButton(panel, "RESTART GAME", new Vector2(.18f, .20f), new Vector2(.82f, .34f), BomButtonStyle.Orange, RestartCurrentScene, 30);
        AddButton(panel, "GO BACK", new Vector2(.28f, .055f), new Vector2(.72f, .17f), BomButtonStyle.Yellow, CloseSettingsMenu, 32);
    }

    private void RestartCurrentScene()
    {
        shopCoins = 250;
        for (int i = 0; i < CharacterCount; i++)
        {
            ownedCharacters[i] = i < 5;
            PlayerPrefs.SetInt(ShopOwnedKeyPrefix + i, ownedCharacters[i] ? 1 : 0);
        }
        PlayerPrefs.SetInt(ShopCoinsKey, shopCoins);
        PlayerPrefs.Save();
        if (selectedCharacter >= 5)
            selectedCharacter = 0;
        SceneManager.LoadScene(SceneManager.GetActiveScene().name);
    }

    private void CloseSettingsMenu()
    {
        if (!isTransitioning)
            StartCoroutine(ReturnFromSettings());
    }

    private IEnumerator ReturnFromSettings()
    {
        isTransitioning = true;
        if (settingsCanvasObject != null) Destroy(settingsCanvasObject);
        settingsCanvasObject = null;
        if (menuCamera != null)
            yield return MoveCamera(menuCamera.transform.position, menuCamera.transform.rotation, mainMenuCameraPosition, mainMenuCameraRotation, 1.5f);
        if (splashscreen != null) splashscreen.SetActive(true);
        if (titleImage != null) titleImage.SetActive(true);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(true);
        if (shopButton != null) shopButton.gameObject.SetActive(true);
        if (settingsButton != null) settingsButton.gameObject.SetActive(true);
        settingsMenuOpen = false;
        isTransitioning = false;
    }

    private void ShowSecondaryMenu()
    {
        if (isTransitioning || secondaryMenuOpen)
            return;

        ResetMatchRoster();
        // In controller-only mode, whoever pressed Play with a controller is Player 1.
        Gamepad clicker = MenuCursor.LastSubmitGamepad;
        if (inputMode == MatchInputMode.AllControllers && clicker != null && clicker.added)
        {
            for (int i = 1; i < MaxLocalPlayers; i++)
                if (playerGamepadDeviceIds[i] == clicker.deviceId) playerGamepadDeviceIds[i] = playerGamepadDeviceIds[0];
            playerGamepadDeviceIds[0] = clicker.deviceId;
            RefreshRosterForInputMode();
        }
        StartSetupMenu();
    }

    private void ShowShopMenu()
    {
        if (isTransitioning || shopMenuOpen || secondaryMenuOpen)
            return;

        isTransitioning = true;
        if (splashscreen != null) splashscreen.SetActive(false);
        if (titleImage != null) titleImage.SetActive(false);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(false);
        StartCoroutine(MoveCameraToShop());
    }

    private IEnumerator MoveCameraToShop()
    {
        GameObject campfire = GameObject.Find("CampFire_02");
        GameObject playerOne = GameObject.Find("Player 1");
        Vector3 campfirePosition = campfire != null ? campfire.transform.position : new Vector3(-311f, 44f, -446f);
        Vector3 towardPlayer = playerOne != null ? playerOne.transform.position - campfirePosition : Vector3.forward;
        towardPlayer.y = 0f;
        if (towardPlayer.sqrMagnitude < .001f) towardPlayer = Vector3.forward;
        towardPlayer.Normalize();

        Vector3 shopPosition = campfirePosition + towardPlayer * 12f + Vector3.up * 4f;
       // shopPosition += new Vector3(-8f, -4f, 0f);
        Quaternion shopRotation = Quaternion.LookRotation(campfirePosition + Vector3.up * 2.5f - shopPosition, Vector3.up);
       // shopRotation = Quaternion.AngleAxis(12f, Vector3.up) * shopRotation;
        yield return MoveCamera(menuCamera != null ? menuCamera.transform.position : shopPosition,
            menuCamera != null ? menuCamera.transform.rotation : shopRotation, shopPosition, shopRotation, 2f);

        shopMenuOpen = true;
        isTransitioning = false;
        BuildShopScreen();
    }

    private IEnumerator MoveCamera(Vector3 startPosition, Quaternion startRotation, Vector3 endPosition, Quaternion endRotation, float duration)
    {
        if (menuCamera == null)
            yield break;

        float elapsed = 0f;
        while (elapsed < duration)
        {
            elapsed += Time.unscaledDeltaTime;
            float t = Mathf.Clamp01(elapsed / duration);
            t = t * t * (3f - 2f * t);
            menuCamera.transform.position = Vector3.Lerp(startPosition, endPosition, t);
            menuCamera.transform.rotation = Quaternion.Slerp(startRotation, endRotation, t);
            yield return null;
        }
        menuCamera.transform.SetPositionAndRotation(endPosition, endRotation);
    }

    private IEnumerator MoveCameraToSetup()
    {
        if (menuCamera != null)
        {
            Vector3 startPosition = menuCamera.transform.position;
            Quaternion startRotation = menuCamera.transform.rotation;
            Quaternion targetRotation = Quaternion.AngleAxis(120f, Vector3.up)
                * Quaternion.LookRotation(SetupCameraLookAt - SetupCameraPosition, Vector3.up);
            float elapsed = 0f;
            const float duration = 2f;
            while (elapsed < duration)
            {
                elapsed += Time.unscaledDeltaTime;
                float t = Mathf.Clamp01(elapsed / duration);
                t = t * t * (3f - 2f * t);
                menuCamera.transform.position = Vector3.Lerp(startPosition, SetupCameraPosition, t);
                menuCamera.transform.rotation = Quaternion.Slerp(startRotation, targetRotation, t);
                yield return null;
            }
            menuCamera.transform.SetPositionAndRotation(SetupCameraPosition, targetRotation);
        }

        secondaryMenuOpen = true;
        isTransitioning = false;
        BuildSetupScreen();
    }

    private IEnumerator ReturnToMainMenu()
    {
        if (setupCanvasObject != null) Destroy(setupCanvasObject);
        if (shopCanvasObject != null) Destroy(shopCanvasObject);
        setupCanvasObject = null;
        shopCanvasObject = null;
        ClearPortraits();
        isTransitioning = true;

        if (menuCamera != null)
        {
            Vector3 startPosition = menuCamera.transform.position;
            Quaternion startRotation = menuCamera.transform.rotation;
            float elapsed = 0f;
            const float duration = 1.5f;
            while (elapsed < duration)
            {
                elapsed += Time.unscaledDeltaTime;
                float t = Mathf.Clamp01(elapsed / duration);
                t = t * t * (3f - 2f * t);
                menuCamera.transform.position = Vector3.Lerp(startPosition, mainMenuCameraPosition, t);
                menuCamera.transform.rotation = Quaternion.Slerp(startRotation, mainMenuCameraRotation, t);
                yield return null;
            }
            menuCamera.transform.SetPositionAndRotation(mainMenuCameraPosition, mainMenuCameraRotation);
        }

        if (splashscreen != null) splashscreen.SetActive(true);
        if (titleImage != null) titleImage.SetActive(true);
        if (mainMenuPlayButton != null) mainMenuPlayButton.gameObject.SetActive(true);
        secondaryMenuOpen = false;
        shopMenuOpen = false;
        isTransitioning = false;
    }

    private IEnumerator FadeToScene(string sceneName)
    {
        isTransitioning = true;
        EnsureFadeCanvas();
        yield return Fade(1f, 0.5f, true);
        SceneManager.LoadScene(sceneName);
    }

    private IEnumerator Fade(float targetAlpha, float duration, bool hold)
    {
        if (fadeImage == null)
            yield break;

        fadeImage.gameObject.SetActive(true);
        float startAlpha = fadeImage.color.a;
        float elapsed = 0f;
        while (elapsed < duration)
        {
            elapsed += Time.unscaledDeltaTime;
            float t = Mathf.Clamp01(elapsed / duration);
            t = t * t * (3f - 2f * t);
            SetFadeAlpha(Mathf.Lerp(startAlpha, targetAlpha, t));
            yield return null;
        }

        SetFadeAlpha(targetAlpha);
        if (!hold && targetAlpha <= 0f)
            fadeImage.gameObject.SetActive(false);
    }

    private void EnsureFadeCanvas()
    {
        if (fadeImage != null)
            return;

        GameObject canvasObject = new GameObject("White Scene Transition", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        DontDestroyOnLoad(canvasObject);
        Canvas canvas = canvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 1000;
        CanvasScaler scaler = canvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);

        GameObject imageObject = new GameObject("White Fade", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        imageObject.transform.SetParent(canvasObject.transform, false);
        RectTransform rect = imageObject.GetComponent<RectTransform>();
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        fadeImage = imageObject.GetComponent<Image>();
        fadeImage.color = new Color(1f, 1f, 1f, 0f);
        fadeImage.raycastTarget = true;
        imageObject.SetActive(false);
    }

    private void SetFadeAlpha(float alpha)
    {
        Color color = fadeImage.color;
        color.a = alpha;
        fadeImage.color = color;
    }

    private void BuildSetupScreen()
    {
        if (setupCanvasObject != null)
            Destroy(setupCanvasObject);

        if (SceneManager.GetActiveScene().name == "LevelSetupScene")
        {
            Canvas[] existingCanvases = FindObjectsByType<Canvas>(FindObjectsInactive.Include, FindObjectsSortMode.None);
            foreach (Canvas existingCanvas in existingCanvases)
                if (existingCanvas.gameObject.name == "UICanvas") existingCanvas.gameObject.SetActive(false);
        }

        GameObject canvasObject = new GameObject("Match Setup Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        setupCanvasObject = canvasObject;
        Canvas canvas = canvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 50;
        CanvasScaler scaler = canvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;

        RectTransform root = canvasObject.GetComponent<RectTransform>();
        root.anchorMin = Vector2.zero;
        root.anchorMax = Vector2.one;
        root.offsetMin = Vector2.zero;
        root.offsetMax = Vector2.zero;

        RectTransform preview = AddPanel(root, "Level Preview Panel", new Vector2(.035f, .665f), new Vector2(.49f, .97f));
        AddHeaderBar(preview, "LEVEL PREVIEW", BomButtonStyle.Blue);
        RectTransform previewWindow = AddRect(preview, "Preview Window", new Vector2(.04f, .08f), new Vector2(.96f, .78f));
        if (yardLevelPreviewTexture == null)
            yardLevelPreviewTexture = Resources.Load<Texture2D>("YardLevelPreview");
        if (bridgeLevelPreviewTexture == null)
            bridgeLevelPreviewTexture = Resources.Load<Texture2D>("BridgeLevelPreview");
        if (towerLevelPreviewTexture == null)
            towerLevelPreviewTexture = Resources.Load<Texture2D>("TowerLevelPreview");
        levelPreviewImage = AddFadedPicture(previewWindow, "Level Preview", Vector2.zero, Vector2.one, out levelPreviewAspect);
        levelPreviewImage.texture = yardLevelPreviewTexture;
        levelName = AddNameTag(previewWindow, LevelNames[selectedLevel], .04f, .30f, 32);
        RefreshLevelPreview();
        AddArrowButton(preview, true, new Vector2(.015f, .34f), new Vector2(.15f, .62f), () => ChangeLevel(-1));
        AddArrowButton(preview, false, new Vector2(.85f, .34f), new Vector2(.985f, .62f), () => ChangeLevel(1));

        RectTransform players = AddPanel(root, "Players Panel", new Vector2(.525f, .665f), new Vector2(.965f, .97f));
        AddHeaderBar(players, "PLAYERS", BomButtonStyle.Orange);
        controllerStatusText = AddText(players, string.Empty, new Vector2(.035f, .73f), new Vector2(.965f, .83f), 22, Color.white, FontStyles.Bold);
        lastControllerStatus = null;
        activeCharacterPlayer = 0;
        playerSlotLabels = new TextMeshProUGUI[MaxLocalPlayers];
        playerSlotPortraits = new RawImage[MaxLocalPlayers];
        playerCursors = new RectTransform[MaxLocalPlayers];
        playerOneSlot = null;
        selectedPlayerPortrait = null;
        for (int i = 0; i < playerSlotLabels.Length; i++)
        {
            float xMin = .0525f + i * .23f;
            RectTransform slot = AddPanel(players, "Player Slot " + (i + 1), new Vector2(xMin, .08f), new Vector2(xMin + .205f, .73f));
            bool joined = i < matchPlayerCount;
            if (i == 0)
            {
                playerOneSlot = slot;
                playerSlotLabels[i] = AddText(slot, "PLAYER 1", SlotLabelMin, SlotLabelMax, SlotLabelSize, Color.white, FontStyles.Bold);
            }
            else
            {
                playerSlotLabels[i] = AddText(slot, joined ? "PLAYER " + (i + 1) : "+\nPRESS X TO JOIN", joined ? SlotLabelMin : Vector2.zero, joined ? SlotLabelMax : Vector2.one, SlotLabelSize, Color.white, FontStyles.Bold);
                int slotIndex = i;
                AddButton(slot, "", Vector2.zero, Vector2.one, new Color(1, 1, 1, .01f), () => JoinPlayer(slotIndex), 18, Color.white);
            }
            playerCharacterCursors[i] = Mathf.Clamp(playerCharacters[i], 0, 4);
        }

        RectTransform characters = AddPanel(root, "Character Selection Panel", new Vector2(.035f, .015f), new Vector2(.725f, .635f));
        AddHeaderBar(characters, "CHARACTER SELECTION", BomButtonStyle.Blue);
        characterButtons = new Button[CharacterCount];
        characterOutlines = new Outline[CharacterCount];
        unlockedCharacterPortraits = new RenderTexture[CharacterCount];
        RenderTexture lockedSilhouette = null;
        for (int i = 0; i < CharacterCount; i++)
        {
            int index = i;
            int col = i % 5;
            int row = i / 5;
            float xMin = .035f + col * .192f;
            float yMax = .855f - row * .28f;
            bool unlocked = ownedCharacters[i];
            // The chalk panel takes on a light wash of the character's colour.
            Color tileColor = unlocked ? Color.Lerp(characterColors[i], Color.white, .45f) : new Color(.55f, .55f, .6f);
            RectTransform tile = AddPanel(characters, unlocked ? "Unlocked Character " + (i + 1) : "Locked Character " + (i - 4), new Vector2(xMin, yMax - .265f), new Vector2(xMin + .168f, yMax), tileColor);
            if (unlocked)
            {
                characterButtons[i] = AddButton(tile, string.Empty, Vector2.zero, Vector2.one, new Color(1f, 1f, 1f, .01f), () => SelectCharacterForPlayer(0, index), 21, Color.white);
                if (unlockedCharacterPortraits[i] == null)
                    unlockedCharacterPortraits[i] = CreateCharacterPortrait(characterColors[i], false);
                AddFramedPortrait(tile, unlockedCharacterPortraits[i], Vector2.zero, Vector2.one);
                characterOutlines[i] = tile.gameObject.AddComponent<Outline>();
                characterOutlines[i].effectColor = characterColors[i];
                characterOutlines[i].effectDistance = new Vector2(5f, -5f);
            }
            else
            {
                characterButtons[i] = AddButton(tile, string.Empty, Vector2.zero, Vector2.one, new Color(1f, 1f, 1f, .01f), () => { }, 21, Color.white);
                if (lockedSilhouette == null)
                    lockedSilhouette = CreateCharacterPortrait(Color.black, true);
                AddFramedPortrait(tile, lockedSilhouette, Vector2.zero, Vector2.one);
                AddText(tile, "LOCKED", new Vector2(.03f, .04f), new Vector2(.97f, .30f), 26, Color.white, FontStyles.Bold);
            }
        }
        for (int i = 0; i < matchPlayerCount; i++)
        {
            int character = Mathf.Clamp(playerCharacters[i], 0, CharacterCount - 1);
            playerSlotLabels[i].text = "PLAYER " + (i + 1) + "\n" + shopCharacterNames[character];
            if (unlockedCharacterPortraits[character] != null)
                playerSlotPortraits[i] = AddFramedPortrait((RectTransform)playerSlotLabels[i].transform.parent, unlockedCharacterPortraits[character], SlotPortraitMin, SlotPortraitMax);
        }
        if (playerSlotPortraits[0] != null)
            selectedPlayerPortrait = playerSlotPortraits[0];
        RefreshCharacterSelection();

        Button inputModeButton = AddButton(root, InputModeLabels[(int)inputMode], new Vector2(.755f, .43f), new Vector2(.97f, .60f), BomButtonStyle.Blue, CycleInputMode, 26);
        inputModeButton.navigation = new Navigation { mode = Navigation.Mode.None };
        inputModeLabel = inputModeButton.GetComponentInChildren<TextMeshProUGUI>();
        startButton = AddButton(root, "LET'S GO!", new Vector2(.755f, .205f), new Vector2(.97f, .405f), BomButtonStyle.Orange, StartGame, 48);
        startButton.navigation = new Navigation { mode = Navigation.Mode.None };
        Button backButton = AddButton(root, "GO BACK", new Vector2(.755f, .07f), new Vector2(.97f, .18f), BomButtonStyle.Yellow, GoBack, 36);
        backButton.navigation = new Navigation { mode = Navigation.Mode.None };
        CreatePlayerCursors(root);
        RefreshRosterForInputMode();
    }

    // A chalk title bar that sits on the panel's top edge. It is sized to its
    // words, so the chalk art keeps roughly the shape it was drawn at.
    internal static TextMeshProUGUI AddHeaderBar(RectTransform parent, string label, BomButtonStyle style, float fontSize = HeaderFontSize)
    {
        RectTransform bar = AddImage(parent, label + " Header", new Vector2(.5f, 1f), new Vector2(.5f, 1f));
        Image image = bar.GetComponent<Image>();
        image.raycastTarget = false;
        bar.pivot = new Vector2(.5f, 1f);
        bar.anchoredPosition = new Vector2(0f, 18f);
        TextMeshProUGUI text = AddText(bar, label, Vector2.zero, Vector2.one, fontSize, Color.white, FontStyles.Bold);
        float textWidth = text.GetPreferredValues(label, float.PositiveInfinity, float.PositiveInfinity).x;
        bar.sizeDelta = new Vector2(Mathf.Max(HeaderMinWidth, textWidth + HeaderSidePadding * 2f), HeaderHeight);
        BomUiSkin.ApplyHeader(image, style);
        return text;
    }

    private void StartGame()
    {
        if (!isTransitioning && CanStartMatch())
        {
            GameAudio.PlayCheerVoice();
            StartCoroutine(FadeToScene(LevelSceneNames[selectedLevel]));
        }
    }

    private bool CanStartMatch()
    {
        if (inputMode != MatchInputMode.AllControllers)
            return true;

        return matchPlayerCount > 0 && playerGamepadDeviceIds[0] >= 0;
    }

    private void CycleInputMode()
    {
        inputMode = (MatchInputMode)(((int)inputMode + 1) % InputModeLabels.Length);
        if (inputMode != MatchInputMode.AllControllers)
        {
            for (int i = inputMode == MatchInputMode.SharedKeyboard ? 2 : 1; i < MaxLocalPlayers; i++)
                playerGamepadDeviceIds[i] = -1;
            matchPlayerCount = inputMode == MatchInputMode.SharedKeyboard ? 2 : 1;
        }
        if (inputModeLabel != null)
            inputModeLabel.text = InputModeLabels[(int)inputMode];
        RefreshRosterForInputMode();
    }

    private void RefreshRosterForInputMode()
    {
        if (inputMode == MatchInputMode.AllControllers)
        {
            for (int i = 0; i < MaxLocalPlayers; i++)
            {
                if (playerGamepadDeviceIds[i] >= 0 && FindGamepad(playerGamepadDeviceIds[i]) == null)
                    playerGamepadDeviceIds[i] = -1;
            }
            foreach (Gamepad gamepad in Gamepad.all)
            {
                bool alreadyAssigned = false;
                for (int i = 0; i < MaxLocalPlayers; i++)
                    alreadyAssigned |= playerGamepadDeviceIds[i] == gamepad.deviceId;
                if (alreadyAssigned)
                    continue;
                for (int i = 0; i < MaxLocalPlayers; i++)
                {
                    if (playerGamepadDeviceIds[i] >= 0)
                        continue;
                    playerGamepadDeviceIds[i] = gamepad.deviceId;
                    break;
                }
            }
            matchPlayerCount = 0;
            for (int i = 0; i < MaxLocalPlayers; i++)
            {
                if (playerGamepadDeviceIds[i] < 0)
                    break;
                matchPlayerCount++;
            }
        }
        else
        {
            int minimumPlayers = inputMode == MatchInputMode.SharedKeyboard ? 2 : 1;
            matchPlayerCount = Mathf.Max(minimumPlayers, matchPlayerCount);
            for (int i = 0; i < MaxLocalPlayers; i++)
            {
                if (i < minimumPlayers)
                    playerGamepadDeviceIds[i] = -1;
                else if (playerGamepadDeviceIds[i] >= 0 && FindGamepad(playerGamepadDeviceIds[i]) == null)
                    playerGamepadDeviceIds[i] = -1;
            }

            while (matchPlayerCount > minimumPlayers && playerGamepadDeviceIds[matchPlayerCount - 1] < 0)
                matchPlayerCount--;
        }

        RefreshPlayerSlots();
        if (startButton != null)
            startButton.interactable = CanStartMatch();
    }

    private static Gamepad FindGamepad(int deviceId)
    {
        foreach (Gamepad gamepad in Gamepad.all)
            if (gamepad.deviceId == deviceId)
                return gamepad;
        return null;
    }

    private void RefreshPlayerSlots()
    {
        if (playerSlotLabels == null)
            return;

        for (int i = 0; i < MaxLocalPlayers; i++)
        {
            bool active = i < matchPlayerCount
                && (inputMode != MatchInputMode.AllControllers || playerGamepadDeviceIds[i] >= 0);
            if (playerSlotLabels[i] != null)
            {
                playerSlotLabels[i].text = active
                    ? "PLAYER " + (i + 1) + "\n" + shopCharacterNames[Mathf.Clamp(playerCharacters[i], 0, CharacterCount - 1)]
                    : "PLAYER " + (i + 1) + "\n" + (inputMode == MatchInputMode.AllControllers ? "WAITING FOR CONTROLLER" : "PRESS X TO JOIN");
                SetPlayerSlotLabelLayout(playerSlotLabels[i], active);
            }
            if (active)
                UpdatePlayerSlot(i);
            if (playerSlotPortraits != null && playerSlotPortraits[i] != null)
                playerSlotPortraits[i].gameObject.SetActive(active);
            if (playerCursors != null && playerCursors[i] != null)
                playerCursors[i].gameObject.SetActive(active);
        }
    }

    private void PlayFromShop()
    {
        if (isTransitioning) return;
        ResetMatchRoster();
        isTransitioning = true;
        if (shopCanvasObject != null) Destroy(shopCanvasObject);
        shopCanvasObject = null;
        shopMenuOpen = false;
        ClearPortraits();
        StartCoroutine(MoveCameraToSetup());
    }

    private void BuildShopScreen()
    {
        if (shopCanvasObject != null) Destroy(shopCanvasObject);
        ClearPortraits();
        unlockedCharacterPortraits = new RenderTexture[CharacterCount];
        for (int i = 0; i < CharacterCount; i++)
            if (ownedCharacters[i]) unlockedCharacterPortraits[i] = CreateCharacterPortrait(characterColors[i], false);
        shopLockedPortrait = CreateCharacterPortrait(Color.black, true);

        shopCanvasObject = new GameObject("Character Shop Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        Canvas canvas = shopCanvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 60;
        CanvasScaler scaler = shopCanvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = .5f;

        RectTransform root = shopCanvasObject.GetComponent<RectTransform>();
        root.anchorMin = Vector2.zero;
        root.anchorMax = Vector2.one;
        root.offsetMin = Vector2.zero;
        root.offsetMax = Vector2.zero;

        RectTransform collection = AddPanel(root, "Character Collection", new Vector2(.035f, .14f), new Vector2(.59f, .87f));
        AddHeaderBar(collection, "CHARACTER SHOP", BomButtonStyle.Orange);
        shopCardPortraits = new RawImage[CharacterCount];
        shopCardOutlines = new Outline[CharacterCount];
        shopCardLockedLabels = new TextMeshProUGUI[CharacterCount];
        shopCardBackgrounds = new Image[CharacterCount];
        for (int i = 0; i < CharacterCount; i++)
        {
            int index = i;
            int col = i % 5;
            int row = i / 5;
            float xMin = .0945f + col * .167f;
            float yMax = .78f - row * .21f;
            RectTransform card = AddPanel(collection, "Shop Character " + (i + 1), new Vector2(xMin, yMax - .19f), new Vector2(xMin + .143f, yMax), Color.white);
            shopCardBackgrounds[i] = card.GetComponent<Image>();
            Button cardButton = AddButton(card, string.Empty, Vector2.zero, Vector2.one, new Color(1f, 1f, 1f, .01f), () => SelectShopCharacter(index), 18, Color.white);
            shopCardPortraits[i] = AddFramedPortrait(card, ownedCharacters[i] ? unlockedCharacterPortraits[i] : shopLockedPortrait, Vector2.zero, Vector2.one);
            if (!ownedCharacters[i])
                shopCardLockedLabels[i] = AddText(card, "LOCKED", new Vector2(.04f, .04f), new Vector2(.96f, .28f), 22, Color.white, FontStyles.Bold);
            SetShopCardBackground(i);
            shopCardOutlines[i] = card.gameObject.AddComponent<Outline>();
            shopCardOutlines[i].effectColor = ownedCharacters[i] ? characterColors[i] : new Color(.67f, .62f, .72f);
            shopCardOutlines[i].effectDistance = new Vector2(5f, -5f);
            shopCardOutlines[i].enabled = false;
            cardButton.navigation = new Navigation { mode = Navigation.Mode.None };
        }

        RectTransform balancePanel = AddPanel(root, "Coin Balance", new Vector2(.62f, .89f), new Vector2(.92f, .98f));
        shopBalanceText = AddCoinBalance(balancePanel);

        RectTransform detail = AddPanel(root, "Character Details", new Vector2(.62f, .18f), new Vector2(.92f, .85f));
        shopNameText = AddText(detail, string.Empty, new Vector2(.05f, .82f), new Vector2(.95f, .975f), 58, Color.white, FontStyles.Bold);
        shopDetailPortrait = AddFramedPortrait(detail, null, new Vector2(.08f, .19f), new Vector2(.92f, .82f), 0f, 44);
        shopPurchaseButton = AddButton(detail, "BUY", new Vector2(.08f, .04f), new Vector2(.92f, .17f), BomButtonStyle.Orange, PurchaseSelectedCharacter, 32);
        shopPurchaseText = shopPurchaseButton.GetComponentInChildren<TextMeshProUGUI>();

        AddButton(root, "GO BACK", new Vector2(.62f, .045f), new Vector2(.76f, .15f), BomButtonStyle.Yellow, GoBackFromShop, 30);
        AddButton(root, "PLAY", new Vector2(.78f, .045f), new Vector2(.92f, .15f), BomButtonStyle.Orange, PlayFromShop, 32);
        shopSelectedCharacter = Mathf.Clamp(selectedCharacter, 0, CharacterCount - 1);
        RefreshShopSelection();
    }

    // The coin model's picture beside the number of coins, centred together.
    private TextMeshProUGUI AddCoinBalance(RectTransform panel)
    {
        RectTransform row = AddRect(panel, "Coin Balance Row", Vector2.zero, Vector2.one);
        HorizontalLayoutGroup layout = row.gameObject.AddComponent<HorizontalLayoutGroup>();
        layout.padding = new RectOffset(20, 20, 6, 6);
        layout.spacing = 14f;
        layout.childAlignment = TextAnchor.MiddleCenter;
        layout.childControlWidth = true;
        layout.childControlHeight = true;
        layout.childForceExpandWidth = false;
        layout.childForceExpandHeight = false;

        RenderTexture coinPicture = ModelSnapshot.Render(BomMenuArt.CoinPrefab, 128, null, ModelSnapshot.Framing.Whole, faceCamera: true);
        if (coinPicture != null)
        {
            coinPicture.name = "Coin Balance Icon";
            portraitTextures.Add(coinPicture);
            RawImage coin = new GameObject("Coin Icon", typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage), typeof(LayoutElement)).GetComponent<RawImage>();
            coin.rectTransform.SetParent(row, false);
            coin.texture = coinPicture;
            coin.raycastTarget = false;
            LayoutElement size = coin.GetComponent<LayoutElement>();
            size.preferredWidth = 66f;
            size.preferredHeight = 66f;
        }

        TextMeshProUGUI amount = AddText(row, shopCoins.ToString(), Vector2.zero, Vector2.one, 46, Color.white, FontStyles.Bold);
        amount.enableAutoSizing = false;
        return amount;
    }

    private void SelectShopCharacter(int index)
    {
        shopSelectedCharacter = index;
        if (ownedCharacters[index]) selectedCharacter = index;
        RefreshShopSelection();
    }

    private void RefreshShopSelection()
    {
        if (shopCardOutlines == null) return;
        for (int i = 0; i < shopCardOutlines.Length; i++)
        {
            shopCardOutlines[i].enabled = i == shopSelectedCharacter;
            if (shopCardLockedLabels != null && shopCardLockedLabels[i] != null)
                shopCardLockedLabels[i].gameObject.SetActive(!ownedCharacters[i]);
            if (shopCardBackgrounds != null && shopCardBackgrounds[i] != null)
                SetShopCardBackground(i);
        }

        bool owned = ownedCharacters[shopSelectedCharacter];
        int characterPrice = GetCharacterPrice(shopSelectedCharacter);
        shopNameText.text = owned ? shopCharacterNames[shopSelectedCharacter] : "Unknown";
        shopDetailPortrait.texture = owned ? unlockedCharacterPortraits[shopSelectedCharacter] : shopLockedPortrait;
        shopPurchaseText.text = owned ? "OWNED" : "BUY  •  " + characterPrice + " COINS";
        shopPurchaseButton.interactable = !owned && shopCoins >= characterPrice;
        shopBalanceText.text = shopCoins.ToString();
    }

    private void PurchaseSelectedCharacter()
    {
        int characterPrice = GetCharacterPrice(shopSelectedCharacter);
        if (ownedCharacters[shopSelectedCharacter] || shopCoins < characterPrice) return;
        shopCoins -= characterPrice;
        ownedCharacters[shopSelectedCharacter] = true;
        GameAudio.PlayPurchase();
        PlayerPrefs.SetInt(ShopCoinsKey, shopCoins);
        PlayerPrefs.SetInt(ShopOwnedKeyPrefix + shopSelectedCharacter, 1);
        PlayerPrefs.Save();
        selectedCharacter = shopSelectedCharacter;
        unlockedCharacterPortraits[shopSelectedCharacter] = CreateCharacterPortrait(characterColors[shopSelectedCharacter], false);
        shopCardPortraits[shopSelectedCharacter].texture = unlockedCharacterPortraits[shopSelectedCharacter];
        if (shopCardLockedLabels[shopSelectedCharacter] != null)
        {
            Destroy(shopCardLockedLabels[shopSelectedCharacter].gameObject);
            shopCardLockedLabels[shopSelectedCharacter] = null;
        }
        SetShopCardBackground(shopSelectedCharacter);
        RefreshShopSelection();
    }

    private static int GetCharacterPrice(int characterIndex)
    {
        if (characterIndex < 5)
            return FirstRowCharacterPrice;
        if (characterIndex < 10)
            return SecondRowCharacterPrice;
        return LastRowCharacterPrice;
    }

    private void SetShopCardBackground(int index)
    {
        Image background = shopCardBackgrounds[index];
        if (background == null) return;
        // Tints the card's chalk panel: a wash of the character's colour, or grey while locked.
        background.color = ownedCharacters[index]
            ? Color.Lerp(characterColors[index], Color.white, .45f)
            : new Color(.55f, .55f, .6f);
    }

    private void LoadShopProgress()
    {
        shopCoins = PlayerPrefs.GetInt(ShopCoinsKey, shopCoins);
        for (int i = 0; i < CharacterCount; i++)
            ownedCharacters[i] = PlayerPrefs.GetInt(ShopOwnedKeyPrefix + i, ownedCharacters[i] ? 1 : 0) != 0;
    }

    private void GoBackFromShop()
    {
        if (!isTransitioning)
            StartCoroutine(ReturnToMainMenu());
    }

    private void GoBack()
    {
        if (SceneManager.GetActiveScene().name == "MainMenuScene")
        {
            if (!isTransitioning)
                StartCoroutine(ReturnToMainMenu());
        }
        else
        {
            SceneManager.LoadScene("MainMenuScene");
        }
    }

    // A chalk panel (BomPanel) stretched over the anchors.
    internal static RectTransform AddPanel(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax)
    {
        return AddPanel(parent, objectName, anchorMin, anchorMax, Color.white);
    }

    // A chalk panel tinted by the colour given (white shows the art as drawn).
    internal static RectTransform AddPanel(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax, Color tint)
    {
        RectTransform rect = AddImage(parent, objectName, anchorMin, anchorMax);
        BomUiSkin.ApplyPanel(rect.GetComponent<Image>(), tint);
        return rect;
    }

    private static RectTransform AddImage(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax)
    {
        GameObject panel = new GameObject(objectName, typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        RectTransform rect = panel.GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        return rect;
    }

    // A slider in the chalk look: a dark chalk track, an orange chalk fill,
    // and a yellow chalk knob.
    internal static Slider AddChalkSlider(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax)
    {
        const float KnobWidth = 46f;
        RectTransform sliderRect = AddRect(parent, objectName, anchorMin, anchorMax);
        Slider slider = sliderRect.gameObject.AddComponent<Slider>();

        // The track also catches clicks, so pressing anywhere along it jumps there.
        RectTransform track = AddPanel(sliderRect, "Track", Vector2.zero, Vector2.one, new Color(.85f, .85f, .85f));

        // Fill and knob travel the same span, so the fill always ends under
        // the knob's middle; the fill reaches back to the track's left edge.
        RectTransform fillArea = AddRect(sliderRect, "Fill Area", Vector2.zero, Vector2.one);
        fillArea.offsetMin = new Vector2(KnobWidth * .5f, 9f);
        fillArea.offsetMax = new Vector2(-KnobWidth * .5f, -9f);
        RectTransform fill = AddImage(fillArea, "Fill", Vector2.zero, Vector2.one);
        fill.offsetMin = new Vector2(-KnobWidth * .5f + 7f, 0f);
        BomUiSkin.ApplyButton(fill.GetComponent<Image>(), BomButtonStyle.Orange);
        fill.GetComponent<Image>().raycastTarget = false;

        RectTransform handleArea = AddRect(sliderRect, "Handle Slide Area", Vector2.zero, Vector2.one);
        handleArea.offsetMin = new Vector2(KnobWidth * .5f, 0f);
        handleArea.offsetMax = new Vector2(-KnobWidth * .5f, 0f);
        RectTransform handle = AddImage(handleArea, "Knob", Vector2.zero, Vector2.one);
        // Wider than the track is tall, and poking out above and below it.
        handle.sizeDelta = new Vector2(KnobWidth, 14f);
        Image knob = handle.GetComponent<Image>();
        BomUiSkin.ApplyButton(knob, BomButtonStyle.Yellow);

        slider.fillRect = fill;
        slider.handleRect = handle;
        slider.targetGraphic = knob;
        slider.direction = Slider.Direction.LeftToRight;
        SetChalkButtonColors(slider);
        return slider;
    }

    // An empty box stretched over the anchors, for grouping.
    internal static RectTransform AddRect(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax)
    {
        RectTransform rect = new GameObject(objectName, typeof(RectTransform)).GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        return rect;
    }

    // A picture with no frame: it fills the area given (cropping to keep its
    // shape) and its edges fade softly into whatever is behind it. Set the
    // aspect's ratio to the texture's when the texture changes.
    internal static RawImage AddFadedPicture(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax, out AspectRatioFitter aspect)
    {
        RectTransform mask = AddRect(parent, objectName + " Mask", anchorMin, anchorMax);
        mask.gameObject.AddComponent<RectMask2D>().softness = new Vector2Int(PictureFadeSides, PictureFadeTopBottom);
        GameObject pictureObject = new GameObject(objectName, typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage), typeof(AspectRatioFitter));
        RectTransform picture = pictureObject.GetComponent<RectTransform>();
        picture.SetParent(mask, false);
        picture.anchorMin = Vector2.zero;
        picture.anchorMax = Vector2.one;
        picture.offsetMin = Vector2.zero;
        picture.offsetMax = Vector2.zero;
        RawImage image = pictureObject.GetComponent<RawImage>();
        image.raycastTarget = false;
        aspect = pictureObject.GetComponent<AspectRatioFitter>();
        aspect.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
        aspect.aspectRatio = 16f / 9f;
        return image;
    }

    // A chalk name tag, centred, that grows and shrinks to fit its words.
    // yMin / yMax set its height within the parent.
    internal static TextMeshProUGUI AddNameTag(RectTransform parent, string value, float yMin, float yMax, float fontSize)
    {
        RectTransform tag = AddPanel(parent, "Name Tag", new Vector2(.5f, yMin), new Vector2(.5f, yMax));
        HorizontalLayoutGroup layout = tag.gameObject.AddComponent<HorizontalLayoutGroup>();
        layout.padding = new RectOffset(34, 34, 2, 2);
        layout.childAlignment = TextAnchor.MiddleCenter;
        layout.childControlWidth = true;
        layout.childControlHeight = true;
        layout.childForceExpandWidth = false;
        layout.childForceExpandHeight = true;
        tag.gameObject.AddComponent<ContentSizeFitter>().horizontalFit = ContentSizeFitter.FitMode.PreferredSize;
        TextMeshProUGUI text = AddText(tag, value, Vector2.zero, Vector2.one, fontSize, Color.white, FontStyles.Bold);
        // A fixed size, so the tag's width follows the words.
        text.enableAutoSizing = false;
        return text;
    }

    // background, if given, puts a chalk panel tinted that colour behind the text.
    internal static TextMeshProUGUI AddText(RectTransform parent, string value, Vector2 anchorMin, Vector2 anchorMax, float size, Color color, FontStyles style, Color? background = null)
    {
        RectTransform rect;
        if (background.HasValue)
            rect = AddPanel(parent, value.Replace("\n", " ") + " Background", anchorMin, anchorMax, background.Value);
        else
        {
            GameObject textObject = new GameObject(value.Replace("\n", " "), typeof(RectTransform), typeof(CanvasRenderer), typeof(TextMeshProUGUI));
            rect = textObject.GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            rect.anchorMin = anchorMin;
            rect.anchorMax = anchorMax;
            rect.offsetMin = new Vector2(6, 4);
            rect.offsetMax = new Vector2(-6, -4);
        }

        TextMeshProUGUI text = rect.GetComponent<TextMeshProUGUI>();
        if (text == null)
        {
            GameObject textObject = new GameObject(value.Replace("\n", " "), typeof(RectTransform), typeof(CanvasRenderer), typeof(TextMeshProUGUI));
            RectTransform textRect = textObject.GetComponent<RectTransform>();
            textRect.SetParent(rect, false);
            textRect.anchorMin = Vector2.zero;
            textRect.anchorMax = Vector2.one;
            textRect.offsetMin = new Vector2(12, 6);
            textRect.offsetMax = new Vector2(-12, -6);
            text = textObject.GetComponent<TextMeshProUGUI>();
        }
        // White and outlined; color only differs for the odd warning or placeholder.
        BomUiSkin.StyleText(text);
        text.text = value;
        text.fontSize = size;
        text.fontStyle = style;
        text.color = color;
        text.alignment = TextAlignmentOptions.Center;
        text.enableAutoSizing = true;
        text.fontSizeMin = size * .55f;
        text.fontSizeMax = size;
        text.raycastTarget = false;
        return text;
    }

    internal static Button AddButton(RectTransform parent, string label, Vector2 anchorMin, Vector2 anchorMax, Color color, UnityEngine.Events.UnityAction action, float fontSize, Color textColor)
    {
        GameObject buttonObject = new GameObject(label.Replace("\n", " ") + " Button", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image), typeof(Button));
        RectTransform rect = buttonObject.GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        Image image = buttonObject.GetComponent<Image>();
        image.color = color;
        Button button = buttonObject.GetComponent<Button>();
        button.targetGraphic = image;
        button.onClick.AddListener(action);
        GameAudio.RegisterButton(button);
        ColorBlock colors = button.colors;
        colors.highlightedColor = Color.Lerp(color, Color.white, .16f);
        colors.pressedColor = Color.Lerp(color, Color.black, .12f);
        button.colors = colors;
        if (!string.IsNullOrEmpty(label))
            AddText(rect, label, Vector2.zero, Vector2.one, fontSize, textColor, FontStyles.Bold);
        return button;
    }

    // A chalk button (BomButton_orange / _yellow / _blue) with a label.
    internal static Button AddButton(RectTransform parent, string label, Vector2 anchorMin, Vector2 anchorMax, BomButtonStyle style, UnityEngine.Events.UnityAction action, float fontSize)
    {
        Button button = AddButton(parent, label, anchorMin, anchorMax, Color.white, action, fontSize, BomUiSkin.TextColor);
        Image image = (Image)button.targetGraphic;
        BomUiSkin.ApplyButton(image, style);
        // The art is already coloured, so the states only brighten or darken it.
        image.color = Color.white;
        SetChalkButtonColors(button);
        AddHover(button);
        TextMeshProUGUI text = button.GetComponentInChildren<TextMeshProUGUI>();
        if (text != null)
        {
            // Keep the words inside the button's fuzzy chalk edge.
            text.rectTransform.offsetMin = new Vector2(18f, 8f);
            text.rectTransform.offsetMax = new Vector2(-18f, -8f);
        }
        return button;
    }

    // A chalk arrow button (BomArrow_left / _right), used to flip between levels.
    internal static Button AddArrowButton(RectTransform parent, bool left, Vector2 anchorMin, Vector2 anchorMax, UnityEngine.Events.UnityAction action)
    {
        // A soft black copy behind the arrow, a little larger and dropped
        // down-right, so the pale chalk stands out on bright level pictures.
        RectTransform shadow = AddImage(parent, left ? "Previous Arrow Shadow" : "Next Arrow Shadow", anchorMin, anchorMax);
        Image shadowImage = shadow.GetComponent<Image>();
        shadowImage.sprite = left ? BomUiSkin.ArrowLeft : BomUiSkin.ArrowRight;
        shadowImage.preserveAspect = true;
        shadowImage.color = new Color(0f, 0f, 0f, .7f);
        shadowImage.raycastTarget = false;
        shadow.anchoredPosition = new Vector2(4f, -6f);
        shadow.localScale = new Vector3(1.14f, 1.14f, 1f);

        RectTransform rect = AddImage(parent, left ? "Previous Arrow Button" : "Next Arrow Button", anchorMin, anchorMax);
        Image image = rect.GetComponent<Image>();
        image.sprite = left ? BomUiSkin.ArrowLeft : BomUiSkin.ArrowRight;
        image.preserveAspect = true;
        image.color = Color.white;
        Button button = rect.gameObject.AddComponent<Button>();
        button.targetGraphic = image;
        button.onClick.AddListener(action);
        button.navigation = new Navigation { mode = Navigation.Mode.None };
        GameAudio.RegisterButton(button);
        SetChalkButtonColors(button, .78f);
        AddHover(button);
        return button;
    }

    // Chalk buttons sit noticeably darker until the pointer or cursor is on
    // them, then light up to the art's full colour. Selected counts as lit,
    // since that is how the controller cursor highlights a button.
    // resting sets how dark an idle button is (1 = no darkening).
    private static void SetChalkButtonColors(Selectable button, float resting = ButtonRestingShade)
    {
        ColorBlock colors = button.colors;
        colors.normalColor = new Color(resting, resting, resting);
        colors.highlightedColor = Color.white;
        colors.selectedColor = Color.white;
        colors.pressedColor = new Color(resting * .8f, resting * .8f, resting * .8f);
        colors.disabledColor = new Color(.4f, .4f, .4f, .6f);
        colors.fadeDuration = .08f;
        button.colors = colors;
    }

    private void ChangeLevel(int direction)
    {
        selectedLevel = (selectedLevel + direction + LevelSceneNames.Length) % LevelSceneNames.Length;
        if (levelName != null)
            levelName.text = LevelNames[selectedLevel];
        RefreshLevelPreview();
    }

    private void RefreshLevelPreview()
    {
        if (levelPreviewImage == null)
            return;

        Texture2D previewTexture = selectedLevel == 0
            ? yardLevelPreviewTexture
            : selectedLevel == 1 ? bridgeLevelPreviewTexture : towerLevelPreviewTexture;
        levelPreviewImage.texture = previewTexture;
        levelPreviewImage.gameObject.SetActive(previewTexture != null);
        if (previewTexture != null && levelPreviewAspect != null)
            levelPreviewAspect.aspectRatio = (float)previewTexture.width / previewTexture.height;
    }

    private void SelectCharacter(int index) => SelectCharacterForPlayer(0, index);

    private void SelectCharacterForPlayer(int playerIndex, int characterIndex)
    {
        if (playerIndex < 0 || playerIndex >= MaxLocalPlayers
            || characterIndex < 0 || characterIndex >= CharacterCount
            || !ownedCharacters[characterIndex])
            return;

        activeCharacterPlayer = playerIndex;
        playerCharacterCursors[playerIndex] = characterIndex;
        playerCharacters[playerIndex] = characterIndex;
        if (playerSlotLabels != null && playerIndex < playerSlotLabels.Length && playerSlotLabels[playerIndex] != null)
            playerSlotLabels[playerIndex].text = "PLAYER " + (playerIndex + 1) + "\n" + shopCharacterNames[characterIndex];
        if (playerSlotPortraits != null && playerIndex < playerSlotPortraits.Length && playerSlotPortraits[playerIndex] != null)
            playerSlotPortraits[playerIndex].texture = unlockedCharacterPortraits[characterIndex];
        UpdatePlayerSlot(playerIndex);
        if (playerIndex == 0)
        {
            selectedCharacter = characterIndex;
            selectedPlayerPortrait = playerSlotPortraits != null ? playerSlotPortraits[0] : null;
        }
        RefreshCharacterSelection();
    }

    private void CreatePlayerCursors(RectTransform root)
    {
        for (int i = 0; i < MaxLocalPlayers; i++)
        {
            GameObject cursorObject = new GameObject("P" + (i + 1) + " Cursor", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
            cursorObject.transform.SetParent(root, false);
            RectTransform cursor = cursorObject.GetComponent<RectTransform>();
            cursor.sizeDelta = new Vector2(72f, 72f);
            Image image = cursorObject.GetComponent<Image>();
            image.sprite = MenuCursor.RingSprite;
            image.color = characterColors[i];
            image.raycastTarget = false;
            TextMeshProUGUI label = AddText(cursor, "P" + (i + 1), Vector2.zero, Vector2.one, 22f, Color.white, FontStyles.Bold);
            label.raycastTarget = false;
            playerCursors[i] = cursor;
            PositionCursorAtCharacter(i);
        }
    }

    private void PositionCursorAtCharacter(int playerIndex)
    {
        if (playerCursors == null || characterButtons == null || playerCursors[playerIndex] == null)
            return;

        int character = Mathf.Clamp(playerCharacterCursors[playerIndex], 0, CharacterCount - 1);
        RectTransform tile = characterButtons[character].transform.parent as RectTransform;
        if (tile == null)
            return;
        Vector3[] corners = new Vector3[4];
        tile.GetWorldCorners(corners);
        playerCursors[playerIndex].position = (corners[0] + corners[2]) * .5f;
    }

    private void UpdateMouseCursor()
    {
        if (inputMode == MatchInputMode.AllControllers || Mouse.current == null || playerCursors == null)
            return;

        Vector2 position = Mouse.current.position.ReadValue();
        playerCursors[0].position = position;
        playerCursors[0].gameObject.SetActive(true);
        int hoveredCharacter = FindCharacterAtScreenPosition(position);
        if (hoveredCharacter >= 0)
        {
            playerCharacterCursors[0] = hoveredCharacter;
            activeCharacterPlayer = 0;
            RefreshCharacterSelection();
            if (Mouse.current.leftButton.wasPressedThisFrame)
                SelectCharacterForPlayer(0, hoveredCharacter);
        }
    }

    private void UpdateGamepadCursor(int playerIndex, Vector2 stick)
    {
        if (playerCursors == null || playerCursors[playerIndex] == null)
            return;
        if (stick.sqrMagnitude > .01f)
        {
            Vector3 position = playerCursors[playerIndex].position;
            position += (Vector3)(stick * (520f * Time.unscaledDeltaTime));
            position.x = Mathf.Clamp(position.x, 0f, Screen.width);
            position.y = Mathf.Clamp(position.y, 0f, Screen.height);
            playerCursors[playerIndex].position = position;
            int hoveredCharacter = FindCharacterAtScreenPosition(position);
            if (hoveredCharacter >= 0)
            {
                playerCharacterCursors[playerIndex] = hoveredCharacter;
                activeCharacterPlayer = playerIndex;
                RefreshCharacterSelection();
            }
        }
    }

    private int FindCharacterAtScreenPosition(Vector2 screenPosition)
    {
        if (characterButtons == null)
            return -1;
        for (int i = 0; i < characterButtons.Length; i++)
        {
            if (!ownedCharacters[i])
                continue;
            RectTransform tile = characterButtons[i].transform.parent as RectTransform;
            if (tile == null)
                continue;
            if (RectTransformUtility.RectangleContainsScreenPoint(tile, screenPosition, null))
                return i;
        }
        return -1;
    }

    private bool IsCursorOverButton(int playerIndex, Button button)
    {
        if (button == null || playerCursors == null || playerIndex < 0 || playerIndex >= playerCursors.Length
            || playerCursors[playerIndex] == null || !button.interactable)
            return false;

        return RectTransformUtility.RectangleContainsScreenPoint(
            button.GetComponent<RectTransform>(),
            playerCursors[playerIndex].position,
            null);
    }

    // True when the player's cursor is over a setup button other than a character tile.
    private bool IsCursorOverMenuButton(int playerIndex)
    {
        if (setupCanvasObject == null || playerCursors == null || playerCursors[playerIndex] == null)
            return false;
        Vector2 point = playerCursors[playerIndex].position;
        foreach (Button button in setupCanvasObject.GetComponentsInChildren<Button>())
        {
            if (System.Array.IndexOf(characterButtons, button) >= 0) continue;
            if (IsCursorOverButton(playerIndex, button)) return true;
        }
        return false;
    }

    private void UpdateSetupInput()
    {
        UpdateMouseCursor();
        foreach (Gamepad gamepad in Gamepad.all)
        {
            int playerIndex = FindPlayerForGamepad(gamepad);
            if (playerIndex < 0)
            {
                if (inputMode != MatchInputMode.AllControllers && gamepad.buttonSouth.wasPressedThisFrame)
                    JoinNextPlayer(gamepad);
                continue;
            }

            Vector2 navigation = gamepad.dpad.ReadValue();
            Vector2 stick = gamepad.leftStick.ReadValue();
            if (inputMode == MatchInputMode.SharedKeyboard && playerIndex == 1
                && navigation.sqrMagnitude > 0.36f && Time.unscaledTime >= nextPlayerNavigationTime[playerIndex])
            {
                MoveCharacterCursor(playerIndex, navigation);
                nextPlayerNavigationTime[playerIndex] = Time.unscaledTime + 0.22f;
            }
            else
            {
                UpdateGamepadCursor(playerIndex, stick);
            }

            if (playerIndex == 0 && gamepad.leftShoulder.wasPressedThisFrame) ChangeLevel(-1);
            if (playerIndex == 0 && gamepad.rightShoulder.wasPressedThisFrame) ChangeLevel(1);

            if (gamepad.buttonSouth.wasPressedThisFrame)
            {
                // Only Player 1 can press the screen's buttons (level arrows,
                // mode, start, back). Everyone else picks characters.
                if (playerIndex == 0 && IsCursorOverMenuButton(0))
                    MenuCursor.ClickAt(playerCursors[0].position);
                else
                    SelectCharacterForPlayer(playerIndex, playerCharacterCursors[playerIndex]);
            }

            if (playerIndex == 0 && gamepad.startButton.wasPressedThisFrame)
                StartGame();
        }

        if (playerSlotLabels != null && playerSlotLabels.Length > 0)
        {
            Vector2 keyboardNavigation = Vector2.zero;
            Keyboard keyboard = Keyboard.current;
            if (keyboard != null)
            {
                if (inputMode == MatchInputMode.SharedKeyboard)
                {
                    if (keyboard.leftArrowKey.wasPressedThisFrame) keyboardNavigation.x = -1f;
                    else if (keyboard.rightArrowKey.wasPressedThisFrame) keyboardNavigation.x = 1f;
                    else if (keyboard.upArrowKey.wasPressedThisFrame) keyboardNavigation.y = 1f;
                    else if (keyboard.downArrowKey.wasPressedThisFrame) keyboardNavigation.y = -1f;
                    if (keyboardNavigation != Vector2.zero)
                        MoveCharacterCursor(1, keyboardNavigation);
                    if (keyboard.enterKey.wasPressedThisFrame)
                        SelectCharacterForPlayer(1, playerCharacterCursors[1]);
                }
                else if (inputMode != MatchInputMode.AllControllers)
                {
                    if (keyboard.leftArrowKey.wasPressedThisFrame || keyboard.aKey.wasPressedThisFrame) keyboardNavigation.x = -1f;
                    else if (keyboard.rightArrowKey.wasPressedThisFrame || keyboard.dKey.wasPressedThisFrame) keyboardNavigation.x = 1f;
                    else if (keyboard.upArrowKey.wasPressedThisFrame || keyboard.wKey.wasPressedThisFrame) keyboardNavigation.y = 1f;
                    else if (keyboard.downArrowKey.wasPressedThisFrame || keyboard.sKey.wasPressedThisFrame) keyboardNavigation.y = -1f;
                    if (keyboardNavigation != Vector2.zero)
                        MoveCharacterCursor(0, keyboardNavigation);
                }
            }
        }
    }

    // Player 1's ring on the setup screen lights up and grows the button
    // under it, as the mouse would (only Player 1 can press these).
    private void UpdateSetupButtonHover()
    {
        bool cursorShown = playerCursors != null && playerCursors[0] != null && playerCursors[0].gameObject.activeInHierarchy;
        foreach (BomButtonHover hover in setupCanvasObject.GetComponentsInChildren<BomButtonHover>())
            hover.CursorOver = cursorShown && IsCursorOverButton(0, hover.GetComponent<Button>());
    }

    private int FindPlayerForGamepad(Gamepad gamepad)
    {
        for (int i = 0; i < matchPlayerCount; i++)
            if (playerGamepadDeviceIds[i] == gamepad.deviceId)
                return i;
        return -1;
    }

    private void JoinNextPlayer(Gamepad gamepad)
    {
        int firstControllerSlot = inputMode == MatchInputMode.SharedKeyboard ? 2 : 1;
        int slot = -1;
        for (int i = firstControllerSlot; i < MaxLocalPlayers; i++)
        {
            if (playerGamepadDeviceIds[i] < 0)
            {
                slot = i;
                break;
            }
        }
        if (slot < 0)
            return;
        JoinPlayerWithDevice(slot, gamepad.deviceId);
    }

    private void JoinPlayerWithDevice(int slotIndex, int deviceId)
    {
        if (slotIndex < 0 || slotIndex >= MaxLocalPlayers || playerGamepadDeviceIds[slotIndex] >= 0)
            return;

        playerGamepadDeviceIds[slotIndex] = deviceId;
        matchPlayerCount = Mathf.Max(matchPlayerCount, slotIndex + 1);
        UpdatePlayerSlot(slotIndex);
        RefreshPlayerSlots();
    }

    private void UpdatePlayerSlot(int playerIndex)
    {
        if (playerSlotLabels == null || playerIndex >= playerSlotLabels.Length)
            return;

        int character = Mathf.Clamp(playerCharacters[playerIndex], 0, CharacterCount - 1);
        playerSlotLabels[playerIndex].text = "PLAYER " + (playerIndex + 1) + "\n" + shopCharacterNames[character];
        SetPlayerSlotLabelLayout(playerSlotLabels[playerIndex], true);
        if (unlockedCharacterPortraits != null && unlockedCharacterPortraits[character] != null)
        {
            if (playerSlotPortraits[playerIndex] == null)
            {
                RectTransform slot = (RectTransform)playerSlotLabels[playerIndex].transform.parent;
                playerSlotPortraits[playerIndex] = AddFramedPortrait(slot, unlockedCharacterPortraits[character], SlotPortraitMin, SlotPortraitMax);
            }
            else
            {
                playerSlotPortraits[playerIndex].texture = unlockedCharacterPortraits[character];
            }
        }
    }

    private void SetPlayerSlotLabelLayout(TextMeshProUGUI label, bool active)
    {
        RectTransform rect = label.rectTransform;
        rect.anchorMin = active ? SlotLabelMin : Vector2.zero;
        rect.anchorMax = active ? SlotLabelMax : Vector2.one;
        rect.offsetMin = new Vector2(6f, 4f);
        rect.offsetMax = new Vector2(-6f, -4f);
    }

    private void MoveCharacterCursor(int playerIndex, Vector2 direction)
    {
        int current = playerCharacterCursors[playerIndex];
        int step = Mathf.Abs(direction.x) > Mathf.Abs(direction.y)
            ? (direction.x > 0f ? 1 : -1)
            : (direction.y > 0f ? -1 : 1);
        int candidate = current;
        for (int attempt = 0; attempt < CharacterCount; attempt++)
        {
            candidate = (candidate + step + CharacterCount) % CharacterCount;
            if (ownedCharacters[candidate])
                break;
        }
        playerCharacterCursors[playerIndex] = candidate;
        activeCharacterPlayer = playerIndex;
        PositionCursorAtCharacter(playerIndex);
        RefreshCharacterSelection();
    }

    private void RefreshCharacterSelection()
    {
        if (characterButtons == null) return;
        int focusedCharacter = Mathf.Clamp(playerCharacterCursors[activeCharacterPlayer], 0, CharacterCount - 1);
        for (int i = 0; i < characterButtons.Length; i++)
        {
            if (characterOutlines[i] != null)
            {
                characterOutlines[i].enabled = i == focusedCharacter;
                if (i == focusedCharacter)
                    characterOutlines[i].effectColor = characterColors[Mathf.Clamp(activeCharacterPlayer, 0, characterColors.Length - 1)];
            }
        }
    }

    private RenderTexture CreateCharacterPortrait(Color tint, bool silhouette)
    {
        GameObject prefab = Resources.Load<GameObject>("PlayerPreview");
        if (prefab == null)
        {
            Debug.LogError("PlayerPreview prefab is missing from a Resources folder.");
            return null;
        }

        RenderTexture texture = ModelSnapshot.Render(prefab, 256, silhouette ? Color.black : tint,
            ModelSnapshot.Framing.Head, silhouette);
        if (texture == null) return null;
        texture.name = silhouette ? "Locked Character Silhouette" : "Unlocked Character Portrait " + (portraitTextures.Count + 1);
        portraitTextures.Add(texture);
        return texture;
    }

    private RawImage AddPortrait(RectTransform parent, RenderTexture texture, Vector2 anchorMin, Vector2 anchorMax)
    {
        GameObject portrait = new GameObject("Character Portrait", typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage));
        RectTransform rect = portrait.GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        RawImage image = portrait.GetComponent<RawImage>();
        image.texture = texture;
        image.color = Color.white;
        image.raycastTarget = false;
        AspectRatioFitter aspect = portrait.AddComponent<AspectRatioFitter>();
        aspect.aspectMode = AspectRatioFitter.AspectMode.FitInParent;
        aspect.aspectRatio = 1f;
        return image;
    }

    // A portrait shown inside its card: it sits PortraitInset inside the
    // card's chalk edge, bottom-aligned, and the soft mask fades the model's
    // cut-off body into the card instead of ending in a hard line on the edge.
    private RawImage AddFramedPortrait(RectTransform parent, RenderTexture texture, Vector2 anchorMin, Vector2 anchorMax,
        float inset = PortraitInset, int fade = PortraitFade)
    {
        // Only the mask's bottom edge matters, so the other three are pushed
        // well out of the way and never fade anything.
        const float Far = 2000f;
        RectTransform frame = new GameObject("Portrait Frame", typeof(RectTransform), typeof(RectMask2D)).GetComponent<RectTransform>();
        frame.SetParent(parent, false);
        frame.anchorMin = anchorMin;
        frame.anchorMax = anchorMax;
        frame.offsetMin = new Vector2(-Far, inset);
        frame.offsetMax = new Vector2(Far, Far);
        frame.GetComponent<RectMask2D>().softness = new Vector2Int(0, fade);

        // Back to the area asked for, less the inset on every side.
        RectTransform area = new GameObject("Portrait Area", typeof(RectTransform)).GetComponent<RectTransform>();
        area.SetParent(frame, false);
        area.anchorMin = Vector2.zero;
        area.anchorMax = Vector2.one;
        area.offsetMin = new Vector2(Far + inset, 0f);
        area.offsetMax = new Vector2(-Far - inset, -Far - inset);

        RawImage image = AddPortrait(area, texture, Vector2.zero, Vector2.one);
        image.rectTransform.pivot = new Vector2(.5f, 0f);
        return image;
    }

    private void ClearPortraits()
    {
        foreach (RenderTexture texture in portraitTextures)
        {
            if (texture == null) continue;
            texture.Release();
            Destroy(texture);
        }
        portraitTextures.Clear();
        characterButtons = null;
        characterOutlines = null;
        unlockedCharacterPortraits = null;
        selectedPlayerPortrait = null;
        playerOneSlot = null;
        playerSlotPortraits = null;
        playerSlotLabels = null;
        playerCursors = null;
        inputModeLabel = null;
        startButton = null;
        controllerStatusText = null;
        shopBalanceText = null;
        shopNameText = null;
        shopPurchaseText = null;
        shopDetailPortrait = null;
        shopCardPortraits = null;
        shopCardOutlines = null;
        shopPurchaseButton = null;
        shopLockedPortrait = null;
    }

    private void JoinPlayer(int slotIndex)
    {
        JoinPlayerWithDevice(slotIndex, -1);
    }
}
