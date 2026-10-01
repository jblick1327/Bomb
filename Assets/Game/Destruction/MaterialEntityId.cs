using System;

namespace Bomb.CanonicalDestruction
{
    [Serializable]
    public readonly struct MaterialEntityId : IEquatable<MaterialEntityId>, IComparable<MaterialEntityId>
    {
        private readonly string value;

        public MaterialEntityId(string value)
        {
            this.value = value ?? string.Empty;
        }

        public string Value => value ?? string.Empty;
        public bool IsValid => !string.IsNullOrWhiteSpace(Value);

        public bool Equals(MaterialEntityId other) => string.Equals(Value, other.Value, StringComparison.Ordinal);
        public override bool Equals(object obj) => obj is MaterialEntityId other && Equals(other);
        public override int GetHashCode() => StringComparer.Ordinal.GetHashCode(Value);
        public int CompareTo(MaterialEntityId other) => string.Compare(Value, other.Value, StringComparison.Ordinal);
        public override string ToString() => Value;

        public static bool operator ==(MaterialEntityId left, MaterialEntityId right) => left.Equals(right);
        public static bool operator !=(MaterialEntityId left, MaterialEntityId right) => !left.Equals(right);
    }
}
