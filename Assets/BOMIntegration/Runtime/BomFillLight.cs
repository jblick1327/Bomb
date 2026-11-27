using System;
using System.Globalization;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Bom.Unity
{
    // Presentation only (owner request 2026-11-27, "the Tower is too dark, craters are hard to read"). Darryn's sun points
    // almost straight down (pitch ~87.5 degrees) in every level, so the faces the camera sees (fronts) get ambient light
    // only and, in the Tower, each floor shadows the one below. This adds a shadowless fill light from the camera side,
    // tilted down and to one side, so fronts read and the left and right cut sides of a crater shade differently.
    // It is added at runtime to the online scenes; Darryn's scenes and the scene files are not changed, and nothing here
    // touches native state. Default: Tower only. --bom-fill-light <intensity> sets it for every online level (0 = off).
    public static class BomFillLight
    {
        // Online scene name -> default fill intensity. Levels not listed get none unless --bom-fill-light is given.
        static float DefaultFor(string scene) => scene == "NetworkTower" ? 0.6f : 0f;

        // Down 30 degrees (camera tilt is 10) and turned 30 degrees, so light arrives from the front-right and above.
        static readonly Quaternion Direction = Quaternion.Euler(30f, -30f, 0f);
        static readonly Color Tint = new Color(1f, 0.97f, 0.92f);

        static readonly float Override = ReadOverride();

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Install()
        {
            SceneManager.sceneLoaded -= OnSceneLoaded;
            SceneManager.sceneLoaded += OnSceneLoaded;
            OnSceneLoaded(SceneManager.GetActiveScene(), LoadSceneMode.Single);
        }

        static void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            if (!scene.IsValid() || UnityEngine.Object.FindFirstObjectByType<BomClientBehaviour>() == null)
                return; // Darryn's offline scenes and the menu keep their own lighting.
            TuneSun(scene);
            float intensity = Override >= 0 ? Override : DefaultFor(scene.name);
            if (intensity <= 0)
                return;
            var obj = new GameObject("BOM fill light");
            SceneManager.MoveGameObjectToScene(obj, scene);
            obj.transform.rotation = Direction;
            var light = obj.AddComponent<Light>();
            light.type = LightType.Directional;
            light.shadows = LightShadows.None;
            light.color = Tint;
            light.intensity = intensity;
            // Below the sun (intensity 2): URP picks the brightest directional light as its main light, so the sun stays it.
            light.renderMode = LightRenderMode.ForcePixel;
            Debug.Log(
                "BOM FILL LIGHT scene=" + scene.name + " intensity=" + intensity.ToString("0.###", CultureInfo.InvariantCulture)
            );
        }

        // Square shadows: the sun grazes the front faces (about 2.5 degrees), so they shadow themselves in blocks the size
        // of a shadow-map texel. --bom-sun-shadow-strength <0..1> scales the sun's shadow on the online scenes (0 = none).
        static readonly float SunShadowStrength = ReadFloat("--bom-sun-shadow-strength");

        static void TuneSun(Scene scene)
        {
            float strength = SunShadowStrength >= 0 ? Mathf.Min(SunShadowStrength, 1f) : DefaultSunShadow(scene.name);
            if (strength < 0)
                return;
            foreach (var light in UnityEngine.Object.FindObjectsByType<Light>(FindObjectsSortMode.None))
            {
                if (light.type != LightType.Directional || light.shadows == LightShadows.None || light.gameObject.scene != scene)
                    continue;
                if (strength <= 0)
                    light.shadows = LightShadows.None;
                else
                    light.shadowStrength = strength;
                Debug.Log(
                    "BOM SUN SHADOW scene=" + scene.name + " light=" + light.name + " strength="
                        + strength.ToString("0.###", CultureInfo.InvariantCulture)
                );
            }
        }

        // -1 leaves Darryn's sun as authored. Tower: off (A/B 2026-11-27, evidence/TOWER-LOOK: the squares go, floors read).
        static float DefaultSunShadow(string scene) => scene == "NetworkTower" ? 0f : -1f;

        static float ReadOverride() => ReadFloat("--bom-fill-light");

        static float ReadFloat(string key)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, key);
            return
                i >= 0
                && i + 1 < args.Length
                && float.TryParse(args[i + 1], NumberStyles.Float, CultureInfo.InvariantCulture, out float value)
                && value >= 0
                ? value
                : -1f;
        }
    }
}
