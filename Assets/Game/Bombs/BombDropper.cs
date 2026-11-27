using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Serialization;

// Creates falling bombs and coordinates their crater, blast, and cleanup effects.
[AddComponentMenu("Arena/Bomb Dropper")]
public sealed class BombDropper : MonoBehaviour
{
    [Tooltip("Reach of the blast on players. A player touched by it loses a limb; the blast ring grows to this radius.")]
    [SerializeField, Min(0f), InspectorName("Lethal radius (units)")]
    private float lethalRadius = 2.2f;
    [Tooltip("Players this close to the bomb are killed outright instead of losing a limb.")]
    [SerializeField, Min(0f), InspectorName("One-shot radius (units)")]
    private float oneShotRadius = 1.2f;
    [SerializeField, Min(0f), InspectorName("Inner destruction radius (units)")]
    private float innerDestructionRadius = 1.25f;
    [Tooltip("Blocks inside this radius are carved; breakable blocks it touches fall apart.")]
    [SerializeField, Min(0f), InspectorName("Outer shatter radius (units)")]
    private float outerShatterRadius = 2.2f;
    [SerializeField, Min(0f), InspectorName("Shatter impulse")]
    private float shatterImpulse = 4f;
    [SerializeField, Range(4, 8), InspectorName("Rubble pieces")]
    private int rubblePieces = 6;
    [SerializeField, Min(0.05f), InspectorName("Rubble piece size")]
    private float rubblePieceSize = 0.35f;
    [SerializeField, Min(0f), InspectorName("Rubble impulse")]
    private float rubbleImpulse = 2.5f;
    [SerializeField] private bool enableRubble = true;
    [Tooltip("A blast this far beyond the lethal radius from a player counts as a near miss (a \"Woah!\").")]
    [SerializeField, Min(0f), InspectorName("Near miss margin (units)")]
    private float nearMissMargin = 1.2f;
    [SerializeField, Tooltip("Development shortcut: allow B to drop an extra bomb.")]
    private bool enableSpawning = false;

    [Header("Automatic bomb drops")]
    [SerializeField, Min(0.1f), InspectorName("Starting minimum interval (seconds)")]
    private float minimumDropInterval = 2f;
    [SerializeField, Min(0.1f), InspectorName("Starting maximum interval (seconds)")]
    private float maximumDropInterval = 5f;
    [SerializeField, Min(0.1f), InspectorName("Fastest interval (seconds)")]
    private float fastestDropInterval = 0.75f;
    [SerializeField, Min(1f), InspectorName("Time to reach fastest rate (seconds)")]
    private float timeToFastestRate = 60f;
    private float dropTimer;
    private float roundElapsedTime;
    public int DroppedBombCount { get; private set; }
    public int DroppedItemCount { get; private set; }

    [SerializeField, Min(0.05f), InspectorName("Bomb radius (units)")]
    private float bombRadius = 0.25f;
    [Tooltip("Extra distance from the side boundaries, in addition to the bomb radius.")]
    [SerializeField, Min(0f), InspectorName("Spawn edge padding (units)")]
    private float spawnEdgePadding = 0.75f;
    [SerializeField, Min(0.5f), InspectorName("Spawn height above arena (units)")]
    private float dropHeightAboveArena = 2f;
    [Tooltip("Positive downward acceleration. Bombs use this instead of Physics gravity.")]
    [SerializeField, Min(0.1f), InspectorName("Fall acceleration (units/s²)")]
    private float fallAcceleration = 18f;
    [SerializeField, Min(1f), InspectorName("Maximum lifetime (seconds)")]
    private float bombLifetime = 15f;
    [Header("Collectible item drops")]
    [SerializeField] private bool enableItemSpawning = true;
    [SerializeField, Min(1f), InspectorName("Minimum item interval (seconds)")]
    private float minimumItemInterval = 12f;
    [SerializeField, Min(1f), InspectorName("Maximum item interval (seconds)")]
    private float maximumItemInterval = 20f;
    [SerializeField, Min(0.05f), InspectorName("Item radius (units)")]
    private float itemRadius = 0.35f;
    [SerializeField, Min(0.01f), InspectorName("Item visual scale")]
    private float itemVisualScale = 0.5f;
    [SerializeField, Min(1f), InspectorName("Item maximum lifetime (seconds)")]
    private float itemLifetime = 15f;
    [SerializeField, Range(0f, 1f), InspectorName("Silver coin chance")]
    private float silverCoinChance = 0.25f;
    [SerializeField, Range(0f, 1f), InspectorName("Gold coin chance")]
    private float goldCoinChance = 0.15f;
    [SerializeField] private UnityEngine.Object coinVisualPrefab;
    [SerializeField] private UnityEngine.Object starCoinVisualPrefab;
    [SerializeField] private UnityEngine.Object timeVisualPrefab;
    [SerializeField] private UnityEngine.Object speedBoostVisualPrefab;
    [SerializeField] private UnityEngine.Object shieldVisualPrefab;
    private float itemWaveTimer;
    [Header("Bomb types")]
    [Tooltip("Chance that each drop is a timed bomb. 0 = all impact, 1 = all timed.")]
    [SerializeField, Range(0f, 1f)] private float timedBombChance = 0.5f;
    [Tooltip("Countdown starts on the timed bomb's first solid impact.")]
    [SerializeField, Min(0.1f), InspectorName("Timed bomb fuse (seconds)")]
    private float timedBombFuse = 3f;

    [Header("Impact bomb appearance")]
    [Tooltip("Drag a model asset or prefab from the Project window here. Its meshes, child objects, and materials are kept.")]
    [FormerlySerializedAs("bombVisualPrefab")]
    [SerializeField] private GameObject impactBombModel;
    [FormerlySerializedAs("bombMeshRotation"), FormerlySerializedAs("impactBombMeshRotation")]
    [SerializeField] private Vector3 impactBombModelRotation;
    [Tooltip("The model is centered and fitted to the bomb diameter, then multiplied by this value. Its collision size automatically follows the final model height.")]
    [FormerlySerializedAs("bombMeshScale"), FormerlySerializedAs("impactBombMeshScale")]
    [SerializeField, Min(0.01f)] private float impactBombModelScale = 1f;

    [Header("Timed bomb appearance")]
    [Tooltip("Separate model asset or prefab for timed bombs, including its materials. Leave empty to use the impact bomb model and its rotation/scale settings.")]
    [SerializeField] private GameObject timedBombModel;
    [FormerlySerializedAs("timedBombMeshRotation")]
    [SerializeField] private Vector3 timedBombModelRotation;
    [FormerlySerializedAs("timedBombMeshScale")]
    [SerializeField, Min(0.01f)] private float timedBombModelScale = 1f;

    [Header("Explosion size by bomb type")]
    [Tooltip("Multiplier for carving, player damage, destruction, and blast ring radii. 0.8 is 20% smaller than the base radii above.")]
    [SerializeField, Min(0.05f)] private float impactExplosionScale = 0.8f;
    [Tooltip("Multiplier for carving, player damage, destruction, and blast ring radii. 1.3 is 30% larger than the base radii above.")]
    [SerializeField, Min(0.05f)] private float timedExplosionScale = 1.3f;

    [SerializeField] private Material bombMaterial;
    [SerializeField] private Material blastMaterial;
    [SerializeField, Min(0.05f), InspectorName("Blast duration (seconds)")]
    private float blastDuration = 0.35f;
    [Tooltip("Draw the spawn range, carve radius and lethal radius when selected in the Scene view.")]
    [SerializeField] private bool showSizePreviews;

    [Header("Explosion audio")]
    [Tooltip("Optional sound played at each explosion. Import an audio file and assign its AudioClip here.")]
    [SerializeField] private AudioClip explosionClip;
    [SerializeField, Range(0f, 1f)] private float explosionVolume = 1f;
    [Tooltip("0 = equal volume everywhere; 1 = positional 3D sound.")]
    [SerializeField, Range(0f, 1f)] private float explosionSpatialBlend = 1f;
    [SerializeField, Min(0.01f)] private float explosionMinDistance = 5f;
    [SerializeField, Min(0.01f)] private float explosionMaxDistance = 50f;

    [Header("Timed bomb countdown audio")]
    [Tooltip("Optional sound that loops from first impact until detonation. Uses the explosion audio's spatial blend and distance settings.")]
    [SerializeField] private AudioClip countdownClip;
    [SerializeField, Range(0f, 1f)] private float countdownVolume = 1f;

    [SerializeField] private ArenaLayout layout;
    [SerializeField] private ArenaSession session;
    [SerializeField] private ArenaPlayerController player;
    [SerializeField, Tooltip("Bombs ignore this collider so they can fall into the arena from above.")]
    private Collider upperBoundary;

    private Transform transientRoot;
    public bool CanRun => session == null || session.IsPlaying;

    // Online, the host numbers each bomb and item so every computer can
    // refer to the same one.
    private int nextNetworkId = 1;
    private readonly Dictionary<int, FallingBomb> networkBombs = new Dictionary<int, FallingBomb>();
    private readonly Dictionary<int, FallingCollectibleItem> networkItems = new Dictionary<int, FallingCollectibleItem>();

    // Models used for the result screen icons.
    public UnityEngine.Object BombPrefab => impactBombModel;

    private void Awake()
    {
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        roundElapsedTime = 0f;
        ResetItemTimer(true);
        ResetDropTimer();
    }

    private void Update()
    {
        if (!CanRun) return;

        roundElapsedTime += Time.deltaTime;
        // Online, only the host drops bombs and items. Other computers create
        // them when the host says so.
        if (OnlineMatch.IsRunning && !OnlineMatch.IsHost) return;

        // B is an optional development shortcut. Automatic drops always continue.
        if (enableSpawning && Keyboard.current != null && Keyboard.current.bKey.wasPressedThisFrame)
            DropBomb();

        dropTimer -= Time.deltaTime;
        if (dropTimer <= 0f && DropBomb() != null) ResetDropTimer();

        if (enableItemSpawning)
        {
            itemWaveTimer -= Time.deltaTime;
            if (itemWaveTimer <= 0f)
            {
                SpawnCollectible();
                ResetItemTimer(false);
            }
        }
    }

    private void ResetDropTimer()
    {
        float fastestInterval = Mathf.Max(0.1f, fastestDropInterval);
        float startingMin = Mathf.Max(0.1f, Mathf.Min(minimumDropInterval, maximumDropInterval));
        float startingMax = Mathf.Max(minimumDropInterval, maximumDropInterval);
        float rampDuration = Mathf.Max(1f, timeToFastestRate);
        float ramp = Mathf.Clamp01(roundElapsedTime / rampDuration);
        float minInterval = Mathf.Lerp(startingMin, fastestInterval, ramp);
        float maxInterval = Mathf.Lerp(startingMax, fastestInterval, ramp);
        dropTimer = Random.Range(minInterval, maxInterval);
    }

    public void ResetSpawnRamp()
    {
        roundElapsedTime = 0f;
        DroppedBombCount = 0;
        DroppedItemCount = 0;
        ResetItemTimer(true);
        ResetDropTimer();
    }

    private void ResetItemTimer(bool initial)
    {
        float minimum = Mathf.Max(1f, Mathf.Min(minimumItemInterval, maximumItemInterval));
        float maximum = Mathf.Max(minimum, maximumItemInterval);
        itemWaveTimer = initial
            ? Random.Range(3f, Mathf.Min(8f, minimum))
            : Random.Range(minimum, maximum);
    }

    public FallingCollectibleItem SpawnCollectible()
    {
        if (!CanRun || layout == null)
            return null;

        float leftEdge = layout.LeftEdge;
        float rightEdge = layout.RightEdge;
        float minX = leftEdge + itemRadius + spawnEdgePadding;
        float maxX = rightEdge - itemRadius - spawnEdgePadding;
        float x = Random.Range(Mathf.Min(minX, maxX), Mathf.Max(minX, maxX));
        CollectibleItemType type = PickCollectibleType();
        int id = nextNetworkId++;
        FallingCollectibleItem item = SpawnItem(type, x, id);
        if (item != null && OnlineMatch.IsRunning) OnlineMatch.SendItemSpawn(id, x, type);
        return item;
    }

    // Online: the host dropped an item.
    public void SpawnNetworkItem(int id, float x, CollectibleItemType type)
    {
        // The host's round has started even if this computer's countdown hasn't.
        if (session != null) session.FinishCountdown();
        if (CanRun && layout != null) SpawnItem(type, x, id);
    }

    private FallingCollectibleItem SpawnItem(CollectibleItemType type, float x, int id)
    {
        GameObject body = SpawnPrefab(GetItemVisualPrefab(type), GetTransientRoot(),
            layout.Origin + new Vector3(x, layout.Height + dropHeightAboveArena, 0f),
            itemVisualScale, type + " Collectible");
        if (body == null)
        {
            Debug.LogError($"[BombDropper] No prefab assigned for collectible type {type}.", this);
            return null;
        }

        Collider collider = PreparePhysicsCollider(body, itemRadius);
        FitColliderToVisual(body, (SphereCollider)collider, itemRadius);
        Rigidbody rigidbody = body.AddComponent<Rigidbody>();
        rigidbody.useGravity = false;
        rigidbody.constraints = RigidbodyConstraints.FreezePositionX | RigidbodyConstraints.FreezePositionZ | RigidbodyConstraints.FreezeRotation;
        rigidbody.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        rigidbody.interpolation = RigidbodyInterpolation.Interpolate;
        if (upperBoundary != null) Physics.IgnoreCollision(collider, upperBoundary);

        // Remote players are only pictures of where someone else is, so
        // items pass through them.
        IgnorePlayers(collider, true);

        body.AddComponent<CollectibleItemTypeHolder>().Type = type;
        body.AddComponent<ItemAura>().Initialize(type);
        FallingCollectibleItem item = body.AddComponent<FallingCollectibleItem>();
        item.Initialize(this, fallAcceleration, itemLifetime);
        item.NetworkId = id;
        networkItems[id] = item;
        DroppedItemCount++;
        return item;
    }

    // Online, host only: true if the item is still there to be taken.
    public bool TryClaimItem(int id, out CollectibleItemType type)
    {
        type = default;
        if (!networkItems.TryGetValue(id, out FallingCollectibleItem item) || item == null || !item.TryClaim()) return false;
        type = item.Type;
        return true;
    }

    // Online: the host gave an item to a player. Every computer removes the
    // item and applies its effect to that player.
    public void ApplyNetworkPickup(int id, CollectibleItemType type, int slot)
    {
        ArenaPlayerController player = session != null ? session.GetPlayer(slot) : null;
        if (networkItems.TryGetValue(id, out FallingCollectibleItem item) && item != null)
            item.CollectBy(player, type);
        else if (player != null)
            player.ApplyCollectible(type);
        networkItems.Remove(id);
    }

    private void IgnorePlayers(Collider collider, bool remoteOnly)
    {
        if (session == null || collider == null) return;
        foreach (ArenaPlayerController target in session.Players)
        {
            if (target == null || remoteOnly && !target.IsRemote) continue;
            CharacterController body = target.GetComponent<CharacterController>();
            if (body != null) Physics.IgnoreCollision(collider, body);
        }
    }

    public UnityEngine.Object GetItemVisualPrefab(CollectibleItemType type)
    {
        switch (type)
        {
            case CollectibleItemType.SilverCoin: return coinVisualPrefab;
            case CollectibleItemType.GoldCoin: return starCoinVisualPrefab;
            case CollectibleItemType.Invincibility: return shieldVisualPrefab;
            case CollectibleItemType.Slow: return timeVisualPrefab;
            case CollectibleItemType.SpeedBoost: return speedBoostVisualPrefab;
            default: return null;
        }
    }

    private static Collider PreparePhysicsCollider(GameObject body, float radius)
    {
        foreach (Collider existing in body.GetComponentsInChildren<Collider>(true))
            existing.enabled = false;

        SphereCollider collider = body.GetComponent<SphereCollider>();
        if (collider == null)
            collider = body.AddComponent<SphereCollider>();
        collider.enabled = true;
        collider.isTrigger = false;
        collider.radius = radius;
        return collider;
    }

    // Centre the sphere on the visible model and make it as tall as the model,
    // so the item rests on its bottom edge instead of sinking into surfaces.
    // Collider radius is in local space, so world sizes are divided by the scale.
    private static void FitColliderToVisual(GameObject body, SphereCollider collider, float fallbackWorldRadius)
    {
        Bounds visual = default;
        bool found = false;
        foreach (Renderer renderer in body.GetComponentsInChildren<Renderer>())
        {
            if (!renderer.enabled || !(renderer is MeshRenderer || renderer is SkinnedMeshRenderer)) continue;
            if (found) visual.Encapsulate(renderer.bounds);
            else { visual = renderer.bounds; found = true; }
        }
        Vector3 lossy = body.transform.lossyScale;
        float scale = Mathf.Max(Mathf.Abs(lossy.x), Mathf.Abs(lossy.y), Mathf.Abs(lossy.z));
        if (scale < 0.0001f) return;
        bool useVisual = found && visual.extents.y > 0.01f;
        collider.center = useVisual ? body.transform.InverseTransformPoint(visual.center) : Vector3.zero;
        collider.radius = (useVisual ? visual.extents.y : fallbackWorldRadius) / scale;
    }

    private static GameObject SpawnPrefab(UnityEngine.Object prefab, Transform parent, Vector3 position, float scale, string name)
    {
        if (prefab == null)
        {
            return null;
        }

        UnityEngine.Object instantiated = UnityEngine.Object.Instantiate(prefab);
        GameObject instance = instantiated as GameObject;
        if (instance == null && instantiated is Component component)
            instance = component.gameObject;
        if (instance == null)
        {
            Debug.LogError($"[BombDropper] Visual asset '{prefab.name}' did not instantiate as a GameObject.", prefab);
            Destroy(instantiated);
            return null;
        }
        instance.name = name;
        instance.transform.SetParent(parent, true);
        instance.transform.position = position;
        instance.transform.localScale = Vector3.one * scale;
        foreach (MonoBehaviour visualScript in instance.GetComponentsInChildren<MonoBehaviour>(true))
            visualScript.enabled = false;
        return instance;
    }

    private CollectibleItemType PickCollectibleType()
    {
        float roll = Random.value;
        if (roll < Mathf.Clamp01(silverCoinChance))
            return CollectibleItemType.SilverCoin;
        if (roll < Mathf.Clamp01(silverCoinChance + goldCoinChance))
            return CollectibleItemType.GoldCoin;
        return (CollectibleItemType)Random.Range((int)CollectibleItemType.Invincibility,
            (int)CollectibleItemType.SpeedBoost + 1);
    }

    private static Material CreateItemMaterial(CollectibleItemType type)
    {
        Shader shader = Shader.Find("Universal Render Pipeline/Lit");
        Material material = new Material(shader != null ? shader : Shader.Find("Standard"));
        material.color = type == CollectibleItemType.SilverCoin ? new Color(0.75f, 0.8f, 0.86f)
            : type == CollectibleItemType.GoldCoin ? new Color(1f, 0.7f, 0.08f)
            : type == CollectibleItemType.Invincibility ? new Color(0.25f, 0.85f, 1f)
            : type == CollectibleItemType.Slow ? new Color(0.35f, 0.2f, 0.8f)
            : new Color(0.2f, 1f, 0.3f);
        return material;
    }

    public FallingBomb DropBomb()
    {
        float chance = Mathf.Clamp01(timedBombChance);
        BombType type = chance >= 1f || (chance > 0f && Random.value < chance)
            ? BombType.Timed : BombType.Impact;
        return DropBomb(type);
    }

    public FallingBomb DropBomb(BombType type)
    {
        if (!CanRun || layout == null || (OnlineMatch.IsRunning && !OnlineMatch.IsHost)) return null;
        float minX = layout.LeftEdge + bombRadius + spawnEdgePadding;
        float maxX = layout.RightEdge - bombRadius - spawnEdgePadding;
        float x = Random.Range(Mathf.Min(minX, maxX), Mathf.Max(minX, maxX));
        int id = nextNetworkId++;
        FallingBomb dropped = SpawnBomb(x, id, type);
        if (dropped != null && OnlineMatch.IsRunning) OnlineMatch.SendBombSpawn(id, x, type);
        return dropped;
    }

    // The host chooses the type once; clients never roll independently.
    public void SpawnNetworkBomb(int id, float x, BombType type = BombType.Impact)
    {
        // The host's round has started even if this computer's countdown hasn't.
        if (session != null) session.FinishCountdown();
        if (CanRun && layout != null && !networkBombs.ContainsKey(id)) SpawnBomb(x, id, type);
    }

    private FallingBomb SpawnBomb(float x, int id, BombType type)
    {
        var body = new GameObject(type == BombType.Timed ? "Timed Bomb" : "Impact Bomb");
        body.transform.position = layout.Origin + new Vector3(x, layout.Height + dropHeightAboveArena, 0f);
        body.transform.SetParent(GetTransientRoot(), true);
        var collider = body.AddComponent<SphereCollider>();
        collider.radius = bombRadius;
        CreateBombVisual(body.transform, type);
        FitBombCollider(body.transform, collider);
        var rigidbody = body.AddComponent<Rigidbody>();
        rigidbody.useGravity = false;
        rigidbody.constraints = RigidbodyConstraints.FreezePositionX | RigidbodyConstraints.FreezePositionZ | RigidbodyConstraints.FreezeRotation;
        rigidbody.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        rigidbody.interpolation = RigidbodyInterpolation.Interpolate;
        if (upperBoundary != null) Physics.IgnoreCollision(collider, upperBoundary);
        foreach (GroundRubble rubble in GroundRubble.Active)
            if (rubble.Collider != null) Physics.IgnoreCollision(collider, rubble.Collider);
        AddBombEffects(body.transform, type);

        // Online, only the host's bombs decide where they go off. Elsewhere a
        // bomb falls through players and waits for the host's explosion.
        if (OnlineMatch.IsRunning && !OnlineMatch.IsHost) IgnorePlayers(collider, false);
        if (type == BombType.Timed) CreateCountdownAudio(body);
        var bomb = body.AddComponent<FallingBomb>();
        bomb.NetworkId = id;
        bomb.Initialize(this, fallAcceleration, bombLifetime, type, timedBombFuse);
        networkBombs[id] = bomb;
        DroppedBombCount++;
        return bomb;
    }

    // Sparks fizzing from the top of the bomb (where its fuse is), and for
    // timed bombs a warning glow and a ring showing how far the blast reaches.
    private void AddBombEffects(Transform bomb, BombType type)
    {
        Vector3 top = bomb.position + Vector3.up * bombRadius;
        bool found = false;
        Bounds bounds = default;
        foreach (Renderer renderer in bomb.GetComponentsInChildren<Renderer>())
        {
            if (!(renderer is MeshRenderer) && !(renderer is SkinnedMeshRenderer)) continue;
            if (found) bounds.Encapsulate(renderer.bounds);
            else { bounds = renderer.bounds; found = true; }
        }
        if (found) top = new Vector3(bounds.center.x, bounds.max.y, bounds.center.z);
        var tip = new GameObject("Fuse Tip").transform;
        tip.SetParent(bomb, true);
        tip.position = top;
        ParticleSystem sparks = BomFx.AddFuseSparks(tip);

        if (type != BombType.Timed) return;
        float frontOffset = (layout != null ? layout.Depth * .5f : 0f) + .1f;
        bomb.gameObject.AddComponent<TimedBombFx>().Initialize(sparks, lethalRadius * GetExplosionScale(BombType.Timed), frontOffset);
    }

    public void StartNetworkBombFuse(int id, Vector3 position, float remaining)
    {
        if (!CanRun) return;
        if (networkBombs.TryGetValue(id, out FallingBomb bomb) && bomb != null)
            bomb.ApplyNetworkFuse(position, remaining);
    }

    public void ForgetNetworkBomb(int id)
    {
        networkBombs.Remove(id);
    }

    // Only a host message detonates a client's bomb; use the host's size too.
    public void ExplodeNetworkBomb(int id, Vector2 center, BombType type = BombType.Impact, float sizeScale = -1f)
    {
        if (networkBombs.TryGetValue(id, out FallingBomb bomb) && bomb != null)
        {
            bomb.gameObject.SetActive(false);
            Destroy(bomb.gameObject);
        }
        networkBombs.Remove(id);
        if (!CanRun) return;
        Explode(new Vector3(center.x, center.y, layout != null ? layout.Origin.z : 0f), type, sizeScale);
    }

    private void CreateBombVisual(Transform bomb, BombType type)
    {
        bool hasTimedModel = type == BombType.Timed && timedBombModel != null;
        GameObject modelPrefab = hasTimedModel ? timedBombModel : impactBombModel;
        Vector3 modelRotation = hasTimedModel ? timedBombModelRotation : impactBombModelRotation;
        float modelScale = hasTimedModel ? timedBombModelScale : impactBombModelScale;
        GameObject visual;
        if (modelPrefab != null)
        {
            // A separate visual hierarchy preserves all material assignments and
            // child transforms while the bomb root owns gameplay physics.
            visual = new GameObject("Bomb Model");
            visual.transform.SetParent(bomb, false);
            GameObject model = Instantiate(modelPrefab, visual.transform, false);
            model.SetActive(true);
            foreach (MonoBehaviour visualScript in model.GetComponentsInChildren<MonoBehaviour>(true))
                visualScript.enabled = false;
            foreach (AudioSource visualAudio in model.GetComponentsInChildren<AudioSource>(true))
                visualAudio.enabled = false;
            foreach (Collider modelCollider in model.GetComponentsInChildren<Collider>(true))
                modelCollider.enabled = false;
            foreach (Rigidbody modelBody in model.GetComponentsInChildren<Rigidbody>(true))
            {
                modelBody.collisionDetectionMode = CollisionDetectionMode.Discrete;
                modelBody.isKinematic = true;
                modelBody.detectCollisions = false;
                Destroy(modelBody);
            }
            foreach (Animator animator in model.GetComponentsInChildren<Animator>(true))
                animator.applyRootMotion = false;

            if (TryGetModelBounds(visual.transform, out Bounds bounds))
            {
                float longestSide = Mathf.Max(bounds.size.x, Mathf.Max(bounds.size.y, bounds.size.z));
                float fitScale = bombRadius * 2f * Mathf.Max(0.01f, modelScale) / Mathf.Max(0.0001f, longestSide);
                Quaternion rotation = Quaternion.Euler(modelRotation);
                visual.transform.localScale = Vector3.one * fitScale;
                visual.transform.localRotation = rotation;
                visual.transform.localPosition = -(rotation * bounds.center) * fitScale;
            }
            return;
        }

        visual = GameObject.CreatePrimitive(PrimitiveType.Sphere);
        visual.name = "Bomb Mesh";
        visual.transform.SetParent(bomb, false);
        visual.transform.localScale = Vector3.one * bombRadius * 2f;
        visual.GetComponent<Renderer>().sharedMaterial = bombMaterial;
        visual.GetComponent<Collider>().enabled = false;
        Destroy(visual.GetComponent<Collider>());

        var fuse = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        fuse.name = "Fuse";
        fuse.transform.SetParent(visual.transform, false);
        fuse.transform.localPosition = new Vector3(0.12f, 0.52f, 0f);
        fuse.transform.localRotation = Quaternion.Euler(0f, 0f, -20f);
        fuse.transform.localScale = new Vector3(0.1f, 0.15f, 0.1f);
        // Disable immediately: Destroy is deferred until the end of the frame.
        fuse.GetComponent<Collider>().enabled = false;
        Destroy(fuse.GetComponent<Collider>());
        fuse.GetComponent<Renderer>().sharedMaterial = blastMaterial;
    }

    private static bool TryGetModelBounds(Transform root, out Bounds bounds)
    {
        bounds = default;
        bool found = false;
        foreach (Renderer renderer in root.GetComponentsInChildren<Renderer>(true))
        {
            if (!renderer.enabled || !renderer.gameObject.activeInHierarchy) continue;
            Bounds meshBounds;
            if (renderer is SkinnedMeshRenderer skinned)
                meshBounds = skinned.localBounds;
            else if (renderer is MeshRenderer)
            {
                MeshFilter filter = renderer.GetComponent<MeshFilter>();
                if (filter == null || filter.sharedMesh == null) continue;
                meshBounds = filter.sharedMesh.bounds;
            }
            else continue;

            // Use mesh-local geometry, not Renderer.bounds: world renderer bounds
            // can still be stale immediately after Instantiate or a scale change.
            Matrix4x4 toRoot = root.worldToLocalMatrix * renderer.transform.localToWorldMatrix;
            for (int x = -1; x <= 1; x += 2)
            for (int y = -1; y <= 1; y += 2)
            for (int z = -1; z <= 1; z += 2)
            {
                Vector3 corner = meshBounds.center + Vector3.Scale(meshBounds.extents, new Vector3(x, y, z));
                Vector3 local = toRoot.MultiplyPoint3x4(corner);
                if (!found)
                {
                    bounds = new Bounds(local, Vector3.zero);
                    found = true;
                }
                else bounds.Encapsulate(local);
            }
        }
        return found;
    }

    private void FitBombCollider(Transform bomb, SphereCollider collider)
    {
        if (!TryGetModelBounds(bomb, out Bounds bounds)) return;
        // Measure AFTER model centering, rotation and visual scale. Matching the
        // collider's lowest point to the visible model's lowest point makes the
        // bomb rest on the ground at any per-type Model Scale.
        collider.center = bounds.center;
        collider.radius = Mathf.Max(0.01f, bounds.extents.y);
    }

    private void CreateCountdownAudio(GameObject bomb)
    {
        if (countdownClip == null || countdownVolume <= 0f) return;
        var source = bomb.AddComponent<AudioSource>();
        source.playOnAwake = false;
        source.loop = true;
        source.clip = countdownClip;
        source.volume = Mathf.Clamp01(countdownVolume);
        source.spatialBlend = Mathf.Clamp01(explosionSpatialBlend);
        source.rolloffMode = AudioRolloffMode.Linear;
        source.dopplerLevel = 0f;
        source.minDistance = Mathf.Max(0.01f, explosionMinDistance);
        source.maxDistance = Mathf.Max(source.minDistance + 0.01f, explosionMaxDistance);
    }

    private void PlayExplosionSound(Vector3 position)
    {
        if (explosionVolume <= 0f) return;
        if (explosionClip == null)
        {
            GameAudio.PlayBombExplosion(position);
            return;
        }
        // Independent of the bomb and round effects, so a lethal explosion or
        // round restart cannot cut the clip off when those objects are cleared.
        var sound = new GameObject("Explosion Sound");
        sound.transform.position = position;
        var source = sound.AddComponent<AudioSource>();
        source.playOnAwake = false;
        source.loop = false;
        source.clip = explosionClip;
        source.volume = Mathf.Clamp01(explosionVolume);
        source.spatialBlend = Mathf.Clamp01(explosionSpatialBlend);
        source.rolloffMode = AudioRolloffMode.Linear;
        source.minDistance = Mathf.Max(0.01f, explosionMinDistance);
        source.maxDistance = Mathf.Max(source.minDistance + 0.01f, explosionMaxDistance);
        source.Play();
        Destroy(sound, explosionClip.length);
    }

    public void Explode(Vector2 center)
    {
        Explode(new Vector3(center.x, center.y, layout != null ? layout.Origin.z : 0f));
    }

    public void Explode(Vector3 position, BombType type = BombType.Impact, float explosionScale = -1f)
    {
        if (!CanRun) return;
        Vector2 center = new Vector2(position.x, position.y);
        float sizeScale = explosionScale >= 0f ? Mathf.Max(0.05f, explosionScale) : GetExplosionScale(type);
        PlayExplosionSound(position);
        ArenaCamera.Shake(Mathf.Clamp(0.75f * sizeScale, 0.55f, 1f));
        List<DestructibleObject> supportedPieces = DestructibleObject.FindSupportedPieces();
        DestroyDebrisInBlast(center, outerShatterRadius * sizeScale);
        Material cutMaterial = AffectBlastReceivers(center, sizeScale);
        DestructibleObject.DropUnsupportedPieces(supportedPieces);
        WakeRestingBodies();
        // Rubble takes the colour of the block the bomb dug into, so a blast
        // in open air makes none.
        if (enableRubble && cutMaterial != null) SpawnRubble(center, cutMaterial, sizeScale);
        // The crumble only when the blast broke into ground or a block.
        if (cutMaterial != null)
            GameAudio.PlayBreaking(new Vector3(center.x, center.y, layout != null ? layout.Origin.z : 0f));
        if (session != null)
        {
            // Online, each computer only checks its own player and reports the result.
            List<ArenaPlayerController> hitPlayers = new List<ArenaPlayerController>();
            foreach (ArenaPlayerController target in session.Players)
                if (target != null && !target.IsRemote && HitPlayer(target, center, sizeScale)) hitPlayers.Add(target);
            session.KillPlayers(hitPlayers, center);
        }
        else if (HitPlayer(player, center, sizeScale))
            player.gameObject.SetActive(false);
        if (IsNearMiss(center, lethalRadius * sizeScale)) GameAudio.PlayNearMissVoice();

        ShowBlast(center, lethalRadius * sizeScale, cutMaterial);
    }

    // True if a player on this computer who is still in the round was only
    // just outside the blast (radius: this blast's lethal radius).
    private bool IsNearMiss(Vector2 center, float radius)
    {
        if (session == null) return false;
        foreach (ArenaPlayerController target in session.Players)
        {
            if (target == null || target.IsRemote || !target.gameObject.activeInHierarchy) continue;
            float distance = target.DistanceToBody(center);
            if (distance > radius && distance <= radius + nearMissMargin) return true;
        }
        return false;
    }

    // Close hits kill; hits from the edge of the blast knock a limb off, and
    // kill only once the player has taken too many. Killed players burst into
    // chunks. Returns true if the player should be removed.
    private bool HitPlayer(ArenaPlayerController target, Vector2 center, float sizeScale)
    {
        if (target == null || !target.gameObject.activeInHierarchy || target.IsInvincible) return false;
        float distance = target.DistanceToBody(center);
        if (distance > lethalRadius * sizeScale) return false;
        bool killed = distance <= oneShotRadius * sizeScale || target.TakeGraze(center);
        if (killed) target.Burst(center);
        else if (OnlineMatch.IsRunning) OnlineMatch.ReportGraze(target.PlayerNumber - 1, center);
        return killed;
    }

    // Unity does not wake a sleeping rigidbody when the surface under it is cut
    // or removed, so fallen pieces and landed items would hang in the air.
    private static void WakeRestingBodies()
    {
        foreach (FallingCollectibleItem item in FindObjectsByType<FallingCollectibleItem>(FindObjectsSortMode.None))
            item.ResumeFalling();
        foreach (Rigidbody body in FindObjectsByType<Rigidbody>(FindObjectsSortMode.None))
            if (!body.isKinematic) body.WakeUp();
    }

    private void DestroyDebrisInBlast(Vector2 center, float radius)
    {
        DestructibleObject.DestroyFragmentsWithin(center, radius);
        // Copy first: deactivating rubble removes it from the active list.
        var rubbleList = new List<GroundRubble>(GroundRubble.Active);
        foreach (GroundRubble rubble in rubbleList)
        {
            Collider collider = rubble.Collider;
            if (collider == null) continue;
            Bounds bounds = collider.bounds;
            Vector2 closest = new Vector2(
                Mathf.Clamp(center.x, bounds.min.x, bounds.max.x),
                Mathf.Clamp(center.y, bounds.min.y, bounds.max.y));
            if (Vector2.Distance(center, closest) > radius) continue;
            rubble.gameObject.SetActive(false);
            Destroy(rubble.gameObject);
        }
    }

    // The explosion's look, sized to the blast (radius): fire, sparks, smoke,
    // dust in the colour of the ground hit (cutMaterial), a flash of light,
    // and a glowing shockwave ring.
    private void ShowBlast(Vector2 center, float radius, Material cutMaterial)
    {
        var visual = new GameObject("Blast");
        visual.transform.SetParent(GetTransientRoot(), true);
        var ring = visual.AddComponent<LineRenderer>();
        Material ringMaterial = BomFx.Strip(2.5f);
        ring.sharedMaterial = ringMaterial != null ? ringMaterial : blastMaterial;
        ring.startColor = ring.endColor = new Color(1f, .82f, .5f);
        ring.useWorldSpace = false;
        ring.loop = true;
        ring.positionCount = 64;
        ring.startWidth = ring.endWidth = 0.45f;
        ring.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        ring.receiveShadows = false;
        for (int i = 0; i < ring.positionCount; i++)
        {
            float angle = i * Mathf.PI * 2f / ring.positionCount;
            ring.SetPosition(i, new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0f));
        }
        Vector3 origin = new Vector3(center.x, center.y, layout != null ? layout.Origin.z : 0f);
        Vector3 forward = Camera.main != null ? Camera.main.transform.forward : Vector3.forward;
        float frontDistance = ((layout != null ? layout.Depth : 0f) * 0.5f + 0.1f) / Mathf.Max(Mathf.Abs(forward.z), 0.1f);
        visual.transform.position = origin - forward * frontDistance;
        visual.AddComponent<BombBlastVisual>().Initialize(radius, blastDuration);

        Color? dustColor = null;
        if (cutMaterial != null)
            dustColor = cutMaterial.HasProperty("_BaseColor") ? cutMaterial.GetColor("_BaseColor") : cutMaterial.color;
        BomFx.Explosion(visual.transform.position, radius, dustColor);
    }

    public bool IsBelowArena(Vector3 position)
    {
        return layout != null && position.y < layout.Origin.y + layout.GroundBottom - itemRadius * 2f;
    }

    // Use a broad phase query, then deduplicate receiver components found on overlapping colliders.
    // Returns the material of a block the blast cut into, or null if it cut nothing.
    private Material AffectBlastReceivers(Vector2 center, float sizeScale)
    {
        Vector3 queryCenter = new Vector3(center.x, center.y, layout != null ? layout.Origin.z : transform.position.z);
        float halfDepth = layout != null ? layout.Depth * 0.5f + 0.5f : 10f;
        float receiverRadius = Mathf.Max(lethalRadius, outerShatterRadius) * sizeScale;
        Collider[] colliders = Physics.OverlapBox(queryCenter, new Vector3(receiverRadius, receiverRadius, halfDepth));
        var receivers = new HashSet<IBlastReceiver>();
        foreach (Collider collider in colliders)
        {
            foreach (MonoBehaviour component in collider.GetComponentsInParent<MonoBehaviour>(true))
            {
                if (component.enabled && component is IBlastReceiver receiver)
                    receivers.Add(receiver);
            }
        }

        var blast = new BlastPayload(center, innerDestructionRadius * sizeScale, outerShatterRadius * sizeScale, shatterImpulse);
        Material groundMaterial = null;
        Material anyMaterial = null;
        foreach (IBlastReceiver receiver in receivers)
        {
            receiver.ReceiveBlast(blast);
            if (!(receiver is DestructibleObject block) || !block.WasCutThisFrame || block.SurfaceMaterial == null) continue;
            if (anyMaterial == null) anyMaterial = block.SurfaceMaterial;
            if (groundMaterial == null && !block.BreaksApart) groundMaterial = block.SurfaceMaterial;
        }
        // Prefer ground blocks so a hit on a bench next to the ground still throws dirt.
        return groundMaterial != null ? groundMaterial : anyMaterial;
    }

    private void SpawnRubble(Vector2 center, Material material, float sizeScale)
    {
        if (rubblePieces <= 0) return;
        float planeZ = layout != null ? layout.Origin.z : transform.position.z;
        for (int index = 0; index < rubblePieces; index++)
        {
            float angle = index * Mathf.PI * 2f / rubblePieces + Random.Range(-0.25f, 0.25f);
            float distance = Random.Range(innerDestructionRadius * 0.8f, Mathf.Max(innerDestructionRadius, outerShatterRadius)) * sizeScale;
            Vector2 position = center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * distance;
            Vector2 direction = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle) * 0.6f).normalized;
            Vector2 flat = direction * Random.Range(rubbleImpulse * 0.7f, rubbleImpulse * 1.3f) + Vector2.up * 0.5f;
            // Some sideways push in Z, so pieces fly toward and away from the camera too.
            Vector3 impulse = new Vector3(flat.x, flat.y, Random.Range(-0.8f, 0.8f) * rubbleImpulse);
            float pieceSize = rubblePieceSize * Random.Range(0.8f, 1.25f);
            position.y += pieceSize * 0.8f;
            GroundRubble.Spawn(new Vector3(position.x, position.y, planeZ), pieceSize, impulse,
                LevelAtmosphere.SurfaceVersion(material), GetTransientRoot());
        }
    }

    public void ClearTransientObjects()
    {
        networkBombs.Clear();
        networkItems.Clear();
        if (transientRoot == null) return;
        transientRoot.gameObject.SetActive(false);
        Destroy(transientRoot.gameObject);
        transientRoot = null;
    }

    private Transform GetTransientRoot()
    {
        if (transientRoot == null)
        {
            transientRoot = new GameObject("Round Effects").transform;
            transientRoot.SetParent(transform, false);
        }
        return transientRoot;
    }

    public float GetExplosionScale(BombType type)
    {
        return Mathf.Max(0.05f, type == BombType.Timed ? timedExplosionScale : impactExplosionScale);
    }

    private void OnDrawGizmosSelected()
    {
        if (!showSizePreviews || layout == null) return;
        Vector3 origin = layout.Origin;
        float minX = layout.LeftEdge + bombRadius + spawnEdgePadding;
        float maxX = layout.RightEdge - bombRadius - spawnEdgePadding;
        Gizmos.color = Color.yellow;
        float y = layout.CameraBounds.max.y + dropHeightAboveArena;
        Gizmos.DrawLine(new Vector3(minX, y, origin.z), new Vector3(maxX, y, origin.z));
        Vector2 center = (Vector2)origin + Vector2.up * layout.GroundTop;
        DrawBlastPreview(center, origin.z, GetExplosionScale(BombType.Impact), Color.cyan, Color.red);
        DrawBlastPreview(center, origin.z, GetExplosionScale(BombType.Timed), Color.blue, Color.yellow);
    }

    private void DrawBlastPreview(Vector2 center, float z, float sizeScale, Color carveColor, Color damageColor)
    {
        Gizmos.color = carveColor;
        DrawCircleGizmo(center, outerShatterRadius * sizeScale, z);
        Gizmos.color = damageColor;
        DrawCircleGizmo(center, lethalRadius * sizeScale, z);
        Gizmos.color = Color.magenta;
        DrawCircleGizmo(center, oneShotRadius * sizeScale, z);
    }

    private static void DrawCircleGizmo(Vector2 center, float radius, float z)
    {
        for (int i = 0; i < 64; i++)
        {
            float a = i * Mathf.PI * 2f / 64f;
            float b = (i + 1) * Mathf.PI * 2f / 64f;
            Gizmos.DrawLine(new Vector3(center.x + Mathf.Cos(a) * radius, center.y + Mathf.Sin(a) * radius, z),
                new Vector3(center.x + Mathf.Cos(b) * radius, center.y + Mathf.Sin(b) * radius, z));
        }
    }
}
