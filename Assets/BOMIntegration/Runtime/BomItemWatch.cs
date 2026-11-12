using System.Collections.Generic;
using Bom.Native;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation bookkeeping for native item actors. Native sends no pickup event, so an item that vanishes
    // while touching (or almost touching) a player's capsule during a Playing round is presented as a pickup:
    // the coin sound plays once per item id. Native already applied the effect or coins; this only decides sound.
    public sealed class BomItemWatch
    {
        // Presentation lags the server by a few ticks; allow that much slack around the inclusive native overlap.
        const float PickupSlack = 0.5f;
        readonly HashSet<ulong> drawn = new HashSet<ulong>();
        readonly HashSet<ulong> gone = new HashSet<ulong>();
        public int Drawn => drawn.Count;
        public int Pickups { get; private set; }

        public void Clear()
        {
            drawn.Clear();
            gone.Clear();
        }

        public void Appeared(BomPose pose, GameObject prefab)
        {
            if (!drawn.Add(pose.id))
                return;
            uint kind = BomItemLook.Kind(pose);
            Debug.Log(
                "BOM UNITY ITEM drawn id=" + pose.id + " kind=" + kind + " type=" + BomItemLook.KindName(kind)
                    + " prefab=" + (prefab != null ? prefab.name : "outline")
                    + " x=" + pose.x.ToString("F2") + " y=" + pose.y.ToString("F2")
            );
        }

        public void Vanished(BomPose item, List<BomPose> players, BomActorShapeInfo shape, BomRoundInfo round, Vector3 at)
        {
            if (!gone.Add(item.id))
                return;
            int nearest = -1;
            float best = float.MaxValue;
            for (int i = 0; i < players.Count; i++)
            {
                var p = players[i];
                float dx = item.x - p.x,
                    dy = item.y - p.y;
                dy -= Mathf.Clamp(dy, -shape.player_segment, shape.player_segment);
                float distance = Mathf.Sqrt(dx * dx + dy * dy) - shape.player_radius - shape.item_radius;
                if (distance < best)
                {
                    best = distance;
                    nearest = i;
                }
            }
            bool pickup = round.mode == 1 && round.state == 2 && nearest >= 0 && best <= PickupSlack;
            if (pickup)
            {
                Pickups++;
                BomGameAudio.CoinPickup(at);
            }
            Debug.Log(
                "BOM UNITY ITEM gone id=" + item.id + " kind=" + BomItemLook.Kind(item) + " pickup=" + (pickup ? 1 : 0)
                    + " player=" + (nearest >= 0 ? players[nearest].id.ToString() : "-")
                    + " gap=" + (nearest >= 0 ? best.ToString("F2") : "-") + " round_state=" + round.state
            );
        }
    }
}
