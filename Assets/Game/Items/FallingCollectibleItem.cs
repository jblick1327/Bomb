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
        if (player != null && player.gameObject.activeInHierarchy)
        {
            TryCollect(player);
            return;
        }

        if (collision.contactCount > 0 && collision.GetContact(0).normal.y > 0.3f)
        {
            landed = true;
            body.linearVelocity = Vector3.zero;
            body.angularVelocity = Vector3.zero;
            body.isKinematic = true;
        }
    }

    public bool TryCollect(ArenaPlayerController player)
    {
        if (collected || owner == null || !owner.CanRun
            || player == null || !player.gameObject.activeInHierarchy)
            return false;

        collected = true;
        player.ApplyCollectible(GetComponent<CollectibleItemTypeHolder>().Type);
        GameAudio.PlayCoinPickup(transform.position);
        Destroy(gameObject);
        return true;
    }
}

public sealed class CollectibleItemTypeHolder : MonoBehaviour
{
    public CollectibleItemType Type { get; set; }
}
