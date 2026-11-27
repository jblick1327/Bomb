using System;
using System.Text;
using TMPro;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;

// The Online screen on the main menu: Host Game (shows the join code), Join
// Game (enter a code), a lobby listing everyone connected, and the level
// picker. Everyone sees the picker; only the host can change it and start.
public sealed class OnlineMenuUI : MonoBehaviour
{
    private const BomButtonStyle ButtonStyle = BomButtonStyle.Orange;
    private const BomButtonStyle SecondaryButtonStyle = BomButtonStyle.Yellow;
    // Menu text is white; only errors and the empty code box differ.
    private static readonly Color LightText = BomUiSkin.TextColor;
    private static readonly Color PlaceholderText = new Color(1f, 1f, 1f, .45f);
    private static readonly Color ErrorText = new Color(1f, .45f, .40f);
    private static readonly string[] LevelPreviewNames = { "YardLevelPreview", "BridgeLevelPreview", "TowerLevelPreview" };

    private enum MenuScreen { Choose, Busy, Lobby, Level }

    private Action onClosed;
    private RectTransform content;
    private TextMeshProUGUI statusText;
    private TextMeshProUGUI playerListText;
    private TextMeshProUGUI networkText;
    private Button modelButton;
    private TextMeshProUGUI modelLabel;
    private RawImage modelPortrait;
    private TMP_InputField codeField;
    private Button chooseLevelButton;
    private Button startButton;
    private RawImage levelPreview;
    private AspectRatioFitter levelPreviewAspect;
    private TextMeshProUGUI levelNameText;
    private MenuScreen screen;
    private bool busy;
    private float nextRefresh;

    // Builds and shows the Online screen. onClosed runs when the player goes back.
    public static OnlineMenuUI Open(Action onClosed)
    {
        var canvasObject = new GameObject("Online Menu Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        Canvas canvas = canvasObject.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 50;
        CanvasScaler scaler = canvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;

        OnlineMenuUI menu = canvasObject.AddComponent<OnlineMenuUI>();
        menu.onClosed = onClosed;
        menu.Build((RectTransform)canvasObject.transform);
        return menu;
    }

    private void Build(RectTransform root)
    {
        root.anchorMin = Vector2.zero;
        root.anchorMax = Vector2.one;
        root.offsetMin = Vector2.zero;
        root.offsetMax = Vector2.zero;
        RectTransform panel = MatchMenuUI.AddPanel(root, "Online Panel", new Vector2(.30f, .14f), new Vector2(.70f, .88f));
        MatchMenuUI.AddHeaderBar(panel, "ONLINE", BomButtonStyle.Blue);
        statusText = MatchMenuUI.AddText(panel, string.Empty, new Vector2(.05f, .80f), new Vector2(.95f, .88f), 24, LightText, FontStyles.Bold);
        content = new GameObject("Content", typeof(RectTransform)).GetComponent<RectTransform>();
        content.SetParent(panel, false);
        content.anchorMin = new Vector2(.05f, .04f);
        content.anchorMax = new Vector2(.95f, .79f);
        content.offsetMin = Vector2.zero;
        content.offsetMax = Vector2.zero;

        // Coming back from a match: go straight to the lobby, or show why the
        // game ended.
        string message = OnlineMatch.PendingMenuMessage;
        OnlineMatch.PendingMenuMessage = null;
        if (OnlineSession.IsActive) ShowLobbyOrLevel();
        else if (!string.IsNullOrEmpty(message)) ShowChooseScreen(message, true);
        else ShowChooseScreen(string.Empty);
    }

    private void OnEnable()
    {
        OnlineSession.Changed += RefreshLobby;
        OnlineSession.Ended += OnSessionEnded;
        OnlineMatch.LobbyChanged += OnLobbyChanged;
    }

    private void OnDisable()
    {
        OnlineSession.Changed -= RefreshLobby;
        OnlineSession.Ended -= OnSessionEnded;
        OnlineMatch.LobbyChanged -= OnLobbyChanged;
    }

    private void Update()
    {
        // The game connection comes up a moment after the session, so poll it.
        if ((screen == MenuScreen.Lobby || screen == MenuScreen.Level) && Time.unscaledTime >= nextRefresh)
        {
            nextRefresh = Time.unscaledTime + 0.5f;
            if (screen == MenuScreen.Lobby) RefreshLobby();
            else RefreshLevel();
        }
        // The host can also flip levels with the controller's shoulder buttons.
        Gamepad gamepad = Gamepad.current;
        if (modelButton != null && modelButton.interactable && gamepad != null && gamepad.buttonNorth.wasPressedThisFrame)
            CycleModel();
        if (screen == MenuScreen.Level && OnlineSession.IsHost && gamepad != null)
        {
            if (gamepad.leftShoulder.wasPressedThisFrame) ChangeLevel(-1);
            if (gamepad.rightShoulder.wasPressedThisFrame) ChangeLevel(1);
        }
    }

    private void ClearContent()
    {
        for (int i = content.childCount - 1; i >= 0; i--) Destroy(content.GetChild(i).gameObject);
        playerListText = null;
        networkText = null;
        modelButton = null;
        modelLabel = null;
        modelPortrait = null;
        codeField = null;
        chooseLevelButton = null;
        startButton = null;
        levelPreview = null;
        levelPreviewAspect = null;
        levelNameText = null;
    }

    private void SetStatus(string message, bool error = false)
    {
        statusText.text = message;
        statusText.color = error ? ErrorText : LightText;
    }

    private void ShowChooseScreen(string message, bool error = false)
    {
        screen = MenuScreen.Choose;
        ClearContent();
        SetStatus(string.IsNullOrEmpty(message) ? "Play with friends over the internet (up to 4 players)." : message, error);
        MatchMenuUI.AddButton(content, "HOST GAME", new Vector2(.1f, .74f), new Vector2(.9f, .96f), ButtonStyle, HostGame, 36);
        MatchMenuUI.AddText(content, "OR JOIN WITH A CODE", new Vector2(.1f, .60f), new Vector2(.9f, .70f), 26, LightText, FontStyles.Bold);
        codeField = CreateCodeField(content, new Vector2(.1f, .42f), new Vector2(.62f, .58f));
        MatchMenuUI.AddButton(content, "JOIN", new Vector2(.65f, .42f), new Vector2(.9f, .58f), ButtonStyle, JoinGame, 34);
        MatchMenuUI.AddButton(content, "BACK", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonStyle, Close, 32);
    }

    private void ShowBusyScreen(string message)
    {
        screen = MenuScreen.Busy;
        ClearContent();
        SetStatus(message);
    }

    private void ShowLobbyOrLevel()
    {
        if (OnlineMatch.Screen == OnlineMatch.LobbyScreen.ChooseLevel) ShowLevelScreen();
        else ShowLobbyScreen();
    }

    // The host moved everyone between the player list and the level picker,
    // or changed the level.
    private void OnLobbyChanged()
    {
        if (screen != MenuScreen.Lobby && screen != MenuScreen.Level) return;
        bool wantLevel = OnlineMatch.Screen == OnlineMatch.LobbyScreen.ChooseLevel;
        if (wantLevel != (screen == MenuScreen.Level)) ShowLobbyOrLevel();
        else if (screen == MenuScreen.Level) RefreshLevel();
        else RefreshLobby();
    }

    private void ShowLobbyScreen()
    {
        screen = MenuScreen.Lobby;
        ClearContent();
        if (OnlineSession.IsHost)
        {
            MatchMenuUI.AddText(content, "JOIN CODE", new Vector2(.1f, .88f), new Vector2(.9f, .98f), 26, LightText, FontStyles.Bold);
            MatchMenuUI.AddText(content, OnlineSession.JoinCode, new Vector2(.1f, .70f), new Vector2(.9f, .88f), 60, Color.white,
                FontStyles.Bold, Color.white);
        }
        else
        {
            MatchMenuUI.AddText(content, "JOINED GAME " + OnlineSession.JoinCode, new Vector2(.1f, .76f), new Vector2(.9f, .96f), 32, LightText, FontStyles.Bold);
        }
        playerListText = MatchMenuUI.AddText(content, string.Empty, new Vector2(.1f, .40f), new Vector2(.9f, .68f), 26, Color.white, FontStyles.Bold);
        playerListText.alignment = TextAlignmentOptions.TopLeft;
        playerListText.enableAutoSizing = false;
        networkText = MatchMenuUI.AddText(content, string.Empty, new Vector2(.1f, .20f), new Vector2(.9f, .27f), 20, LightText, FontStyles.Normal);
        AddModelPicker(.27f, .39f);
        if (OnlineSession.IsHost)
        {
            MatchMenuUI.AddButton(content, "LEAVE", new Vector2(.1f, .04f), new Vector2(.42f, .2f), SecondaryButtonStyle, LeaveGame, 32);
            chooseLevelButton = MatchMenuUI.AddButton(content, "CHOOSE LEVEL", new Vector2(.45f, .04f), new Vector2(.9f, .2f),
                ButtonStyle, () => OnlineMatch.HostShowLobby(OnlineMatch.LobbyScreen.ChooseLevel, OnlineMatch.SelectedLevel), 32);
        }
        else
        {
            MatchMenuUI.AddButton(content, "LEAVE", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonStyle, LeaveGame, 32);
        }
        RefreshLobby();
    }

    private void RefreshLobby()
    {
        if (screen != MenuScreen.Lobby || playerListText == null) return;
        SetStatus(OnlineSession.IsHost
            ? "Share the code with your friends."
            : "Waiting for the host to choose a level.");

        var list = new StringBuilder();
        list.Append("PLAYERS (").Append(OnlineSession.Players.Count).Append('/').Append(OnlineSession.MaxPlayers).Append(")\n");
        for (int i = 0; i < OnlineSession.Players.Count; i++)
        {
            var player = OnlineSession.Players[i];
            list.Append("Player ").Append(i + 1);
            if (OnlineSession.IsHostPlayer(player)) list.Append("  (host)");
            if (OnlineSession.IsLocalPlayer(player)) list.Append("  (you)");
            list.Append('\n');
        }
        playerListText.text = list.ToString();
        RefreshModelPicker();
        networkText.text = OnlineSession.IsNetworkConnected ? "Game connection: ready" : "Game connection: connecting...";
        if (chooseLevelButton != null)
        {
            bool enoughPlayers = OnlineMatch.ConnectedPlayerCount >= 2;
            chooseLevelButton.interactable = enoughPlayers;
            if (!enoughPlayers) SetStatus("Share the code. You can choose a level once someone joins.");
        }
    }

    private void ShowLevelScreen()
    {
        screen = MenuScreen.Level;
        ClearContent();
        // No frame: the picture's edges fade into the panel.
        levelPreview = MatchMenuUI.AddFadedPicture(content, "Level Preview", new Vector2(.06f, .48f), new Vector2(.94f, .97f), out levelPreviewAspect);
        levelNameText = MatchMenuUI.AddText(content, string.Empty, new Vector2(.1f, .36f), new Vector2(.9f, .47f), 34, Color.white, FontStyles.Bold);

        AddModelPicker(.22f, .33f);
        if (OnlineSession.IsHost)
        {
            MatchMenuUI.AddArrowButton(content, true, new Vector2(-.02f, .62f), new Vector2(.09f, .83f), () => ChangeLevel(-1));
            MatchMenuUI.AddArrowButton(content, false, new Vector2(.91f, .62f), new Vector2(1.02f, .83f), () => ChangeLevel(1));
            MatchMenuUI.AddButton(content, "BACK", new Vector2(.1f, .04f), new Vector2(.42f, .2f), SecondaryButtonStyle,
                () => OnlineMatch.HostShowLobby(OnlineMatch.LobbyScreen.Players, OnlineMatch.SelectedLevel), 32);
            startButton = MatchMenuUI.AddButton(content, "START", new Vector2(.45f, .04f), new Vector2(.9f, .2f), ButtonStyle, StartMatch, 36);
        }
        else
        {
            MatchMenuUI.AddButton(content, "LEAVE", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonStyle, LeaveGame, 32);
        }
        RefreshLevel();
    }

    private void RefreshLevel()
    {
        if (screen != MenuScreen.Level || levelNameText == null) return;
        int level = Mathf.Clamp(OnlineMatch.SelectedLevel, 0, MatchMenuUI.LevelNames.Length - 1);
        levelNameText.text = MatchMenuUI.LevelNames[level];
        RefreshModelPicker();
        if (levelPreview != null)
        {
            Texture2D picture = Resources.Load<Texture2D>(LevelPreviewNames[level]);
            levelPreview.texture = picture;
            if (picture != null && levelPreviewAspect != null)
                levelPreviewAspect.aspectRatio = (float)picture.width / picture.height;
        }
        if (OnlineSession.IsHost)
        {
            bool enoughPlayers = OnlineMatch.ConnectedPlayerCount >= 2;
            if (startButton != null) startButton.interactable = enoughPlayers;
            if (enoughPlayers) SetStatus("Pick a level, then press START.  (LB / RB also change it)");
            else SetStatus("Waiting for another player to connect...", true);
        }
        else
        {
            SetStatus("The host is choosing a level...");
        }
    }

    // The body-style picker: a blue chalk option button with this player's
    // body style pictured on its left. Pressing it moves to the next style.
    private void AddModelPicker(float bottom, float top)
    {
        modelButton = MatchMenuUI.AddButton(content, "BODY STYLE", new Vector2(.10f, bottom), new Vector2(.90f, top),
            BomButtonStyle.Blue, CycleModel, 28);
        modelLabel = modelButton.GetComponentInChildren<TextMeshProUGUI>();
        // Leave the picture's side of the button clear of the words.
        modelLabel.rectTransform.offsetMin = new Vector2(90f, modelLabel.rectTransform.offsetMin.y);
        modelPortrait = MatchMenuUI.AddPortrait((RectTransform)modelButton.transform, null,
            new Vector2(.06f, .06f), new Vector2(.26f, .94f));
        RefreshModelPicker();
    }

    private void CycleModel()
    {
        OnlineMatch.CycleLocalModel();
        RefreshModelPicker();
    }

    private void RefreshModelPicker()
    {
        if (modelButton == null) return;
        modelButton.interactable = OnlineSession.IsNetworkConnected;
        modelPortrait.texture = CharacterModels.Portrait(OnlineMatch.LocalModel);
        modelLabel.text = "BODY STYLE   " + CharacterModels.Name(OnlineMatch.LocalModel) + "   >";
    }

    private void ChangeLevel(int direction)
    {
        int count = MatchMenuUI.LevelSceneNames.Length;
        OnlineMatch.HostShowLobby(OnlineMatch.LobbyScreen.ChooseLevel, (OnlineMatch.SelectedLevel + direction + count) % count);
    }

    private void StartMatch()
    {
        if (busy || OnlineMatch.ConnectedPlayerCount < 2) return;
        busy = true;
        ShowBusyScreen("Starting " + MatchMenuUI.LevelNames[OnlineMatch.SelectedLevel] + "...");
        OnlineMatch.HostStartMatch();
    }

    private async void HostGame()
    {
        if (busy) return;
        busy = true;
        ShowBusyScreen("Creating game...");
        try
        {
            await OnlineSession.HostAsync();
            if (this == null) return;
            OnlineMatch.HostShowLobby(OnlineMatch.LobbyScreen.Players, 0);
            ShowLobbyScreen();
        }
        catch (Exception e)
        {
            Debug.LogException(e);
            if (this != null) ShowChooseScreen("Couldn't create a game. " + Describe(e), true);
        }
        finally { busy = false; }
    }

    private async void JoinGame()
    {
        if (busy) return;
        string code = codeField != null ? codeField.text.Trim() : string.Empty;
        if (code.Length < 4)
        {
            SetStatus("Enter the join code from the host.", true);
            return;
        }
        busy = true;
        ShowBusyScreen("Joining " + code.ToUpperInvariant() + "...");
        try
        {
            await OnlineSession.JoinAsync(code);
            if (this == null) return;
            ShowLobbyOrLevel();
        }
        catch (Exception e)
        {
            Debug.LogException(e);
            if (this != null) ShowChooseScreen("Couldn't join that game. " + Describe(e), true);
        }
        finally { busy = false; }
    }

    private async void LeaveGame()
    {
        if (busy) return;
        busy = true;
        ShowBusyScreen("Leaving...");
        await OnlineSession.LeaveAsync();
        busy = false;
        if (this != null) ShowChooseScreen(string.Empty);
    }

    private void OnSessionEnded(string reason)
    {
        busy = false;
        ShowChooseScreen(reason, true);
    }

    private async void Close()
    {
        if (busy) return;
        if (OnlineSession.IsActive) await OnlineSession.LeaveAsync();
        onClosed?.Invoke();
        if (this != null) Destroy(gameObject);
    }

    private static string Describe(Exception e)
    {
        string message = e.InnerException != null ? e.InnerException.Message : e.Message;
        return message.Length > 120 ? message.Substring(0, 120) + "..." : message;
    }

    // A text box for the join code: letters and numbers only, shown in capitals.
    private static TMP_InputField CreateCodeField(RectTransform parent, Vector2 anchorMin, Vector2 anchorMax)
    {
        RectTransform box = MatchMenuUI.AddPanel(parent, "Join Code Field", anchorMin, anchorMax);
        var viewport = new GameObject("Text Area", typeof(RectTransform), typeof(RectMask2D)).GetComponent<RectTransform>();
        viewport.SetParent(box, false);
        viewport.anchorMin = Vector2.zero;
        viewport.anchorMax = Vector2.one;
        viewport.offsetMin = new Vector2(14f, 6f);
        viewport.offsetMax = new Vector2(-14f, -6f);

        TextMeshProUGUI placeholder = MatchMenuUI.AddText(viewport, "CODE", Vector2.zero, Vector2.one, 34, PlaceholderText, FontStyles.Bold);
        TextMeshProUGUI text = MatchMenuUI.AddText(viewport, string.Empty, Vector2.zero, Vector2.one, 34, Color.white, FontStyles.Bold | FontStyles.UpperCase);
        text.enableAutoSizing = false;

        TMP_InputField field = box.gameObject.AddComponent<TMP_InputField>();
        field.textViewport = viewport;
        field.textComponent = text;
        field.placeholder = placeholder;
        field.characterValidation = TMP_InputField.CharacterValidation.Alphanumeric;
        field.characterLimit = 12;
        field.targetGraphic = box.GetComponent<Image>();
        return field;
    }
}
