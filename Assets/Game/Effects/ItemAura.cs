using UnityEngine;

// Makes a falling item stand out: a soft pulsing glow behind it in the item's
// colour, sparkles drifting up off it, and a slow spin. BombDropper adds it
// to every item it drops.
[AddComponentMenu("Arena/Item Aura")]
public sealed class ItemAura : MonoBehaviour
{
    private const float SpinSpeed = 110f;   // degrees per second
    private const float GlowSize = 1.6f;    // across, in world units
    private static Mesh quad;
    private static readonly int TintColorId = Shader.PropertyToID("_TintColor");

    private Transform glow;
    private Renderer glowRenderer;
    private MaterialPropertyBlock glowProperties;
    private Color color;
    private Rigidbody body;
    private SphereCollider sphere;
    private Quaternion startRotation;
    private bool spins;
    private float spinAngle;
    private float pulseOffset;

    // Each item's colour, also used for its pickup burst.
    public static Color ColorFor(CollectibleItemType type)
    {
        switch (type)
        {
            case CollectibleItemType.SilverCoin: return new Color(.82f, .88f, 1f);
            case CollectibleItemType.GoldCoin: return new Color(1f, .78f, .2f);
            case CollectibleItemType.Invincibility: return new Color(.35f, .85f, 1f);
            case CollectibleItemType.Slow: return new Color(.7f, .45f, 1f);
            default: return new Color(.4f, 1f, .45f);   // speed boost
        }
    }

    public void Initialize(CollectibleItemType type)
    {
        color = ColorFor(type);
        body = GetComponent<Rigidbody>();
        sphere = GetComponent<SphereCollider>();
        startRotation = transform.rotation;
        pulseOffset = Random.Range(0f, 10f);
        // Spin only if the collider sits on the pivot, so turning the item
        // doesn't swing its collider around.
        spins = sphere == null || new Vector2(sphere.center.x, sphere.center.z).magnitude < .05f;

        Vector3 center = sphere != null ? transform.TransformPoint(sphere.center) : transform.position;
        CreateGlow(center);
        CreateSparkles(center);
    }

    private void CreateGlow(Vector3 center)
    {
        if (quad == null) quad = CreateQuad();
        var glowObject = new GameObject("Aura Glow");
        glow = glowObject.transform;
        glow.SetParent(transform, true);
        glow.position = center;
        glowObject.AddComponent<MeshFilter>().sharedMesh = quad;
        var renderer = glowObject.AddComponent<MeshRenderer>();
        renderer.sharedMaterial = BomFx.Additive(1.8f);
        renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        renderer.receiveShadows = false;
        glowRenderer = renderer;
        glowProperties = new MaterialPropertyBlock();
    }

    // A 1x1 quad with white vertex colours (the glow shader multiplies by them).
    private static Mesh CreateQuad()
    {
        var mesh = new Mesh { name = "Aura Quad" };
        mesh.vertices = new[] { new Vector3(-.5f, -.5f, 0f), new Vector3(.5f, -.5f, 0f), new Vector3(-.5f, .5f, 0f), new Vector3(.5f, .5f, 0f) };
        mesh.uv = new[] { new Vector2(0f, 0f), new Vector2(1f, 0f), new Vector2(0f, 1f), new Vector2(1f, 1f) };
        mesh.colors = new[] { Color.white, Color.white, Color.white, Color.white };
        mesh.triangles = new[] { 0, 2, 1, 2, 3, 1 };
        mesh.RecalculateBounds();
        return mesh;
    }

    private void CreateSparkles(Vector3 center)
    {
        ParticleSystem sparkles = BomFx.CreateSystem("Aura Sparkles", transform, BomFx.Additive(2.6f), 40, 8f);
        sparkles.transform.position = center;
        ParticleSystem.MainModule main = sparkles.main;
        main.startLifetime = new ParticleSystem.MinMaxCurve(.7f, 1.2f);
        main.startSpeed = 0f;
        main.startSize = new ParticleSystem.MinMaxCurve(.05f, .11f);
        main.startColor = Color.Lerp(color, Color.white, .35f);
        ParticleSystem.ShapeModule shape = sparkles.shape;
        shape.enabled = true;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = .4f;
        ParticleSystem.VelocityOverLifetimeModule velocity = sparkles.velocityOverLifetime;
        velocity.enabled = true;
        velocity.space = ParticleSystemSimulationSpace.World;
        velocity.x = new ParticleSystem.MinMaxCurve(-.08f, .08f);
        velocity.y = new ParticleSystem.MinMaxCurve(.35f, .7f);
        velocity.z = new ParticleSystem.MinMaxCurve(0f, 0f);
        // Each sparkle grows in and shrinks away: a twinkle.
        ParticleSystem.SizeOverLifetimeModule size = sparkles.sizeOverLifetime;
        size.enabled = true;
        size.size = new ParticleSystem.MinMaxCurve(1f, new AnimationCurve(
            new Keyframe(0f, 0f), new Keyframe(.3f, 1f), new Keyframe(1f, 0f)));
        BomFx.FadeOverLife(sparkles, BomFx.MakeGradient((0f, Color.white, 1f), (1f, Color.white, 0f)));
    }

    private void FixedUpdate()
    {
        if (!spins || body == null) return;
        spinAngle = (spinAngle + SpinSpeed * Time.fixedDeltaTime) % 360f;
        body.MoveRotation(Quaternion.AngleAxis(spinAngle, Vector3.up) * startRotation);
    }

    // The glow faces the camera, sits just behind the item, and breathes.
    private void LateUpdate()
    {
        if (glow == null) return;
        Camera view = Camera.main;
        Vector3 center = sphere != null ? transform.TransformPoint(sphere.center) : transform.position;
        if (view != null)
        {
            glow.rotation = view.transform.rotation;
            glow.position = center + view.transform.forward * .25f;
        }
        float pulse = .5f + .5f * Mathf.Sin((Time.time + pulseOffset) * 3.2f);
        // World size regardless of the item's own scale.
        Vector3 parentScale = transform.lossyScale;
        float size = GlowSize * (.9f + .15f * pulse);
        glow.localScale = new Vector3(size / Mathf.Max(parentScale.x, .0001f),
            size / Mathf.Max(parentScale.y, .0001f), size / Mathf.Max(parentScale.z, .0001f));
        Color tint = color;
        tint.a = .38f + .22f * pulse;
        glowProperties.SetColor(TintColorId, tint);
        glowRenderer.SetPropertyBlock(glowProperties);
    }
}
