using System;
using System.Collections.Generic;
using System.IO;
using Bom.Native;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace Bom.Unity
{
    public sealed class BomClientBehaviour : MonoBehaviour
    {
        public Material Material;
        public Camera View;
        public GameObject PlayerPrefab,
            BombPrefab;
        public GameObject BlastPrefab;
        public int ExplosionVisuals { get; private set; }
        public int RunningPresentationFrames { get; private set; }
        public bool DrivenByRoundScenario { get; set; }
        public double PresentationMilliseconds,
            GeometryMilliseconds;
        public long PresentationAllocatedBytes,
            GeometryAllocatedBytes;
        public bool PresentationHadTopology,
            PresentationHadActorChange,
            GeometryWorkThisFrame;

        public void VerifyRepeatedEventPresentation()
        {
            if (Array.IndexOf(Environment.GetCommandLineArgs(), "--bom-round-test") < 0)
                throw new InvalidOperationException(
                    "Repeated-event check requires the executable test mode"
                );
            int before = ExplosionVisuals;
            Accept(session);
            if (ExplosionVisuals != before)
                throw new InvalidOperationException(
                    "A repeated native event spawned duplicate effects"
                );
        }

        public uint Port = 32000;
        public string Address = "127.0.0.1";
        public bool Prediction = true;
        public BomVisualRegistry VisualRegistry;
        readonly HashSet<ulong> reportedVisualFallbacks = new HashSet<ulong>();
        uint fallbackEpoch;
        ulong fallbackConnection;
        readonly HashSet<ulong> reportedRegistryMatches = new HashSet<ulong>();
        BomSession session;
        Action<BomSession> acceptSample;
        readonly HashSet<(uint, ulong)> seenActors = new HashSet<(uint, ulong)>();
        readonly List<(uint, ulong)> goneActors = new List<(uint, ulong)>();
        public BomSession Session => session;
        BomSourcePresentation sourcePresentation;
        // G2: the only cell path unless ClippedSourceArt (the pre-G2 per-revision batches plus clipped source art,
        // kept for one release behind --bom-clipped-source-art and for the source-capture/job-gate test tools).
        BomCellPresenter cellPresenter;
        bool cellsShown;
        public bool ClippedSourceArt;
        BomCameraRig cameraRig;
        public BomSourcePresentation SourcePresentation => sourcePresentation;
        // Source-art counts from whichever presenter draws cells (intact = Darryn's own mesh, fragments = his art on
        // native cells, fallback = no matching registry art).
        public bool HasSourceArt => ClippedSourceArt ? sourcePresentation != null : cellPresenter != null;
        public int IntactSources => ClippedSourceArt ? sourcePresentation?.IntactSources ?? 0 : cellPresenter?.IntactSources ?? 0;
        public int FragmentSources => ClippedSourceArt ? sourcePresentation?.FragmentSources ?? 0 : cellPresenter?.FragmentSources ?? 0;
        public int FallbackSources => ClippedSourceArt ? sourcePresentation?.FallbackSources ?? 0 : cellPresenter?.FallbackSources ?? 0;
        public BomCellPresenter CellPresenter => cellPresenter;
        public bool AutomatedProfile { get; private set; }

        public bool TryLocalVisualPosition(out Vector3 position)
        {
            position = default;
            if (session == null)
                return false;
            if (!actors.TryGetValue((2, session.Sample.local_player_id), out var actor))
                return false;
            position = actor.TryGetComponent<BomActorView>(out var look)
                ? look.VisualPosition
                : actor.transform.position;
            return true;
        }

        BomActorShapeInfo shapeInfo;
        InputAction move,
            jump,
            blast;
        double inputOffset,
            start;
        GameObject terrain;
        readonly Dictionary<(uint, ulong), Transform> bodies =
            new Dictionary<(uint, ulong), Transform>();
        readonly Dictionary<(uint, ulong), GameObject> actors =
            new Dictionary<(uint, ulong), GameObject>();
        readonly List<Mesh> meshes = new List<Mesh>();
        readonly BomActorPool actorPool = new BomActorPool();
        // One persistent parent for blast, death-burst and graze-chunk effects. The per-revision terrain object
        // is destroyed on every topology revision; this root survives that and is cleared by ClearScene(false).
        GameObject effects;
        readonly BomDeathWatch deaths = new BomDeathWatch();
        readonly BomGrazeQueue grazes = new BomGrazeQueue();
        // E1-N4: native item actors (pose kind 4) and this sample's player poses for the pickup sound.
        readonly BomItemWatch items = new BomItemWatch();
        readonly List<BomPose> framePlayers = new List<BomPose>();
        public int ItemsDrawn => items.Drawn;
        readonly List<BomDeathWatch.Burst> deathsDue = new List<BomDeathWatch.Burst>();
        readonly List<BomGrazeQueue.Release> grazesDue = new List<BomGrazeQueue.Release>();
        public int PooledActorCount => actorPool.OwnedCount;
        public int IdleActorCount => actorPool.IdleCount;
        readonly Dictionary<ulong, BomMeshGeometry> cellGeometry =
            new Dictionary<ulong, BomMeshGeometry>();

        sealed class TerrainBatch
        {
            public Transform Body;
            public uint Color;
            public ulong SourceId;
            public readonly List<Vector3> Vertices = new List<Vector3>(),
                Normals = new List<Vector3>();
            public readonly List<Vector2> UV = new List<Vector2>();
            public readonly List<int> Faces = new List<int>(),
                Sides = new List<int>();

            public void Add(BomMeshGeometry geometry, Vector2 offset)
            {
                int first = Vertices.Count;
                foreach (var v in geometry.Vertices)
                    Vertices.Add(v + new Vector3(offset.x, offset.y, 0));
                Normals.AddRange(geometry.Normals);
                UV.AddRange(geometry.UV);
                foreach (int i in geometry.Faces)
                    Faces.Add(first + i);
                foreach (int i in geometry.Sides)
                    Sides.Add(first + i);
            }

            public Mesh Upload() =>
                new BomMeshGeometry
                {
                    Vertices = Vertices.ToArray(),
                    Normals = Normals.ToArray(),
                    UV = UV.ToArray(),
                    Faces = Faces.ToArray(),
                    Sides = Sides.ToArray(),
                }.Upload("Native terrain batch");
        }

        ulong generation,
            revision = ulong.MaxValue,
            lastEvent,
            acceptedTopology;
        uint epoch;
        bool smoke,
            reset,
            reconnected,
            blasted;
        double smokeSeconds;
        string smokeStartFile = "",
            smokeStopFile = "";
        bool smokeActive,
            levelSmoke;
        float smokeMove = float.NaN;
        double reconnectSeconds = 8;
        double smokeElapsed;
        float traveled,
            jumpRise;
        Vector2 lastLocal;
        bool hasLocal;
        ulong metricGeneration;
        uint metricEpoch;
        int snapshots,
            events,
            predictedFrames,
            conservativeFrames;
        string failure = "",
            identity = "";
        public bool ConnectOnEnable = true,
            InputBlocked,
            DiagnosticOverlay = true;
        public string ConnectionError => failure;
        public bool ConnectionRequested { get; private set; }
        string connectionToken = "";

        public void Close()
        {
            ConnectionRequested = false;
            sourcePresentation?.Clear();
            cellGeometry.Clear();
            session?.Dispose();
            session = null;
            generation = 0;
            epoch = 0;
            lastEvent = 0;
            acceptedTopology = 0;
        }

        public void ConnectTo(string address, uint port, string token, bool spectator = false)
        {
            if (session == null)
                throw new InvalidOperationException("Native client is unavailable");
            if (ConnectionRequested)
                Disconnect();
            Address = address;
            Port = port;
            connectionToken = token;
            failure = "";
            BomSession.Check(
                BomNative.bom_client_set_join_options(session.Handle, spectator ? 1u : 0u)
            );
            Connect();
        }

        public void Disconnect()
        {
            if (session == null)
                return;
            BomSession.Check(BomNative.bom_client_disconnect(session.Handle));
            ConnectionRequested = false;
            sourcePresentation?.Clear();
            cellGeometry.Clear();
            ClearScene();
            generation = 0;
            epoch = 0;
            lastEvent = 0;
            acceptedTopology = 0;
            session.Round = default;
        }

        public void Reconnect()
        {
            if (session == null)
                return;
            if (ConnectionRequested)
                Disconnect();
            Connect();
        }

        void OnEnable()
        {
            try
            {
                Application.runInBackground = true;
                acceptSample = TimedAccept;
                start = BomSession.Now;
                inputOffset = start - InputState.currentTime;
                var args = Environment.GetCommandLineArgs();
                string Arg(string key, string value)
                {
                    int i = Array.IndexOf(args, key);
                    return i >= 0 && i + 1 < args.Length ? args[i + 1] : value;
                }
                Port = uint.Parse(Arg("--bom-port", Port.ToString()));
                smokeSeconds = double.Parse(
                    Arg("--bom-smoke-seconds", "0"),
                    System.Globalization.CultureInfo.InvariantCulture
                );
                smoke = smokeSeconds > 0;
                smokeStartFile = Arg("--bom-smoke-start-file", "");
                smokeActive = string.IsNullOrEmpty(smokeStartFile);
                smokeStopFile = Arg("--bom-smoke-stop-file", "");
                levelSmoke = Array.IndexOf(args, "--bom-level-smoke") >= 0;
                reconnectSeconds = double.Parse(
                    Arg("--bom-reconnect-seconds", "8"),
                    System.Globalization.CultureInfo.InvariantCulture
                );
                if (levelSmoke)
                {
                    QualitySettings.vSyncCount = 0;
                    Application.targetFrameRate = 60;
                }
                AutomatedProfile =
                    double.Parse(
                        Arg("--bom-profile-seconds", "0"),
                        System.Globalization.CultureInfo.InvariantCulture
                    ) > 0;
                Time.timeScale = float.Parse(
                    Arg(
                        "--bom-time-scale",
                        Time.timeScale.ToString(System.Globalization.CultureInfo.InvariantCulture)
                    ),
                    System.Globalization.CultureInfo.InvariantCulture
                );
                BomAuthorityAudit.ValidateScene();
                BomAuthorityAudit.Validate(PlayerPrefab);
                BomAuthorityAudit.Validate(BombPrefab);
                BomAuthorityAudit.Validate(BlastPrefab);
                Debug.Log(
                    "BOM UNITY AUTHORITY PASS: recursive scene and inactive prefab audit; runtime spawns use audited presentation prefabs; timeScale="
                        + Time.timeScale
                );
                Prediction = Prediction && Array.IndexOf(args, "--bom-prediction-off") < 0;
                session = new BomSession();
                BomSession.Check(
                    BomNative.bom_client_set_prediction(session.Handle, Prediction ? 1u : 0u)
                );
                // G1 draws every cell from native outlines, so it runs without Darryn's clipped source art (and its manifest pin).
                if (Array.IndexOf(args, "--bom-no-visual-registry") >= 0 || BomCellPresenter.G1)
                    VisualRegistry = null;
                ClippedSourceArt =
                    !BomCellPresenter.G1
                    && (
                        ClippedSourceArt
                        || Array.IndexOf(args, "--bom-clipped-source-art") >= 0
                        || Array.IndexOf(args, "--bom-source-capture") >= 0
                        || Array.IndexOf(args, "--bom-source-job-gate") >= 0
                    );
                string expected = Arg(
                    "--bom-expected-manifest",
                    VisualRegistry != null ? VisualRegistry.GameplayManifestHash : ""
                );
                if (VisualRegistry != null && string.IsNullOrEmpty(expected))
                    throw new InvalidOperationException(
                        "Visual registry has no finalized native gameplay manifest"
                    );
                if (!string.IsNullOrEmpty(expected))
                    session.ExpectGameplayManifest(expected);
                if (ClippedSourceArt)
                    sourcePresentation = new BomSourcePresentation(
                        VisualRegistry,
                        Material,
                        Array.IndexOf(args, "--bom-tier1") < 0
                    );
                else
                    Debug.Log("BOM SOURCE ART " + (VisualRegistry != null ? "ON" : "OFF") + " path=cells clip=off");
                connectionToken = Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN") ?? "";
                if (ConnectOnEnable || Array.IndexOf(args, "--bom-auto-connect") >= 0)
                    Connect();
                shapeInfo = new BomActorShapeInfo
                {
                    struct_size = (uint)
                        System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(),
                    version = 1,
                };
                BomSession.Check(BomNative.bom_actor_shape_info(ref shapeInfo));
                var build = new BomBuildInfo
                {
                    struct_size = (uint)
                        System.Runtime.InteropServices.Marshal.SizeOf<BomBuildInfo>(),
                    version = 1,
                };
                BomSession.Check(BomNative.bom_build_info(ref build));
                identity =
                    "Native " + build.source_build_tag + " / protocol " + build.game_protocol;
                Debug.Log("BOM UNITY ABI PASS: 23 layouts, offsets, alignment; " + identity);
                move = new InputAction("Move", InputActionType.Value);
                move.AddCompositeBinding("1DAxis")
                    .With("Negative", "<Keyboard>/a")
                    .With("Positive", "<Keyboard>/d");
                move.AddCompositeBinding("1DAxis")
                    .With("Negative", "<Keyboard>/leftArrow")
                    .With("Positive", "<Keyboard>/rightArrow");
                jump = new InputAction("Jump", InputActionType.Button, "<Keyboard>/space");
                jump.performed += c =>
                    SendInput(() =>
                        BomSession.Check(
                            BomNative.bom_client_enqueue_jump(session.Handle, c.time + inputOffset)
                        )
                    );
                blast = new InputAction("Blast", InputActionType.Button, "<Mouse>/leftButton");
                blast.performed += c =>
                    SendInput(() =>
                    {
                        var permissions = new BomStats
                        {
                            struct_size = (uint)
                                System.Runtime.InteropServices.Marshal.SizeOf<BomStats>(),
                            version = 1,
                        };
                        BomSession.Check(
                            BomNative.bom_client_get_stats(session.Handle, ref permissions)
                        );
                        if ((permissions.flags & 4) == 0 || session.Round.mode == 1)
                            return;
                        if (View == null || Mouse.current == null)
                            return;
                        var ray = View.ScreenPointToRay(Mouse.current.position.ReadValue());
                        if (
                            new Plane(Vector3.forward, Vector3.zero).Raycast(
                                ray,
                                out float distance
                            )
                        )
                        {
                            Vector3 point = ray.GetPoint(distance);
                            // A click is a one-off host diagnostic, so stamp it with the native clock now. The input event's own
                            // timestamp (c.time + inputOffset) lagged by more than the native 0.5 s bound on the owner's machine,
                            // so every click came back Expired (status 3). The age is logged so that is visible.
                            double now = BomSession.Now;
                            Debug.Log(
                                "BOM UNITY BLAST click_age_s="
                                    + (now - (c.time + inputOffset)).ToString("F3")
                                    + " x="
                                    + point.x.ToString("F2")
                                    + " y="
                                    + point.y.ToString("F2")
                            );
                            BomSession.Check(
                                BomNative.bom_client_enqueue_action(
                                    session.Handle,
                                    now,
                                    point.x,
                                    point.y
                                )
                            );
                        }
                    });
                move.Enable();
                jump.Enable();
                blast.Enable();
            }
            catch (Exception e)
            {
                Fail(e);
            }
        }

        void SendInput(Action send)
        {
            if (session == null || !ConnectionRequested || InputBlocked || DrivenByRoundScenario)
                return;
            try
            {
                send();
            }
            catch (Exception error)
            {
                Fail(error);
            }
        }

        void OnMove(InputAction.CallbackContext context) =>
            SendInput(() =>
                BomSession.Check(
                    BomNative.bom_client_set_held_input(
                        session.Handle,
                        context.time + inputOffset,
                        context.ReadValue<float>()
                    )
                )
            );

        void Connect()
        {
            var octets = Address.Split('.');
            if (octets.Length != 4)
                throw new ArgumentException("Enter a numeric IPv4 address");
            uint ip = 0;
            foreach (string octet in octets)
                ip = (ip << 8) | byte.Parse(octet);
            session.Connect(ip, Port, connectionToken);
            ConnectionRequested = true;
        }

        void Update()
        {
            if (session == null || !ConnectionRequested)
                return;
            try
            {
                double now = BomSession.Now,
                    elapsed = now - start;
                if (smoke && !smokeActive)
                {
                    if (
                        File.Exists(smokeStartFile)
                        && (!levelSmoke || (session.Sample.flags & 6) == 6)
                    )
                    {
                        smokeActive = true;
                        start = now;
                        elapsed = 0;
                        hasLocal = false;
                        Debug.Log("BOM UNITY SYNCHRONIZED START");
                    }
                    else if (elapsed > 180)
                        throw new TimeoutException(
                            "Live test start signal or usable baseline did not arrive"
                        );
                }
                smokeElapsed = elapsed;
                if (smoke && smokeActive)
                {
                    float requested = (elapsed % 4 < 2 ? 1 : -1) * (levelSmoke ? .2f : 1);
                    BomSession.Check(
                        BomNative.bom_client_set_held_input(session.Handle, now, requested)
                    );
                    smokeMove = requested;
                    if (elapsed > 3 && !blasted)
                    {
                        BomSession.Check(
                            BomNative.bom_client_enqueue_action(
                                session.Handle,
                                now,
                                levelSmoke ? -12 : -6.4f,
                                levelSmoke ? 7.25f : 2.3f
                            )
                        );
                        BomSession.Check(BomNative.bom_client_enqueue_jump(session.Handle, now));
                        blasted = true;
                    }
                }
                else if (!smoke && !AutomatedProfile && !DrivenByRoundScenario)
                {
                    BomSession.Check(
                        BomNative.bom_client_set_held_input(
                            session.Handle,
                            now,
                            Application.isFocused && !InputBlocked ? move.ReadValue<float>() : 0
                        )
                    );
                }
                session.Poll(now, acceptSample);
                GeometryWorkThisFrame =
                    sourcePresentation != null
                    && (
                        sourcePresentation.Jobs.ActiveCount > 0
                        || sourcePresentation.Jobs.PendingCount > 0
                        || sourcePresentation.FallbackSources > 0
                    );
                long geometryStart = System.Diagnostics.Stopwatch.GetTimestamp(),
                    geometryBytes = BomAllocationCounter.Read();
                sourcePresentation?.Pump(session);
                GeometryMilliseconds =
                    (System.Diagnostics.Stopwatch.GetTimestamp() - geometryStart)
                    * 1000.0
                    / System.Diagnostics.Stopwatch.Frequency;
                GeometryAllocatedBytes = BomAllocationCounter.Since(geometryBytes);
                if (
                    fallbackEpoch != session.Sample.epoch
                    || fallbackConnection != session.Sample.connection_generation
                )
                {
                    reportedVisualFallbacks.Clear();
                    reportedRegistryMatches.Clear();
                    fallbackEpoch = session.Sample.epoch;
                    fallbackConnection = session.Sample.connection_generation;
                }
                foreach (var source in session.Sources.Values)
                {
                    if (
                        VisualRegistry != null
                        && VisualRegistry.TryFind(source.AssetKey, source.VisualHash, out var entry)
                    )
                    {
                        if (reportedRegistryMatches.Add(source.Binding.source_identity))
                            Debug.Log(
                                "BOM REGISTRY MATCH source="
                                    + source.Binding.source_identity
                                    + " groups="
                                    + entry.Groups.Length
                                    + " mesh_vertices="
                                    + (entry.Groups.Length > 0 ? entry.Groups[0].Mesh.vertexCount : 0)
                                    + " hidden="
                                    + (entry.Hidden ? 1 : 0)
                                    + " native_gameplay="
                                    + BomSession.HashText(
                                        session.Catalog.gameplay_hash0,
                                        session.Catalog.gameplay_hash1,
                                        session.Catalog.gameplay_hash2,
                                        session.Catalog.gameplay_hash3
                                    )
                            );
                    }
                    else if (reportedVisualFallbacks.Add(source.Binding.source_identity))
                        Debug.LogWarning(
                            "BOM VISUAL FALLBACK source="
                                + source.Binding.source_identity
                                + " asset="
                                + source.AssetKey
                                + " reason=missing_or_mismatched_local_visual tier=extrusion"
                        );
                }
                foreach (var request in session.RequestResults)
                    Debug.Log(
                        "BOM UNITY REQUEST id="
                            + request.request_id
                            + " kind="
                            + request.kind
                            + " status="
                            + request.status
                            + " effect_tick="
                            + request.effect_tick
                            + " event_id="
                            + request.event_id
                            + " reason="
                            + request.reason
                    );
                if (session.Prediction.status == 1)
                    predictedFrames++;
                if (session.Prediction.status == 2)
                    conservativeFrames++;
                if (
                    smoke
                    && smokeActive
                    && elapsed > 5
                    && !reset
                    && (session.Sample.flags & 2) != 0
                    && !string.IsNullOrEmpty(
                        Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")
                    )
                )
                {
                    BomSession.Check(BomNative.bom_client_host_command(session.Handle, 1, 0, 0));
                    reset = true;
                }
                if (smoke && smokeActive && elapsed > reconnectSeconds && !reconnected)
                {
                    BomSession.Check(BomNative.bom_client_disconnect(session.Handle));
                    Connect();
                    reconnected = true;
                    smokeMove = float.NaN;
                }
                if (
                    smoke
                    && smokeActive
                    && (
                        elapsed >= smokeSeconds
                        || !string.IsNullOrEmpty(smokeStopFile) && File.Exists(smokeStopFile)
                    )
                )
                {
                    bool passed =
                        snapshots > 1
                        && events > 0
                        && reconnected
                        && session.Sample.input_count > 60
                        && traveled > 0.25f
                        && jumpRise > 0.03f
                        && (!Prediction || predictedFrames > 0);
                    Debug.Log(
                        "BOM UNITY LIVE "
                            + (passed ? "PASS" : "FAIL")
                            + " snapshots="
                            + snapshots
                            + " events="
                            + events
                            + " epoch="
                            + epoch
                            + " generation="
                            + generation
                            + " inputs="
                            + session.Sample.input_count
                            + " traveled="
                            + traveled
                            + " jumpRise="
                            + jumpRise
                            + " predicted_frames="
                            + predictedFrames
                            + " conservative_frames="
                            + conservativeFrames
                    );
                    Application.Quit(passed ? 0 : 2);
                    Close();
                }
            }
            catch (Exception e)
            {
                Fail(e);
            }
        }

        void Fail(Exception error)
        {
            failure = error.Message;
            Debug.LogError(error);
            if (smoke || AutomatedProfile)
            {
                Close();
                ClearScene();
                Application.Quit(3);
            }
            else
            {
                try
                {
                    Disconnect();
                }
                catch
                {
                    Close();
                    ClearScene();
                }
            }
        }

        void OnApplicationFocus(bool focused)
        {
            if (!focused)
                SendInput(() =>
                    BomSession.Check(BomNative.bom_client_clear_intent(session.Handle))
                );
        }

        void OnDisable()
        {
            move?.Dispose();
            jump?.Dispose();
            blast?.Dispose();
            move = jump = blast = null;
            Close();
            ClearScene();
            sourcePresentation?.Dispose();
            sourcePresentation = null;
            cellPresenter?.Dispose();
            cellPresenter = null;
        }

        void OnApplicationQuit()
        {
            Close();
        }

        Transform EffectsRoot()
        {
            if (effects == null)
                effects = new GameObject("Native effects");
            return effects.transform;
        }

        void ClearEffects()
        {
            if (effects != null)
            {
                effects.SetActive(false);
                Destroy(effects);
                effects = null;
            }
            deaths.Clear();
            grazes.Clear();
            items.Clear();
        }

        void ClearScene(bool keepSource = false)
        {
            if (!keepSource)
            {
                sourcePresentation?.Clear();
                ClearEffects();
                cellPresenter?.Hide();
                cellsShown = false;
            }
            if (terrain != null)
            {
                terrain.SetActive(false);
                Destroy(terrain);
                terrain = null;
            }
            ReturnActors();
            if (!keepSource)
                actorPool.Dispose();
            bodies.Clear();
            foreach (var mesh in meshes)
                Destroy(mesh);
            meshes.Clear();
            revision = ulong.MaxValue;
        }

        void ReturnActors()
        {
            foreach (var actor in actors.Values)
                if (!actorPool.Return(actor))
                    Destroy(actor);
            actors.Clear();
        }

        GameObject Visual(string name, Transform parent, Mesh mesh, uint rgba, List<Mesh> owned)
        {
            var obj = new GameObject(name);
            obj.transform.SetParent(parent, false);
            obj.AddComponent<MeshFilter>().sharedMesh = mesh;
            var renderer = obj.AddComponent<MeshRenderer>();
            renderer.sharedMaterials = new[] { Material, Material };
            Color color = new Color32((byte)rgba, (byte)(rgba >> 8), (byte)(rgba >> 16), 255);
            var properties = new MaterialPropertyBlock();
            properties.SetColor("_BaseColor", color);
            renderer.SetPropertyBlock(properties, 0);
            properties.SetColor(
                "_BaseColor",
                new Color(color.r * 0.7f, color.g * 0.7f, color.b * 0.7f, 1)
            );
            renderer.SetPropertyBlock(properties, 1);
            owned.Add(mesh);
            if (Application.isPlaying)
                mesh.UploadMeshData(true);
            return obj;
        }

        void ConfigureCamera(BomSession client)
        {
            var s = client.Sample;
            if (s.vertex_count == 0 || View == null)
                return;
            Vector2 min = new Vector2(float.MaxValue, float.MaxValue),
                max = new Vector2(float.MinValue, float.MinValue);
            if ((client.Catalog.level.flags & 1) != 0)
            {
                var level = client.Catalog.level;
                min = new Vector2(level.camera_lo_x, level.camera_lo_y);
                max = new Vector2(level.camera_hi_x, level.camera_hi_y);
            }
            else
                for (int i = 0; i < s.vertex_count; i++)
                {
                    var v = client.Vertices[i];
                    min = Vector2.Min(min, new Vector2(v.x, v.y));
                    max = Vector2.Max(max, new Vector2(v.x, v.y));
                }
            if (cameraRig == null && !View.TryGetComponent(out cameraRig))
                cameraRig = View.gameObject.AddComponent<BomCameraRig>();
            cameraRig.Configure(min, max);
        }

        void AcceptedTopology(BomSample s, bool newSession, int batches, long cacheBytes)
        {
            generation = s.connection_generation;
            epoch = s.epoch;
            revision = s.revision;
            acceptedTopology = s.transaction_id;
            if (newSession)
                lastEvent = 0;
            snapshots++;
            Debug.Log(
                "BOM UNITY SNAPSHOT generation="
                    + generation
                    + " epoch="
                    + epoch
                    + " revision="
                    + revision
                    + " cells="
                    + s.cell_count
                    + " hash="
                    + s.canonical_hash
                    + " terrain_batches="
                    + batches
                    + " geometry_cache_bytes="
                    + cacheBytes
            );
        }

        void TimedAccept(BomSession client)
        {
            PresentationHadTopology = PresentationHadActorChange = false;
            long started = System.Diagnostics.Stopwatch.GetTimestamp(),
                bytes = BomAllocationCounter.Read();
            Accept(client);
            PresentationMilliseconds =
                (System.Diagnostics.Stopwatch.GetTimestamp() - started)
                * 1000.0
                / System.Diagnostics.Stopwatch.Frequency;
            PresentationAllocatedBytes = BomAllocationCounter.Since(bytes);
        }

        void Accept(BomSession client)
        {
            var s = client.Sample;
            if ((s.flags & 6) != 6)
            {
                if ((terrain != null || cellsShown) && (s.flags & 2) == 0)
                    ClearScene();
                return;
            }
            if (s.to_revision != s.revision || s.effective_tick > s.presentation_tick + 0.00001)
                throw new InvalidOperationException(
                    "Native topology is not due at this presentation tick"
                );
            if (
                generation != s.connection_generation
                || epoch != s.epoch
                || revision != s.revision
                || ((s.transaction_flags & 1) != 0 && s.transaction_id != acceptedTopology)
            )
            {
                PresentationHadTopology = true;
                bool newSession = generation != s.connection_generation || epoch != s.epoch;
                if (!ClippedSourceArt)
                {
                    // G2: persistent bodies and chunks; only touched chunks rebuild, and an epoch with unchanged cells
                    // rebuilds nothing. Actors are returned only for a new session/epoch, as the old swap did then.
                    if (newSession)
                        ReturnActors();
                    cellPresenter ??= new BomCellPresenter(transform, Material, BomCellPresenter.G1);
                    cellPresenter.Apply(client, VisualRegistry, bodies);
                    cellsShown = true;
                    if (newSession)
                        ConfigureCamera(client);
                    AcceptedTopology(s, newSession, cellPresenter.LastChunks, cellPresenter.ArenaBytes);
                }
                else
                {
                if (newSession)
                    cellGeometry.Clear();
                var activeCells = new HashSet<ulong>();
                sourcePresentation?.BeforeTopology();
                var batches = new Dictionary<(uint, ulong, uint, ulong), TerrainBatch>();
                var nextFallbacks = new Dictionary<ulong, List<Renderer>>();
                var next = new GameObject("Native geometry " + s.epoch + ":" + s.revision);
                next.SetActive(false);
                var nextBodies = new Dictionary<(uint, ulong), Transform>();
                var nextMeshes = new List<Mesh>();
                void Flush(TerrainBatch batch)
                {
                    var obj = Visual(
                        "Terrain batch",
                        batch.Body,
                        batch.Upload(),
                        batch.Color,
                        nextMeshes
                    );
                    if (!nextFallbacks.TryGetValue(batch.SourceId, out var renderers))
                    {
                        renderers = new List<Renderer>();
                        nextFallbacks.Add(batch.SourceId, renderers);
                    }
                    renderers.Add(obj.GetComponent<MeshRenderer>());
                }
                try
                {
                    for (int i = 0; i < s.cell_count; i++)
                    {
                        var cell = client.Cells[i];
                        if (
                            cell.vertex_count < 3
                            || cell.vertex_start + cell.vertex_count > s.vertex_count
                        )
                            throw new InvalidOperationException("Cell outline out of bounds");
                        var key = (cell.pose_kind, cell.pose_kind == 1 ? cell.id : cell.piece_id);
                        if (!nextBodies.TryGetValue(key, out var body))
                        {
                            body = new GameObject("Body " + key).transform;
                            body.SetParent(next.transform, false);
                            body.position = new Vector3(cell.pivot_x, cell.pivot_y, 0);
                            nextBodies.Add(key, body);
                        }

                        ulong sourceId = 0;
                        float depthLo = -.3f,
                            depthHi = .3f;
                        if (client.Catalog.binding_count == s.cell_count)
                        {
                            var binding = client.CellBindings[i];
                            sourceId = binding.source_identity;
                            if (binding.cell_id != cell.id)
                                throw new InvalidOperationException(
                                    "Native source binding order differs from cell array"
                                );
                            if (client.Sources.TryGetValue(binding.source_identity, out var source))
                            {
                                depthLo = source.Binding.depth_lo;
                                depthHi = source.Binding.depth_hi;
                            }
                        }
                        activeCells.Add(cell.id);
                        if (!cellGeometry.TryGetValue(cell.id, out var geometry))
                        {
                            var outline = new Vector2[cell.vertex_count];
                            for (uint j = 0; j < cell.vertex_count; j++)
                            {
                                var v = client.Vertices[cell.vertex_start + j];
                                outline[j] = new Vector2(v.x - cell.rest_x, v.y - cell.rest_y);
                            }
                            geometry = BomExtrusion.BuildData(
                                outline,
                                depthHi - depthLo,
                                new Vector2(cell.rest_x, cell.rest_y),
                                (depthLo + depthHi) / 2
                            );
                            cellGeometry.Add(cell.id, geometry);
                        }
                        var batchKey = (key.Item1, key.Item2, cell.color_rgba, sourceId);
                        if (
                            !batches.TryGetValue(batchKey, out var batch)
                            || batch.Vertices.Count + geometry.Vertices.Length > 50000
                        )
                        {
                            if (batch != null)
                                Flush(batch);
                            batch = new TerrainBatch
                            {
                                Body = body,
                                Color = cell.color_rgba,
                                SourceId = sourceId,
                            };
                            batches[batchKey] = batch;
                        }
                        batch.Add(
                            geometry,
                            new Vector2(cell.rest_x - cell.pivot_x, cell.rest_y - cell.pivot_y)
                        );
                    }
                    foreach (var batch in batches.Values)
                        Flush(batch);
                }
                catch
                {
                    Destroy(next);
                    foreach (var mesh in nextMeshes)
                        Destroy(mesh);
                    throw;
                }
                var obsolete = new List<ulong>();
                long cacheBytes = 0;
                foreach (var pair in cellGeometry)
                {
                    if (!activeCells.Contains(pair.Key))
                        obsolete.Add(pair.Key);
                    else
                        cacheBytes += pair.Value.Bytes;
                }
                foreach (ulong id in obsolete)
                    cellGeometry.Remove(id);
                if (cacheBytes > 256L * 1024 * 1024)
                    throw new InvalidOperationException(
                        "Fallback geometry cache exceeds its explicit 256 MiB budget"
                    );
                if (newSession)
                    ConfigureCamera(client);
                ClearScene(true);
                terrain = next;
                meshes.AddRange(nextMeshes);
                foreach (var pair in nextBodies)
                    bodies.Add(pair.Key, pair.Value);
                terrain.SetActive(true);
                sourcePresentation?.SetFallbackBytes(cacheBytes * 3);
                sourcePresentation?.SetTopology(client, bodies, nextFallbacks);
                AcceptedTopology(s, newSession, nextMeshes.Count, cacheBytes);
                }
            }
            var seen = seenActors;
            seen.Clear();
            framePlayers.Clear();
            for (int i = 0; i < s.pose_count; i++)
            {
                var pose = client.Poses[i];
                var key = (pose.kind, pose.id);
                if (pose.kind == 2)
                    framePlayers.Add(pose);
                Transform body;
                if (pose.kind < 2)
                {
                    if (!bodies.TryGetValue(key, out body))
                        continue;
                }
                else
                {
                    seen.Add(key);
                    if (!actors.TryGetValue(key, out var actor))
                    {
                        PresentationHadActorChange = true;
                        bool item = pose.kind == BomItemLook.PoseKind;
                        var prefab =
                            pose.kind == 2 ? PlayerPrefab
                            : item ? BomItemLook.Prefab(BomItemLook.Kind(pose))
                            : BombPrefab;
                        if (item)
                            items.Appeared(pose, prefab);
                        if (prefab != null)
                        {
                            actor = actorPool.Rent(prefab);
                            actor.name = (pose.kind == 2 ? "Player " : item ? "Item " : "Bomb ") + pose.id;
                            var properties = new MaterialPropertyBlock();
                            Color color =
                                pose.kind == 2
                                    ? new Color32(66, 174, 231, 255)
                                    : new Color32(234, 72, 72, 255);
                            properties.SetColor("_BaseColor", color);
                            actor.GetComponent<MeshRenderer>().SetPropertyBlock(properties, 0);
                            if (pose.kind == 2)
                            {
                                if (!actor.TryGetComponent<BomPlayerLook>(out var look))
                                    look = actor.AddComponent<BomPlayerLook>();
                                look.Configure((int)pose.id);
                                if (!actor.TryGetComponent<BomLimbLoss>(out var limbLoss))
                                    limbLoss = actor.AddComponent<BomLimbLoss>();
                                limbLoss.ResetBody();
                                if (!actor.TryGetComponent<BomItemGlow>(out var glow))
                                    glow = actor.AddComponent<BomItemGlow>();
                                glow.ResetGlow();
                            }
                        }
                        else
                        {
                            actor = Visual(
                                (pose.kind == 2 ? "Player " : "Bomb ") + pose.id,
                                null,
                                BomExtrusion.Build(
                                    BomUnityCoordinates.ActorOutline(pose.kind == 2, shapeInfo)
                                ),
                                pose.kind == 2 ? 0xffe7ae42u
                                : item ? 0xff28c8ffu
                                : 0xff4848eau,
                                meshes
                            );
                            actor.AddComponent<BomActorView>();
                        }
                        actors.Add(key, actor);
                    }
                    body = actor.transform;
                }
                Vector2 correction =
                    pose.kind == 2 && pose.id == s.local_player_id && s.owner_prediction_status == 1
                        ? new Vector2(
                            client.Prediction.visual_offset_x,
                            client.Prediction.visual_offset_y
                        )
                        : Vector2.zero;
                if (body.TryGetComponent<BomActorView>(out var actorView))
                {
                    actorView.Apply(pose, correction);
                    if (pose.kind == 2 && actorView.Running)
                        RunningPresentationFrames++;
                }
                else
                    body.SetPositionAndRotation(
                        new Vector3(pose.x, pose.y, 0),
                        BomUnityCoordinates.Rotation(pose.angle)
                    );
                if (pose.kind == 2)
                    deaths.Remember(
                        (uint)pose.id,
                        actorView != null ? actorView.VisualPosition : body.position
                    );
                if (smoke && smokeActive && pose.kind == 2 && pose.id == s.local_player_id)
                {
                    if (
                        hasLocal
                        && metricGeneration == s.connection_generation
                        && metricEpoch == s.epoch
                    )
                    {
                        traveled += Mathf.Abs(pose.x - lastLocal.x);
                        if (smokeElapsed >= 3 && smokeElapsed <= 5)
                            jumpRise += Mathf.Max(0, pose.y - lastLocal.y);
                    }
                    lastLocal = new Vector2(pose.x, pose.y);
                    hasLocal = true;
                    metricGeneration = s.connection_generation;
                    metricEpoch = s.epoch;
                }
            }
            var gone = goneActors;
            gone.Clear();
            foreach (var pair in actors)
                if (!seen.Contains(pair.Key))
                    gone.Add(pair.Key);
            foreach (var key in gone)
            {
                PresentationHadActorChange = true;
                if (key.Item1 == BomItemLook.PoseKind && actors[key].TryGetComponent<BomActorView>(out var lastItem))
                    items.Vanished(lastItem.Pose, framePlayers, shapeInfo, client.Round, lastItem.VisualPosition);
                var filter = actors[key].GetComponent<MeshFilter>();
                if (meshes.Remove(filter.sharedMesh))
                    Destroy(filter.sharedMesh);
                if (!actorPool.Return(actors[key]))
                    Destroy(actors[key]);
                actors.Remove(key);
            }
            if (cameraRig != null)
            {
                cameraRig.Targets.Clear();
                foreach (var pair in actors)
                    if (pair.Key.Item1 == 2)
                        cameraRig.Targets.Add(
                            pair.Value.TryGetComponent<BomActorView>(out var look)
                                ? (Vector2)look.VisualPosition
                                : (Vector2)pair.Value.transform.position
                        );
            }
            BomGameAudio.RoundState(client.Round.flags, client.Round.round_id, client.Round.state);
            ObserveRoster(client);
            for (int i = 0; i < s.event_count; i++)
            {
                var e = client.Events[i];
                if (e.tick > s.presentation_tick + 0.00001)
                    throw new InvalidOperationException("Native event is ahead of presentation");
                if (e.id <= lastEvent)
                    continue;
                lastEvent = e.id;
                events++;
                if (e.radius > 0)
                {
                    float front = -.5f;
                    foreach (var source in client.Sources.Values)
                        front = Mathf.Min(front, source.Binding.depth_lo - .1f);
                    var center = new Vector3(e.x, e.y, front);
                    grazes.Explosion(e.tick, new Vector2(e.x, e.y));
                    BomGameAudio.BombExplosion(center);
                    if (BlastPrefab != null)
                    {
                        BomAuthorityAudit.Validate(BlastPrefab);
                        var effect = Instantiate(BlastPrefab, EffectsRoot());
                        BomAuthorityAudit.Validate(effect);
                        effect.name = "Native blast " + e.id;
                        effect
                            .GetComponent<BomLegacyBlastView>()
                            .Show(
                                center,
                                client.Round.mode == 1 ? client.Round.lethal_radius : e.radius
                            );
                        if (
                            client.Round.mode == 1
                            && client.Round.graze_radius > client.Round.lethal_radius
                        )
                            BomGrazeRing.Show(
                                EffectsRoot(),
                                BlastPrefab.GetComponent<LineRenderer>(),
                                center,
                                client.Round.graze_radius
                            );
                    }
                    else
                    {
                        var effect = new GameObject("Native explosion " + e.id);
                        effect.transform.SetParent(EffectsRoot(), false);
                        effect.AddComponent<BomExplosionView>().Show(Material, center, e.radius);
                    }
                    ExplosionVisuals++;
                    cameraRig?.Shake(
                        new Vector2(e.x, e.y),
                        e.radius,
                        TryLocalVisualPosition(out var localAt),
                        localAt
                    );
                }
                Debug.Log(
                    "BOM UNITY EVENT id="
                        + e.id
                        + " tick="
                        + e.tick
                        + " presentation="
                        + s.presentation_tick
                );
            }
            PresentDeaths(client);
            PresentLimbLoss(client);
            PresentItemEffects(client, s.presentation_tick);
        }

        // E1-N4: Darryn's item glow from the copied round roster. Slot is the pose id (see PresentLimbLoss).
        void PresentItemEffects(BomSession client, double tick)
        {
            var round = client.Round;
            var players = client.RoundPlayers;
            int playerCount = Mathf.Min((int)round.player_count, players.Length);
            foreach (var pair in actors)
            {
                if (pair.Key.Item1 != 2 || !pair.Value.TryGetComponent<BomItemGlow>(out var glow))
                    continue;
                uint effects = 0;
                ulong invincibleEnd = 0,
                    speedEnd = 0;
                for (int i = 0; i < playerCount; i++)
                    if (players[i].slot == pair.Key.Item2)
                    {
                        effects = players[i].effects;
                        invincibleEnd = players[i].invincible_end_tick;
                        speedEnd = players[i].speed_end_tick;
                        break;
                    }
                var tint = pair.Value.TryGetComponent<BomPlayerLook>(out var look)
                    ? look.Color
                    : BomPlayerLook.SlotColor(0);
                glow.Apply(pair.Key.Item2, effects, invincibleEnd, speedEnd, tick, tint);
            }
        }

        // Copied native roster -> presentation queues, before this sample's events are shown. A death is the
        // roster's alive 1 -> 0 (Blast or Bounds, never Disconnect), not a pose vanishing; a graze increase waits
        // for its explosion event. Slot is the native server client index, the same number as the pose id.
        void ObserveRoster(BomSession client)
        {
            var round = client.Round;
            var players = client.RoundPlayers;
            int playerCount = Mathf.Min((int)round.player_count, players.Length);
            double now = Time.unscaledTimeAsDouble;
            for (int i = 0; i < playerCount; i++)
            {
                var p = players[i];
                grazes.Observe(
                    p.slot,
                    round.round_id,
                    p.session_id,
                    p.generation,
                    p.graze_count,
                    round.tick,
                    now
                );
                string skipped = deaths.Observe(
                    p.slot,
                    round.round_id,
                    p.session_id,
                    p.generation,
                    p.alive != 0,
                    p.death,
                    p.death_tick,
                    now
                );
                if (skipped.Length > 0)
                    Debug.Log(
                        "BOM UNITY NOBURST player="
                            + p.slot
                            + " round="
                            + round.round_id
                            + " death="
                            + p.death
                            + " reason="
                            + skipped
                    );
            }
        }

        void PresentDeaths(BomSession client)
        {
            deathsDue.Clear();
            deaths.Collect(client.Sample.presentation_tick, Time.unscaledTimeAsDouble, deathsDue);
            foreach (var burst in deathsDue)
            {
                BomDeathBurst.Spawn(
                    EffectsRoot(),
                    Material,
                    burst.Position,
                    BomPlayerLook.SlotColor((int)burst.Slot),
                    burst.Position - Vector3.up
                );
                Debug.Log(
                    "BOM UNITY BURST player="
                        + burst.Slot
                        + " round="
                        + burst.Round
                        + " death="
                        + burst.Death
                        + " session="
                        + burst.Session
                        + " generation="
                        + burst.Generation
                );
            }
        }

        // Limb loss from the copied native graze counts (N3). A player pose id is the native server client
        // index, and BomRoundPlayer.slot is that same index (no offset): in Rounds the observer holds slot 0,
        // so the two players are slots/pose ids 1 and 2 (guest logs local=2 and slot=2). Actors are recycled on
        // every topology revision, so the already-shown count is presented first (a silent rebuild when the
        // actor is new) and each released increase after it, with its own blast centre.
        void PresentLimbLoss(BomSession client)
        {
            var round = client.Round;
            var players = client.RoundPlayers;
            int playerCount = Mathf.Min((int)round.player_count, players.Length);
            double now = Time.unscaledTimeAsDouble;
            foreach (var pair in actors)
            {
                if (pair.Key.Item1 != 2 || !pair.Value.TryGetComponent<BomLimbLoss>(out var limbLoss))
                    continue;
                ulong session = 0,
                    playerGeneration = 0;
                for (int i = 0; i < playerCount; i++)
                    if (players[i].slot == pair.Key.Item2)
                    {
                        session = players[i].session_id;
                        playerGeneration = players[i].generation;
                        break;
                    }
                var tint = pair.Value.TryGetComponent<BomPlayerLook>(out var look)
                    ? look.Color
                    : BomPlayerLook.SlotColor(0);
                grazesDue.Clear();
                uint settled = grazes.Collect((uint)pair.Key.Item2, now, grazesDue);
                var at = (pair.Key.Item2, session, playerGeneration, tint);
                PresentGraze(round, limbLoss, at, settled, default, false);
                foreach (var release in grazesDue)
                    PresentGraze(round, limbLoss, at, release.Count, release.Blast, release.HasBlast);
            }
        }

        void PresentGraze(
            BomRoundInfo round,
            BomLimbLoss limbLoss,
            (ulong, ulong, ulong, Color) who,
            uint count,
            Vector2 blast,
            bool hasBlast
        )
        {
            var (player, session, playerGeneration, tint) = who;
            uint before = limbLoss.ShownCount;
            int presented = limbLoss.Present(
                round.round_id,
                session,
                playerGeneration,
                count,
                Material,
                EffectsRoot(),
                tint,
                blast,
                hasBlast
            );
            if (presented > 0 || before != limbLoss.ShownCount)
                Debug.Log(
                    "BOM UNITY GRAZE player="
                        + player
                        + " round="
                        + round.round_id
                        + " session="
                        + session
                        + " count="
                        + count
                        + " presented="
                        + presented
                        + " limbs_lost="
                        + limbLoss.LostLimbs
                        + "/"
                        + limbLoss.LimbCount
                        + " blast="
                        + (hasBlast ? blast.x + "," + blast.y : "none")
                );
        }

        void OnGUI()
        {
            if (!DiagnosticOverlay)
                return;
            string movement =
                session == null ? ""
                : session.Prediction.status == 1 ? "Predicted movement"
                : session.Prediction.status == 2 ? "Server view (collision history unavailable)"
                : session.Prediction.status == 0 ? "Prediction off"
                : "Synchronizing movement";
            GUI.Box(
                new Rect(12, 12, 700, 106),
                "BOM native client — A/D move · Space jump · Click blast\n"
                    + identity
                    + "\n"
                    + (
                        session != null
                            ? "Epoch "
                                + epoch
                                + " · revision "
                                + revision
                                + " · events "
                                + events
                                + " "
                                + session.Error
                            : failure
                    )
                    + "\n"
                    + movement
            );
        }
    }
}
