using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace Bomb.CanonicalDestruction
{
    public enum DefinitionKind { Material, Response, Appearance, Environment, Level, Character, Bomb }
    public enum LimbSlot { LeftHand, RightHand, LeftFoot, RightFoot }

    [Serializable]
    public struct DefinitionReference : IEquatable<DefinitionReference>
    {
        public DefinitionKind kind;
        public string id;
        public string hash;
        public bool IsValid => !string.IsNullOrWhiteSpace(id) && !string.IsNullOrWhiteSpace(hash);
        public bool Equals(DefinitionReference other) => kind == other.kind && id == other.id && hash == other.hash;
        public override bool Equals(object obj) => obj is DefinitionReference other && Equals(other);
        public override int GetHashCode() => HashCode.Combine(kind, id, hash);
    }

    // Import/export DTO only. DefinitionSet keeps a frozen JSON copy, never this mutable instance.
    [Serializable]
    public sealed class DefinitionSpec
    {
        public DefinitionKind kind;
        public string id;
        public float density, friction, restitution, linearDamping, angularDamping;
        public bool destructible;
        public float minimumRetainedCellArea;
        public Color tint;
        public float depth;
        public CanonicalBodyMode bodyMode;
        public bool holdEligible;
        public Vector2 leftHand, rightHand, leftFoot, rightFoot;
        public float handReach, footReach;
        public DefinitionReference corpseRole, corpseMaterial, corpseResponse, corpseAppearance;
        public float countdownSeconds, blastPower, blastRadius;
        public DefinitionCell[] levelCells;

        public Vector2 Root(LimbSlot slot) => slot == LimbSlot.LeftHand ? leftHand
            : slot == LimbSlot.RightHand ? rightHand : slot == LimbSlot.LeftFoot ? leftFoot : rightFoot;
        public float Reach(LimbSlot slot) => slot == LimbSlot.LeftHand || slot == LimbSlot.RightHand ? handReach : footReach;
        public bool TryValidate(out string error)
        {
            error = "Invalid definition: " + id;
            if (string.IsNullOrWhiteSpace(id) || !Enum.IsDefined(typeof(DefinitionKind), kind)) return false;
            if (kind == DefinitionKind.Material && (!Positive(density) || !Nonnegative(friction)
                || !Nonnegative(restitution) || restitution > 1 || !Nonnegative(linearDamping) || !Nonnegative(angularDamping))) return false;
            if (kind == DefinitionKind.Response && (!Nonnegative(minimumRetainedCellArea)
                || (destructible && minimumRetainedCellArea < 0.00001f))) return false;
            if (kind == DefinitionKind.Appearance && (!Positive(depth) || !Finite(tint.r)
                || !Finite(tint.g) || !Finite(tint.b) || !Finite(tint.a))) return false;
            if ((kind == DefinitionKind.Environment || kind == DefinitionKind.Level || kind == DefinitionKind.Character || kind == DefinitionKind.Bomb)
                && !Enum.IsDefined(typeof(CanonicalBodyMode), bodyMode)) return false;
            if (kind == DefinitionKind.Character && (!Positive(handReach) || !Positive(footReach)
                || !Finite(leftHand) || !Finite(rightHand) || !Finite(leftFoot) || !Finite(rightFoot)
                || !corpseRole.IsValid || !corpseMaterial.IsValid || !corpseResponse.IsValid || !corpseAppearance.IsValid)) return false;
            if (kind == DefinitionKind.Bomb && (!Positive(countdownSeconds) || !Positive(blastRadius) || !Nonnegative(blastPower))) return false;
            if (kind == DefinitionKind.Level && (levelCells == null || !new CanonicalMaterialShape(levelCells.Select(c =>
                new CanonicalPolygon2D(c.points))).TryValidate(out error))) return false;
            error = null;
            return true;
        }
        internal static bool Finite(float v) => float.IsFinite(v);
        internal static bool Finite(Vector2 v) => Finite(v.x) && Finite(v.y);
        internal static bool Positive(float v) => Finite(v) && v > 0;
        internal static bool Nonnegative(float v) => Finite(v) && v >= 0;
    }
    [Serializable] public sealed class DefinitionCell { public Vector2[] points; }

    public sealed class DefinitionSet
    {
        private readonly Dictionary<string, string> frozen = new Dictionary<string, string>(StringComparer.Ordinal);
        public DefinitionSet(IEnumerable<DefinitionSpec> definitions = null)
        {
            foreach (var spec in definitions ?? Array.Empty<DefinitionSpec>())
            {
                if (spec == null || !spec.TryValidate(out _)) throw new ArgumentException("Invalid definition input.");
                frozen.Add(Key(spec.kind, spec.id), JsonUtility.ToJson(spec));
            }
        }
        private static string Key(DefinitionKind kind, string id) => kind + ":" + id;
        private static string Hash(string json)
        {
            using (var sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(json))).Replace("-", "").ToLowerInvariant();
        }
        public DefinitionReference Reference(DefinitionKind kind, string id)
        {
            if (!frozen.TryGetValue(Key(kind, id), out var json)) throw new ArgumentException("Missing definition " + id);
            return new DefinitionReference { kind = kind, id = id, hash = Hash(json) };
        }
        public bool TryResolve(DefinitionReference reference, DefinitionKind kind, out DefinitionSpec spec, out string error)
        {
            spec = null;
            if (!reference.IsValid || reference.kind != kind || !frozen.TryGetValue(Key(kind, reference.id), out var json)
                || Hash(json) != reference.hash)
            {
                error = "Missing, changed, or incorrectly typed definition: " + reference.id;
                return false;
            }
            spec = JsonUtility.FromJson<DefinitionSpec>(json);
            return spec.TryValidate(out error);
        }
        public DefinitionSpec Resolve(DefinitionReference reference)
        {
            if (!TryResolve(reference, reference.kind, out var spec, out var error)) throw new InvalidOperationException(error);
            return spec;
        }
        public DefinitionSpec[] Export() => frozen.OrderBy(p => p.Key, StringComparer.Ordinal)
            .Select(p => JsonUtility.FromJson<DefinitionSpec>(p.Value)).ToArray();
    }

    public sealed class BodyDefinitionSelection : IEquatable<BodyDefinitionSelection>
    {
        public BodyDefinitionSelection(DefinitionReference material, DefinitionReference response,
            DefinitionReference appearance, DefinitionReference role)
        { Material = material; Response = response; Appearance = appearance; Role = role; }
        public DefinitionReference Material { get; }
        public DefinitionReference Response { get; }
        public DefinitionReference Appearance { get; }
        public DefinitionReference Role { get; }
        public bool IsCharacter => Role.kind == DefinitionKind.Character;
        public bool IsBomb => Role.kind == DefinitionKind.Bomb;
        public bool TryValidate(DefinitionSet definitions, CanonicalBodyMode mode, out string error)
        {
            if (!definitions.TryResolve(Material, DefinitionKind.Material, out _, out error)
                || !definitions.TryResolve(Response, DefinitionKind.Response, out _, out error)
                || !definitions.TryResolve(Appearance, DefinitionKind.Appearance, out _, out error)) return false;
            if (Role.kind != DefinitionKind.Environment && Role.kind != DefinitionKind.Level
                && Role.kind != DefinitionKind.Character && Role.kind != DefinitionKind.Bomb)
            { error = "Invalid physical role definition."; return false; }
            if (!definitions.TryResolve(Role, Role.kind, out var role, out error)) return false;
            if (role.bodyMode != mode) { error = "Body mode conflicts with its selected role."; return false; }
            if (IsCharacter)
            {
                var corpse = new BodyDefinitionSelection(role.corpseMaterial, role.corpseResponse, role.corpseAppearance, role.corpseRole);
                if (corpse.Role.kind != DefinitionKind.Environment || !definitions.TryResolve(corpse.Role,DefinitionKind.Environment,out var corpseRole,out error)
                    || !corpse.TryValidate(definitions, corpseRole.bodyMode, out error)) return false;
            }
            error = null;
            return true;
        }
        public bool Equals(BodyDefinitionSelection other) => other != null && Material.Equals(other.Material)
            && Response.Equals(other.Response) && Appearance.Equals(other.Appearance) && Role.Equals(other.Role);
        public override bool Equals(object obj) => Equals(obj as BodyDefinitionSelection);
        public override int GetHashCode() => HashCode.Combine(Material, Response, Appearance, Role);
    }

    public sealed class BombCountdown
    {
        // One duration value in milliseconds; fractional milliseconds remain representable.
        // Subtracting the integral fixed step avoids repeated inexact 0.02-second subtraction.
        private readonly double remainingMilliseconds;
        public BombCountdown(bool active, double remainingSeconds)
        { Active = active; remainingMilliseconds = remainingSeconds * 1000d; }
        private BombCountdown(BombCountdown current, int elapsedMilliseconds)
        {
            if (elapsedMilliseconds < 0) throw new ArgumentOutOfRangeException(nameof(elapsedMilliseconds));
            Active = current.Active;
            remainingMilliseconds = Math.Max(0d, current.remainingMilliseconds - elapsedMilliseconds);
        }
        public bool Active { get; }
        public double RemainingSeconds => remainingMilliseconds / 1000d;
        internal BombCountdown AdvanceMilliseconds(int elapsedMilliseconds) => new BombCountdown(this, elapsedMilliseconds);
        public bool IsValid => !double.IsNaN(remainingMilliseconds) && !double.IsInfinity(remainingMilliseconds)
            && remainingMilliseconds >= 0 && (Active || remainingMilliseconds == 0);
    }
}
