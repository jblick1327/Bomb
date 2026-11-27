using UnityEngine;

public enum CollectibleItemType
{
    SilverCoin,
    GoldCoin,
    Invincibility,
    Slow,
    SpeedBoost
}

[RequireComponent(typeof(Rigidbody), typeof(Collider))]
[AddComponentMenu("Arena/Falling Collectible Item")]
public sealed class FallingCollectibleItem : MonoBehaviour
{
    private const float GroundHoverHeight = 0.22f;
    private const float SupportProbeTolerance = 0.06f;
    private const float MinSupportNormalY = 0.3f;

    private BombDropper owner;
    private Rigidbody body;
    private SphereCollider pickupCollider;
    private float fallAcceleration;
    private bool collected;
    private bool landed;
    private Collider landingSurface;
    private Ray supportProbe;
    // Online: a pickup was asked for and the host hasn't answered yet.
    private bool pickupRequested;

    // Online: the number the host gave this item.
    public int NetworkId { get; set; }
    public CollectibleItemType Type => GetComponent<CollectibleItemTypeHolder>().Type;

    public void Initialize(BombDropper dropper, float acceleration, float lifetime)
    {
        owner = dropper;
        body = GetComponent<Rigidbody>();
        pickupCollider = GetComponent<SphereCollider>();
        fallAcceleration = acceleration;
        Destroy(gameObject, lifetime);
    }

    private void FixedUpdate()
    {
        if (!collected && !landed && body != null && owner != null && owner.CanRun)
        {
            body.AddForce(Vector3.down * fallAcceleration, ForceMode.Acceleration);

            if (owner.IsBelowArena(transform.position))
            {
                collected = true;
                Destroy(gameObject);
            }
        }
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (collected || owner == null || !owner.CanRun)
            return;

        ArenaPlayerController player = collision.collider.GetComponentInParent<ArenaPlayerController>();
        if (player != null && player.IsRemote) return;
        if (player != null && player.gameObject.activeInHierarchy)
        {
            TryCollect(player);
            return;
        }

        if (landed || body.isKinematic || collision.contactCount == 0) return;
        ContactPoint contact = collision.GetContact(0);
        if (contact.normal.y <= MinSupportNormalY) return;

        // Keep the original contact so a blast can check this exact spot, even on a ledge.
        landingSurface = collision.collider;
        supportProbe = new Ray(contact.point + contact.normal * SupportProbeTolerance, -contact.normal);
        landed = true;
        body.linearVelocity = Vector3.zero;
        body.angularVelocity = Vector3.zero;
        body.isKinematic = true;
        body.position += Vector3.up * GroundHoverHeight;
    }

    // Called after a blast has updated the terrain colliders.
    public void ResumeFalling()
    {
        if (!landed || collected || body == null) return;
        if (landingSurface != null && landingSurface.enabled && landingSurface.gameObject.activeInHierarchy &&
            landingSurface.Raycast(supportProbe, out RaycastHit hit, SupportProbeTolerance * 2f) &&
            hit.normal.y > MinSupportNormalY) return;

        landingSurface = null;
        landed = false;
        body.isKinematic = false;
        body.WakeUp();
    }

    public bool TryCollect(ArenaPlayerController player)
    {
        if (collected || owner == null || !owner.CanRun
            || player == null || !player.gameObject.activeInHierarchy || player.IsRemote)
            return false;

        // Online, the host decides who got there first.
        if (OnlineMatch.IsRunning)
        {
            if (pickupRequested) return false;
            pickupRequested = true;
            OnlineMatch.RequestPickup(NetworkId, player.PlayerNumber - 1);
            return true;
        }

        CollectBy(player, Type);
        return true;
    }

    // Online, host only: marks the item as taken. False if it already was.
    public bool TryClaim()
    {
        if (collected) return false;
        collected = true;
        return true;
    }

    internal bool IsInBlast(Vector2 center, float radius)
    {
        if (collected || !isActiveAndEnabled || pickupCollider == null || !pickupCollider.enabled)
            return false;

        Bounds bounds = pickupCollider.bounds;
        float reach = radius + bounds.extents.x;
        return ((Vector2)bounds.center - center).sqrMagnitude <= reach * reach;
    }

    internal void DestroyByBlast()
    {
        collected = true;
        gameObject.SetActive(false);
        Destroy(gameObject);
    }

    public void CollectBy(ArenaPlayerController player, CollectibleItemType type)
    {
        collected = true;
        if (player != null) player.ApplyCollectible(type);
        GameAudio.PlayCoinPickup(transform.position);
        if (player != null) GameAudio.PlayPickupVoice();
        BomFx.Pickup(transform.position, ItemAura.ColorFor(type));
        gameObject.SetActive(false);
        Destroy(gameObject);
    }
}

public sealed class CollectibleItemTypeHolder : MonoBehaviour
{
    public CollectibleItemType Type { get; set; }
}
