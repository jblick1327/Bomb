using UnityEngine;

namespace Bom.Unity
{
    // Presentation-only port of Darryn's PlayerItemGlow (same colours, light, tint, pulse and 2 s warning flicker).
    // Driven from copied native round state: BomRoundPlayer.effects (1 invincible, 2 speed boost, 4 slow) and the
    // inclusive end ticks, compared with the snapshot's presentation tick. Nothing here decides an outcome.
    [DisallowMultipleComponent]
    public sealed class BomItemGlow : MonoBehaviour
    {
        public const uint Invincible = 1,
            SpeedBoost = 2,
            Slow = 4;
        const double TicksPerSecond = 60;
        static readonly Color InvincibilityColor = new Color(1f, 0.78f, 0.2f),
            SpeedBoostColor = new Color(0.2f, 0.6f, 1f),
            SlowColor = new Color(0.65f, 0.3f, 1f);
        const float LightIntensity = 3f,
            LightRange = 3f,
            TintStrength = 0.55f,
            PulseSpeed = 1.5f,
            WarningTime = 2f,
            ColorCycleSeconds = 0.6f;
        static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
        static readonly int ColorId = Shader.PropertyToID("_Color");

        Light glowLight;
        Renderer[] bodies;
        MaterialPropertyBlock properties;
        bool tinted;
        Color baseColor = Color.white;
        readonly Color[] active = new Color[2];
        uint shown;
        public uint Shown => shown;

        public void ResetGlow()
        {
            if (glowLight != null)
                glowLight.enabled = false;
            Restore();
            shown = 0;
        }

        void OnDisable() => ResetGlow();

        public void Apply(ulong slot, uint effects, ulong invincibleEnd, ulong speedEnd, double tick, Color body)
        {
            baseColor = body;
            int count = 0;
            double shortest = double.MaxValue;
            uint visible = 0;
            if ((effects & Invincible) != 0 && invincibleEnd + 1 > tick)
            {
                active[count++] = InvincibilityColor;
                shortest = (invincibleEnd + 1 - tick) / TicksPerSecond;
                visible |= Invincible;
            }
            if ((effects & (SpeedBoost | Slow)) != 0 && speedEnd + 1 > tick)
            {
                bool boost = (effects & SpeedBoost) != 0;
                active[count++] = boost ? SpeedBoostColor : SlowColor;
                shortest = System.Math.Min(shortest, (speedEnd + 1 - tick) / TicksPerSecond);
                visible |= boost ? SpeedBoost : Slow;
            }
            if (visible != shown)
            {
                Debug.Log(
                    "BOM UNITY EFFECT player=" + slot + " effects=" + visible + " native=" + effects
                        + " invincible_end=" + invincibleEnd + " speed_end=" + speedEnd + " tick=" + tick.ToString("F1")
                );
                shown = visible;
            }
            if (count == 0)
            {
                if (glowLight != null)
                    glowLight.enabled = false;
                Restore();
                return;
            }
            float now = Time.unscaledTime;
            Color color = active[0];
            if (count > 1)
                color = Color.Lerp(active[0], active[1], Mathf.SmoothStep(0f, 1f, Mathf.PingPong(now / ColorCycleSeconds, 1f)));
            float pulse = 0.5f + 0.5f * Mathf.Sin(now * PulseSpeed * Mathf.PI * 2f);
            if (shortest <= WarningTime)
                pulse = Mathf.Repeat(now * 8f, 1f) < 0.5f ? 1f : 0.15f;
            if (glowLight == null)
                glowLight = CreateLight();
            glowLight.enabled = true;
            glowLight.color = color;
            glowLight.intensity = LightIntensity * Mathf.Lerp(0.45f, 1f, pulse);
            glowLight.range = LightRange;
            SetBody(Color.Lerp(baseColor, color, TintStrength * pulse));
            tinted = true;
        }

        Light CreateLight()
        {
            var child = new GameObject("Item Glow Light");
            var parent = TryGetComponent<BomActorView>(out var view) && view.AuthoredVisual != null ? view.AuthoredVisual : transform;
            child.transform.SetParent(parent, false);
            child.transform.localPosition = Vector3.zero;
            var light = child.AddComponent<Light>();
            light.type = LightType.Point;
            light.shadows = LightShadows.None;
            light.renderMode = LightRenderMode.ForcePixel;
            return light;
        }

        void Restore()
        {
            if (!tinted)
                return;
            SetBody(baseColor);
            tinted = false;
        }

        void SetBody(Color color)
        {
            if (bodies == null)
            {
                properties = new MaterialPropertyBlock();
                bodies = TryGetComponent<BomActorView>(out var view) && view.AuthoredVisual != null
                    ? view.AuthoredVisual.GetComponentsInChildren<SkinnedMeshRenderer>(true)
                    : new Renderer[0];
            }
            foreach (var body in bodies)
            {
                if (body == null)
                    continue;
                body.GetPropertyBlock(properties);
                properties.SetColor(BaseColorId, color);
                properties.SetColor(ColorId, color);
                body.SetPropertyBlock(properties);
            }
        }
    }
}
