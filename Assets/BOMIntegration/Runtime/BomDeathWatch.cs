using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation only. Finds round-ending and ordinary deaths from the copied native RoundPlayers roster instead
    // of a pose vanishing: the death that ends a round also removes the body on the same server tick, and a quit
    // removes it too. A death is alive 1 -> 0 inside one (round, session, generation) with death Blast(1) or
    // Bounds(2); Disconnect(3) and None(0) never burst. The burst plays at the player's last remembered visual
    // position, once per (round, session, generation, slot), when the presentation tick reaches the native
    // death_tick (or after a short unscaled-time timeout), so it lines up with the body leaving the scene.
    public sealed class BomDeathWatch
    {
        public const double TimeoutSeconds = .75;
        public const uint DeathBlast = 1,
            DeathBounds = 2;

        public struct Burst
        {
            public ulong Round,
                Session,
                Generation;
            public uint Slot,
                Death;
            public Vector3 Position;
        }

        struct Waiting
        {
            public ulong Round,
                Session,
                Generation,
                DeathTick;
            public uint Slot,
                Death;
            public double Since;
        }

        sealed class Track
        {
            public ulong Round,
                Session,
                Generation;
            public bool Alive,
                HasPosition;
            public Vector3 Position;
        }

        readonly Dictionary<uint, Track> tracks = new Dictionary<uint, Track>();
        readonly List<Waiting> pending = new List<Waiting>();
        readonly HashSet<(ulong, ulong, ulong, uint)> fired = new HashSet<(ulong, ulong, ulong, uint)>();

        public int PendingTotal => pending.Count;

        public void Clear()
        {
            tracks.Clear();
            pending.Clear();
            fired.Clear();
        }

        // Call every frame for each player pose that exists, so the position survives the pose going away.
        public void Remember(uint slot, Vector3 position)
        {
            if (!tracks.TryGetValue(slot, out var track))
                tracks[slot] = track = new Track();
            track.Position = position;
            track.HasPosition = true;
        }

        // Call once per sample for every roster player. Returns a reason when a death will not burst, else "".
        public string Observe(
            uint slot,
            ulong round,
            ulong session,
            ulong generation,
            bool alive,
            uint death,
            ulong deathTick,
            double now
        )
        {
            if (!tracks.TryGetValue(slot, out var track))
                tracks[slot] = track = new Track();
            if (track.Round != round || track.Session != session || track.Generation != generation)
            {
                track.Round = round;
                track.Session = session;
                track.Generation = generation;
                track.Alive = alive;
                return "";
            }
            bool died = track.Alive && !alive;
            track.Alive = alive;
            if (!died)
                return "";
            if (death != DeathBlast && death != DeathBounds)
                return death == 3 ? "disconnect" : "death_" + death;
            if (!track.HasPosition)
                return "no_position";
            if (!fired.Add((round, session, generation, slot)))
                return "";
            if (fired.Count > 256)
                fired.Clear();
            pending.Add(
                new Waiting
                {
                    Round = round,
                    Session = session,
                    Generation = generation,
                    DeathTick = deathTick,
                    Slot = slot,
                    Death = death,
                    Since = now,
                }
            );
            return "";
        }

        // Appends the bursts that are due: the presentation tick has reached the native death tick, or the
        // timeout passed. The position is the latest one remembered for that player.
        public void Collect(double presentationTick, double now, List<Burst> bursts)
        {
            for (int i = 0; i < pending.Count; )
            {
                var wait = pending[i];
                if (
                    wait.DeathTick != 0
                    && presentationTick + .00001 < wait.DeathTick
                    && now - wait.Since < TimeoutSeconds
                )
                {
                    i++;
                    continue;
                }
                pending.RemoveAt(i);
                if (!tracks.TryGetValue(wait.Slot, out var track) || !track.HasPosition)
                    continue;
                bursts.Add(
                    new Burst
                    {
                        Round = wait.Round,
                        Session = wait.Session,
                        Generation = wait.Generation,
                        Slot = wait.Slot,
                        Death = wait.Death,
                        Position = track.Position,
                    }
                );
            }
        }
    }
}
