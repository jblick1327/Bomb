var scenes = new System.Collections.Generic.List<object>();
for (int i = 0; i < UnityEngine.SceneManagement.SceneManager.sceneCount; i++)
{
    var scene = UnityEngine.SceneManagement.SceneManager.GetSceneAt(i);
    scenes.Add(new { name = scene.name, path = scene.path, dirty = scene.isDirty, loaded = scene.isLoaded,
        roots = System.Array.ConvertAll(scene.GetRootGameObjects(), o => o.name) });
}
return new { project = UnityEngine.Application.dataPath, version = UnityEngine.Application.unityVersion,
    playing = UnityEditor.EditorApplication.isPlaying, background = UnityEngine.Application.runInBackground, scenes };
