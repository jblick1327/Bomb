using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.Serialization;

// The polygon shape used when cutting a crater from the ground.
public enum CraterShape { Circle, Ellipse, Box }

// Creates falling bombs and coordinates their crater, blast, and cleanup effects.
[AddComponentMenu("Arena/Bomb Dropper")]
public sealed class BombDropper : MonoBehaviour
{
    [SerializeField] private CraterShape craterShape = CraterShape.Circle;
    [Tooltip("Size of the ground cut. For Box this is the base half-width and half-height, before shape scale.")]
    [SerializeField, Min(0.05f), InspectorName("Crater radius (units)")]
    private float craterRadius = 1.6f;
    [Tooltip("Width and height multipliers for Ellipse and Box. Circle ignores this setting.")]
    [SerializeField] private Vector2 craterShapeScale = Vector2.one;
    [Tooltip("Number of polygon edges for Circle and Ellipse. Box always uses four edges.")]
    [SerializeField, Range(8, 96)] private int craterSegments = 40;
    [SerializeField, InspectorName("Crater rotation (degrees)")]
    private float craterRotation;

    [Tooltip("Kills when the circle touches any part of the player's capsule. The blast ring grows to this radius.")]
    [SerializeField, Min(0f), InspectorName("Lethal radius (units)")]
    private float lethalRadius = 2.2f;
    [SerializeField, Min(0f), InspectorName("Inner destruction radius (units)")]
    private float innerDestructionRadius = 1.25f;
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
    [SerializeField] private bool enableCrater = true;
    [SerializeField] private bool enableRubble = true;
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

    [Header("Bomb types")]
    [Tooltip("Chance that each drop is a timed bomb. 0 = all impact, 1 = all timed.")]
    [SerializeField, Range(0f, 1f)] private float timedBombChance = 0.5f;
    [Tooltip("Countdown starts on the timed bomb's first solid impact.")]
    [SerializeField, Min(0.1f), InspectorName("Timed bomb fuse (seconds)")]
    private float timedBombFuse = 3f;

    [Header("Impact bomb appearance")]
    [Tooltip("Drag a model asset or prefab from the Project window here. Its meshes, child objects, and materials are kept.")]
    [SerializeField] private GameObject impactBombModel;
    [FormerlySerializedAs("bombMeshRotation"), FormerlySerializedAs("impactBombMeshRotation")]
    [SerializeField] private Vector3 impactBombModelRotation;
    [Tooltip("The model is centered and fitted to the bomb diameter, then multiplied by this value. Collision size uses Bomb Radius.")]
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
    [Tooltip("Multiplier for crater, player damage, destruction, and blast ring radii. 0.8 is 20% smaller than the base radii above.")]
    [SerializeField, Min(0.05f)] private float impactExplosionScale = 0.8f;
    [Tooltip("Multiplier for crater, player damage, destruction, and blast ring radii. 1.3 is 30% larger than the base radii above.")]
    [SerializeField, Min(0.05f)] private float timedExplosionScale = 1.3f;

    [SerializeField] private Material bombMaterial;
    [SerializeField] private Material blastMaterial;
    [SerializeField] private Material yardGrassMaterial;
    [SerializeField] private Material yardDirtMaterial;
    [SerializeField, Min(0.05f), InspectorName("Blast duration (seconds)")]
    private float blastDuration = 0.35f;
    [Tooltip("Draw spawn range, crater outline and lethal radius when selected in the Scene view.")]
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
    [SerializeField] private DestructibleGround ground;
    [SerializeField] private ArenaGameplayGround gameplayGround;
    [SerializeField] private Collider gameplayGroundCollider;
    [SerializeField] private ArenaPlayerController player;
    [SerializeField, Tooltip("Bombs ignore this collider so they can fall into the arena from above.")]
    private Collider upperBoundary;

    private Transform transientRoot;
    private bool groundResolutionFailureReported;
    private bool yardLayersConfigured;
    private float pendingYardGrassDepth;
    public bool CanRun => session == null || session.IsPlaying;
    public Collider GameplayGroundCollider
    {
        get
        {
            ResolveGround();
            return gameplayGroundCollider;
        }
    }

    private void Awake()
    {
        if (session == null) session = FindFirstObjectByType<ArenaSession>();
        ResolveGround();
        roundElapsedTime = 0f;
        ResetDropTimer();
    }

    private void Update()
    {
        if (!CanRun) return;

        roundElapsedTime += Time.deltaTime;

        // B is an optional development shortcut. Automatic drops always continue.
        if (enableSpawning && Keyboard.current != null && Keyboard.current.bKey.wasPressedThisFrame)
            DropBomb();

        dropTimer -= Time.deltaTime;
        if (dropTimer <= 0f && DropBomb() != null) ResetDropTimer();
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
        ResetDropTimer();
    }

    public FallingBomb DropBomb()
    {
        BombType type = Random.value < Mathf.Clamp01(timedBombChance)
            ? BombType.Timed : BombType.Impact;
        return DropBomb(type);
    }

    public FallingBomb DropBomb(BombType type)
    {
        if (!CanRun || layout == null) return null;
        ResolveGround();
        float leftEdge = gameplayGroundCollider != null ? gameplayGroundCollider.bounds.min.x : layout.LeftEdge;
        float rightEdge = gameplayGroundCollider != null ? gameplayGroundCollider.bounds.max.x : layout.RightEdge;
        float minX = leftEdge + bombRadius + spawnEdgePadding;
        float maxX = rightEdge - bombRadius - spawnEdgePadding;
        float x = Random.Range(Mathf.Min(minX, maxX), Mathf.Max(minX, maxX));
        var body = new GameObject();
        body.name = type == BombType.Timed ? "Timed Bomb" : "Impact Bomb";
        body.transform.position = layout.Origin + new Vector3(x, layout.Height + dropHeightAboveArena, 0f);
        body.transform.SetParent(GetTransientRoot(), true);
        var collider = body.AddComponent<SphereCollider>();
        collider.radius = bombRadius;
        CreateBombVisual(body.transform, type);
        var rigidbody = body.AddComponent<Rigidbody>();
        rigidbody.useGravity = false;
        rigidbody.constraints = RigidbodyConstraints.FreezePositionX | RigidbodyConstraints.FreezePositionZ | RigidbodyConstraints.FreezeRotation;
        rigidbody.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        rigidbody.interpolation = RigidbodyInterpolation.Interpolate;
        if (upperBoundary != null) Physics.IgnoreCollision(collider, upperBoundary);
        foreach (GroundRubble rubble in FindObjectsByType<GroundRubble>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            Collider rubbleCollider = rubble.GetComponent<Collider>();
            if (rubbleCollider != null) Physics.IgnoreCollision(collider, rubbleCollider);
        }

        if (type == BombType.Timed) CreateCountdownAudio(body);

        var bomb = body.AddComponent<FallingBomb>();
        bomb.Initialize(this, fallAcceleration, bombLifetime, type, timedBombFuse);
        DroppedBombCount++;
        return bomb;
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
            foreach (Collider modelCollider in model.GetComponentsInChildren<Collider>(true))
                modelCollider.enabled = false;
            foreach (Rigidbody modelBody in model.GetComponentsInChildren<Rigidbody>(true))
            {
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
            if (!(renderer is MeshRenderer) && !(renderer is SkinnedMeshRenderer)) continue;
            Bounds worldBounds = renderer.bounds;
            // Convert all corners: imported models may have rotated children,
            // nonuniform scales, multiple meshes, and an off-center pivot.
            for (int x = -1; x <= 1; x += 2)
            for (int y = -1; y <= 1; y += 2)
            for (int z = -1; z <= 1; z += 2)
            {
                Vector3 corner = worldBounds.center + Vector3.Scale(worldBounds.extents, new Vector3(x, y, z));
                Vector3 local = root.InverseTransformPoint(corner);
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
        if (explosionClip == null || explosionVolume <= 0f) return;
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

    public void Explode(Vector3 position, BombType type = BombType.Impact)
    {
        if (!CanRun) return;
        Vector2 center = new Vector2(position.x, position.y);
        float sizeScale = GetExplosionScale(type);
        float blastLethalRadius = lethalRadius * sizeScale;
        PlayExplosionSound(position);
        ResolveGround();
        if (enableCrater)
        {
            Vector2[] outline = CreateCraterOutline(center, sizeScale);
            GameObject grassObject = GameObject.Find("Grass_Mesh");
            DestructibleGround grass = grassObject != null ? grassObject.GetComponent<DestructibleGround>() : null;
            if (ground != null && ground.gameObject != grassObject
                && BlastOutlineTouchesSurface(outline, ground.GetComponent<Renderer>()))
                ground.Carve(outline);
            if (grass != null && BlastOutlineTouchesSurface(outline, grass.GetComponent<Renderer>()))
                grass.Carve(outline);
            if (gameplayGround != null) gameplayGround.ApplyCrater(center, craterRadius * sizeScale);
        }
        DestroyDebrisInBlast(center, outerShatterRadius * sizeScale);
        AffectBlastReceivers(center, sizeScale);
        if (enableRubble) SpawnRubble(center, sizeScale);
        if (session != null)
        {
            foreach (ArenaPlayerController target in new[] { session.Player1, session.Player2 })
            {
                if (target == null || !target.gameObject.activeInHierarchy) continue;
                if (target.DistanceToBody(center) > blastLethalRadius) continue;
                session.KillPlayer(target);
                break; // The first death ends the round.
            }
        }
        else if (player != null && player.gameObject.activeInHierarchy
                 && player.DistanceToBody(center) <= blastLethalRadius)
            player.gameObject.SetActive(false);

        ShowBlast(center, blastLethalRadius);
    }

    // A 2D outline can carve every XY layer it crosses. Only apply it to a
    // terrain surface when the outline actually reaches that layer's height.
    private static bool BlastOutlineTouchesSurface(IReadOnlyList<Vector2> outline, Renderer surface)
    {
        if (outline == null || outline.Count < 3 || surface == null) return true;
        float minY = outline[0].y;
        float maxY = minY;
        for (int i = 1; i < outline.Count; i++)
        {
            minY = Mathf.Min(minY, outline[i].y);
            maxY = Mathf.Max(maxY, outline[i].y);
        }
        float surfaceY = surface.bounds.max.y;
        return minY <= surfaceY && maxY >= surfaceY;
    }

    private void DestroyDebrisInBlast(Vector2 center, float radius)
    {
        DestructibleObject.DestroyFragmentsWithin(center, radius);
        foreach (GroundRubble rubble in FindObjectsByType<GroundRubble>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
        {
            Collider collider = rubble.GetComponent<Collider>();
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

    private void ShowBlast(Vector2 center, float radius)
    {
        var visual = new GameObject("Blast");
        visual.transform.SetParent(GetTransientRoot(), true);
        var ring = visual.AddComponent<LineRenderer>();
        ring.sharedMaterial = blastMaterial;
        ring.useWorldSpace = false;
        ring.loop = true;
        ring.positionCount = 64;
        ring.startWidth = ring.endWidth = 0.12f;
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
    }

    // Resolve both the visual terrain and the collider used for bomb placement and landing.
    private void ResolveGround()
    {
        ConfigureYardLayers();
        if (ground == null)
            ground = FindFirstObjectByType<DestructibleGround>(FindObjectsInactive.Include);
        if (ground == null)
        {
            foreach (MeshFilter filter in FindObjectsByType<MeshFilter>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (filter.gameObject.name != "Grass_Mesh" || filter.sharedMesh == null) continue;
                ground = filter.GetComponent<DestructibleGround>();
                if (ground == null) ground = filter.gameObject.AddComponent<DestructibleGround>();
                ground.SetCollisionEnabled(true);
                break;
            }
        }
        if (pendingYardGrassDepth > 0f && ground != null)
        {
            ground.SetExtrusionDepth(pendingYardGrassDepth);
            pendingYardGrassDepth = 0f;
        }

        if (gameplayGround == null)
            gameplayGround = FindFirstObjectByType<ArenaGameplayGround>(FindObjectsInactive.Include);
        if (gameplayGround == null)
        {
            foreach (MeshFilter filter in FindObjectsByType<MeshFilter>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (filter.gameObject.name != "Ground_Mesh" || filter.sharedMesh == null) continue;
                gameplayGround = filter.GetComponent<ArenaGameplayGround>();
                if (gameplayGround == null) gameplayGround = filter.gameObject.AddComponent<ArenaGameplayGround>();
                break;
            }
        }
        if (gameplayGround != null)
        {
            gameplayGround.Initialize();
            gameplayGroundCollider = gameplayGround.GameplayCollider;
        }
        else if (gameplayGroundCollider == null)
        {
            foreach (MeshCollider candidate in FindObjectsByType<MeshCollider>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (candidate.gameObject.name != "Ground_Mesh" || !candidate.enabled || candidate.isTrigger) continue;
                gameplayGroundCollider = candidate;
                Debug.Log($"[BombDropper] Gameplay ground collider resolved to {candidate.name} on {candidate.gameObject.name}, mesh={candidate.sharedMesh?.name}, layer={candidate.gameObject.layer}");
                break;
            }
        }
        if (gameplayGroundCollider == null && ground != null)
        {
            Collider legacyCollider = ground.GetComponent<Collider>();
            if (legacyCollider != null && legacyCollider.enabled && !legacyCollider.isTrigger)
                gameplayGroundCollider = legacyCollider;
        }
        if (gameplayGroundCollider == null && groundResolutionFailureReported == false)
        {
            groundResolutionFailureReported = true;
            Debug.LogError("[BombDropper] No gameplay ground resolved. YardLevel requires an enabled MeshCollider on Ground_Mesh or ArenaGameplayGround.", this);
        }
    }

    private void ConfigureYardLayers()
    {
        if (yardLayersConfigured || UnityEngine.SceneManagement.SceneManager.GetActiveScene().name != "YardLevel") return;

        MeshRenderer grassRenderer = null;
        MeshRenderer dirtRenderer = null;
        foreach (MeshRenderer renderer in FindObjectsByType<MeshRenderer>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (renderer.gameObject.name == "Grass_Mesh") grassRenderer = renderer;
            else if (renderer.gameObject.name == "Ground_Mesh") dirtRenderer = renderer;
        }
        if (grassRenderer == null || dirtRenderer == null) return;

        grassRenderer.gameObject.SetActive(true);
        dirtRenderer.gameObject.SetActive(true);
        grassRenderer.enabled = true;
        dirtRenderer.enabled = true;
        if (yardGrassMaterial != null) grassRenderer.sharedMaterial = yardGrassMaterial;
        if (yardDirtMaterial != null) dirtRenderer.sharedMaterial = yardDirtMaterial;

        Vector3 grassPosition = grassRenderer.transform.position;

        // Span the dirt's full depth so turf is also present at the player's Z,
        // instead of appearing only on the distant camera-facing edge.
        float cameraZ = Camera.main != null ? Camera.main.transform.position.z : grassRenderer.bounds.min.z - 1f;
        float towardCamera = cameraZ < dirtRenderer.bounds.center.z ? -1f : 1f;
        pendingYardGrassDepth = dirtRenderer.bounds.size.z + 0.2f;
        grassPosition.z = dirtRenderer.bounds.center.z + towardCamera * 0.1f;
        grassRenderer.transform.position = grassPosition;
        yardLayersConfigured = true;
    }

    public bool IsGameplayGroundCollider(Collider collider)
    {
        ResolveGround();
        if (gameplayGround != null) return collider == gameplayGround.GameplayCollider;
        return collider == gameplayGroundCollider;
    }

    // Use a broad phase query, then deduplicate receiver components found on overlapping colliders.
    private void AffectBlastReceivers(Vector2 center, float sizeScale)
    {
        Vector3 queryCenter = new Vector3(center.x, center.y, layout != null ? layout.Origin.z : transform.position.z);
        float halfDepth = layout != null ? layout.Depth * 0.5f + 0.5f : 10f;
        float receiverRadius = Mathf.Max(lethalRadius, outerShatterRadius) * sizeScale;
        Collider[] colliders = Physics.OverlapBox(queryCenter, new Vector3(receiverRadius, receiverRadius, halfDepth));
        var receivers = new HashSet<IBlastReceiver>();
        DestructibleMultiMesh[] multiMeshes = FindObjectsByType<DestructibleMultiMesh>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        if (multiMeshes.Length == 0)
        {
            foreach (Transform candidate in FindObjectsByType<Transform>(FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (candidate.parent != null || !HasTerrainChildren(candidate)) continue;
                candidate.gameObject.AddComponent<DestructibleMultiMesh>();
            }
            multiMeshes = FindObjectsByType<DestructibleMultiMesh>(FindObjectsInactive.Include, FindObjectsSortMode.None);
        }
        foreach (DestructibleMultiMesh target in multiMeshes)
        {
            if (target.isActiveAndEnabled) receivers.Add(target);
        }
        foreach (Collider collider in colliders)
        {
            foreach (MonoBehaviour component in collider.GetComponentsInParent<MonoBehaviour>(true))
            {
                if (component.enabled && component is IBlastReceiver receiver)
                    receivers.Add(receiver);
            }
        }

        var blast = new BlastPayload(center, innerDestructionRadius * sizeScale, outerShatterRadius * sizeScale, shatterImpulse);
        foreach (IBlastReceiver receiver in receivers)
            receiver.ReceiveBlast(blast);
    }

    private static bool HasTerrainChildren(Transform root)
    {
        bool grass = false;
        bool ground = false;
        foreach (Transform child in root.GetComponentsInChildren<Transform>(true))
        {
            grass |= child.name == "Grass_Mesh";
            ground |= child.name == "Ground_Mesh";
        }
        return grass && ground;
    }

    private void SpawnRubble(Vector2 center, float sizeScale)
    {
        if (rubblePieces <= 0) return;
        Material material = FindTerrainMaterial();
        if (material == null) return;
        for (int index = 0; index < rubblePieces; index++)
        {
            float angle = index * Mathf.PI * 2f / rubblePieces + Random.Range(-0.25f, 0.25f);
            float distance = Random.Range(Mathf.Max(innerDestructionRadius, craterRadius) * 0.8f, outerShatterRadius) * sizeScale;
            Vector2 position = center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * distance;
            Vector2 direction = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle) * 0.6f).normalized;
            Vector2 impulse = direction * Random.Range(rubbleImpulse * 0.7f, rubbleImpulse * 1.3f) + Vector2.up * 0.5f;
            float pieceSize = rubblePieceSize * Random.Range(0.8f, 1.25f);
            position.y += pieceSize * 0.8f;
            GroundRubble rubble = GroundRubble.Spawn(position, pieceSize, impulse,
                material, GetTransientRoot());
            Collider rubbleCollider = rubble != null ? rubble.GetComponent<Collider>() : null;
            if (rubbleCollider != null)
            {
                foreach (FallingBomb fallingBomb in FindObjectsByType<FallingBomb>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                {
                    Collider bombCollider = fallingBomb.GetComponent<Collider>();
                    if (bombCollider != null) Physics.IgnoreCollision(rubbleCollider, bombCollider);
                }
            }
        }
    }

    private static Material FindTerrainMaterial()
    {
        foreach (MeshRenderer renderer in FindObjectsByType<MeshRenderer>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (renderer.transform.name == "Ground_Mesh" && renderer.sharedMaterial != null)
                return renderer.sharedMaterial;
        }
        return null;
    }

    public void ClearTransientObjects()
    {
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

    // Return a counterclockwise outline in world XY so the terrain clipper can subtract it.
    public float GetExplosionScale(BombType type)
    {
        return Mathf.Max(0.05f, type == BombType.Timed ? timedExplosionScale : impactExplosionScale);
    }

    public Vector2[] CreateCraterOutline(Vector2 center) => CreateCraterOutline(center, 1f);

    private Vector2[] CreateCraterOutline(Vector2 center, float sizeScale)
    {
        int count = craterShape == CraterShape.Box ? 4 : Mathf.Clamp(craterSegments, 8, 96);
        var outline = new Vector2[count];
        Vector2 scale = craterShape == CraterShape.Circle ? Vector2.one
            : new Vector2(Mathf.Max(0.05f, craterShapeScale.x), Mathf.Max(0.05f, craterShapeScale.y));
        Quaternion rotation = Quaternion.Euler(0f, 0f, craterRotation);
        for (int i = 0; i < count; i++)
        {
            Vector2 point;
            if (craterShape == CraterShape.Box)
                point = new Vector2(i == 0 || i == 3 ? -1f : 1f, i < 2 ? -1f : 1f);
            else
            {
                float angle = i * Mathf.PI * 2f / count;
                point = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
            }
            outline[i] = center + (Vector2)(rotation * (Vector3)(Vector2.Scale(point, scale) * Mathf.Max(0.05f, craterRadius) * sizeScale));
        }
        return outline;
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

    private void DrawBlastPreview(Vector2 center, float z, float sizeScale, Color craterColor, Color blastColor)
    {
        Vector2[] outline = CreateCraterOutline(center, sizeScale);
        Gizmos.color = craterColor;
        for (int i = 0; i < outline.Length; i++)
            Gizmos.DrawLine(new Vector3(outline[i].x, outline[i].y, z), new Vector3(outline[(i + 1) % outline.Length].x, outline[(i + 1) % outline.Length].y, z));
        Gizmos.color = blastColor;
        float radius = lethalRadius * sizeScale;
        for (int i = 0; i < 64; i++)
        {
            float a = i * Mathf.PI * 2f / 64f;
            float b = (i + 1) * Mathf.PI * 2f / 64f;
            Gizmos.DrawLine(new Vector3(center.x + Mathf.Cos(a) * radius, center.y + Mathf.Sin(a) * radius, z),
                new Vector3(center.x + Mathf.Cos(b) * radius, center.y + Mathf.Sin(b) * radius, z));
        }
    }
}
