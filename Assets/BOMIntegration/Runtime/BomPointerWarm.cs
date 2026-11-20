using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace Bom.Unity
{
    // G2b: the first mouse click of a process cost 25-30 ms in UI Toolkit's first pointer dispatch
    // (PreLateUpdate.UIElementsUpdatePanels 24.8 ms, Input System 3 ms; measured with --bom-hitch-trace on Yard).
    // At join, one synthetic left press/release is queued on the real mouse far outside the window and the real pointer
    // position is restored in the same update. The blast callback ignores clicks while Swallowing, so nothing is
    // enqueued or sent.
    public static class BomPointerWarm
    {
        static bool done;
        static int until = -1;

        // True for the frames in which the synthetic click is processed (the next input update and UI panel update).
        public static bool Swallowing => Time.frameCount <= until;

        public static void Run()
        {
            var mouse = Mouse.current;
            if (done || mouse == null)
                return;
            done = true;
            until = Time.frameCount + 2;
            Vector2 real = mouse.position.ReadValue();
            var away = new Vector2(-4096, -4096);
            InputSystem.QueueStateEvent(mouse, new MouseState { position = away }.WithButton(MouseButton.Left, true));
            InputSystem.QueueStateEvent(mouse, new MouseState { position = away });
            InputSystem.QueueStateEvent(mouse, new MouseState { position = real });
            Debug.Log("BOM WARM pointer");
        }
    }
}
