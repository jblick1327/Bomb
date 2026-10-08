using System.IO;
using UnityEngine;

// Captures the current arena camera view to a temporary preview image.
public static class CaptureArena
{
    public static string Main()
    {
        var camera = Camera.main;
        var previous = camera.targetTexture;
        var active = RenderTexture.active;
        var target = new RenderTexture(1280, 720, 24);
        var image = new Texture2D(1280, 720, TextureFormat.RGB24, false);
        try
        {
            camera.targetTexture = target;
            camera.aspect = 1280f / 720f;
            camera.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
            camera.Render();
            RenderTexture.active = target;
            image.ReadPixels(new Rect(0, 0, 1280, 720), 0, 0);
            image.Apply();
            File.WriteAllBytes("Temp/Arena-preview.png", image.EncodeToPNG());
            return "Temp/Arena-preview.png; camera=" + camera.transform.position + "; rotation=" + camera.transform.eulerAngles;
        }
        finally
        {
            camera.targetTexture = previous;
            camera.ResetAspect();
            camera.GetComponent<ArenaCamera>().SendMessage("LateUpdate");
            RenderTexture.active = active;
            target.Release();
            Object.DestroyImmediate(target);
            Object.DestroyImmediate(image);
        }
    }
}
