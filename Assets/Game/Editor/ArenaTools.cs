using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class ArenaTools
{
    public const string ScenePath = "Assets/Game/Scenes/Arena.unity";

    [MenuItem("Arena/Open Arena Scene", false, 0)]
    private static void OpenScene()
    {
        if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
            EditorSceneManager.OpenScene(ScenePath);
    }

    [MenuItem("Arena/Open Arena Scene", true)]
    private static bool CanOpenScene() => !EditorApplication.isPlaying;

    [MenuItem("Arena/Checks/Run All", false, 40)]
    private static void RunChecksFromMenu() => Debug.Log(RunChecks());

    public static string RunChecks()
    {
        if (!CanCheck()) throw new InvalidOperationException("Open the Arena scene and enter Play mode first.");
        var session = UnityEngine.Object.FindFirstObjectByType<ArenaSession>();
        var results = new List<string>();
        try
        {
            foreach (var check in new Func<string>[] { VerifySideArena.Main, VerifyCraterMovement.Main,
                VerifyArenaLayout.Main, VerifyBombs.Main, VerifyFoundation.Main })
            {
                session.RestartRound();
                results.Add(check());
            }
            return "Arena checks: 5 passed.\n" + string.Join("\n", results);
        }
        finally { session.RestartRound(); }
    }

    [MenuItem("Arena/Checks/Run All", true)]
    private static bool CanCheck() => EditorApplication.isPlaying && SceneManager.GetActiveScene().path == ScenePath;

    [MenuItem("Arena/Preview/Craters", false, 60)]
    private static void PreviewCraters() => Debug.Log(PreviewCrater.Main());

    [MenuItem("Arena/Preview/Craters", true)]
    private static bool CanPreviewCraters() => CanCheck();

    [MenuItem("Arena/Preview/Capture", false, 61)]
    private static void Capture() => Debug.Log(CaptureArena.Main());

    [MenuItem("Arena/Preview/Capture", true)]
    private static bool CanCapture() => SceneManager.GetActiveScene().path == ScenePath;
}
