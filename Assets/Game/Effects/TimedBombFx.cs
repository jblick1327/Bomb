using UnityEngine;

// Makes a timed bomb read as a threat. A red glow sits behind it; once its
// fuse is lit the glow pulses faster and faster (in step with the bomb's own
// white flashing), the fuse sparks get busier, and a faint red ring shows how
// far the blast will reach. BombDropper adds it to every timed bomb.
[AddComponentMenu("Arena/Timed Bomb Effects")]
public sealed class TimedBombFx : MonoBehaviour
{
    private static readonly int TintColorId = Shader.PropertyToID("_TintColor");
    private static readonly Color Danger = new Color(1f, .22f, .12f);

    private FallingBomb bomb;
    private ParticleSystem sparks;
    private Transform glow;
    private Renderer glowRenderer;
    private MaterialPropertyBlock glowProperties;
    private LineRenderer ring;
    private float dangerRadius;
    private float frontOffset;
    private float pulse;

    // dangerRadius: how far the blast reaches. frontOffset: how far in front
    // of the bomb to draw the ring, so the level's blocks don't hide it.
    public void Initialize(ParticleSystem fuseSparks, float radius, float ringFrontOffset)
    {
        sparks = fuseSparks;
        dangerRadius = radius;
        frontOffset = ringFrontOffset;
        CreateGlow();
        CreateRing();
    }

    private void Start() => bomb = GetComponent<FallingBomb>();

    private void CreateGlow()
    {
        var glowObject = new GameObject("Danger Glow");
        glow = glowObject.transform;
        glow.SetParent(transform, false);
        glowObject.AddComponent<MeshFilter>().sharedMesh = BomFx.GlowQuad();
        var renderer = glowObject.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = BomFx.Additive(2f);
        renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        renderer.receiveShadows = false;
        glowRenderer = renderer;
        glowProperties = new MaterialPropertyBlock();
    }

    private void CreateRing()
    {
        var ringObject = new GameObject("Danger Ring");
        // Not a child: it stays upright and unscaled whatever the bomb does.
        ringObject.transform.SetParent(transform.parent, false);
        ring = ringObject.AddComponent<LineRenderer>();
        ring.sharedMaterial = BomFx.Strip(2f);
        ring.useWorldSpace = false;
        ring.loop = true;
        ring.positionCount = 64;
        ring.startWidth = ring.endWidth = .09f;
        ring.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        ring.receiveShadows = false;
        for (int i = 0; i < ring.positionCount; i++)
        {
            float angle = i * Mathf.PI * 2f / ring.positionCount;
            ring.SetPosition(i, new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0f) * dangerRadius);
        }
        ring.enabled = false;
    }

    private void OnDestroy()
    {
        if (ring != null) Destroy(ring.gameObject);
    }

    private void LateUpdate()
    {
        if (glow == null) return;
        bool lit = bomb != null && bomb.FuseLit;
        float left = lit ? bomb.FuseLeft : 1f;
        float urgency = 1f - left;   // 0 when lit, 1 at the bang

        // Pulse faster as the fuse runs down (4 to 12 a second, like the flash).
        float speed = lit ? Mathf.Lerp(4f, 12f, urgency) : 1.5f;
        pulse += Time.deltaTime * speed;
        float beat = Mathf.PingPong(pulse, 1f);

        Camera view = Camera.main;
        if (view != null)
        {
            glow.rotation = view.transform.rotation;
            glow.position = transform.position + view.transform.forward * .3f;
        }
        Vector3 parentScale = transform.lossyScale;
        float size = lit ? Mathf.Lerp(1.3f, 2f, urgency) * (.9f + .2f * beat) : 1.1f;
        glow.localScale = new Vector3(size / Mathf.Max(parentScale.x, .0001f),
            size / Mathf.Max(parentScale.y, .0001f), size / Mathf.Max(parentScale.z, .0001f));
        Color tint = Danger;
        tint.a = lit ? Mathf.Lerp(.35f, .9f, beat) : .28f;
        glowProperties.SetColor(TintColorId, tint);
        glowRenderer.SetPropertyBlock(glowProperties);

        if (sparks != null)
        {
            ParticleSystem.EmissionModule emission = sparks.emission;
            emission.rateOverTime = lit ? Mathf.Lerp(40f, 110f, urgency) : 28f;
        }

        if (ring != null)
        {
            ring.enabled = lit;
            if (lit)
            {
                ring.transform.position = transform.position + Vector3.back * frontOffset;
                Color ringColor = Danger;
                ringColor.a = Mathf.Lerp(.25f, .75f, beat) * Mathf.Lerp(.6f, 1f, urgency);
                ring.startColor = ring.endColor = ringColor;
            }
        }
    }
}
