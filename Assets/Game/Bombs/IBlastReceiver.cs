using UnityEngine;

// Receives the damage and shatter data produced by a bomb blast.
public interface IBlastReceiver
{
    void ReceiveBlast(BlastPayload blast);
}

// Carries the center and radii of a blast to destructible objects.
public readonly struct BlastPayload
{
    public readonly Vector2 Center;
    public readonly float InnerRadius;
    public readonly float OuterRadius;
    public readonly float Impulse;

    public BlastPayload(Vector2 center, float innerRadius, float outerRadius, float impulse)
    {
        Center = center;
        InnerRadius = Mathf.Max(0f, innerRadius);
        OuterRadius = Mathf.Max(InnerRadius, outerRadius);
        Impulse = Mathf.Max(0f, impulse);
    }
}
