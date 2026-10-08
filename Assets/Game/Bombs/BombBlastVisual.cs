using UnityEngine;

// Animates and removes the expanding ring shown after a bomb explodes.
[AddComponentMenu("Arena/Blast Visual")]
public sealed class BombBlastVisual : MonoBehaviour
{
    private float radius;
    private float duration;
    private float elapsed;
    private LineRenderer ring;

    public void Initialize(float blastRadius, float lifetime)
    {
        radius = blastRadius;
        duration = lifetime;
        ring = GetComponent<LineRenderer>();
        transform.localScale = Vector3.one * radius * 0.15f;
    }

    private void Update()
    {
        elapsed += Time.deltaTime;
        float progress = Mathf.Clamp01(elapsed / duration);
        transform.localScale = Vector3.one * Mathf.Lerp(radius * 0.15f, radius, progress);
        ring.startWidth = ring.endWidth = Mathf.Lerp(0.12f, 0f, progress);
        if (progress >= 1f) Destroy(gameObject);
    }
}
