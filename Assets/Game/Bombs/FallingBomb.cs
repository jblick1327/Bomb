using System.Collections.Generic;
using UnityEngine;

public enum BombType { Impact, Timed }

// Impact bombs detonate immediately; timed bombs start their fuse on impact.
[RequireComponent(typeof(Rigidbody), typeof(SphereCollider))]
[AddComponentMenu("Arena/Falling Bomb")]
public sealed class FallingBomb : MonoBehaviour
{
    private static readonly List<FallingBomb> active = new List<FallingBomb>();
    public static IReadOnlyList<FallingBomb> Active => active;
    public int NetworkId { get; set; }
    private bool IsAuthority => !OnlineMatch.IsRunning || OnlineMatch.IsHost;
    private float networkSyncTimer;

    private void OnEnable() => active.Add(this);

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
                fuseRemaining = 0f;
                if (IsAuthority)
                {
                    Detonate(transform.position);
                    return;
                }
                // Client countdowns are cosmetic. Only the host's Boom message
                // applies terrain damage and player damage.
            }
            if (OnlineMatch.IsRunning && OnlineMatch.IsHost)
            {
                networkSyncTimer -= Time.deltaTime;
                if (networkSyncTimer <= 0f)
                {
                    OnlineMatch.SendBombFuse(NetworkId, transform.position, fuseRemaining);
                    networkSyncTimer = 0.1f;
                }
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
        if (!exploded && body != null && !body.isKinematic && owner != null && owner.CanRun)
            body.AddForce(Vector3.down * fallAcceleration, ForceMode.Acceleration);
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (exploded || owner == null || !owner.CanRun || !IsAuthority) return;
        if (collision.collider.GetComponentInParent<GroundRubble>() != null) return;

        if (Type == BombType.Timed)
        {
            // Further collisions never restart the countdown. Keep physics active
            // so the bomb can fall again if the ground underneath is destroyed.
            if (!fuseStarted)
            {
                fuseStarted = true;
                if (countdownAudio != null) countdownAudio.Play();
                if (OnlineMatch.IsRunning)
                {
                    OnlineMatch.SendBombFuse(NetworkId, transform.position, fuseRemaining);
                    networkSyncTimer = 0.1f;
                }
            }
            return;
        }

        Vector3 point = collision.contactCount > 0
            ? collision.GetContact(0).point : transform.position;
        Detonate(point);
    }

    private void Detonate(Vector3 point)
    {
        if (exploded || owner == null || !owner.CanRun || !IsAuthority) return;
        exploded = true;
        if (countdownAudio != null) countdownAudio.Stop();
        if (OnlineMatch.IsRunning)
            OnlineMatch.SendExplosion(NetworkId, new Vector2(point.x, point.y), Type, owner.GetExplosionScale(Type));
        owner.Explode(point, Type);
        Destroy(gameObject);
    }

    public void ApplyNetworkFuse(Vector3 position, float remaining)
    {
        if (exploded || IsAuthority || Type != BombType.Timed) return;
        if (!fuseStarted)
        {
            fuseStarted = true;
            fuseDuration = Mathf.Max(0.1f, remaining);
            if (countdownAudio != null) countdownAudio.Play();
        }
        fuseRemaining = Mathf.Max(0f, remaining);
        if (body != null)
        {
            // While armed, the visual follows the host instead of simulating
            // different player collisions or unsupported ground on each client.
            body.collisionDetectionMode = CollisionDetectionMode.Discrete;
            body.isKinematic = true;
            body.position = position;
        }
        transform.position = position;
    }

    private void OnDestroy()
    {
        if (owner != null) owner.ForgetNetworkBomb(NetworkId);
    }

    private void OnDisable()
    {
        active.Remove(this);
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
