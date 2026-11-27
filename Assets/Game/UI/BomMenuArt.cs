using UnityEngine;

// Models the menus show as pictures. The menu scene has none of the level's
// objects, so this asset (Resources/BomMenuArt) points at the prefabs instead.
[CreateAssetMenu(fileName = "BomMenuArt", menuName = "Bom/Menu Art")]
public sealed class BomMenuArt : ScriptableObject
{
    [Tooltip("The coin shown next to the player's coin balance (the gold star coin).")]
    [SerializeField] private GameObject coinPrefab;

    private static BomMenuArt instance;
    private static bool loaded;

    public static GameObject CoinPrefab => Instance != null ? Instance.coinPrefab : null;

    private static BomMenuArt Instance
    {
        get
        {
            if (!loaded)
            {
                loaded = true;
                instance = Resources.Load<BomMenuArt>("BomMenuArt");
                if (instance == null) Debug.LogWarning("BomMenuArt is missing from a Resources folder.");
            }
            return instance;
        }
    }
}
