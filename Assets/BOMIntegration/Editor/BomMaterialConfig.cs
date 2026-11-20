using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Bom.Unity;
using UnityEngine;

// G6b (owner 2026-11-19): every exporter takes destruction material values from integration/fixtures/materials.json,
// so they can be tuned by editing one file and re-exporting. Values are checked against the native custom_problem ranges.
public static class BomMaterialConfig
{
    public const string Path = "C:/Users/jblic/Desktop/Bomb-integration/integration/fixtures/materials.json";
    static readonly string[] Bases = { "stone", "wood", "glass", "rubber" };

    [Serializable]
    sealed class Entry
    {
        public string name = "", @base = "", builtin = "";
        public float toughness = float.NaN, blast_resistance = float.NaN, strip_thickness = float.NaN, shock_loss = float.NaN, flexibility = float.NaN;
        public int[] color = Array.Empty<int>();
    }

    [Serializable]
    sealed class File
    {
        public Entry[] materials = Array.Empty<Entry>();
        public Entry[] builtin_overrides = Array.Empty<Entry>();
    }

    static File Load()
    {
        if (!System.IO.File.Exists(Path))
            throw new InvalidOperationException("Missing " + Path);
        return JsonUtility.FromJson<File>(System.IO.File.ReadAllText(Path)) ?? throw new InvalidOperationException("Unreadable " + Path);
    }

    static void Range(string name, string field, float v, float lo, float hi)
    {
        if (float.IsNaN(v) || float.IsInfinity(v) || v < lo || v > hi)
            throw new InvalidOperationException(Path + ": material '" + name + "' " + field + " must be between " + lo + " and " + hi);
    }

    static BomCustomMaterial ToMaterial(Entry e)
    {
        if (string.IsNullOrEmpty(e.name) || e.name.Length > 20)
            throw new InvalidOperationException(Path + ": every material needs a name of 1-20 characters");
        if (Array.IndexOf(Bases, e.name) >= 0)
            throw new InvalidOperationException(Path + ": '" + e.name + "' is a built-in name; pick another");
        if (Array.IndexOf(Bases, e.@base) < 0)
            throw new InvalidOperationException(Path + ": material '" + e.name + "' base must be stone, wood, glass or rubber");
        Range(e.name, "toughness", e.toughness, .25f, 4);
        Range(e.name, "blast_resistance", e.blast_resistance, 0, 6);
        Range(e.name, "strip_thickness", e.strip_thickness, .1f, .6f);
        Range(e.name, "shock_loss", e.shock_loss, 1, 12);
        Range(e.name, "flexibility", e.flexibility, .2f, 1);
        if (e.color == null || e.color.Length != 3 || e.color.Any(c => c < 0 || c > 255))
            throw new InvalidOperationException(Path + ": material '" + e.name + "' color must be [r,g,b] with 0..255");
        return new BomCustomMaterial
        {
            Name = e.name,
            Base = e.@base,
            Toughness = e.toughness,
            BlastResistance = e.blast_resistance,
            StripThickness = e.strip_thickness,
            ShockLoss = e.shock_loss,
            Flexibility = e.flexibility,
            Color = new Color32((byte)e.color[0], (byte)e.color[1], (byte)e.color[2], 255),
        };
    }

    // A named custom material from the file; throws if it is missing.
    public static BomCustomMaterial Get(string name)
    {
        var e = Load().materials.FirstOrDefault(m => m.name == name);
        if (e == null)
            throw new InvalidOperationException(Path + ": no material named '" + name + "'");
        return ToMaterial(e);
    }

    public static bool Has(string name) => Load().materials.Any(m => m.name == name);

    // Built-in overrides for the tile levels: built-in name -> custom material that replaces it.
    public static Dictionary<string, BomCustomMaterial> BuiltinOverrides()
    {
        var result = new Dictionary<string, BomCustomMaterial>(StringComparer.Ordinal);
        foreach (var e in Load().builtin_overrides)
        {
            if (Array.IndexOf(Bases, e.builtin) < 0)
                throw new InvalidOperationException(Path + ": builtin_overrides entry '" + e.name + "' must name a built-in (stone, wood, glass, rubber)");
            if (result.ContainsKey(e.builtin))
                throw new InvalidOperationException(Path + ": built-in '" + e.builtin + "' is overridden twice");
            result[e.builtin] = ToMaterial(e);
        }
        return result;
    }
}
