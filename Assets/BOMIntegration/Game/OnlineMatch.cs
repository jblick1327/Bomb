using UnityEngine;

// OD-13 (owner 2026-11-19): AlphaV0.1 "Online v0.2" added an NGO online match (Assets/Game/Online/OnlineMatch.cs).
// Online play is Odin's (BOM-server + the Network* scenes, C5/C7), so that file is not merged. Darryn's offline
// scripts still ask OnlineMatch whether an NGO match is running; this stand-in always answers "no", so they take
// their offline path (Game Over panel, HUD, wallet) unchanged. Lives in Assembly-CSharp next to Assets/Game.
public static class OnlineMatch
{
    public static bool IsRunning => false;
    public static bool IsHost => false;
    public static int PlayerCount => 0;
    public static int LocalSlot => 0;
    public static string PendingMenuMessage { get; set; }

    public static void ArenaLoaded(ArenaSession session) { }
    public static void HostRestartRound() { }
    public static void ReturnFromResults() { }
    public static void LeaveMatch() { }
    public static void SendBombSpawn(int id, float x) { }
    public static void SendItemSpawn(int id, float x, CollectibleItemType type) { }
    public static void SendExplosion(int id, Vector2 center) { }
    public static void RequestPickup(int itemId, int slot) { }
    public static void ReportGraze(int slot, Vector2 center) { }
    public static void ReportDeath(int slot, Vector2? center) { }
}
