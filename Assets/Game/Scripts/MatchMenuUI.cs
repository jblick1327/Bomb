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
    private static Sprite cursorSprite;
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
    private readonly List<GameObject> portraitRigs = new List<GameObject>();
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

    private static readonly string[] LevelNames = { "THE YARD", "THE BRIDGE", "THE TOWER" };
    private static readonly string[] LevelSceneNames = { "YardLevel", "BridgeLevel", "TowerLevel" };
    private const int CharacterCount = 15;
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
            HookShopButton();
            HookSettingsButton();
            HookQuitButton();
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
        if (SceneManager.GetActiveScene().name == "MainMenuScene"
            && !secondaryMenuOpen && !shopMenuOpen && !settingsMenuOpen && !isTransitioning)
        {
            foreach (Gamepad gamepad in Gamepad.all)
            {
                if (gamepad.buttonSouth.wasPressedThisFrame)
                {
                    ResetMatchRoster();
                    if (inputMode == MatchInputMode.AllControllers)
                        playerGamepadDeviceIds[0] = gamepad.deviceId;
                    StartSetupMenu();
                    break;
                }
            }
        }

        if ((secondaryMenuOpen || SceneManager.GetActiveScene().name == "LevelSetupScene")
            && setupCanvasObject != null && !isTransitioning)
        {
            RefreshRosterForInputMode();
            UpdateSetupInput();
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
            return;
        }
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
            shopRect.anchoredPosition = playRect.anchoredPosition + new Vector2(0f, -110f);
            shopButton = shopObject.GetComponent<Button>();
            TMP_Text buttonLabel = shopObject.GetComponentInChildren<TMP_Text>(true);
            if (buttonLabel != null) buttonLabel.text = "SHOP";
            GameAudio.RegisterButton(shopButton);
        }

        if (shopButton != null)
        {
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

        RectTransform panel = AddPanel(root, "Settings Panel", new Vector2(.32f, .25f), new Vector2(.68f, .75f), new Color(.13f, .14f, .22f, .97f));
        AddHeaderBar(panel, "SETTINGS", new Color(.13f, .39f, .83f), .72f, 36);
        AddText(panel, "MASTER VOLUME", new Vector2(.10f, .57f), new Vector2(.90f, .69f), 28, Color.white, FontStyles.Bold);

        GameObject sliderObject = new GameObject("Master Volume Slider", typeof(RectTransform), typeof(Slider));
        RectTransform sliderRect = sliderObject.GetComponent<RectTransform>();
        sliderRect.SetParent(panel, false);
        sliderRect.anchorMin = new Vector2(.12f, .43f);
        sliderRect.anchorMax = new Vector2(.88f, .51f);
        sliderRect.offsetMin = Vector2.zero;
        sliderRect.offsetMax = Vector2.zero;
        GameObject trackObject = new GameObject("Track", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        RectTransform trackRect = trackObject.GetComponent<RectTransform>();
        trackRect.SetParent(sliderRect, false);
        trackRect.anchorMin = new Vector2(0f, .40f);
        trackRect.anchorMax = new Vector2(1f, .60f);
        trackRect.offsetMin = Vector2.zero;
        trackRect.offsetMax = Vector2.zero;
        trackObject.GetComponent<Image>().color = new Color(.28f, .28f, .36f);
        GameObject fillObject = new GameObject("Fill", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        RectTransform fillRect = fillObject.GetComponent<RectTransform>();
        fillRect.SetParent(sliderRect, false);
        fillRect.anchorMin = new Vector2(0f, .40f);
        fillRect.anchorMax = new Vector2(1f, .60f);
        fillRect.offsetMin = Vector2.zero;
        fillRect.offsetMax = Vector2.zero;
        fillObject.GetComponent<Image>().color = new Color(1f, .62f, .09f);
        GameObject handleObject = new GameObject("Handle", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        RectTransform handleRect = handleObject.GetComponent<RectTransform>();
        handleRect.SetParent(sliderRect, false);
        handleRect.sizeDelta = new Vector2(28f, 34f);
        handleObject.GetComponent<Image>().color = new Color(.91f, .82f, .73f);
        Slider volumeSlider = sliderObject.GetComponent<Slider>();
        volumeSlider.fillRect = fillRect;
        volumeSlider.handleRect = handleRect;
        volumeSlider.targetGraphic = handleObject.GetComponent<Image>();
        volumeSlider.minValue = 0f;
        volumeSlider.maxValue = 1f;
        volumeSlider.value = AudioListener.volume;
        volumeSlider.onValueChanged.AddListener(value => AudioListener.volume = value);
        AddButton(panel, "RESTART GAME", new Vector2(.18f, .20f), new Vector2(.82f, .34f), new Color(1f, .62f, .09f), RestartCurrentScene, 25, new Color(.17f, .13f, .16f));
        AddButton(panel, "GO BACK", new Vector2(.28f, .055f), new Vector2(.72f, .17f), new Color(.91f, .82f, .73f), CloseSettingsMenu, 26, new Color(.15f, .16f, .22f));
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

        RectTransform preview = AddPanel(root, "Level Preview Panel", new Vector2(.035f, .665f), new Vector2(.49f, .97f), new Color(.13f, .14f, .22f, .96f));
        AddHeaderBar(preview, "LEVEL PREVIEW", new Color(.13f, .39f, .83f), .72f, 34);
        RectTransform previewWindow = AddPanel(preview, "Preview Window", new Vector2(.055f, .10f), new Vector2(.945f, .76f), new Color(.25f, .34f, .52f));
        previewWindow.gameObject.AddComponent<RectMask2D>();
        if (yardLevelPreviewTexture == null)
            yardLevelPreviewTexture = Resources.Load<Texture2D>("YardLevelPreview");
        if (bridgeLevelPreviewTexture == null)
            bridgeLevelPreviewTexture = Resources.Load<Texture2D>("BridgeLevelPreview");
        if (towerLevelPreviewTexture == null)
            towerLevelPreviewTexture = Resources.Load<Texture2D>("TowerLevelPreview");
        GameObject previewImageObject = new GameObject("Yard Level Preview Image", typeof(RectTransform), typeof(CanvasRenderer), typeof(RawImage), typeof(AspectRatioFitter));
        RectTransform previewImageRect = previewImageObject.GetComponent<RectTransform>();
        previewImageRect.SetParent(previewWindow, false);
        previewImageRect.anchorMin = Vector2.zero;
        previewImageRect.anchorMax = Vector2.one;
        previewImageRect.offsetMin = Vector2.zero;
        previewImageRect.offsetMax = Vector2.zero;
        levelPreviewImage = previewImageObject.GetComponent<RawImage>();
        levelPreviewImage.texture = yardLevelPreviewTexture;
        levelPreviewImage.raycastTarget = false;
        levelPreviewAspect = previewImageObject.GetComponent<AspectRatioFitter>();
        levelPreviewAspect.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
        levelName = AddText(previewWindow, LevelNames[selectedLevel], new Vector2(.08f, .08f), new Vector2(.92f, .25f), 25, Color.white, FontStyles.Bold, new Color(.12f, .13f, .20f, .9f));
        RefreshLevelPreview();
        Button previousLevelButton = AddButton(preview, "‹", new Vector2(.015f, .34f), new Vector2(.15f, .62f), new Color(.91f, .82f, .73f), () => ChangeLevel(-1), 50, new Color(.15f, .16f, .22f));
        previousLevelButton.navigation = new Navigation { mode = Navigation.Mode.None };
        Button nextLevelButton = AddButton(preview, "›", new Vector2(.85f, .34f), new Vector2(.985f, .62f), new Color(.91f, .82f, .73f), () => ChangeLevel(1), 50, new Color(.15f, .16f, .22f));
        nextLevelButton.navigation = new Navigation { mode = Navigation.Mode.None };

        RectTransform players = AddPanel(root, "Players Panel", new Vector2(.525f, .665f), new Vector2(.965f, .97f), new Color(.13f, .14f, .22f, .96f));
        AddHeaderBar(players, "PLAYERS", new Color(.79f, .18f, .22f), .48f, 34);
        controllerStatusText = AddText(players, string.Empty, new Vector2(.035f, .73f), new Vector2(.965f, .83f), 17, new Color(.79f, .84f, .94f), FontStyles.Bold);
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
            RectTransform slot = AddPanel(players, "Player Slot " + (i + 1), new Vector2(xMin, .08f), new Vector2(xMin + .205f, .73f), new Color(.20f, .20f, .30f));
            bool joined = i < matchPlayerCount;
            if (i == 0)
            {
                playerOneSlot = slot;
                playerSlotLabels[i] = AddText(slot, "PLAYER 1", new Vector2(.05f, .76f), new Vector2(.95f, .98f), 20, new Color(.98f, .88f, .77f), FontStyles.Bold);
            }
            else
            {
                playerSlotLabels[i] = AddText(slot, joined ? "PLAYER " + (i + 1) : "+\nPRESS X TO JOIN", joined ? new Vector2(.05f, .76f) : Vector2.zero, joined ? new Vector2(.95f, .98f) : Vector2.one, joined ? 20 : 20, joined ? new Color(.98f, .88f, .77f) : new Color(.62f, .60f, .69f), FontStyles.Bold);
                int slotIndex = i;
                AddButton(slot, "", Vector2.zero, Vector2.one, new Color(1, 1, 1, .01f), () => JoinPlayer(slotIndex), 18, Color.white);
            }
            playerCharacterCursors[i] = Mathf.Clamp(playerCharacters[i], 0, 4);
        }

        RectTransform characters = AddPanel(root, "Character Selection Panel", new Vector2(.035f, .015f), new Vector2(.725f, .635f), new Color(.13f, .14f, .22f, .97f));
        AddHeaderBar(characters, "CHARACTER SELECTION", new Color(.13f, .39f, .83f), .60f, 36);
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
            float yMax = .86f - row * .29f;
            bool unlocked = ownedCharacters[i];
            Color tileColor = unlocked ? Color.Lerp(characterColors[i], Color.white, .52f) : new Color(.24f, .24f, .34f);
            RectTransform tile = AddPanel(characters, unlocked ? "Unlocked Character " + (i + 1) : "Locked Character " + (i - 4), new Vector2(xMin, yMax - .27f), new Vector2(xMin + .168f, yMax), tileColor);
            if (unlocked)
            {
                characterButtons[i] = AddButton(tile, string.Empty, Vector2.zero, Vector2.one, new Color(1f, 1f, 1f, .01f), () => SelectCharacterForPlayer(0, index), 21, Color.white);
                if (unlockedCharacterPortraits[i] == null)
                    unlockedCharacterPortraits[i] = CreateCharacterPortrait(characterColors[i], false);
                AddPortrait(tile, unlockedCharacterPortraits[i], new Vector2(.04f, .035f), new Vector2(.96f, .965f));
                characterOutlines[i] = tile.gameObject.AddComponent<Outline>();
                characterOutlines[i].effectColor = characterColors[i];
                characterOutlines[i].effectDistance = new Vector2(4f, -4f);
            }
            else
            {
                characterButtons[i] = AddButton(tile, string.Empty, Vector2.zero, Vector2.one, new Color(1f, 1f, 1f, .01f), () => { }, 21, Color.white);
                if (lockedSilhouette == null)
                    lockedSilhouette = CreateCharacterPortrait(Color.black, true);
                AddPortrait(tile, lockedSilhouette, new Vector2(.10f, .20f), new Vector2(.90f, .98f));
                AddText(tile, "Locked", new Vector2(.03f, .03f), new Vector2(.97f, .27f), 19, new Color(.77f, .76f, .81f), FontStyles.Bold);
            }
        }
        for (int i = 0; i < matchPlayerCount; i++)
        {
            int character = Mathf.Clamp(playerCharacters[i], 0, CharacterCount - 1);
            playerSlotLabels[i].text = "PLAYER " + (i + 1) + "\n" + shopCharacterNames[character];
            if (unlockedCharacterPortraits[character] != null)
                playerSlotPortraits[i] = AddPortrait((RectTransform)playerSlotLabels[i].transform.parent, unlockedCharacterPortraits[character], new Vector2(.08f, .04f), new Vector2(.92f, .73f));
        }
        if (playerSlotPortraits[0] != null)
            selectedPlayerPortrait = playerSlotPortraits[0];
        RefreshCharacterSelection();

        Button inputModeButton = AddButton(root, InputModeLabels[(int)inputMode], new Vector2(.755f, .43f), new Vector2(.97f, .60f), new Color(.30f, .39f, .58f), CycleInputMode, 18, Color.white);
        inputModeButton.navigation = new Navigation { mode = Navigation.Mode.None };
        inputModeLabel = inputModeButton.GetComponentInChildren<TextMeshProUGUI>();
        startButton = AddButton(root, "LET'S GO!", new Vector2(.755f, .205f), new Vector2(.97f, .405f), new Color(1f, .62f, .09f), StartGame, 48, new Color(.17f, .13f, .16f));
        startButton.navigation = new Navigation { mode = Navigation.Mode.None };
        Button backButton = AddButton(root, "GO BACK", new Vector2(.755f, .07f), new Vector2(.97f, .18f), new Color(.91f, .82f, .73f), GoBack, 30, new Color(.15f, .16f, .22f));
        backButton.navigation = new Navigation { mode = Navigation.Mode.None };
        CreatePlayerCursors(root);
        RefreshRosterForInputMode();
    }

    private TextMeshProUGUI AddHeaderBar(RectTransform parent, string label, Color color, float widthFraction, float fontSize)
    {
        float halfWidth = widthFraction * .5f;
        RectTransform bar = AddPanel(parent, label + " Header", new Vector2(.5f - halfWidth, 1f), new Vector2(.5f + halfWidth, 1f), color);
        bar.pivot = new Vector2(.5f, 1f);
        bar.anchoredPosition = Vector2.zero;
        bar.sizeDelta = new Vector2(0f, 60f);
        return AddText(bar, label, Vector2.zero, Vector2.one, fontSize, Color.white, FontStyles.Bold);
    }

    private void StartGame()
    {
        if (!isTransitioning && CanStartMatch())
            StartCoroutine(FadeToScene(LevelSceneNames[selectedLevel]));
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
                playerSlotLabels[i].color = active ? new Color(.98f, .88f, .77f) : new Color(.62f, .60f, .69f);
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

        RectTransform collection = AddPanel(root, "Character Collection", new Vector2(.035f, .14f), new Vector2(.59f, .87f), new Color(.12f, .10f, .12f, .96f));
        AddHeaderBar(collection, "CHARACTER SHOP", new Color(.39f, .20f, .12f), .76f, 36);
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
            shopCardPortraits[i] = AddPortrait(card, ownedCharacters[i] ? unlockedCharacterPortraits[i] : shopLockedPortrait, new Vector2(.04f, .04f), new Vector2(.96f, .96f));
            if (!ownedCharacters[i])
                shopCardLockedLabels[i] = AddText(card, "LOCKED", new Vector2(.04f, .02f), new Vector2(.96f, .22f), 14, new Color(.86f, .83f, .88f), FontStyles.Bold);
            SetShopCardBackground(i);
            shopCardOutlines[i] = card.gameObject.AddComponent<Outline>();
            shopCardOutlines[i].effectColor = ownedCharacters[i] ? characterColors[i] : new Color(.67f, .62f, .72f);
            shopCardOutlines[i].effectDistance = new Vector2(4f, -4f);
            shopCardOutlines[i].enabled = false;
            cardButton.navigation = new Navigation { mode = Navigation.Mode.None };
        }

        RectTransform balancePanel = AddPanel(root, "Coin Balance", new Vector2(.62f, .89f), new Vector2(.92f, .98f), new Color(.15f, .14f, .16f, .97f));
        AddText(balancePanel, "★  " + shopCoins, Vector2.zero, Vector2.one, 34, new Color(1f, .80f, .25f), FontStyles.Bold);
        shopBalanceText = balancePanel.GetComponentInChildren<TextMeshProUGUI>();

        RectTransform detail = AddPanel(root, "Character Details", new Vector2(.62f, .18f), new Vector2(.92f, .85f), new Color(.84f, .72f, .57f, .98f));
        shopNameText = AddText(detail, string.Empty, new Vector2(.04f, .83f), new Vector2(.96f, .98f), 32, new Color(.22f, .15f, .12f), FontStyles.Bold);
        shopDetailPortrait = AddPortrait(detail, null, new Vector2(.10f, .16f), new Vector2(.90f, .82f));
        shopPurchaseButton = AddButton(detail, "BUY", new Vector2(.08f, .035f), new Vector2(.92f, .16f), new Color(.24f, .21f, .23f), PurchaseSelectedCharacter, 27, new Color(.91f, .89f, .92f));
        shopPurchaseText = shopPurchaseButton.GetComponentInChildren<TextMeshProUGUI>();

        AddButton(root, "GO BACK", new Vector2(.62f, .055f), new Vector2(.76f, .14f), new Color(.91f, .82f, .73f), GoBackFromShop, 21, new Color(.15f, .16f, .22f));
        AddButton(root, "PLAY", new Vector2(.78f, .055f), new Vector2(.92f, .14f), new Color(1f, .62f, .09f), PlayFromShop, 23, new Color(.17f, .13f, .16f));
        shopSelectedCharacter = Mathf.Clamp(selectedCharacter, 0, CharacterCount - 1);
        RefreshShopSelection();
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
        shopBalanceText.text = "★  " + shopCoins;
    }

    private void PurchaseSelectedCharacter()
    {
        int characterPrice = GetCharacterPrice(shopSelectedCharacter);
        if (ownedCharacters[shopSelectedCharacter] || shopCoins < characterPrice) return;
        shopCoins -= characterPrice;
        ownedCharacters[shopSelectedCharacter] = true;
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
        background.sprite = null;
        background.color = ownedCharacters[index]
            ? Color.Lerp(characterColors[index], Color.white, .42f)
            : new Color(.25f, .23f, .28f);
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

    private RectTransform AddPanel(RectTransform parent, string objectName, Vector2 anchorMin, Vector2 anchorMax, Color color)
    {
        GameObject panel = new GameObject(objectName, typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
        RectTransform rect = panel.GetComponent<RectTransform>();
        rect.SetParent(parent, false);
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.offsetMin = Vector2.zero;
        rect.offsetMax = Vector2.zero;
        panel.GetComponent<Image>().color = color;
        return rect;
    }

    private TextMeshProUGUI AddText(RectTransform parent, string value, Vector2 anchorMin, Vector2 anchorMax, float size, Color color, FontStyles style, Color? background = null)
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
            textRect.offsetMin = new Vector2(6, 4);
            textRect.offsetMax = new Vector2(-6, -4);
            text = textObject.GetComponent<TextMeshProUGUI>();
        }
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

    private Button AddButton(RectTransform parent, string label, Vector2 anchorMin, Vector2 anchorMax, Color color, UnityEngine.Events.UnityAction action, float fontSize, Color textColor)
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
        if (cursorSprite == null)
        {
            Texture2D texture = new Texture2D(64, 64, TextureFormat.RGBA32, false);
            Color[] pixels = new Color[64 * 64];
            for (int y = 0; y < 64; y++)
                for (int x = 0; x < 64; x++)
                {
                    float distance = Vector2.Distance(new Vector2(x, y), new Vector2(31.5f, 31.5f));
                    pixels[y * 64 + x] = distance <= 30f && distance >= 25f ? Color.white : Color.clear;
                }
            texture.SetPixels(pixels);
            texture.Apply();
            cursorSprite = Sprite.Create(texture, new Rect(0f, 0f, 64f, 64f), new Vector2(.5f, .5f));
        }

        for (int i = 0; i < MaxLocalPlayers; i++)
        {
            GameObject cursorObject = new GameObject("P" + (i + 1) + " Cursor", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image));
            cursorObject.transform.SetParent(root, false);
            RectTransform cursor = cursorObject.GetComponent<RectTransform>();
            cursor.sizeDelta = new Vector2(72f, 72f);
            Image image = cursorObject.GetComponent<Image>();
            image.sprite = cursorSprite;
            image.color = characterColors[i];
            image.raycastTarget = false;
            TextMeshProUGUI label = AddText(cursor, "P" + (i + 1), Vector2.zero, Vector2.one, 18f, Color.white, FontStyles.Bold);
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
                if (playerIndex == 0 && inputMode == MatchInputMode.AllControllers && IsCursorOverButton(0, startButton))
                    StartGame();
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
                playerSlotPortraits[playerIndex] = AddPortrait(slot, unlockedCharacterPortraits[character], new Vector2(.08f, .04f), new Vector2(.92f, .73f));
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
        rect.anchorMin = active ? new Vector2(.05f, .76f) : Vector2.zero;
        rect.anchorMax = active ? new Vector2(.95f, .98f) : Vector2.one;
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

        int portraitIndex = portraitRigs.Count;
        const int portraitLayer = 31;
        GameObject rig = new GameObject("Character Portrait Rig " + (portraitIndex + 1));
        rig.transform.SetParent(transform, false);
        Vector3 rigOffset = new Vector3(10000f + portraitIndex * 20f, 0f, 0f);
        GameObject model = Instantiate(prefab, rigOffset, Quaternion.identity, rig.transform);
        model.name = "Character Portrait Model";
        ArenaPlayerController controller = model.GetComponent<ArenaPlayerController>();
        if (controller != null) controller.enabled = false;
        CharacterController characterController = model.GetComponent<CharacterController>();
        if (characterController != null) characterController.enabled = false;

        Renderer[] renderers = model.GetComponentsInChildren<Renderer>(true);
        Bounds bounds = new Bounds(model.transform.position, Vector3.one);
        bool hasBounds = false;
        foreach (Renderer renderer in renderers)
        {
            SetLayerRecursively(renderer.gameObject, portraitLayer);
            if (renderer is ParticleSystemRenderer) continue;
            if (!hasBounds)
            {
                bounds = renderer.bounds;
                hasBounds = true;
            }
            else
            {
                bounds.Encapsulate(renderer.bounds);
            }

            MaterialPropertyBlock properties = new MaterialPropertyBlock();
            renderer.GetPropertyBlock(properties);
            Color materialColor = silhouette ? Color.black : tint;
            properties.SetColor("_BaseColor", materialColor);
            properties.SetColor("_Color", materialColor);
            if (silhouette)
            {
                properties.SetColor("_SpecColor", Color.black);
                properties.SetColor("_EmissionColor", Color.black);
            }
            renderer.SetPropertyBlock(properties);
        }

        if (!hasBounds)
            bounds = new Bounds(model.transform.position + Vector3.up, new Vector3(1f, 2f, 1f));

        RenderTexture texture = new RenderTexture(256, 256, 16, RenderTextureFormat.ARGB32);
        texture.name = silhouette ? "Locked Character Silhouette" : "Unlocked Character Portrait " + (portraitIndex + 1);
        texture.Create();
        portraitTextures.Add(texture);

        GameObject cameraObject = new GameObject("Character Portrait Camera");
        cameraObject.transform.SetParent(rig.transform, false);
        Camera portraitCamera = cameraObject.AddComponent<Camera>();
        portraitCamera.clearFlags = CameraClearFlags.SolidColor;
        portraitCamera.backgroundColor = new Color(0f, 0f, 0f, 0f);
        portraitCamera.cullingMask = 1 << portraitLayer;
        portraitCamera.orthographic = true;
        portraitCamera.orthographicSize = Mathf.Max(bounds.extents.y * .48f, .1f);
        portraitCamera.aspect = 1f;
        portraitCamera.nearClipPlane = .01f;
        portraitCamera.farClipPlane = 20f;
        Vector3 focus = bounds.center + Vector3.up * bounds.extents.y * .53f;
        portraitCamera.transform.position = focus + Vector3.back * 5f;
        portraitCamera.transform.rotation = Quaternion.LookRotation(Vector3.forward, Vector3.up);
        portraitCamera.targetTexture = texture;
        portraitCamera.Render();
        portraitCamera.targetTexture = null;
        portraitCamera.enabled = false;
        portraitRigs.Add(rig);
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

    private void SetLayerRecursively(GameObject target, int layer)
    {
        target.layer = layer;
        foreach (Transform child in target.transform)
            SetLayerRecursively(child.gameObject, layer);
    }

    private void ClearPortraits()
    {
        foreach (GameObject rig in portraitRigs)
            if (rig != null) Destroy(rig);
        portraitRigs.Clear();
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
