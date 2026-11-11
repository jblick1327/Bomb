using UnityEngine;

namespace Bom.Unity
{
    // Darryn's MenuCursor hides the system pointer every frame (Update, order -50) and draws its own "P1" ring only
    // while an ArenaSession menu is open. The network scenes have no ArenaSession, so the pointer was simply gone,
    // which made the connection menu and the host's click-to-blast hard to use. LateUpdate runs after his Update, so
    // the operating system pointer wins here. Presentation only: it never touches input to the native client.
    public sealed class BomCursorGuard : MonoBehaviour
    {
        void LateUpdate()
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }

        void OnDisable()
        {
            // Leave the pointer to MenuCursor again if this scene's HUD goes away (for example a scene change).
            Cursor.visible = false;
        }
    }
}
