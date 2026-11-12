using System;
using System.Reflection;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation-only bridge to Darryn's GameAudio statics. GameAudio compiles into Assembly-CSharp, which the
    // Bom.Unity.Runtime asmdef cannot reference, so the three methods are bound once by name. If any is missing,
    // one warning is logged and the sounds stay off. No outcome is decided here.
    public static class BomGameAudio
    {
        const string AudioType = "GameAudio, Assembly-CSharp";
        static bool bound;
        static Action<Vector3> bombExplosion;
        static Action whistle;
        static Action buttonPop;
        static Action<Vector3> coinPickup;
        static bool roundSeen;
        static ulong seenRound;
        static uint seenState;

        public static void BombExplosion(Vector3 position)
        {
            Bind();
            bombExplosion?.Invoke(position);
        }

        // E1-N4: item pickup sound, bound on its own so a missing method cannot silence the other three.
        public static void CoinPickup(Vector3 position)
        {
            Bind();
            coinPickup?.Invoke(position);
        }

        public static void ButtonPop()
        {
            Bind();
            buttonPop?.Invoke();
        }

        // Called once per native snapshot. The whistle plays when the round (id and state) changes into Playing (2)
        // or Finished (3). The first state seen is only recorded, so a client that joins mid-round stays quiet.
        public static void RoundState(uint flags, ulong round, uint state)
        {
            if ((flags & 1) == 0)
                return;
            if (roundSeen && seenRound == round && seenState == state)
                return;
            bool changed = roundSeen;
            roundSeen = true;
            seenRound = round;
            seenState = state;
            if (!changed || (state != 2 && state != 3))
                return;
            Bind();
            whistle?.Invoke();
            Debug.Log("BOM AUDIO whistle round=" + round + " state=" + state);
        }

        static void Bind()
        {
            if (bound)
                return;
            bound = true;
            const BindingFlags statics = BindingFlags.Public | BindingFlags.Static;
            Type audio = Type.GetType(AudioType);
            MethodInfo explosion = audio?.GetMethod(
                "PlayBombExplosion",
                statics,
                null,
                new[] { typeof(Vector3) },
                null
            );
            MethodInfo whistleMethod = audio?.GetMethod(
                "PlayWhistle",
                statics,
                null,
                Type.EmptyTypes,
                null
            );
            MethodInfo popMethod = audio?.GetMethod(
                "PlayButtonPopSound",
                statics,
                null,
                Type.EmptyTypes,
                null
            );
            MethodInfo coinMethod = audio?.GetMethod(
                "PlayCoinPickup",
                statics,
                null,
                new[] { typeof(Vector3) },
                null
            );
            if (coinMethod != null)
                coinPickup =
                    (Action<Vector3>)Delegate.CreateDelegate(typeof(Action<Vector3>), coinMethod);
            else
                Debug.LogWarning("BOM AUDIO could not bind GameAudio.PlayCoinPickup; the item sound is off.");
            if (explosion == null || whistleMethod == null || popMethod == null)
            {
                Debug.LogWarning("BOM AUDIO could not bind GameAudio statics; game audio is off.");
                return;
            }
            bombExplosion =
                (Action<Vector3>)Delegate.CreateDelegate(typeof(Action<Vector3>), explosion);
            whistle = (Action)Delegate.CreateDelegate(typeof(Action), whistleMethod);
            buttonPop = (Action)Delegate.CreateDelegate(typeof(Action), popMethod);
        }
    }
}
