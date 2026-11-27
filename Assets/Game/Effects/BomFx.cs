using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

// The game's particle effects: shared glow materials, a builder for particle
// systems, and the one-shot bursts (bomb explosions, item pickups). Bursts
// reuse a handful of systems per level and Emit into them, rather than
// creating new objects each time.
public static class BomFx
{
    private static Material additiveBase, softBase;
    private static readonly Dictionary<int, Material> additive = new Dictionary<int, Material>();
    private static readonly Dictionary<int, Material> strips = new Dictionary<int, Material>();
    private static Material soft;

    // Glowing, added on top of what's behind (sparks, fire, auras).
    // intensity > 1 makes it bright enough for the bloom.
    public static Material Additive(float intensity)
    {
        int key = Mathf.RoundToInt(intensity * 100f);
        if (additive.TryGetValue(key, out Material material) && material != null) return material;
        if (additiveBase == null) additiveBase = Resources.Load<Material>("BomFxAdditive");
        if (additiveBase == null) return null;
        material = new Material(additiveBase) { name = "Bom FX Additive x" + intensity };
        material.SetFloat("_Intensity", intensity);
        additive[key] = material;
        return material;
    }

    // Like Additive, but faded only across its width, for line renderers.
    public static Material Strip(float intensity)
    {
        int key = Mathf.RoundToInt(intensity * 100f);
        if (strips.TryGetValue(key, out Material material) && material != null) return material;
        Material source = Additive(intensity);
        if (source == null) return null;
        material = new Material(source) { name = "Bom FX Strip x" + intensity };
        material.SetFloat("_Strip", 1f);
        material.SetFloat("_Softness", 1f);
        strips[key] = material;
        return material;
    }

    // Ordinary see-through puffs (smoke, dust).
    public static Material Soft()
    {
        if (soft != null) return soft;
        if (softBase == null) softBase = Resources.Load<Material>("BomFxSoft");
        if (softBase == null) return null;
        return soft = new Material(softBase) { name = "Bom FX Soft" };
    }

    // A particle system with the settings every effect here shares: world
    // space, round billboards, no shadows. emitRate 0 makes one that only
    // releases particles when Emit is called.
    public static ParticleSystem CreateSystem(string name, Transform parent, Material material, int maxParticles, float emitRate = 0f)
    {
        var holder = new GameObject(name);
        holder.SetActive(false);
        holder.transform.SetParent(parent, false);
        ParticleSystem system = holder.AddComponent<ParticleSystem>();
        ParticleSystem.MainModule main = system.main;
        main.playOnAwake = true;
        main.loop = true;
        main.duration = 1f;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.scalingMode = ParticleSystemScalingMode.Local;
        main.maxParticles = maxParticles;
        main.startSpeed = 0f;
        main.startLifetime = 1f;
        main.startSize = 0.2f;
        ParticleSystem.EmissionModule emission = system.emission;
        emission.rateOverTime = emitRate;
        ParticleSystem.ShapeModule shape = system.shape;
        shape.enabled = false;
        ParticleSystemRenderer renderer = holder.GetComponent<ParticleSystemRenderer>();
        renderer.sharedMaterial = material;
        renderer.renderMode = ParticleSystemRenderMode.Billboard;
        renderer.shadowCastingMode = ShadowCastingMode.Off;
        renderer.receiveShadows = false;
        renderer.lightProbeUsage = LightProbeUsage.Off;
        renderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
        holder.SetActive(true);
        return system;
    }

    public static void FadeOverLife(ParticleSystem system, Gradient gradient)
    {
        ParticleSystem.ColorOverLifetimeModule color = system.colorOverLifetime;
        color.enabled = true;
        color.color = gradient;
    }

    public static void SizeOverLife(ParticleSystem system, float start, float end)
    {
        ParticleSystem.SizeOverLifetimeModule size = system.sizeOverLifetime;
        size.enabled = true;
        size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, start, 1f, end));
    }

    // Slows particles down the way air would.
    public static void Drag(ParticleSystem system, float drag)
    {
        ParticleSystem.LimitVelocityOverLifetimeModule limit = system.limitVelocityOverLifetime;
        limit.enabled = true;
        limit.limit = 1000f;
        limit.drag = drag;
        limit.multiplyDragByParticleSize = false;
        limit.multiplyDragByParticleVelocity = true;
    }

    // Colour stops (time, colour) and alpha stops (time, alpha) in one call.
    public static Gradient MakeGradient(params (float time, Color color, float alpha)[] stops)
    {
        var colors = new GradientColorKey[stops.Length];
        var alphas = new GradientAlphaKey[stops.Length];
        for (int i = 0; i < stops.Length; i++)
        {
            colors[i] = new GradientColorKey(stops[i].color, stops[i].time);
            alphas[i] = new GradientAlphaKey(stops[i].alpha, stops[i].time);
        }
        var gradient = new Gradient();
        gradient.SetKeys(colors, alphas);
        return gradient;
    }

    // ---------- Pooled bursts ----------

    private static Transform root;
    private static ParticleSystem flash, fire, sparks, smoke, dust, glints;

    // One set per level; the level's objects take it with them when it unloads.
    private static void EnsureSystems()
    {
        if (root != null) return;
        root = new GameObject("Bom Effects").transform;

        flash = CreateSystem("Flash", root, Additive(4f), 16);
        FadeOverLife(flash, MakeGradient((0f, Color.white, 1f), (1f, Color.white, 0f)));
        SizeOverLife(flash, 0.6f, 1.25f);

        fire = CreateSystem("Fireball", root, Additive(2.4f), 160);
        FadeOverLife(fire, MakeGradient(
            (0f, new Color(1f, .95f, .65f), 1f),
            (.3f, new Color(1f, .6f, .18f), .95f),
            (.65f, new Color(.85f, .2f, .06f), .6f),
            (1f, new Color(.4f, .08f, .04f), 0f)));
        SizeOverLife(fire, .55f, 1.25f);
        Drag(fire, 4f);

        sparks = CreateSystem("Sparks", root, Additive(3.2f), 200);
        ParticleSystemRenderer sparkRenderer = sparks.GetComponent<ParticleSystemRenderer>();
        sparkRenderer.renderMode = ParticleSystemRenderMode.Stretch;
        sparkRenderer.velocityScale = .07f;
        sparkRenderer.lengthScale = 1.5f;
        ParticleSystem.MainModule sparkMain = sparks.main;
        sparkMain.gravityModifier = .6f;
        FadeOverLife(sparks, MakeGradient(
            (0f, new Color(1f, .95f, .7f), 1f),
            (.6f, new Color(1f, .6f, .15f), .9f),
            (1f, new Color(1f, .35f, .05f), 0f)));
        Drag(sparks, 1.5f);

        smoke = CreateSystem("Smoke", root, Soft(), 120);
        ParticleSystem.MainModule smokeMain = smoke.main;
        smokeMain.gravityModifier = -.04f;
        FadeOverLife(smoke, MakeGradient(
            (0f, new Color(.25f, .22f, .2f), 0f),
            (.15f, new Color(.22f, .2f, .19f), .55f),
            (1f, new Color(.42f, .4f, .39f), 0f)));
        SizeOverLife(smoke, .6f, 1.7f);
        Drag(smoke, 2.5f);
        ParticleSystem.RotationOverLifetimeModule spin = smoke.rotationOverLifetime;
        spin.enabled = true;
        spin.z = new ParticleSystem.MinMaxCurve(-.8f, .8f);

        dust = CreateSystem("Dust", root, Soft(), 160);
        ParticleSystem.MainModule dustMain = dust.main;
        dustMain.gravityModifier = .7f;
        FadeOverLife(dust, MakeGradient((0f, Color.white, 1f), (.7f, Color.white, .8f), (1f, Color.white, 0f)));
        SizeOverLife(dust, 1f, .55f);
        Drag(dust, 1.2f);

        glints = CreateSystem("Glints", root, Additive(2.6f), 200);
        FadeOverLife(glints, MakeGradient((0f, Color.white, 1f), (.6f, Color.white, .8f), (1f, Color.white, 0f)));
        SizeOverLife(glints, 1f, .2f);
        Drag(glints, 3f);
    }

    // A bomb going off at position (on the arena's front face), with blast
    // radius radius. dustColor is the ground it dug into, if any.
    public static void Explosion(Vector3 position, float radius, Color? dustColor)
    {
        EnsureSystems();
        var emit = new ParticleSystem.EmitParams { applyShapeToPosition = false };

        // A white-hot flash the size of the blast.
        emit.position = position;
        emit.velocity = Vector3.zero;
        emit.startSize = radius * 1.5f;
        emit.startLifetime = .16f;
        emit.startColor = new Color(1f, .93f, .78f);
        emit.rotation = 0f;
        flash.Emit(emit, 1);

        // The fireball: hot puffs thrown out, slowed by the air, cooling to red.
        for (int i = 0; i < 16; i++)
        {
            Vector2 direction = Random.insideUnitCircle.normalized;
            emit.position = position + (Vector3)(direction * radius * Random.Range(0f, .2f));
            emit.velocity = new Vector3(direction.x, direction.y * .85f + .15f, Random.Range(-.3f, .3f)) * radius * Random.Range(1.2f, 3f);
            emit.startSize = radius * Random.Range(.35f, .62f);
            emit.startLifetime = Random.Range(.32f, .55f);
            emit.startColor = Color.white;
            emit.rotation = Random.Range(0f, 360f);
            fire.Emit(emit, 1);
        }

        // Sparks streaking out and arcing down.
        for (int i = 0; i < 24; i++)
        {
            Vector2 direction = Random.insideUnitCircle.normalized;
            emit.position = position;
            emit.velocity = new Vector3(direction.x, direction.y + .35f, Random.Range(-.4f, .4f)) * Random.Range(4.5f, 10f);
            emit.startSize = Random.Range(.05f, .1f);
            emit.startLifetime = Random.Range(.35f, .75f);
            emit.startColor = Color.white;
            emit.rotation = 0f;
            sparks.Emit(emit, 1);
        }

        // Smoke that rolls out and hangs a moment after the fire.
        for (int i = 0; i < 9; i++)
        {
            Vector2 direction = Random.insideUnitCircle;
            emit.position = position + (Vector3)(direction * radius * .3f) + Vector3.back * .05f;
            emit.velocity = new Vector3(direction.x, direction.y * .6f + .35f, 0f) * Random.Range(.6f, 1.8f);
            emit.startSize = radius * Random.Range(.45f, .75f);
            emit.startLifetime = Random.Range(1.1f, 1.8f);
            emit.startColor = Color.white;
            emit.rotation = Random.Range(0f, 360f);
            smoke.Emit(emit, 1);
        }

        // Dirt kicked up in the colour of the ground that was hit.
        if (dustColor.HasValue)
        {
            Color baseColor = dustColor.Value;
            for (int i = 0; i < 14; i++)
            {
                float side = Random.Range(-1f, 1f);
                emit.position = position + new Vector3(side * radius * .3f, 0f, 0f);
                emit.velocity = new Vector3(side * Random.Range(1.5f, 3.5f), Random.Range(2.5f, 5.5f), Random.Range(-.6f, .6f));
                emit.startSize = Random.Range(.12f, .3f);
                emit.startLifetime = Random.Range(.6f, 1.1f);
                emit.startColor = Color.Lerp(baseColor, Color.white, Random.Range(0f, .2f));
                emit.rotation = Random.Range(0f, 360f);
                dust.Emit(emit, 1);
            }
        }

        // A brief warm light on everything nearby.
        var lightObject = new GameObject("Blast Light");
        lightObject.transform.SetParent(root, false);
        lightObject.transform.position = position + Vector3.back * .5f;
        Light light = lightObject.AddComponent<Light>();
        light.type = LightType.Point;
        light.color = new Color(1f, .62f, .28f);
        light.range = radius * 4f;
        light.shadows = LightShadows.None;
        lightObject.AddComponent<BomFadingLight>().Begin(light, 7f, .32f);
    }

    // An item picked up: a burst of glints in its colour and a soft flash.
    public static void Pickup(Vector3 position, Color color)
    {
        EnsureSystems();
        var emit = new ParticleSystem.EmitParams { applyShapeToPosition = false };
        emit.position = position;
        emit.velocity = Vector3.zero;
        emit.startSize = 1.3f;
        emit.startLifetime = .22f;
        emit.startColor = Color.Lerp(color, Color.white, .35f);
        emit.rotation = 0f;
        flash.Emit(emit, 1);

        for (int i = 0; i < 18; i++)
        {
            float angle = i * Mathf.PI * 2f / 18f + Random.Range(-.15f, .15f);
            Vector3 direction = new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0f);
            emit.position = position;
            emit.velocity = (direction + Vector3.up * .4f) * Random.Range(2.2f, 4.2f);
            emit.startSize = Random.Range(.08f, .16f);
            emit.startLifetime = Random.Range(.4f, .7f);
            emit.startColor = Color.Lerp(color, Color.white, Random.Range(.2f, .6f));
            glints.Emit(emit, 1);
        }
    }

    // Sparks fizzing off a bomb's fuse. tip is where the fuse is.
    public static ParticleSystem AddFuseSparks(Transform tip)
    {
        ParticleSystem system = CreateSystem("Fuse Sparks", tip, Additive(3f), 80, 28f);
        system.transform.localPosition = Vector3.zero;
        ParticleSystem.MainModule main = system.main;
        main.startLifetime = new ParticleSystem.MinMaxCurve(.12f, .28f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(.6f, 1.8f);
        main.startSize = new ParticleSystem.MinMaxCurve(.03f, .07f);
        main.gravityModifier = .25f;
        ParticleSystem.ShapeModule shape = system.shape;
        shape.enabled = true;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = .02f;
        FadeOverLife(system, MakeGradient(
            (0f, new Color(1f, .95f, .6f), 1f),
            (1f, new Color(1f, .45f, .1f), 0f)));
        return system;
    }

    private static Mesh glowQuad;

    // A 1x1 quad with white vertex colours, for camera-facing glows (the
    // glow shader multiplies by vertex colour).
    public static Mesh GlowQuad()
    {
        if (glowQuad != null) return glowQuad;
        glowQuad = new Mesh { name = "Glow Quad" };
        glowQuad.vertices = new[] { new Vector3(-.5f, -.5f, 0f), new Vector3(.5f, -.5f, 0f), new Vector3(-.5f, .5f, 0f), new Vector3(.5f, .5f, 0f) };
        glowQuad.uv = new[] { new Vector2(0f, 0f), new Vector2(1f, 0f), new Vector2(0f, 1f), new Vector2(1f, 1f) };
        glowQuad.colors = new[] { Color.white, Color.white, Color.white, Color.white };
        glowQuad.triangles = new[] { 0, 2, 1, 2, 3, 1 };
        glowQuad.RecalculateBounds();
        return glowQuad;
    }
}
