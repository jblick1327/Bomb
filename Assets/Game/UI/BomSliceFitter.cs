using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

// Keeps a sliced chalk sprite's border in proportion to the box it is drawn
// on, so small boxes get a thin edge and big panels don't get a huge one.
[RequireComponent(typeof(Image))]
public sealed class BomSliceFitter : UIBehaviour
{
    [SerializeField] private float maxBorder = 40f;
    [SerializeField, Range(.05f, .5f)] private float sizeFraction = .2f;
    // Scales the whole sprite to the box's height instead, so the art keeps
    // its proportions top to bottom (used by the long title bars).
    [SerializeField] private bool matchHeight;
    private Image image;

    public void Configure(float newMaxBorder, float newSizeFraction)
    {
        maxBorder = newMaxBorder;
        sizeFraction = newSizeFraction;
        matchHeight = false;
        Fit();
    }

    public void ConfigureMatchHeight()
    {
        matchHeight = true;
        Fit();
    }

    protected override void OnEnable()
    {
        base.OnEnable();
        Fit();
    }

    protected override void OnRectTransformDimensionsChange() => Fit();

    private void Fit()
    {
        if (image == null) image = GetComponent<Image>();
        if (image == null || image.sprite == null) return;
        Rect rect = ((RectTransform)transform).rect;
        float multiplier;
        if (matchHeight)
        {
            if (rect.height <= 0f) return;
            // A sprite drawn at multiplier m covers (pixels / m) canvas units.
            multiplier = image.sprite.rect.height / rect.height;
        }
        else
        {
            float shortSide = Mathf.Min(rect.width, rect.height);
            Vector4 border = image.sprite.border;
            float spriteBorder = Mathf.Max(Mathf.Max(border.x, border.y), Mathf.Max(border.z, border.w));
            if (shortSide <= 0f || spriteBorder <= 0f) return;
            float target = Mathf.Clamp(shortSide * sizeFraction, 4f, maxBorder);
            multiplier = spriteBorder / target;
        }
        if (!Mathf.Approximately(image.pixelsPerUnitMultiplier, multiplier))
            image.pixelsPerUnitMultiplier = multiplier;
    }
}
