using System;
using System.Globalization;
using UnityEngine;

namespace Bom.Unity
{
    // G3 (owner decision OD-4, 2026-11-17): how deep a native piece is drawn. Physics is 2D; depth is presentation only.
    // This is the ONE place that decides the depth look. The owner approved "band 1.6, d = clamp(sqrt(area), 0.1, band),
    // terrain back wall" for now and may replace it ("naive extrusion in general isn't optimal"). To try another rule,
    // change PieceDepth, IsTerrain or the back-wall values here; BomCellPresenter only calls them.
    // Design: integration/review/destruction-design-2026-11.md section 4.
    public static class BomDepthLook
    {
        // Band (default): every cell is drawn from its native outline at its piece's depth inside the play band, centred
        // on the player plane, dressed in Darryn's materials from the visual registry; terrain gets a static back wall.
        // Stock (--bom-stock-look, kept for one release): the G2 look, i.e. an intact source draws Darryn's own mesh and
        // debris is extruded over the source's full authored depth.
        public enum Mode
        {
            Band,
            Stock,
        }

        public static readonly Mode Current = Has("--bom-stock-look") ? Mode.Stock : Mode.Band;

        // Play band: the deepest a piece is drawn. 1.6 >= the 0.9-deep player capsule, so a player never looks inside a slab.
        // The G1 prototype flags still work as aliases.
        public static readonly float Band = Arg("--bom-depth-band", "--bom-g1-band", 1.6f),
            MinDepth = Arg("--bom-depth-min", "--bom-g1-min-depth", 0.1f),
            Scale = Arg("--bom-depth-scale", "--bom-g1-depth-scale", 1f);

        // Depth is quantised so tiny area changes do not rebuild geometry.
        public const float Step = 0.02f;

        // The depth of a native piece (a rigid body after native regrouping) from its total cell area. A pure function of
        // native outlines, so every client and late joiner draws the same thing. An intact slab fills the band; a chip
        // is about as deep as it is wide.
        public static float PieceDepth(float area)
        {
            float d = Mathf.Clamp(Mathf.Sqrt(Mathf.Max(area, 0)) * Scale, MinDepth, Band);
            return Mathf.Max(1, Mathf.RoundToInt(d / Step)) * Step;
        }

        // Terrain gets the back wall; structures do not (Darryn's scenery is their backdrop). Darryn authors ground as
        // deep blocks (Yard ground and Tower base 10 units, Classic Yard ground 11) and structures as shallow ones (Bridge
        // deck, Tower floors 4), so the authored depth tells them apart.
        public const float TerrainMinDepth = 6f;

        public static bool IsTerrain(float lo, float hi) => hi - lo >= TerrainMinDepth;

        // The back wall: the source's authored front outline, flat, just behind the band, darker, no top cap, never rebuilt.
        // A crater reads as a hole in the front layer with dark earth behind; nothing about it looks walkable.
        public static float BackWallZ => Band / 2 + 0.02f;

        public const float BackWallShade = 0.42f;

        public static string Describe() =>
            Current == Mode.Stock
                ? "stock"
                : "band band="
                    + Band.ToString("0.###", CultureInfo.InvariantCulture)
                    + " min_depth="
                    + MinDepth.ToString("0.###", CultureInfo.InvariantCulture)
                    + " depth_scale="
                    + Scale.ToString("0.###", CultureInfo.InvariantCulture)
                    + " terrain_min_depth="
                    + TerrainMinDepth.ToString("0.###", CultureInfo.InvariantCulture);

        static bool Has(string key) => Array.IndexOf(Environment.GetCommandLineArgs(), key) >= 0;

        static float Arg(string key, string alias, float value)
        {
            var args = Environment.GetCommandLineArgs();
            int i = Array.IndexOf(args, key);
            if (i < 0)
                i = Array.IndexOf(args, alias);
            return
                i >= 0
                && i + 1 < args.Length
                && float.TryParse(args[i + 1], NumberStyles.Float, CultureInfo.InvariantCulture, out float parsed)
                && parsed > 0
                ? parsed
                : value;
        }
    }
}
