using UnityEngine;

// Animates and removes the glowing shockwave ring shown after a bomb
// explodes: it races out fast, thins and fades.
[AddComponentMenu("Arena/Blast Visual")]
public sealed class BombBlastVisual : MonoBehaviour
{
    private float radius;
    private float duration;
    private float elapsed;
    private LineRenderer ring;
    private Color startColor;
    private float startWidth;

    public void Initialize(float blastRadius, float lifetime)
    {
        radius = blastRadius;
        duration = lifetime;
        ring = GetComponent<LineRenderer>();
        startColor = ring.startColor;
        startWidth = ring.startWidth;
        transform.localScale = Vector3.one * radius * 0.15f;
    }

    private void Update()
    {
        elapsed += Time.deltaTime;
        float progress = Mathf.Clamp01(elapsed / duration);
        // Fast at first, easing out as it reaches the edge of the blast.
        float eased = 1f - (1f - progress) * (1f - progress) * (1f - progress);
        transform.localScale = Vector3.one * Mathf.Lerp(radius * 0.15f, radius * 1.1f, eased);
        ring.startWidth = ring.endWidth = Mathf.Lerp(startWidth, 0f, progress);
        Color color = startColor;
        color.a *= 1f - progress * progress;
        ring.startColor = ring.endColor = color;
        if (progress >= 1f) Destroy(gameObject);
    }
}
