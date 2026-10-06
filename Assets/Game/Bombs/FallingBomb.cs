using UnityEngine;

// Moves a bomb downward and reports its first valid impact to its owner.
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
        bool isRubble = collision.collider.GetComponentInParent<GroundRubble>() != null;
        bool isGround = owner.IsGameplayGroundCollider(collision.collider);
        ContactPoint contact = collision.contactCount > 0 ? collision.GetContact(0) : default;
        Debug.Log($"[FallingBomb] collision gameObject={collision.collider.gameObject.name} collider={collision.collider.name} "
            + $"layer={LayerMask.LayerToName(collision.collider.gameObject.layer)}({collision.collider.gameObject.layer}) "
            + $"type={collision.collider.GetType().Name} enabled={collision.collider.enabled} trigger={collision.collider.isTrigger} "
            + $"convex={(collision.collider is MeshCollider mesh && mesh.convex)} mesh={(collision.collider is MeshCollider meshCollider && meshCollider.sharedMesh != null ? meshCollider.sharedMesh.name : "n/a")} "
            + $"point={contact.point} normal={contact.normal} validGround={isGround} rubble={isRubble}");
        // Bombs detonate on any solid impact. Requiring a ground collider or a
        // receiver here lets the bomb sit on ordinary objects without exploding.
        if (isRubble) return;
        exploded = true;
        Vector3 point = collision.contactCount > 0 ? contact.point : transform.position;
        owner.Explode(new Vector2(point.x, point.y));
        Destroy(gameObject);
    }
}
