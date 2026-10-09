return new { project=UnityEngine.Application.dataPath, unity=UnityEngine.Application.unityVersion,
    pid=System.Diagnostics.Process.GetCurrentProcess().Id,
    playing=UnityEditor.EditorApplication.isPlaying, paused=UnityEditor.EditorApplication.isPaused,
    compiling=UnityEditor.EditorApplication.isCompiling,
    scenes=Enumerable.Range(0,UnityEngine.SceneManagement.SceneManager.sceneCount)
        .Select(i=>UnityEngine.SceneManagement.SceneManager.GetSceneAt(i)).Select(s=>new {s.name,s.path,s.isDirty}).ToArray() };
