using System;
using System.Text;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

// The Online screen on the main menu: Host Game (shows the join code), Join
// Game (enter a code), and a lobby listing everyone connected.
public sealed class OnlineMenuUI : MonoBehaviour
{
    private static readonly Color PanelColor = new Color(.13f, .14f, .22f, .97f);
    private static readonly Color HeaderColor = new Color(.13f, .39f, .83f);
    private static readonly Color ButtonColor = new Color(1f, .62f, .09f);
    private static readonly Color SecondaryButtonColor = new Color(.91f, .82f, .73f);
    private static readonly Color DarkText = new Color(.15f, .16f, .22f);
    private static readonly Color LightText = new Color(.98f, .88f, .77f);
    private static readonly Color ErrorText = new Color(1f, .45f, .40f);

    private enum MenuScreen { Choose, Busy, Lobby }

    private Action onClosed;
    private RectTransform content;
    private TextMeshProUGUI statusText;
    private TextMeshProUGUI playerListText;
    private TextMeshProUGUI networkText;
    private TMP_InputField codeField;
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
        RectTransform panel = MatchMenuUI.AddPanel(root, "Online Panel", new Vector2(.30f, .14f), new Vector2(.70f, .88f), PanelColor);
        MatchMenuUI.AddHeaderBar(panel, "ONLINE", HeaderColor, .5f, 36);
        statusText = MatchMenuUI.AddText(panel, string.Empty, new Vector2(.05f, .80f), new Vector2(.95f, .88f), 20, LightText, FontStyles.Bold);
        content = new GameObject("Content", typeof(RectTransform)).GetComponent<RectTransform>();
        content.SetParent(panel, false);
        content.anchorMin = new Vector2(.05f, .04f);
        content.anchorMax = new Vector2(.95f, .79f);
        content.offsetMin = Vector2.zero;
        content.offsetMax = Vector2.zero;
        ShowChooseScreen(string.Empty);
    }

    private void OnEnable()
    {
        OnlineSession.Changed += RefreshLobby;
        OnlineSession.Ended += OnSessionEnded;
    }

    private void OnDisable()
    {
        OnlineSession.Changed -= RefreshLobby;
        OnlineSession.Ended -= OnSessionEnded;
    }

    private void Update()
    {
        // The game connection comes up a moment after the session, so poll it.
        if (screen == MenuScreen.Lobby && Time.unscaledTime >= nextRefresh)
        {
            nextRefresh = Time.unscaledTime + 0.5f;
            RefreshLobby();
        }
    }

    private void ClearContent()
    {
        for (int i = content.childCount - 1; i >= 0; i--) Destroy(content.GetChild(i).gameObject);
        playerListText = null;
        networkText = null;
        codeField = null;
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
        MatchMenuUI.AddButton(content, "HOST GAME", new Vector2(.1f, .74f), new Vector2(.9f, .96f), ButtonColor, HostGame, 36, DarkText);
        MatchMenuUI.AddText(content, "OR JOIN WITH A CODE", new Vector2(.1f, .60f), new Vector2(.9f, .70f), 20, LightText, FontStyles.Bold);
        codeField = CreateCodeField(content, new Vector2(.1f, .42f), new Vector2(.62f, .58f));
        MatchMenuUI.AddButton(content, "JOIN", new Vector2(.65f, .42f), new Vector2(.9f, .58f), ButtonColor, JoinGame, 30, DarkText);
        MatchMenuUI.AddButton(content, "BACK", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonColor, Close, 28, DarkText);
    }

    private void ShowBusyScreen(string message)
    {
        screen = MenuScreen.Busy;
        ClearContent();
        SetStatus(message);
    }

    private void ShowLobbyScreen()
    {
        screen = MenuScreen.Lobby;
        ClearContent();
        if (OnlineSession.IsHost)
        {
            MatchMenuUI.AddText(content, "JOIN CODE", new Vector2(.1f, .88f), new Vector2(.9f, .98f), 20, LightText, FontStyles.Bold);
            MatchMenuUI.AddText(content, OnlineSession.JoinCode, new Vector2(.1f, .70f), new Vector2(.9f, .88f), 60, Color.white,
                FontStyles.Bold, new Color(.20f, .20f, .30f));
        }
        else
        {
            MatchMenuUI.AddText(content, "JOINED GAME " + OnlineSession.JoinCode, new Vector2(.1f, .76f), new Vector2(.9f, .96f), 26, LightText, FontStyles.Bold);
        }
        playerListText = MatchMenuUI.AddText(content, string.Empty, new Vector2(.1f, .30f), new Vector2(.9f, .68f), 24, Color.white, FontStyles.Bold);
        playerListText.alignment = TextAlignmentOptions.TopLeft;
        playerListText.enableAutoSizing = false;
        networkText = MatchMenuUI.AddText(content, string.Empty, new Vector2(.1f, .22f), new Vector2(.9f, .30f), 18, LightText, FontStyles.Normal);
        MatchMenuUI.AddButton(content, "LEAVE", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonColor, LeaveGame, 28, DarkText);
        RefreshLobby();
    }

    private void RefreshLobby()
    {
        if (screen != MenuScreen.Lobby || playerListText == null) return;
        SetStatus(OnlineSession.IsHost
            ? "Share the code with your friends."
            : "Waiting for the host to start.");

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
        networkText.text = OnlineSession.IsNetworkConnected ? "Game connection: ready" : "Game connection: connecting...";
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
            ShowLobbyScreen();
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

    private void OnSessionEnded(string reason) => ShowChooseScreen(reason, true);

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
        RectTransform box = MatchMenuUI.AddPanel(parent, "Join Code Field", anchorMin, anchorMax, new Color(.95f, .93f, .90f));
        var viewport = new GameObject("Text Area", typeof(RectTransform), typeof(RectMask2D)).GetComponent<RectTransform>();
        viewport.SetParent(box, false);
        viewport.anchorMin = Vector2.zero;
        viewport.anchorMax = Vector2.one;
        viewport.offsetMin = new Vector2(14f, 6f);
        viewport.offsetMax = new Vector2(-14f, -6f);

        TextMeshProUGUI placeholder = MatchMenuUI.AddText(viewport, "CODE", Vector2.zero, Vector2.one, 34, new Color(.55f, .55f, .6f), FontStyles.Bold);
        TextMeshProUGUI text = MatchMenuUI.AddText(viewport, string.Empty, Vector2.zero, Vector2.one, 34, DarkText, FontStyles.Bold | FontStyles.UpperCase);
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
