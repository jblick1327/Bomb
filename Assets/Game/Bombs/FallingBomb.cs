using UnityEngine;

// Moves a bomb downward and reports its first valid impact to its owner.
[RequireComponent(typeof(Rigidbody), typeof(SphereCollider))]
[AddComponentMenu("Arena/Falling Bomb")]
public sealed class FallingBomb : MonoBehaviour
{
    private static readonly System.Collections.Generic.List<FallingBomb> active =
        new System.Collections.Generic.List<FallingBomb>();

    // Bombs currently in the scene, so callers do not need to search for them.
    public static System.Collections.Generic.IReadOnlyList<FallingBomb> Active => active;

    private BombDropper owner;
    private Rigidbody body;
    private float fallAcceleration;
    private bool exploded;

    private void OnEnable() => active.Add(this);
    private void OnDisable() => active.Remove(this);

    public void Initialize(BombDropper dropper, float acceleration, float lifetime)
    {
        owner = dropper;
        body = GetComponent<Rigidbody>();
        fallAcceleration = acceleration;
        Destroy(gameObject, lifetime);
    }

    private void FixedUpdate()
    {
        if (!exploded && body != null && owner != null && owner.CanRun)
            body.AddForce(Vector3.down * fallAcceleration, ForceMode.Acceleration);
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (exploded || owner == null || !owner.CanRun) return;
        // Bombs detonate on any solid impact except loose rubble.
        if (collision.collider.GetComponentInParent<GroundRubble>() != null) return;
        exploded = true;
        Vector3 point = collision.contactCount > 0 ? collision.GetContact(0).point : transform.position;
        GameAudio.PlayBombExplosion(point);
        owner.Explode(new Vector2(point.x, point.y));
        Destroy(gameObject);
    }
}
