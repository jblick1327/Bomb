using UnityEngine;
using UnityEngine.Rendering;

namespace Bom.Unity
{
    // Presentation only. Slot colour and a floating P1-P4 label for a native player pose.
    // The slot is the native player id (connection index), so P1 is id 0. Facing flip and the
    // Animator Running bool already live in BomActorView.
    [DisallowMultipleComponent]
    public sealed class BomPlayerLook : MonoBehaviour
    {
        // Darryn's first four MatchMenuUI.characterColors (blue, red, yellow, green), copied (D7).
        public static readonly Color[] SlotColors =
        {
            new Color(.16f, .48f, .98f),
            new Color(.92f, .19f, .22f),
            new Color(1f, .83f, .12f),
            new Color(.20f, .76f, .34f),
        };

        [SerializeField]
        float labelHeight = 1.3f;

        [SerializeField, Tooltip("Pulls the label toward the camera so it draws over the body.")]
        float labelCameraOffset = 1f;

        [SerializeField]
        float labelFontSize = 60f;

        public int Slot { get; private set; } = -1;
        public Color Color => SlotColor(Slot);
        public string LabelText => label != null ? label.text : "";
        TextMesh label;
        MeshRenderer labelRenderer;

        public static Color SlotColor(int slot) =>
            SlotColors[Mathf.Clamp(slot, 0, SlotColors.Length - 1)];

        public void Configure(int slot)
        {
            Slot = Mathf.Clamp(slot, 0, SlotColors.Length - 1);
            var properties = new MaterialPropertyBlock();
            properties.SetColor("_BaseColor", Color);
            if (TryGetComponent<MeshRenderer>(out var body))
                body.SetPropertyBlock(properties, 0);
            if (TryGetComponent<BomActorView>(out var view) && view.AuthoredVisual != null)
                foreach (
                    var skin in view.AuthoredVisual.GetComponentsInChildren<SkinnedMeshRenderer>(
                        true
                    )
                )
                    skin.SetPropertyBlock(properties);
            EnsureLabel();
            label.text = "P" + (Slot + 1);
            label.color = Color.white;
        }

        void EnsureLabel()
        {
            if (label != null)
                return;
            var child = new GameObject("Player Label");
            child.transform.SetParent(transform, false);
            label = child.AddComponent<TextMesh>();
            var font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            label.font = font;
            label.fontSize = (int)labelFontSize;
            label.characterSize = 0.05f;
            label.anchor = TextAnchor.MiddleCenter;
            label.alignment = TextAlignment.Center;
            labelRenderer = child.GetComponent<MeshRenderer>();
            labelRenderer.sharedMaterial = font.material;
            labelRenderer.shadowCastingMode = ShadowCastingMode.Off;
            labelRenderer.receiveShadows = false;
            labelRenderer.allowOcclusionWhenDynamic = false;
            labelRenderer.sortingOrder = 10;
        }

        void LateUpdate()
        {
            var camera = Camera.main;
            if (label == null || camera == null)
                return;
            var anchor = TryGetComponent<BomActorView>(out var view)
                ? view.VisualPosition
                : transform.position;
            var t = label.transform;
            t.SetPositionAndRotation(
                anchor
                    + Vector3.up * labelHeight
                    - camera.transform.forward * labelCameraOffset,
                Quaternion.LookRotation(camera.transform.forward, camera.transform.up)
            );
        }
    }
}
