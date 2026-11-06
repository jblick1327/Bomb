using System.Collections.Generic;
using UnityEngine;

public enum BombType { Impact, Timed }

// Impact bombs detonate immediately; timed bombs start their fuse on impact.
[RequireComponent(typeof(Rigidbody), typeof(SphereCollider))]
[AddComponentMenu("Arena/Falling Bomb")]
public sealed class FallingBomb : MonoBehaviour
{
    private BombDropper owner;
    private Rigidbody body;
    private float fallAcceleration;
    private bool exploded;
    private bool fuseStarted;
    private float fuseDuration;
    private float fuseRemaining;
    private float lifetimeRemaining;
    private readonly List<FlashSurface> flashSurfaces = new List<FlashSurface>();
    private MaterialPropertyBlock colorProperties;

    private struct FlashSurface
    {
        public Renderer Renderer;
        public int MaterialIndex;
        public string ColorProperty;
        public Color BaseColor;
    }
    private AudioSource countdownAudio;
    private bool countdownPaused;

    public BombType Type { get; private set; }

    public void Initialize(BombDropper dropper, float acceleration, float lifetime,
        BombType type = BombType.Impact, float fuseSeconds = 3f)
    {
        owner = dropper;
        body = GetComponent<Rigidbody>();
        fallAcceleration = acceleration;
        Type = type;
        lifetimeRemaining = Mathf.Max(0.1f, lifetime);
        fuseDuration = Mathf.Max(0.1f, fuseSeconds);
        fuseRemaining = fuseDuration;
        if (Type == BombType.Timed)
        {
            countdownAudio = GetComponent<AudioSource>();
            CacheFlashSurfaces();
        }
    }

    private void Update()
    {
        if (exploded || owner == null) return;
        if (!owner.CanRun)
        {
            if (countdownAudio != null && countdownAudio.isPlaying)
            {
                countdownAudio.Pause();
                countdownPaused = true;
            }
            return;
        }
        if (countdownPaused && countdownAudio != null)
        {
            countdownAudio.UnPause();
            countdownPaused = false;
        }

        if (fuseStarted)
        {
            // Once armed, the fuse takes precedence over airborne cleanup.
            fuseRemaining -= Time.deltaTime;
            if (fuseRemaining <= 0f)
            {
                Detonate(transform.position);
                return;
            }

            // Flash faster as the countdown approaches zero.
            float elapsed = fuseDuration - fuseRemaining;
            float flashSpeed = Mathf.Lerp(4f, 12f, 1f - fuseRemaining / fuseDuration);
            float flash = Mathf.PingPong(elapsed * flashSpeed, 1f);
            SetCountdownFlash(flash);
        }
        else
        {
            lifetimeRemaining -= Time.deltaTime;
            if (lifetimeRemaining <= 0f) Destroy(gameObject);
        }
    }

    private void FixedUpdate()
    {
        if (!exploded && body != null && owner != null && owner.CanRun)
            body.AddForce(Vector3.down * fallAcceleration, ForceMode.Acceleration);
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (exploded || owner == null || !owner.CanRun) return;
        if (collision.collider.GetComponentInParent<GroundRubble>() != null) return;

        if (Type == BombType.Timed)
        {
            // Further collisions never restart the countdown. Keep physics active
            // so the bomb can fall again if the ground underneath is destroyed.
            if (!fuseStarted)
            {
                fuseStarted = true;
                if (countdownAudio != null) countdownAudio.Play();
            }
            return;
        }

        Vector3 point = collision.contactCount > 0
            ? collision.GetContact(0).point : transform.position;
        Detonate(point);
    }

    private void Detonate(Vector3 point)
    {
        if (exploded || owner == null || !owner.CanRun) return;
        exploded = true;
        if (countdownAudio != null) countdownAudio.Stop();
        owner.Explode(point, Type);
        Destroy(gameObject);
    }

    private void OnDisable()
    {
        // Round cleanup disables bombs before destroying them.
        if (countdownAudio != null) countdownAudio.Stop();
        countdownPaused = false;
    }

    private void CacheFlashSurfaces()
    {
        colorProperties = new MaterialPropertyBlock();
        flashSurfaces.Clear();
        foreach (Renderer renderer in GetComponentsInChildren<Renderer>(true))
        {
            if (!(renderer is MeshRenderer) && !(renderer is SkinnedMeshRenderer)) continue;
            Material[] materials = renderer.sharedMaterials;
            for (int i = 0; i < materials.Length; i++)
            {
                Material material = materials[i];
                if (material == null) continue;
                string property = material.HasProperty("_BaseColor") ? "_BaseColor"
                    : material.HasProperty("_Color") ? "_Color" : null;
                if (property == null) continue;
                flashSurfaces.Add(new FlashSurface
                {
                    Renderer = renderer,
                    MaterialIndex = i,
                    ColorProperty = property,
                    BaseColor = material.GetColor(property)
                });
            }
        }
    }

    private void SetCountdownFlash(float amount)
    {
        foreach (FlashSurface surface in flashSurfaces)
        {
            if (surface.Renderer == null) continue;
            colorProperties.Clear();
            surface.Renderer.GetPropertyBlock(colorProperties, surface.MaterialIndex);
            Color color = Color.Lerp(surface.BaseColor, Color.white, amount * 0.7f);
            color.a = surface.BaseColor.a;
            colorProperties.SetColor(surface.ColorProperty, color);
            surface.Renderer.SetPropertyBlock(colorProperties, surface.MaterialIndex);
        }
    }
}
