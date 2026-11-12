using System;
using System.IO;
using Bom.Unity;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

// C5: the game player with Darryn's MainMenuScene as the first scene. "Play" runs his local levels unchanged (D4);
// "Online" hosts or joins Odin play in the network yard. The native server and the level layout are copied next to the
// exe as Server/BOM-server.exe and Server/levels/<file> (see BomHostServer.FindServer); C6 adds YardLevel.json,
// BridgeLevel.json and TowerLevel.json from BOM_TILE_LEVEL_DIR and their network scenes. Built only in the validation
// project; the source project's EditorBuildSettings are not changed.
public static class BomFrontDoorBuilder
{
    public const string MainMenuScene = "Assets/Game/Scenes/MainMenuScene.unity";
    static readonly string[] LocalLevels =
    {
        "Assets/Game/Scenes/YardLevel.unity",
        "Assets/Game/Scenes/BridgeLevel.unity",
        "Assets/Game/Scenes/TowerLevel.unity",
    };

    static string Env(string name)
    {
        string value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrEmpty(value))
            throw new InvalidOperationException("Set " + name);
        return value;
    }

    public static void BuildMono()
    {
        string output = Env("BOM_GAME_PLAYER_OUT"),
            server = Env("BOM_NATIVE_SERVER_EXE"),
            layout = Env("BOM_YARD_LAYOUT_OUT"),
            tileLevels = Env("BOM_TILE_LEVEL_DIR");
        // Same level preparation as the Rounds gate: re-export the yard, then configure the network scene from it.
        BomYardBuilder.CreateAndExport();
        EditorSceneManager.OpenScene(BomNetworkMenuBuilder.ScenePath, OpenSceneMode.Single);
        BomNetworkMenuBuilder.ConfigureScene();
        BomSession.VerifyLayouts();
        // C6: Darryn's tile levels as native layouts + derived network scenes (session/HUD/camera cloned from NetworkMenu).
        BomTileLevelBuilder.ExportAll(tileLevels);
        var scenes = new System.Collections.Generic.List<string> { MainMenuScene };
        scenes.AddRange(LocalLevels);
        scenes.Add(BomNetworkMenuBuilder.ScenePath);
        foreach (var spec in BomTileLevelBuilder.Levels)
            scenes.Add(spec.Scene);
        foreach (string scene in scenes)
            if (!File.Exists(scene))
                throw new InvalidOperationException("Missing front-door scene " + scene);
        Directory.CreateDirectory(output);
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Standalone, ScriptingImplementation.Mono2x);
        var report = BuildPipeline.BuildPlayer(
            new BuildPlayerOptions
            {
                scenes = scenes.ToArray(),
                target = BuildTarget.StandaloneWindows64,
                locationPathName = Path.Combine(output, "Bomb.exe"),
                options = BuildOptions.Development,
            }
        );
        if (report.summary.result != BuildResult.Succeeded)
            throw new InvalidOperationException("Front-door player build failed");
        string serverFolder = Path.Combine(output, "Server");
        Directory.CreateDirectory(Path.Combine(serverFolder, "levels"));
        File.Copy(server, Path.Combine(serverFolder, "BOM-server.exe"), true);
        foreach (var level in BomFrontDoor.Levels)
        {
            string from = level.Layout == "yard.json" ? layout : Path.Combine(tileLevels, level.Layout);
            if (!File.Exists(from) || !scenes.Exists(s => Path.GetFileNameWithoutExtension(s) == level.Scene))
                throw new InvalidOperationException("No exported layout or scene for level " + level.Name);
            File.Copy(from, Path.Combine(serverFolder, "levels", level.Layout), true);
        }
        Debug.Log("BOM FRONT DOOR MONO BUILD PASS scenes=" + string.Join(",", scenes) + " server=" + serverFolder);
    }
}
