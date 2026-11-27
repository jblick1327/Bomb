using TMPro;
using UnityEngine;
using UnityEngine.UI;

// The three chalk button colours from Assets/Game/UI/Resources.
public enum BomButtonStyle
{
    Orange, // main actions: LET'S GO, PLAY, START, BUY
    Yellow, // back / leave / secondary actions
    Blue    // headers and option toggles
}

// The game's hand-drawn menu art and font, loaded once from Resources and
// shared by every menu screen built in code.
public static class BomUiSkin
{
    private const string FontPath = "Fonts & Materials/Yellowchalk Regular SDF";
    private const string HudFontPath = "Fonts & Materials/Yellowchalk Regular";

    // All menu text is white, with a thin dark outline so it stays readable on
    // every chalk colour, the yellow buttons included.
    public static readonly Color TextColor = Color.white;
    public static readonly Color TextOutlineColor = new Color(.13f, .09f, .07f, .9f);

    private static TMP_FontAsset font;
    private static Material textMaterial;
    private static Font hudFont;
    private static Sprite panel, buttonOrange, buttonYellow, buttonBlue, headerOrange, headerYellow, headerBlue, arrowLeft, arrowRight;
    private static readonly Texture2D[] countdown = new Texture2D[4];
    private static Texture2D countdownGo;

    // The main menu's button font, for uGUI text.
    public static TMP_FontAsset MenuFont => font != null ? font : font = Load<TMP_FontAsset>(FontPath);
    // The same font as a plain Font, for the UI Toolkit HUD.
    public static Font HudFont => hudFont != null ? hudFont : hudFont = Load<Font>(HudFontPath);

    // MenuFont's material with the dark outline added. One shared copy, so
    // the menus don't make a material per label.
    public static Material MenuTextMaterial
    {
        get
        {
            if (textMaterial != null || MenuFont == null || MenuFont.material == null) return textMaterial;
            textMaterial = new Material(MenuFont.material) { name = "Bom Menu Text (Outline)" };
            textMaterial.SetFloat(ShaderUtilities.ID_OutlineWidth, .2f);
            textMaterial.SetColor(ShaderUtilities.ID_OutlineColor, TextOutlineColor);
            // Fattens the letters a touch so the outline doesn't thin them.
            textMaterial.SetFloat(ShaderUtilities.ID_FaceDilate, .1f);
            ShaderUtilities.UpdateShaderRatios(textMaterial);
            return textMaterial;
        }
    }

    public static Sprite Panel => panel != null ? panel : panel = Load<Sprite>("BomPanel");
    public static Sprite ArrowLeft => arrowLeft != null ? arrowLeft : arrowLeft = Load<Sprite>("BomArrow_left");
    public static Sprite ArrowRight => arrowRight != null ? arrowRight : arrowRight = Load<Sprite>("BomArrow_right");

    public static Sprite Button(BomButtonStyle style)
    {
        switch (style)
        {
            case BomButtonStyle.Yellow: return buttonYellow != null ? buttonYellow : buttonYellow = Load<Sprite>("BomButton_yellow");
            case BomButtonStyle.Blue: return buttonBlue != null ? buttonBlue : buttonBlue = Load<Sprite>("BomButton_blue");
            default: return buttonOrange != null ? buttonOrange : buttonOrange = Load<Sprite>("BomButton_orange");
        }
    }

    // A long version of the button art for the title bars, so a wide, short
    // title doesn't stretch the chalk grain sideways.
    public static Sprite Header(BomButtonStyle style)
    {
        switch (style)
        {
            case BomButtonStyle.Yellow: return headerYellow != null ? headerYellow : headerYellow = Load<Sprite>("BomHeader_yellow");
            case BomButtonStyle.Blue: return headerBlue != null ? headerBlue : headerBlue = Load<Sprite>("BomHeader_blue");
            default: return headerOrange != null ? headerOrange : headerOrange = Load<Sprite>("BomHeader_orange");
        }
    }

    // Makes a menu label white and outlined, in the menu font.
    public static void StyleText(TMP_Text text)
    {
        if (text == null) return;
        if (MenuFont != null) text.font = MenuFont;
        // Set after the font, which resets the material.
        if (MenuTextMaterial != null) text.fontSharedMaterial = MenuTextMaterial;
        text.color = TextColor;
    }

    // The "GO!" shown as the round starts, after 3, 2, 1.
    public static Texture2D CountdownGo => countdownGo != null ? countdownGo : countdownGo = Load<Texture2D>("BomCountdown_Go");

    // The "3", "2", "1" pictures for the start-of-round countdown.
    public static Texture2D CountdownNumber(int number)
    {
        if (number < 1 || number > 3) return null;
        if (countdown[number] == null) countdown[number] = Load<Texture2D>("BomCountdown_" + number);
        return countdown[number];
    }

    // Draws the image as the chalk panel, tinted by the colour given.
    public static void ApplyPanel(Image image, Color tint)
    {
        ApplySliced(image, Panel, tint, 40f, .2f);
    }

    public static void ApplyButton(Image image, BomButtonStyle style)
    {
        ApplySliced(image, Button(style), Color.white, 30f, .25f);
    }

    // The title bar art, drawn at the bar's height so only its long middle
    // stretches, and only a little.
    public static void ApplyHeader(Image image, BomButtonStyle style)
    {
        Sprite sprite = Header(style);
        if (sprite == null)
        {
            ApplyButton(image, style);
            return;
        }
        ApplySliced(image, sprite, Color.white, 0f, 0f, true);
    }

    private static void ApplySliced(Image image, Sprite sprite, Color tint, float maxBorder, float sizeFraction, bool matchHeight = false)
    {
        if (image == null || sprite == null) return;
        image.sprite = sprite;
        image.type = Image.Type.Sliced;
        image.fillCenter = true;
        image.color = tint;
        BomSliceFitter fitter = image.GetComponent<BomSliceFitter>();
        if (fitter == null) fitter = image.gameObject.AddComponent<BomSliceFitter>();
        if (matchHeight) fitter.ConfigureMatchHeight();
        else fitter.Configure(maxBorder, sizeFraction);
    }

    private static T Load<T>(string path) where T : Object
    {
        T asset = Resources.Load<T>(path);
        if (asset == null) Debug.LogWarning($"Menu art '{path}' ({typeof(T).Name}) is missing from a Resources folder.");
        return asset;
    }
}
