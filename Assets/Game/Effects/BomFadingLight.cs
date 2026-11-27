using UnityEngine;

// Fades a light out and then removes it (the blast's flash of light).
public sealed class BomFadingLight : MonoBehaviour
{
    private Light target;
    private float peak, duration, age;

    public void Begin(Light light, float intensity, float seconds)
    {
        target = light;
        peak = intensity;
        duration = Mathf.Max(.01f, seconds);
        target.intensity = peak;
    }

    private void Update()
    {
        age += Time.deltaTime;
        float t = age / duration;
        if (target != null) target.intensity = peak * (1f - t) * (1f - t);
        if (t >= 1f) Destroy(gameObject);
    }
}
