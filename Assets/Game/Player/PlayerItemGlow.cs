using UnityEngine;

// Makes a player glow while an item effect is active: a pulsing coloured light
// around them, and their body pulsing toward the effect colour. With two
// effects at once the glow cycles between their colours. In the last few
// seconds it flickers faster as a warning that the effect is running out.
[RequireComponent(typeof(ArenaPlayerController))]
[AddComponentMenu("Arena/Player Item Glow")]
public sealed class PlayerItemGlow : MonoBehaviour
{
    [Header("Effect colours")]
    [SerializeField] private Color invincibilityColor = new Color(1f, 0.78f, 0.2f);
    [SerializeField] private Color speedBoostColor = new Color(0.2f, 0.6f, 1f);
    [SerializeField] private Color slowColor = new Color(0.65f, 0.3f, 1f);

    [Header("Glow")]
    [SerializeField, Min(0f), InspectorName("Light intensity")]
    private float lightIntensity = 3f;
    [SerializeField, Min(0.1f), InspectorName("Light range (units)")]
    private float lightRange = 3f;
    [SerializeField, Range(0f, 1f), InspectorName("Body tint strength")]
    private float tintStrength = 0.55f;
    [SerializeField, Min(0.1f), InspectorName("Pulses per second")]
    private float pulseSpeed = 1.5f;
    [SerializeField, Min(0f), InspectorName("Warning time (seconds)")]
    private float warningTime = 2f;

    private const float ColorCycleSeconds = 0.6f;
    private static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    private static readonly int ColorId = Shader.PropertyToID("_Color");

    private ArenaPlayerController player;
    private Renderer[] bodyRenderers;
    private MaterialPropertyBlock properties;
    private Light glowLight;
    private bool tinted;
    private readonly Color[] activeColors = new Color[2];

    private void Awake()
    {
        player = GetComponent<ArenaPlayerController>();
        bodyRenderers = GetComponentsInChildren<Renderer>(true);
        properties = new MaterialPropertyBlock();
    }

    private void OnDisable()
    {
        // The player is disabled when they die; drop the glow with them.
        if (glowLight != null) glowLight.enabled = false;
        RestoreBodyColor();
    }

    private void LateUpdate()
    {
        int count = 0;
        float shortestRemaining = float.MaxValue;
        if (player.InvincibilityRemaining > 0f)
        {
            activeColors[count++] = invincibilityColor;
            shortestRemaining = player.InvincibilityRemaining;
        }
        if (player.SpeedEffectRemaining > 0f && player.ActiveSpeedEffect != ArenaPlayerController.SpeedEffect.None)
        {
            activeColors[count++] = player.ActiveSpeedEffect == ArenaPlayerController.SpeedEffect.Boost
                ? speedBoostColor : slowColor;
            shortestRemaining = Mathf.Min(shortestRemaining, player.SpeedEffectRemaining);
        }

        if (count == 0)
        {
            if (glowLight != null) glowLight.enabled = false;
            RestoreBodyColor();
            return;
        }

        Color color = activeColors[0];
        if (count > 1)
        {
            // Blend smoothly back and forth between the two effect colours.
            float t = Mathf.PingPong(Time.time / ColorCycleSeconds, 1f);
            color = Color.Lerp(activeColors[0], activeColors[1], Mathf.SmoothStep(0f, 1f, t));
        }

        float pulse = 0.5f + 0.5f * Mathf.Sin(Time.time * pulseSpeed * Mathf.PI * 2f);
        if (shortestRemaining <= warningTime)
        {
            // Fast on/off flicker so players can tell the effect is about to end.
            pulse = Mathf.Repeat(Time.time * 8f, 1f) < 0.5f ? 1f : 0.15f;
        }

        UpdateLight(color, pulse);
        UpdateBodyColor(color, pulse);
    }

    private void UpdateLight(Color color, float pulse)
    {
        if (glowLight == null) glowLight = CreateLight();
        glowLight.enabled = true;
        glowLight.color = color;
        glowLight.intensity = lightIntensity * Mathf.Lerp(0.45f, 1f, pulse);
        glowLight.range = lightRange;
    }

    private Light CreateLight()
    {
        var lightObject = new GameObject("Item Glow Light");
        lightObject.transform.SetParent(transform, false);
        CharacterController body = GetComponent<CharacterController>();
        lightObject.transform.localPosition = body != null ? body.center : Vector3.up;
        Light light = lightObject.AddComponent<Light>();
        light.type = LightType.Point;
        light.shadows = LightShadows.None;
        light.renderMode = LightRenderMode.ForcePixel;
        return light;
    }

    private void UpdateBodyColor(Color effectColor, float pulse)
    {
        Color tint = Color.Lerp(player.CharacterColor, effectColor, tintStrength * pulse);
        SetBodyColor(tint);
        tinted = true;
    }

    private void RestoreBodyColor()
    {
        if (!tinted || player == null) return;
        SetBodyColor(player.CharacterColor);
        tinted = false;
    }

    private void SetBodyColor(Color color)
    {
        foreach (Renderer body in bodyRenderers)
        {
            if (body == null) continue;
            body.GetPropertyBlock(properties);
            properties.SetColor(BaseColorId, color);
            properties.SetColor(ColorId, color);
            body.SetPropertyBlock(properties);
        }
    }
}
