using UnityEngine;

[RequireComponent(typeof(Rigidbody), typeof(SphereCollider))]
[AddComponentMenu("Arena/Falling Bomb")]
public sealed class FallingBomb : MonoBehaviour
{
    private BombDropper owner;
    private Rigidbody body;
    private float fallAcceleration;
    private bool exploded;

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
        exploded = true;
        Vector3 point = collision.contactCount > 0 ? collision.GetContact(0).point : transform.position;
        // Craters run through the full depth, while gameplay and blast distances use XY.
        owner.Explode(new Vector2(point.x, point.y));
        Destroy(gameObject);
    }
}
