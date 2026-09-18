using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

public static class VerifyBombs
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Run bomb verification in Play mode.");
        var dropper = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var session = UnityEngine.Object.FindFirstObjectByType<ArenaSession>();
        var player = UnityEngine.Object.FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);
        var controller = player.GetComponent<CharacterController>();
        var settings = new SerializedObject(dropper);
        var inputBehavior = InputSystem.settings.editorInputBehaviorInPlayMode;
        var inputBackground = InputSystem.settings.backgroundBehavior;
        InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        var keyboard = InputSystem.AddDevice<Keyboard>();
        var previousSimulation = Physics.simulationMode;
        var spawn = player.transform.position;
        bool wasActive = player.gameObject.activeSelf;
        bool wasEnabled = player.enabled;
        var randomState = UnityEngine.Random.state;
        int shape = settings.FindProperty("craterShape").enumValueIndex;
        float radius = settings.FindProperty("craterRadius").floatValue;
        Vector2 scale = settings.FindProperty("craterShapeScale").vector2Value;
        float rotation = settings.FindProperty("craterRotation").floatValue;
        float lethal = settings.FindProperty("lethalRadius").floatValue;
        try
        {
            Physics.simulationMode = SimulationMode.Script;
            session.RestartRound();
            player.enabled = false;
            player.gameObject.SetActive(true);
            MovePlayer(player, new Vector3(7f, 6.85f, 0f));
            ground.ResetGround();
            SetCrater(settings, CraterShape.Circle, 1.6f, Vector2.one);
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.B));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            typeof(BombDropper).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(dropper, null);
            var bombs = UnityEngine.Object.FindObjectsByType<FallingBomb>(FindObjectsSortMode.None);
            Require(bombs.Length == 1, "B must drop exactly one bomb.");
            var bomb = bombs[0];
            Require(bomb.transform.position.x >= -9f && bomb.transform.position.x <= 9f && bomb.transform.position.y > 12f,
                "Bomb spawn must be above the box within the horizontal range.");
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            bomb.transform.position = new Vector3(-6f, 14f, 0f);
            bomb.GetComponent<Rigidbody>().position = bomb.transform.position;
            Physics.SyncTransforms();
            var exploded = typeof(FallingBomb).GetField("exploded", BindingFlags.Instance | BindingFlags.NonPublic);
            for (int i = 0; i < 300 && !(bool)exploded.GetValue(bomb); i++)
            {
                bomb.SendMessage("FixedUpdate");
                Physics.Simulate(0.02f);
            }
            Require((bool)exploded.GetValue(bomb), "Falling bomb did not explode on impact.");
            Require(!ground.ContainsSolid(new Vector2(-6f, 5.8f)), "Impact did not remove the crater from the ground. Bomb=" + bomb.GetComponent<Rigidbody>().position);
            Require(ground.ContainsSolid(new Vector2(-3f, 5.8f)), "Impact removed ground beyond its radius.");
            Require(player.gameObject.activeSelf, "Player outside blast radius was killed.");
            UnityEngine.Object.DestroyImmediate(bomb.gameObject);
            Require(Physics.Raycast(new Vector3(-6f, 10f, 0f), Vector3.down, out var craterHit, 20f)
                && craterHit.collider == ground.GetComponent<MeshCollider>() && craterHit.point.y < 4.8f,
                "Crater collision does not match the visible hole.");

            ground.Carve(dropper.CreateCraterOutline(new Vector2(-5f, 5.5f)));
            Require(!ground.ContainsSolid(new Vector2(-6f, 5.8f)) && !ground.ContainsSolid(new Vector2(-5f, 4.5f)),
                "Overlapping craters must preserve the union of removed terrain.");
            Require(ground.ContainsSolid(new Vector2(4f, 2f)), "Overlapping craters removed unrelated ground.");

            ground.ResetGround();
            ground.Carve(dropper.CreateCraterOutline(new Vector2(0f, 6f)));
            MovePlayer(player, new Vector3(0f, 6.85f, 0f));
            for (int i = 0; i < 150; i++) controller.Move(Vector3.down * 0.05f);
            Require(controller.isGrounded && player.transform.position.y < 5.6f && player.transform.position.y > 4.9f,
                "Player must fall into and stand on the crater floor. Position=" + player.transform.position);

            ground.ResetGround();
            SetCrater(settings, CraterShape.Ellipse, 1f, new Vector2(2f, 0.5f));
            ground.Carve(dropper.CreateCraterOutline(new Vector2(0f, 6f)));
            Require(!ground.ContainsSolid(new Vector2(1.5f, 5.9f)) && ground.ContainsSolid(new Vector2(0f, 5.3f)),
                "Serialized ellipse size must change crater width and depth.");
            ground.ResetGround();
            SetCrater(settings, CraterShape.Box, 1f, Vector2.one);
            ground.Carve(dropper.CreateCraterOutline(new Vector2(0f, 6f)));
            Require(!ground.ContainsSolid(new Vector2(0.9f, 5.1f)) && ground.ContainsSolid(new Vector2(1.1f, 5.1f)),
                "Serialized box shape must produce square crater edges.");

            var wall = GameObject.Find("Right Wall").GetComponent<Collider>();
            var wallBounds = wall.bounds;
            dropper.Explode(new Vector2(10f, 6f));
            Require(wall.enabled && wall.bounds == wallBounds
                && Physics.Raycast(new Vector3(8f, 7f, 0f), Vector3.right, out var wallHit, 5f) && wallHit.collider == wall,
                "Bombs must not alter wall geometry or collision.");

            ground.ResetGround();
            MovePlayer(player, new Vector3(0f, 6.85f, 0f));
            SetCrater(settings, CraterShape.Circle, 1.6f, Vector2.one);
            settings.FindProperty("lethalRadius").floatValue = 2.2f;
            settings.ApplyModifiedPropertiesWithoutUndo();
            dropper.Explode(new Vector2(0f, 6f));
            Require(!player.gameObject.activeSelf, "Player inside lethal radius survived.");
            Require(session.State == ArenaRoundState.Dead && dropper.DropBomb() == null, "Death must stop bomb input.");
            session.RestartRound();
            player.enabled = false;
            MovePlayer(player, new Vector3(0f, 6.85f, 0f));
            session.RestartRound();
            var direct = dropper.DropBomb();
            direct.transform.position = new Vector3(0f, 14f, 0f);
            direct.GetComponent<Rigidbody>().position = direct.transform.position;
            Physics.SyncTransforms();
            for (int i = 0; i < 300 && !(bool)exploded.GetValue(direct); i++)
            {
                direct.SendMessage("FixedUpdate");
                Physics.Simulate(0.02f);
            }
            Require((bool)exploded.GetValue(direct) && !player.gameObject.activeSelf, "A bomb falling onto the player must explode and kill them.");

            for (int i = 0; i < 12; i++)
                ground.Carve(dropper.CreateCraterOutline(new Vector2(-8f + i * 1.4f, 5.5f - (i % 3) * 0.35f)));
            Require(ground.ContainsSolid(new Vector2(0f, 0f)), "Repeated overlapping craters damaged distant terrain.");
            return "PASS: B spawns a bomb above the box; bomb passes invisible roof and explodes on ground; circular crater updates mesh and collision; player falls into crater; overlapping cuts and ellipse/box settings work; walls remain solid; outside radius survives; inside radius and direct bomb hit kill player; repeated craters remain valid.";
        }
        finally
        {
            Physics.simulationMode = previousSimulation;
            InputSystem.RemoveDevice(keyboard);
            InputSystem.settings.editorInputBehaviorInPlayMode = inputBehavior;
            InputSystem.settings.backgroundBehavior = inputBackground;
            UnityEngine.Random.state = randomState;
            settings.Update();
            settings.FindProperty("craterShape").enumValueIndex = shape;
            settings.FindProperty("craterRadius").floatValue = radius;
            settings.FindProperty("craterShapeScale").vector2Value = scale;
            settings.FindProperty("craterRotation").floatValue = rotation;
            settings.FindProperty("lethalRadius").floatValue = lethal;
            settings.ApplyModifiedPropertiesWithoutUndo();
            session.RestartRound();
            foreach (var bomb in UnityEngine.Object.FindObjectsByType<FallingBomb>(FindObjectsSortMode.None))
                UnityEngine.Object.DestroyImmediate(bomb.gameObject);
            foreach (var blast in UnityEngine.Object.FindObjectsByType<BombBlastVisual>(FindObjectsSortMode.None))
                UnityEngine.Object.DestroyImmediate(blast.gameObject);
            player.gameObject.SetActive(true);
            MovePlayer(player, spawn);
            player.enabled = wasEnabled;
            player.gameObject.SetActive(wasActive);
        }
    }

    private static void SetCrater(SerializedObject settings, CraterShape shape, float radius, Vector2 scale)
    {
        settings.Update();
        settings.FindProperty("craterShape").enumValueIndex = (int)shape;
        settings.FindProperty("craterRadius").floatValue = radius;
        settings.FindProperty("craterShapeScale").vector2Value = scale;
        settings.FindProperty("craterRotation").floatValue = 0f;
        settings.ApplyModifiedPropertiesWithoutUndo();
    }

    private static void MovePlayer(ArenaPlayerController player, Vector3 position)
    {
        var controller = player.GetComponent<CharacterController>();
        controller.enabled = false;
        player.transform.position = position;
        controller.enabled = true;
        Physics.SyncTransforms();
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
