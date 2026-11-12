using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;

namespace Bom.Unity
{
    // D5: pays Odin's round award (xp_gained) into Darryn's local shop wallet, once per finished round id.
    // MatchMenuUI compiles into Assembly-CSharp, so AddShopCoins is bound by name. Presentation only; Odin decided the award.
    public static class BomWallet
    {
        const string MenuType = "MatchMenuUI, Assembly-CSharp";
        const string CoinsKey = "CharacterShop.Coins";
        static readonly HashSet<ulong> paid = new HashSet<ulong>();
        static bool bound;
        static Action<int> add;

        public static int Total => PlayerPrefs.GetInt(CoinsKey, 250);

        // Forget paid rounds (the player left the server on purpose); a different server may reuse round ids.
        public static void Forget() => paid.Clear();

        public static bool TryPay(ulong round, ulong award)
        {
            if (paid.Contains(round))
                return false;
            Bind();
            if (add == null)
                return false;
            paid.Add(round);
            int amount = (int)Math.Min(award, (ulong)int.MaxValue);
            Debug.Log("BOM WALLET round=" + round + " +" + amount);
            add(amount);
            return true;
        }

        static void Bind()
        {
            if (bound)
                return;
            bound = true;
            MethodInfo method = Type.GetType(MenuType)?.GetMethod("AddShopCoins", BindingFlags.Public | BindingFlags.Static, null, new[] { typeof(int) }, null);
            if (method == null)
            {
                Debug.LogWarning("BOM WALLET could not bind MatchMenuUI.AddShopCoins; the wallet is not paid.");
                return;
            }
            add = (Action<int>)Delegate.CreateDelegate(typeof(Action<int>), method);
        }
    }
}
