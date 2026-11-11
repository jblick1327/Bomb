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
    private BombDropper owner;
    private Rigidbody body;
    private float fallAcceleration;
    private bool collected;
    private bool landed;
    // Online: a pickup was asked for and the host hasn't answered yet.
    private bool pickupRequested;

    // Online: the number the host gave this item.
    public int NetworkId { get; set; }
    public CollectibleItemType Type => GetComponent<CollectibleItemTypeHolder>().Type;

    public void Initialize(BombDropper dropper, float acceleration, float lifetime)
    {
        owner = dropper;
        body = GetComponent<Rigidbody>();
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

        // Already resting: a kinematic body can't have its velocity set.
        if (!landed && !body.isKinematic && collision.contactCount > 0 && collision.GetContact(0).normal.y > 0.3f)
        {
            landed = true;
            body.linearVelocity = Vector3.zero;
            body.angularVelocity = Vector3.zero;
            body.isKinematic = true;
        }
    }

    // Called after a blast. A landed item is frozen in place, so let it fall
    // again; if its surface is still there it lands again straight away.
    public void ResumeFalling()
    {
        if (!landed || collected || body == null) return;
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

    public void CollectBy(ArenaPlayerController player, CollectibleItemType type)
    {
        collected = true;
        if (player != null) player.ApplyCollectible(type);
        GameAudio.PlayCoinPickup(transform.position);
        gameObject.SetActive(false);
        Destroy(gameObject);
    }
}

public sealed class CollectibleItemTypeHolder : MonoBehaviour
{
    public CollectibleItemType Type { get; set; }
}
