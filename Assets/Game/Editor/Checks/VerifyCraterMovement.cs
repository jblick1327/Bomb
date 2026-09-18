using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

public static class VerifyCraterMovement
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Movement checks require Play mode.");
        var session = UnityEngine.Object.FindFirstObjectByType<ArenaSession>();
        var player = UnityEngine.Object.FindFirstObjectByType<ArenaPlayerController>(FindObjectsInactive.Include);
        var body = player.GetComponent<CharacterController>();
        var ground = UnityEngine.Object.FindFirstObjectByType<DestructibleGround>();
        var bombs = UnityEngine.Object.FindFirstObjectByType<BombDropper>();
        var layout = UnityEngine.Object.FindFirstObjectByType<ArenaLayout>();
        var settings = new SerializedObject(bombs);
        float radius = settings.FindProperty("craterRadius").floatValue;
        int shape = settings.FindProperty("craterShape").enumValueIndex;
        var behavior = InputSystem.settings.editorInputBehaviorInPlayMode;
        var background = InputSystem.settings.backgroundBehavior;
        InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        var keyboard = InputSystem.AddDevice<Keyboard>();
        var update = typeof(ArenaPlayerController).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic);
        var inputUpdate = typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic,
            null, new[] { typeof(InputUpdateType) }, null);
        var velocity = typeof(ArenaPlayerController).GetField("verticalSpeed", BindingFlags.Instance | BindingFlags.NonPublic);
        void Step(params Key[] keys)
        {
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(keys));
            inputUpdate.Invoke(null, new object[] { InputUpdateType.Dynamic });
            update.Invoke(player, null);
        }
        void Place(Vector3 point)
        {
            player.enabled = true;
            player.enabled = false;
            body.enabled = false;
            player.transform.position = point;
            body.enabled = true;
            Physics.SyncTransforms();
        }
        try
        {
            session.RestartRound();
            settings.FindProperty("craterRadius").floatValue = 1.6f;
            settings.FindProperty("craterShape").enumValueIndex = 0;
            settings.ApplyModifiedPropertiesWithoutUndo();
            ground.Carve(bombs.CreateCraterOutline(new Vector2(0f, layout.GroundTop)));
            Place(layout.PlayerSpawn);
            for (int i = 0; i < 150; i++) Step();
            Require(body.isGrounded && player.transform.position.y < layout.GroundTop - 0.5f,
                "Player did not settle inside the crater: " + player.transform.position);
            Step(Key.D, Key.Space);
            for (int i = 0; i < 100; i++) Step(Key.D);
            Require(player.transform.position.x > 2f && player.transform.position.y >= layout.GroundTop + 0.7f,
                "Player cannot jump out of a normal crater: " + player.transform.position);

            Place(layout.PlayerSpawn + Vector3.left * 2.3f);
            for (int i = 0; i < 5; i++) Step();
            bool leftEdge = false;
            for (int i = 0; i < 50; i++)
            {
                Step(Key.D);
                if (!body.isGrounded) { leftEdge = true; break; }
            }
            Require(leftEdge, "Crater edge was never crossed.");
            Step(Key.Space);
            Require((float)velocity.GetValue(player) > 0f, "Coyote jump failed just after leaving the crater edge.");

            ground.ResetGround();
            Place(layout.PlayerSpawn + Vector3.up * 2f);
            bool nearLanding = false;
            for (int i = 0; i < 250; i++)
            {
                Step();
                if (!body.isGrounded && player.transform.position.y < layout.PlayerSpawn.y + 0.15f)
                { nearLanding = true; break; }
            }
            Require(nearLanding, "Could not reach the frame just before landing.");
            Step(Key.Space);
            bool bufferedJump = (float)velocity.GetValue(player) > 0f;
            for (int i = 0; i < 5 && !bufferedJump; i++)
            {
                Step();
                bufferedJump = (float)velocity.GetValue(player) > 0f;
            }
            Require(bufferedJump, "Jump pressed before landing was lost.");
            return "PASS: player settles inside a crater, jumps out, jumps just after stepping off its edge, and buffers a jump pressed before landing.";
        }
        finally
        {
            InputSystem.RemoveDevice(keyboard);
            InputSystem.settings.editorInputBehaviorInPlayMode = behavior;
            InputSystem.settings.backgroundBehavior = background;
            settings.Update();
            settings.FindProperty("craterRadius").floatValue = radius;
            settings.FindProperty("craterShape").enumValueIndex = shape;
            settings.ApplyModifiedPropertiesWithoutUndo();
            session.RestartRound();
            player.enabled = true;
        }
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
