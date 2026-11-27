using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement;

// The look of every level, added when a level loads (any scene with an
// ArenaSession), so the level scenes themselves don't need editing:
//  - post-processing: bloom (so explosions, sparks and item glows shine),
//    gentle tonemapping, a touch more colour and contrast, and a vignette;
//  - drifting motes of light in the air, tinted per level;
//  - a hand-made clay look on the level's plain-coloured surfaces
//    (Bom/Clay Lit: soft blotches, grain, lighter tops). Set UseClaySurfaces
//    to false to keep the original flat colours.
[AddComponentMenu("Arena/Level Atmosphere")]
public sealed class LevelAtmosphere : MonoBehaviour
{
    // Turn the clay surfaces off here to compare with the original flat look.
    public static bool UseClaySurfaces = true;

    // Post-processing amounts.
    private const float BloomThreshold = 1f;
    private const float BloomIntensity = .65f;
    private const float BloomScatter = .65f;
    private const float Contrast = 8f;
    private const float Saturation = 14f;
    private const float Exposure = .08f;
    private const float VignetteAmount = .24f;

    private static Material clayBase;
    // Each original level material and its clay version (or itself, if it
    // isn't a plain-coloured surface).
    private static readonly Dictionary<Material, Material> clayVersions = new Dictionary<Material, Material>();
    private VolumeProfile profile;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Initialize()
    {
        SceneManager.sceneLoaded -= OnSceneLoaded;
        SceneManager.sceneLoaded += OnSceneLoaded;
        OnSceneLoaded(SceneManager.GetActiveScene(), LoadSceneMode.Single);
    }

    private static void OnSceneLoaded(Scene scene, LoadSceneMode mode)
    {
        if (FindFirstObjectByType<ArenaSession>() == null) return;
        if (FindFirstObjectByType<LevelAtmosphere>() != null) return;
        new GameObject("Level Atmosphere").AddComponent<LevelAtmosphere>();
    }

    // The clay version of a level material, for things made from it later
    // (bomb rubble). Returns the material itself if it has none.
    public static Material SurfaceVersion(Material material)
    {
        if (material == null || !UseClaySurfaces) return material;
        return clayVersions.TryGetValue(material, out Material clay) && clay != null ? clay : material;
    }

    private void Awake()
    {
        SetUpPostProcessing();
        SetUpMotes(SceneManager.GetActiveScene().name);
        if (UseClaySurfaces) ApplyClaySurfaces();
    }

    private void OnDestroy()
    {
        if (profile != null) Destroy(profile);
    }

    // ---------- Post-processing ----------

    private void SetUpPostProcessing()
    {
        Camera view = Camera.main;
        if (view != null) view.GetUniversalAdditionalCameraData().renderPostProcessing = true;

        profile = ScriptableObject.CreateInstance<VolumeProfile>();
        profile.name = "Level Atmosphere";
        Bloom bloom = profile.Add<Bloom>(true);
        bloom.threshold.Override(BloomThreshold);
        bloom.intensity.Override(BloomIntensity);
        bloom.scatter.Override(BloomScatter);
        Tonemapping tonemapping = profile.Add<Tonemapping>(true);
        tonemapping.mode.Override(TonemappingMode.Neutral);
        ColorAdjustments colour = profile.Add<ColorAdjustments>(true);
        colour.postExposure.Override(Exposure);
        colour.contrast.Override(Contrast);
        colour.saturation.Override(Saturation);
        Vignette vignette = profile.Add<Vignette>(true);
        vignette.intensity.Override(VignetteAmount);
        vignette.smoothness.Override(.45f);

        Volume volume = gameObject.AddComponent<Volume>();
        volume.isGlobal = true;
        volume.priority = 10f;
        volume.sharedProfile = profile;
    }

    // ---------- Motes ----------

    // Slow specks of light drifting through the arena.
    private void SetUpMotes(string sceneName)
    {
        ArenaLayout layout = FindFirstObjectByType<ArenaLayout>();
        if (layout == null) return;
        Bounds area = layout.ViewBounds;
        Color tint = sceneName.Contains("Yard") ? new Color(1f, .93f, .62f)    // pollen in the sun
            : sceneName.Contains("Tower") ? new Color(.72f, .88f, 1f)          // cool city air
            : new Color(.8f, 1f, .95f);                                        // sea spray

        ParticleSystem motes = BomFx.CreateSystem("Motes", transform, BomFx.Additive(1.6f), 140, 9f);
        // In front of the arena's middle, so they drift over the play area.
        motes.transform.position = new Vector3(area.center.x, area.center.y, layout.Origin.z - layout.Depth * .5f - .3f);
        // Duration and prewarm can only be set while stopped; prewarm then
        // fills the air from the first frame.
        motes.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        ParticleSystem.MainModule main = motes.main;
        main.prewarm = true;
        main.duration = 5f;
        main.startLifetime = new ParticleSystem.MinMaxCurve(7f, 11f);
        main.startSpeed = 0f;
        main.startSize = new ParticleSystem.MinMaxCurve(.05f, .11f);
        main.startColor = tint;
        ParticleSystem.ShapeModule shape = motes.shape;
        shape.enabled = true;
        shape.shapeType = ParticleSystemShapeType.Box;
        shape.scale = new Vector3(area.size.x, area.size.y, 1.5f);
        ParticleSystem.VelocityOverLifetimeModule velocity = motes.velocityOverLifetime;
        velocity.enabled = true;
        velocity.space = ParticleSystemSimulationSpace.World;
        velocity.x = new ParticleSystem.MinMaxCurve(-.12f, .12f);
        velocity.y = new ParticleSystem.MinMaxCurve(.04f, .16f);
        velocity.z = new ParticleSystem.MinMaxCurve(0f, 0f);
        ParticleSystem.NoiseModule noise = motes.noise;
        noise.enabled = true;
        noise.strength = .25f;
        noise.frequency = .25f;
        noise.scrollSpeed = .15f;
        BomFx.FadeOverLife(motes, BomFx.MakeGradient(
            (0f, Color.white, 0f), (.25f, Color.white, .55f), (.75f, Color.white, .55f), (1f, Color.white, 0f)));
        motes.Play();
    }

    // ---------- Clay surfaces ----------

    // Swaps the level's plain-coloured Lit materials (no texture, not see-through,
    // not glowing) for clay versions of the same colour. Players are left alone.
    private static void ApplyClaySurfaces()
    {
        foreach (MeshRenderer renderer in FindObjectsByType<MeshRenderer>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (renderer.GetComponentInParent<ArenaPlayerController>(true) != null) continue;
            Material[] materials = renderer.sharedMaterials;
            bool changed = false;
            for (int i = 0; i < materials.Length; i++)
            {
                Material clay = ClayVersionOf(materials[i]);
                if (clay == materials[i]) continue;
                materials[i] = clay;
                changed = true;
            }
            if (changed) renderer.sharedMaterials = materials;
        }
    }

    private static Material ClayVersionOf(Material source)
    {
        if (source == null) return null;
        if (clayVersions.TryGetValue(source, out Material known) && known != null) return known;

        Material result = source;
        if (IsPlainSurface(source))
        {
            if (clayBase == null) clayBase = Resources.Load<Material>("BomClayLit");
            if (clayBase != null)
            {
                result = new Material(clayBase) { name = source.name + " (Clay)" };
                Color colour = source.HasProperty("_BaseColor") ? source.GetColor("_BaseColor") : source.color;
                result.SetColor("_BaseColor", colour);
                TuneClay(result, colour);
            }
        }
        clayVersions[source] = result;
        return result;
    }

    private static bool IsPlainSurface(Material material)
    {
        string shader = material.shader != null ? material.shader.name : string.Empty;
        if (shader != "Universal Render Pipeline/Lit" && shader != "Universal Render Pipeline/Simple Lit") return false;
        if (material.HasProperty("_BaseMap") && material.GetTexture("_BaseMap") != null) return false;
        if (material.HasProperty("_Surface") && material.GetFloat("_Surface") > .5f) return false;
        if (material.IsKeywordEnabled("_EMISSION")) return false;
        return true;
    }

    // A little more character for grass and earth, judged by colour.
    private static void TuneClay(Material clay, Color colour)
    {
        Color.RGBToHSV(colour, out float hue, out float saturation, out float value);
        bool grassy = hue > .18f && hue < .45f && saturation > .3f;
        bool earthy = hue < .12f && saturation > .4f && value < .5f;
        if (grassy)
        {
            clay.SetFloat("_Mottle", .16f);
            clay.SetFloat("_Grain", .07f);
            clay.SetFloat("_TopLight", .22f);
        }
        else if (earthy)
        {
            clay.SetFloat("_Mottle", .14f);
            clay.SetFloat("_Grain", .08f);
            clay.SetFloat("_Bands", .05f);
        }
        else
        {
            clay.SetFloat("_Mottle", .1f);
            clay.SetFloat("_Grain", .045f);
            clay.SetFloat("_TopLight", .1f);
        }
    }
}
