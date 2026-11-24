using UnityEngine;
using UnityEngine.InputSystem;

namespace Bom.Unity
{
    // The Input System's default background behaviour (ResetAndDisableNonBackgroundDevices) soft-resets the keyboard and mouse
    // from inside Application.focusChanged, which Windows delivers from its message pump. On 2026-11-11 that path crashed a guest
    // player (InputManager.OnFocusChanged -> ResetDevice -> NativeArray Temp -> MemClear; see ALPHA-SYNC Findings). While a network
    // HUD is alive this sets IgnoreFocus, so that path returns early, and resets the keyboard and mouse itself on the next frame
    // (inside the player loop) after any focus change, so a key released while the other window had focus does not stay held.
    // The previous setting comes back in OnDisable, so Darryn's own scenes keep Unity's default. Input handling only.
    // Launch option --bom-focus-default leaves Unity's default in place (for A/B checks).
    public sealed class BomFocusGuard : MonoBehaviour
    {
        InputSettings.BackgroundBehavior previous;
        bool applied, resetPending;

        void OnEnable()
        {
            var settings = InputSystem.settings;
            if (settings == null)
                return;
            if (System.Array.IndexOf(System.Environment.GetCommandLineArgs(), "--bom-focus-default") >= 0)
            {
                Debug.Log($"BOM UNITY FOCUS off by --bom-focus-default; background={settings.backgroundBehavior}");
                enabled = false;
                return;
            }
            previous = settings.backgroundBehavior;
            settings.backgroundBehavior = InputSettings.BackgroundBehavior.IgnoreFocus;
            applied = true;
            // A window that was already in the background had its keyboard/mouse disabled by the old behaviour, and with
            // IgnoreFocus nothing would re-enable them, so the next Update re-enables or resets them.
            resetPending = true;
            Debug.Log($"BOM UNITY FOCUS background={settings.backgroundBehavior} previous={previous}");
        }

        void OnApplicationFocus(bool focused) => resetPending = true;

        void Update()
        {
            if (!resetPending)
                return;
            resetPending = false;
            bool keyboard = Restore(Keyboard.current),
                mouse = Restore(Mouse.current);
            Debug.Log($"BOM UNITY FOCUS reset focused={Application.isFocused} reenabled_keyboard={keyboard} reenabled_mouse={mouse}");
        }

        static bool Restore(InputDevice device)
        {
            if (device == null)
                return false;
            if (!device.enabled)
            {
                InputSystem.EnableDevice(device);
                return true;
            }
            InputSystem.ResetDevice(device);
            return false;
        }

        void OnDisable()
        {
            if (applied && InputSystem.settings != null)
                InputSystem.settings.backgroundBehavior = previous;
            applied = false;
        }
    }
}
