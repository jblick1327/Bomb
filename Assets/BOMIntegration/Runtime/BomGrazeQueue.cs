using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation only. The copied native graze_count comes from the latest reliable round snapshot, which is not
    // delayed to the presentation tick, so it rises one interpolation delay before the explosion that caused it is
    // drawn. This queue holds each increase until an explosion event with tick >= the snapshot's tick is shown
    // (that event's centre picks the limb), or until a short unscaled-time timeout passes. It decides nothing:
    // Odin's count is the only truth and every increase is released exactly once.
    public sealed class BomGrazeQueue
    {
        public const double TimeoutSeconds = .75;

        public struct Release
        {
            public uint Count;
            public Vector2 Blast;
            public bool HasBlast;
        }

        struct Waiting
        {
            public ulong Tick;
            public double Since;
        }

        sealed class Track
        {
            public ulong Round,
                Session,
                Generation;
            public uint Seen,
                Released;
            public readonly List<Waiting> Pending = new List<Waiting>();
            public readonly List<Release> Ready = new List<Release>();
        }

        readonly Dictionary<uint, Track> tracks = new Dictionary<uint, Track>();

        public int PendingTotal
        {
            get
            {
                int total = 0;
                foreach (var track in tracks.Values)
                    total += track.Pending.Count;
                return total;
            }
        }

        public void Clear() => tracks.Clear();

        // Call once per sample for every roster player, before that sample's events are shown. A new round,
        // session or generation (or a smaller count) starts again from the native count and queues nothing, so
        // late observers never replay an effect.
        public void Observe(
            uint slot,
            ulong round,
            ulong session,
            ulong generation,
            uint count,
            ulong snapshotTick,
            double now
        )
        {
            if (
                !tracks.TryGetValue(slot, out var track)
                || track.Round != round
                || track.Session != session
                || track.Generation != generation
                || count < track.Seen
            )
            {
                track = new Track
                {
                    Round = round,
                    Session = session,
                    Generation = generation,
                    Seen = count,
                    Released = count,
                };
                tracks[slot] = track;
                return;
            }
            for (; track.Seen < count; track.Seen++)
                track.Pending.Add(new Waiting { Tick = snapshotTick, Since = now });
        }

        // A native explosion event is being shown: it answers the oldest queued increase of each player whose
        // snapshot is not newer than the event (an explosion grazes a player at most once).
        public void Explosion(ulong eventTick, Vector2 center)
        {
            foreach (var track in tracks.Values)
            {
                if (track.Pending.Count == 0 || track.Pending[0].Tick > eventTick)
                    continue;
                track.Pending.RemoveAt(0);
                track.Ready.Add(
                    new Release
                    {
                        Count = ++track.Released,
                        Blast = center,
                        HasBlast = true,
                    }
                );
            }
        }

        // Appends this player's due releases to `releases` (timed-out increases carry no blast) and returns the
        // count already presented before them, which rebuilds a recycled actor to what was already shown.
        public uint Collect(uint slot, double now, List<Release> releases)
        {
            if (!tracks.TryGetValue(slot, out var track))
                return 0;
            while (track.Pending.Count > 0 && now - track.Pending[0].Since >= TimeoutSeconds)
            {
                track.Pending.RemoveAt(0);
                track.Ready.Add(new Release { Count = ++track.Released });
            }
            uint settled = track.Released - (uint)track.Ready.Count;
            releases.AddRange(track.Ready);
            track.Ready.Clear();
            return settled;
        }
    }
}
