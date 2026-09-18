using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

public static class VerifySideArena
{
    public static string Main()
    {
        if (!EditorApplication.isPlaying) throw new Exception("Enter Play mode first.");
        var player = GameObject.Find("Player");
        var controller = player.GetComponent<CharacterController>();
        var movement = player.GetComponent<ArenaPlayerController>();
        var update = typeof(ArenaPlayerController).GetMethod("Update", BindingFlags.Instance | BindingFlags.NonPublic);
        var inputBehavior = InputSystem.settings.editorInputBehaviorInPlayMode;
        var inputBackground = InputSystem.settings.backgroundBehavior;
        InputSystem.settings.editorInputBehaviorInPlayMode = InputSettings.EditorInputBehaviorInPlayMode.AllDeviceInputAlwaysGoesToGameView;
        InputSystem.settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
        var keyboard = InputSystem.AddDevice<Keyboard>();
        var spawn = player.transform.position;
        var cameraPosition = Camera.main.transform.position;
        var cameraRotation = Camera.main.transform.rotation;
        movement.enabled = false;
        try
        {
            controller.enabled = false;
            player.transform.position = new Vector3(0f, 6.85f, 0f);
            controller.enabled = true;
            Physics.SyncTransforms();
            controller.Move(Vector3.down * 0.15f);
            if (!controller.isGrounded) throw new Exception("Player is not grounded on the bottom floor.");
            float ground = player.transform.position.y;
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.D));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            update.Invoke(movement, null);
            if (player.transform.position.x <= 0f || Mathf.Abs(player.transform.position.z) > 0.001f)
                throw new Exception("Horizontal movement failed or left the side view plane.");
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.Space));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            update.Invoke(movement, null);
            if (player.transform.position.y <= ground) throw new Exception("Space did not initiate a jump.");
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            float peak = player.transform.position.y;
            bool landed = false;
            for (int i = 0; i < 10000; i++)
            {
                update.Invoke(movement, null);
                peak = Mathf.Max(peak, player.transform.position.y);
                if (controller.isGrounded) { landed = true; break; }
            }
            if (!landed || peak - ground < 1.8f || peak + 0.8f >= 12f)
                throw new Exception("Jump arc / landing / ceiling clearance failed. Peak=" + peak);
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.Space));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            update.Invoke(movement, null);
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            for (int i = 0; i < 5; i++) update.Invoke(movement, null);
            float before = player.transform.position.y;
            float velocity = (float)typeof(ArenaPlayerController).GetField("verticalSpeed", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(movement);
            InputSystem.QueueStateEvent(keyboard, new KeyboardState(Key.Space));
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            update.Invoke(movement, null);
            float afterVelocity = (float)typeof(ArenaPlayerController).GetField("verticalSpeed", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(movement);
            if (afterVelocity > velocity) throw new Exception("An airborne press caused a second jump.");
            InputSystem.QueueStateEvent(keyboard, new KeyboardState());
            typeof(InputSystem).GetMethod("Update", BindingFlags.Static | BindingFlags.NonPublic, null, new[] { typeof(InputUpdateType) }, null).Invoke(null, new object[] { InputUpdateType.Dynamic });
            foreach (float direction in new[] { -1f, 1f })
            {
                controller.enabled = false;
                player.transform.position = new Vector3(0f, ground, 0f);
                controller.enabled = true;
                Physics.SyncTransforms();
                for (int i = 0; i < 300; i++) controller.Move(new Vector3(direction * 0.2f, -0.02f, 0f));
                if (Mathf.Abs(player.transform.position.x) > 9.61f || Mathf.Abs(player.transform.position.x) < 9.4f)
                    throw new Exception("Side wall collision failed.");
            }
            if (Camera.main.transform.position != cameraPosition || Quaternion.Angle(Camera.main.transform.rotation, cameraRotation) > 0.01f)
                throw new Exception("Camera did not stay fixed.");
            var upper = GameObject.Find("Upper Boundary");
            if (upper == null || upper.GetComponent<Renderer>().enabled || !upper.GetComponent<Collider>().enabled)
                throw new Exception("Upper boundary must be invisible and solid.");
            controller.enabled = false;
            player.transform.position = new Vector3(0f, ground, 0f);
            controller.enabled = true;
            Physics.SyncTransforms();
            for (int i = 0; i < 300; i++) controller.Move(Vector3.up * 0.2f);
            if (player.transform.position.y > 11.25f || player.transform.position.y < 11f)
                throw new Exception("Invisible upper boundary did not prevent escaping.");
            var floor = GameObject.Find("Arena/Floor").GetComponent<Collider>();
            if (Mathf.Abs(floor.bounds.max.y - 6f) > 0.001f || floor.bounds.min.y > 0f)
                throw new Exception("Solid ground does not fill the lower half.");
            return "PASS: left/right movement stays in the XY plane; bottom floor grounds player; Space jumps and lands; no double jump; jump peak "
                + (peak - ground).ToString("F2") + " units leaves ample ceiling clearance; both side walls block movement; camera stays fixed; solid ground fills lower half; invisible upper boundary blocks escape.";
        }
        finally
        {
            InputSystem.RemoveDevice(keyboard);
            InputSystem.settings.editorInputBehaviorInPlayMode = inputBehavior;
            InputSystem.settings.backgroundBehavior = inputBackground;
            controller.enabled = false;
            player.transform.position = spawn;
            controller.enabled = true;
            movement.enabled = true;
        }
    }
}
