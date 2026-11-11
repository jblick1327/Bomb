using UnityEngine;

namespace Bom.Unity
{
    // Darryn's MenuCursor (a DontDestroyOnLoad object named "Menu Cursor") sets Cursor.visible = false every frame and
    // draws its own "P1" ring only while an ArenaSession menu is open. The network scenes have no ArenaSession, so the
    // pointer was simply gone. Fighting it from LateUpdate flips the pointer twice per frame (visible flicker), so instead
    // this switches his object off for as long as a network HUD is alive and then sets the OS pointer once.
    // It reactivates his object in OnDisable, so Darryn's own scenes keep their ring. Presentation only.
    public sealed class BomCursorGuard : MonoBehaviour
    {
        const string MenuCursorName = "Menu Cursor";
        GameObject menuCursor;
        bool applied;

        void OnEnable() => Apply();

        void Update()
        {
            if (!applied)
                Apply();
        }

        void Apply()
        {
            if (menuCursor == null)
                menuCursor = GameObject.Find(MenuCursorName);
            if (menuCursor == null)
                return;
            menuCursor.SetActive(false);
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            applied = true;
            Debug.Log("BOM UNITY CURSOR menu cursor off; system pointer visible");
        }

        void OnDisable()
        {
            if (menuCursor != null)
                menuCursor.SetActive(true);
            menuCursor = null;
            applied = false;
        }
    }
}
