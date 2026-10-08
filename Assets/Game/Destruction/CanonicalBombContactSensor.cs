using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public sealed class CanonicalBombContactSensor : MonoBehaviour
    {
        private CanonicalWorldRuntime2D owner;
        private MaterialEntityId id;
        internal void Initialize(CanonicalWorldRuntime2D owner, MaterialEntityId id) { this.owner = owner; this.id = id; }
        private void OnCollisionEnter2D(Collision2D collision) => owner.ObserveLanding(id, collision);
        private void OnCollisionStay2D(Collision2D collision) => owner.ObserveLanding(id, collision);
    }
}
