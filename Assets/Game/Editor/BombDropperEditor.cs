using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine.UIElements;

[CustomEditor(typeof(BombDropper))]
public sealed class BombDropperEditor : Editor
{
    public override VisualElement CreateInspectorGUI()
    {
        var root = new VisualElement();
        var script = new PropertyField(serializedObject.FindProperty("m_Script"));
        script.SetEnabled(false);
        root.Add(script);
        root.Add(new HelpBox("Crater removes ground. Lethal radius touches the player's body; the visible ring uses that radius.", HelpBoxMessageType.Info));
        Add(root, "craterShape", "Crater shape");
        Add(root, "craterRadius", "Crater radius (units)");
        Add(root, "lethalRadius", "Lethal radius (units)");

        var shape = new Foldout { text = "Crater detail", value = false };
        var scale = Add(shape, "craterShapeScale", "Width / height scale");
        var segments = Add(shape, "craterSegments", "Curved edge segments");
        Add(shape, "craterRotation", "Rotation (degrees)");
        root.Add(shape);
        var shapeProperty = serializedObject.FindProperty("craterShape");
        void RefreshShape()
        {
            scale.SetEnabled(shapeProperty.enumValueIndex != (int)CraterShape.Circle);
            segments.SetEnabled(shapeProperty.enumValueIndex != (int)CraterShape.Box);
        }
        root.TrackPropertyValue(shapeProperty, _ => RefreshShape());
        RefreshShape();

        var drop = new Foldout { text = "Bomb drop", value = false };
        Add(drop, "bombRadius", "Bomb radius (units)");
        Add(drop, "spawnEdgePadding", "Edge padding (units)");
        Add(drop, "dropHeightAboveArena", "Height above arena (units)");
        Add(drop, "fallAcceleration", "Fall acceleration (units/s²)");
        Add(drop, "bombLifetime", "Maximum lifetime (seconds)");
        root.Add(drop);

        var visuals = new Foldout { text = "Visuals and previews", value = false };
        Add(visuals, "bombMaterial");
        Add(visuals, "blastMaterial");
        Add(visuals, "blastDuration", "Blast duration (seconds)");
        Add(visuals, "showSizePreviews", "Show Scene size previews");
        root.Add(visuals);

        var references = new Foldout { text = "Scene references", value = false };
        foreach (string name in new[] { "layout", "session", "ground", "player", "upperBoundary" })
            Add(references, name);
        root.Add(references);
        return root;
    }

    private PropertyField Add(VisualElement parent, string name, string label = null)
    {
        var field = new PropertyField(serializedObject.FindProperty(name), label);
        parent.Add(field);
        return field;
    }
}
