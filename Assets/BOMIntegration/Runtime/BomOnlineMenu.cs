using System;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace Bom.Unity
{
    // C5: the ONLINE screen on Darryn's main menu (opened from MatchMenuUI.ShowOnlineMenu). Host: level, port and who may
    // join (this PC only, or LAN / direct IP). Join: address and port. Styled like Darryn's OnlineMenuUI (same colours and
    // layout); his helpers live in Assembly-CSharp, which this assembly cannot reference, so the few needed are copied.
    public sealed class BomOnlineMenu : MonoBehaviour
    {
        static readonly Color PanelColor = new Color(.13f, .14f, .22f, .97f);
        static readonly Color HeaderColor = new Color(.13f, .39f, .83f);
        static readonly Color ButtonColor = new Color(1f, .62f, .09f);
        static readonly Color SecondaryButtonColor = new Color(.91f, .82f, .73f);
        static readonly Color DarkText = new Color(.15f, .16f, .22f);
        static readonly Color LightText = new Color(.98f, .88f, .77f);
        static readonly Color ErrorText = new Color(1f, .45f, .40f);
        const string AddressKey = "Bom.Online.JoinAddress",
            JoinPortKey = "Bom.Online.JoinPort",
            HostPortKey = "Bom.Online.HostPort",
            LanKey = "Bom.Online.HostLan",
            LevelKey = "Bom.Online.Level";

        public enum MenuScreen { Choose, Host, Join, Busy }

        public static BomOnlineMenu Current { get; private set; }
        public MenuScreen Showing { get; private set; }
        public string Status => statusText != null ? statusText.text : "";
        public bool StatusIsError { get; private set; }

        // Named controls, also used by the scripted front-door run (BomFrontDoorScenario) to press the real buttons.
        public Button HostButton,
            JoinButton,
            StartButton,
            ConnectButton,
            LanButton,
            BackButton;
        public TMP_InputField AddressField,
            PortField;
        public int LevelIndex => level;

        Action onClosed;
        RectTransform content;
        TextMeshProUGUI statusText,
            levelText,
            lanHint;
        int level;
        bool lan;

        public static BomOnlineMenu Open(Action onClosed)
        {
            var canvasObject = new GameObject("Odin Online Menu Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 50;
            var scaler = canvasObject.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = .5f;
            var menu = canvasObject.AddComponent<BomOnlineMenu>();
            menu.onClosed = onClosed;
            menu.Build((RectTransform)canvasObject.transform);
            Current = menu;
            Debug.Log("BOM FRONTDOOR MENU open");
            return menu;
        }

        void OnDestroy()
        {
            if (Current == this)
                Current = null;
        }

        void Build(RectTransform root)
        {
            root.anchorMin = Vector2.zero;
            root.anchorMax = Vector2.one;
            root.offsetMin = Vector2.zero;
            root.offsetMax = Vector2.zero;
            var panel = AddPanel(root, "Online Panel", new Vector2(.30f, .14f), new Vector2(.70f, .88f), PanelColor);
            var header = AddPanel(panel, "Header", new Vector2(0f, .9f), Vector2.one, HeaderColor);
            AddText(header, "ONLINE", Vector2.zero, Vector2.one, 36, Color.white, FontStyles.Bold);
            statusText = AddText(panel, "", new Vector2(.05f, .78f), new Vector2(.95f, .89f), 20, LightText, FontStyles.Bold);
            content = new GameObject("Content", typeof(RectTransform)).GetComponent<RectTransform>();
            content.SetParent(panel, false);
            content.anchorMin = new Vector2(.05f, .04f);
            content.anchorMax = new Vector2(.95f, .77f);
            content.offsetMin = Vector2.zero;
            content.offsetMax = Vector2.zero;
            lan = PlayerPrefs.GetInt(LanKey, 0) == 1;
            level = Mathf.Clamp(PlayerPrefs.GetInt(LevelKey, 0), 0, BomFrontDoor.Levels.Count - 1);
            ShowChoose("");
        }

        void Clear()
        {
            for (int i = content.childCount - 1; i >= 0; i--)
                Destroy(content.GetChild(i).gameObject);
            HostButton = JoinButton = StartButton = ConnectButton = LanButton = BackButton = null;
            AddressField = PortField = null;
            levelText = null;
            lanHint = null;
        }

        public void SetStatus(string message, bool error = false)
        {
            statusText.text = message;
            statusText.color = error ? ErrorText : LightText;
            StatusIsError = error;
            if (!string.IsNullOrEmpty(message))
                Debug.Log("BOM FRONTDOOR MENU status error=" + error + " text=" + message);
        }

        void ShowChoose(string message, bool error = false)
        {
            Showing = MenuScreen.Choose;
            Clear();
            SetStatus(string.IsNullOrEmpty(message) ? "Play with friends on this PC, your LAN or by IP address (up to 4 players)." : message, error);
            HostButton = AddButton(content, "HOST GAME", new Vector2(.1f, .70f), new Vector2(.9f, .94f), ButtonColor, () => ShowHost(""), 36, DarkText);
            JoinButton = AddButton(content, "JOIN GAME", new Vector2(.1f, .40f), new Vector2(.9f, .64f), ButtonColor, () => ShowJoin(""), 36, DarkText);
            BackButton = AddButton(content, "BACK", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonColor, Close, 28, DarkText);
        }

        void ShowHost(string message, bool error = false)
        {
            Showing = MenuScreen.Host;
            Clear();
            SetStatus(string.IsNullOrEmpty(message) ? "Pick a level and start. Others join with your address and port." : message, error);
            AddText(content, "LEVEL", new Vector2(.05f, .88f), new Vector2(.30f, .98f), 20, LightText, FontStyles.Bold);
            AddButton(content, "‹", new Vector2(.32f, .86f), new Vector2(.42f, .99f), SecondaryButtonColor, () => ChangeLevel(-1), 40, DarkText);
            levelText = AddText(content, "", new Vector2(.43f, .86f), new Vector2(.85f, .99f), 26, Color.white, FontStyles.Bold);
            AddButton(content, "›", new Vector2(.86f, .86f), new Vector2(.96f, .99f), SecondaryButtonColor, () => ChangeLevel(1), 40, DarkText);
            ChangeLevel(0);
            AddText(content, "PORT", new Vector2(.05f, .71f), new Vector2(.30f, .82f), 20, LightText, FontStyles.Bold);
            PortField = AddField(content, "Port", PlayerPrefs.GetInt(HostPortKey, (int)BomFrontDoor.DefaultPort).ToString(), new Vector2(.32f, .70f), new Vector2(.96f, .83f), TMP_InputField.ContentType.IntegerNumber, 5);
            LanButton = AddButton(content, "", new Vector2(.05f, .52f), new Vector2(.96f, .66f), SecondaryButtonColor, ToggleLan, 22, DarkText);
            lanHint = AddText(content, "", new Vector2(.05f, .24f), new Vector2(.96f, .50f), 18, LightText, FontStyles.Normal);
            RefreshLan();
            StartButton = AddButton(content, "START", new Vector2(.52f, .04f), new Vector2(.96f, .2f), ButtonColor, StartHost, 30, DarkText);
            BackButton = AddButton(content, "BACK", new Vector2(.05f, .04f), new Vector2(.48f, .2f), SecondaryButtonColor, () => ShowChoose(""), 28, DarkText);
        }

        void ShowJoin(string message, bool error = false)
        {
            Showing = MenuScreen.Join;
            Clear();
            SetStatus(string.IsNullOrEmpty(message) ? "Enter the host's address and port." : message, error);
            AddText(content, "ADDRESS", new Vector2(.05f, .82f), new Vector2(.30f, .95f), 20, LightText, FontStyles.Bold);
            AddressField = AddField(content, "127.0.0.1", PlayerPrefs.GetString(AddressKey, "127.0.0.1"), new Vector2(.32f, .80f), new Vector2(.96f, .96f), TMP_InputField.ContentType.Standard, 15);
            AddText(content, "PORT", new Vector2(.05f, .60f), new Vector2(.30f, .73f), 20, LightText, FontStyles.Bold);
            PortField = AddField(content, "Port", PlayerPrefs.GetInt(JoinPortKey, (int)BomFrontDoor.DefaultPort).ToString(), new Vector2(.32f, .58f), new Vector2(.96f, .74f), TMP_InputField.ContentType.IntegerNumber, 5);
            AddText(content, "LEVEL", new Vector2(.05f, .40f), new Vector2(.30f, .52f), 20, LightText, FontStyles.Bold);
            AddButton(content, "‹", new Vector2(.32f, .39f), new Vector2(.42f, .53f), SecondaryButtonColor, () => ChangeLevel(-1), 40, DarkText);
            levelText = AddText(content, "", new Vector2(.43f, .39f), new Vector2(.85f, .53f), 26, Color.white, FontStyles.Bold);
            AddButton(content, "›", new Vector2(.86f, .39f), new Vector2(.96f, .53f), SecondaryButtonColor, () => ChangeLevel(1), 40, DarkText);
            ChangeLevel(0);
            AddText(content, "Same PC: 127.0.0.1. Another PC: the address the host's screen shows. Pick the level the host chose.", new Vector2(.05f, .22f), new Vector2(.96f, .37f), 18, LightText, FontStyles.Normal);
            ConnectButton = AddButton(content, "JOIN", new Vector2(.52f, .04f), new Vector2(.96f, .2f), ButtonColor, StartJoin, 30, DarkText);
            BackButton = AddButton(content, "BACK", new Vector2(.05f, .04f), new Vector2(.48f, .2f), SecondaryButtonColor, () => ShowChoose(""), 28, DarkText);
        }

        void ShowBusy(string message)
        {
            Showing = MenuScreen.Busy;
            Clear();
            SetStatus(message);
            BackButton = AddButton(content, "CANCEL", new Vector2(.1f, .04f), new Vector2(.9f, .2f), SecondaryButtonColor, () =>
            {
                BomFrontDoor.CancelHost();
                ShowHost("Cancelled.");
            }, 28, DarkText);
        }

        void ChangeLevel(int step)
        {
            int count = BomFrontDoor.Levels.Count;
            level = ((level + step) % count + count) % count;
            if (levelText != null)
                levelText.text = BomFrontDoor.Levels[level].Name;
        }

        // Scripted runs (BomFrontDoorScenario --bom-frontdoor-level) pick a level the same way the arrows do.
        public void SelectLevel(int index) => ChangeLevel(index - level);

        void ToggleLan()
        {
            lan = !lan;
            RefreshLan();
        }

        void RefreshLan()
        {
            if (LanButton != null)
                LanButton.GetComponentInChildren<TextMeshProUGUI>().text = lan ? "WHO CAN JOIN: LAN / DIRECT IP" : "WHO CAN JOIN: THIS PC ONLY";
            if (lanHint != null)
                lanHint.text = lan
                    ? "Windows may ask whether BOM-server may use the network. Allow it on Private networks, or other PCs cannot join."
                    : "Only windows on this PC can join (address 127.0.0.1). No firewall prompt.";
        }

        void StartHost()
        {
            string error = BomFrontDoor.ValidatePort(PortField.text, out uint port);
            if (error != null)
            {
                SetStatus(error, true);
                return;
            }
            PlayerPrefs.SetInt(HostPortKey, (int)port);
            PlayerPrefs.SetInt(LanKey, lan ? 1 : 0);
            PlayerPrefs.SetInt(LevelKey, level);
            PlayerPrefs.Save();
            var chosen = BomFrontDoor.Levels[level];
            Debug.Log("BOM FRONTDOOR MENU host level=" + chosen.Name + " port=" + port + " lan=" + lan);
            ShowBusy("Starting the server…");
            BomFrontDoor.Host(
                chosen,
                port,
                lan,
                (message, isError) =>
                {
                    if (this == null)
                        return;
                    if (isError)
                        ShowHost(message, true);
                    else
                        SetStatus(message);
                },
                ok => { }
            );
        }

        void StartJoin()
        {
            string address = AddressField.text.Trim();
            string error = BomFrontDoor.ValidateJoin(address, PortField.text, out uint port);
            if (error != null)
            {
                SetStatus(error, true);
                return;
            }
            PlayerPrefs.SetString(AddressKey, address);
            PlayerPrefs.SetInt(JoinPortKey, (int)port);
            PlayerPrefs.SetInt(LevelKey, level);
            PlayerPrefs.Save();
            var chosen = BomFrontDoor.Levels[level];
            Debug.Log("BOM FRONTDOOR MENU join address=" + address + " port=" + port + " level=" + chosen.Name);
            ShowBusy("Joining " + address + ":" + port + "…");
            BomFrontDoor.Join(chosen, address, port);
        }

        void Close()
        {
            if (BomFrontDoor.Busy)
                return;
            onClosed?.Invoke();
            Destroy(gameObject);
        }

        static void Pop() => BomGameAudio.ButtonPop();

        static RectTransform AddPanel(RectTransform parent, string name, Vector2 min, Vector2 max, Color color)
        {
            var rect = new GameObject(name, typeof(RectTransform), typeof(CanvasRenderer), typeof(Image)).GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            rect.anchorMin = min;
            rect.anchorMax = max;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
            rect.GetComponent<Image>().color = color;
            return rect;
        }

        static TextMeshProUGUI AddText(RectTransform parent, string value, Vector2 min, Vector2 max, float size, Color color, FontStyles style)
        {
            var rect = new GameObject("Text " + value, typeof(RectTransform), typeof(CanvasRenderer), typeof(TextMeshProUGUI)).GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            rect.anchorMin = min;
            rect.anchorMax = max;
            rect.offsetMin = new Vector2(6, 4);
            rect.offsetMax = new Vector2(-6, -4);
            var text = rect.GetComponent<TextMeshProUGUI>();
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

        static Button AddButton(RectTransform parent, string label, Vector2 min, Vector2 max, Color color, Action action, float size, Color textColor)
        {
            var rect = AddPanel(parent, label + " Button", min, max, color);
            var image = rect.GetComponent<Image>();
            var button = rect.gameObject.AddComponent<Button>();
            button.targetGraphic = image;
            button.onClick.AddListener(() =>
            {
                Pop();
                action();
            });
            var colors = button.colors;
            colors.highlightedColor = Color.Lerp(color, Color.white, .16f);
            colors.pressedColor = Color.Lerp(color, Color.black, .12f);
            button.colors = colors;
            AddText(rect, label, Vector2.zero, Vector2.one, size, textColor, FontStyles.Bold);
            return button;
        }

        static TMP_InputField AddField(RectTransform parent, string placeholderText, string value, Vector2 min, Vector2 max, TMP_InputField.ContentType type, int limit)
        {
            var box = AddPanel(parent, placeholderText + " Field", min, max, new Color(.95f, .93f, .90f));
            var viewport = new GameObject("Text Area", typeof(RectTransform), typeof(RectMask2D)).GetComponent<RectTransform>();
            viewport.SetParent(box, false);
            viewport.anchorMin = Vector2.zero;
            viewport.anchorMax = Vector2.one;
            viewport.offsetMin = new Vector2(14f, 6f);
            viewport.offsetMax = new Vector2(-14f, -6f);
            var placeholder = AddText(viewport, placeholderText, Vector2.zero, Vector2.one, 30, new Color(.55f, .55f, .6f), FontStyles.Bold);
            var text = AddText(viewport, "", Vector2.zero, Vector2.one, 30, DarkText, FontStyles.Bold);
            text.enableAutoSizing = false;
            var field = box.gameObject.AddComponent<TMP_InputField>();
            field.textViewport = viewport;
            field.textComponent = text;
            field.placeholder = placeholder;
            field.contentType = type;
            field.characterLimit = limit;
            field.targetGraphic = box.GetComponent<Image>();
            field.text = value;
            return field;
        }
    }
}
