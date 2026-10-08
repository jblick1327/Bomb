if (UnityEditor.EditorApplication.isPlaying) throw new System.InvalidOperationException("Stop Play mode before restoring settings.");
UnityEngine.Application.runInBackground = false;
UnityEditor.AssetDatabase.SaveAssets();
return new { project = UnityEngine.Application.dataPath, version = UnityEngine.Application.unityVersion,
    playing = UnityEditor.EditorApplication.isPlaying, compiling = UnityEditor.EditorApplication.isCompiling,
    background = UnityEngine.Application.runInBackground,
    scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().path };
