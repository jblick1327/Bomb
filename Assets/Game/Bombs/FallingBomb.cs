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
    private Renderer bombRenderer;
    private MaterialPropertyBlock colorProperties;
    private Color timedColor;

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
            bombRenderer = GetComponentInChildren<Renderer>();
            colorProperties = new MaterialPropertyBlock();
            timedColor = new Color(1f, 0.45f, 0.05f);
            SetTimedColor(timedColor);
        }
    }

    private void Update()
    {
        if (exploded || owner == null || !owner.CanRun) return;

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
            SetTimedColor(Color.Lerp(timedColor, Color.white, flash));
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
            fuseStarted = true;
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
        owner.Explode(point);
        Destroy(gameObject);
    }

    private void SetTimedColor(Color color)
    {
        if (bombRenderer == null) return;
        bombRenderer.GetPropertyBlock(colorProperties);
        // Support both URP/Lit and the built-in Standard shader without
        // modifying the material shared by impact bombs.
        colorProperties.SetColor("_BaseColor", color);
        colorProperties.SetColor("_Color", color);
        bombRenderer.SetPropertyBlock(colorProperties);
    }
}
