using UnityEngine;

namespace Bom.Unity
{
    // A fainter second blast ring for the native graze zone (BomRoundInfo.graze_radius). Same timing as Darryn's
    // BombBlastVisual (grows from 15 % to full over 0.35 s while thinning out) but half the width and a dimmer
    // copy of the blast colour. The blast material is opaque, so "fainter" means darker and thinner, not alpha.
    public sealed class BomGrazeRing : MonoBehaviour
    {
        const int Points = 64;
        const float Lifetime = .35f,
            StartWidth = .06f,
            Dim = .5f;
        LineRenderer ring;
        float radius;
        double started;

        public static void Show(Transform parent, LineRenderer blast, Vector3 center, float radius)
        {
            if (blast == null || radius <= 0)
                return;
            var root = new GameObject("Native graze ring");
            root.transform.SetParent(parent, false);
            root.transform.position = center;
            var line = root.AddComponent<LineRenderer>();
            line.sharedMaterial = blast.sharedMaterial;
            line.useWorldSpace = false;
            line.loop = true;
            line.positionCount = Points;
            line.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            line.receiveShadows = false;
            for (int i = 0; i < Points; i++)
            {
                float angle = i * Mathf.PI * 2 / Points;
                line.SetPosition(i, new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0));
            }
            var material = blast.sharedMaterial;
            if (material != null)
            {
                Color color = material.HasProperty("_BaseColor") ? material.GetColor("_BaseColor") : material.color;
                color = new Color(color.r * Dim, color.g * Dim, color.b * Dim, color.a);
                var properties = new MaterialPropertyBlock();
                properties.SetColor("_BaseColor", color);
                properties.SetColor("_Color", color);
                line.SetPropertyBlock(properties);
            }
            var view = root.AddComponent<BomGrazeRing>();
            view.ring = line;
            view.radius = radius;
            view.started = BomSession.Now;
            view.Step();
        }

        void Update() => Step();

        void Step()
        {
            float progress = Mathf.Clamp01((float)(BomSession.Now - started) / Lifetime);
            transform.localScale = Vector3.one * Mathf.Lerp(radius * .15f, radius, progress);
            ring.startWidth = ring.endWidth = Mathf.Lerp(StartWidth, 0f, progress);
            if (progress >= 1f)
                Destroy(gameObject);
        }
    }
}
