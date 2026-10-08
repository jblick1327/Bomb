if(UnityEditor.EditorApplication.isPlaying) throw new System.InvalidOperationException("Scene authoring requires Play mode stopped.");
for (int i = 0; i < UnityEngine.SceneManagement.SceneManager.sceneCount; i++)
    if (UnityEngine.SceneManagement.SceneManager.GetSceneAt(i).isDirty)
        throw new System.InvalidOperationException("Preserve the dirty editor scene before authoring the fixture.");
var scene = UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.EmptyScene,UnityEditor.SceneManagement.NewSceneMode.Single);
UnityEngine.SceneManagement.SceneManager.SetActiveScene(scene);
var fixture = new UnityEngine.GameObject("Handbook conformance fixture");
fixture.AddComponent<Bomb.CanonicalDestruction.HandbookConformanceScene>();
var cameraObject = new UnityEngine.GameObject("Main Camera");
cameraObject.tag = "MainCamera";
cameraObject.transform.position = new UnityEngine.Vector3(0,2,-12);
var camera = cameraObject.AddComponent<UnityEngine.Camera>();
camera.orthographic = true; camera.orthographicSize = 5.3f;
camera.clearFlags = UnityEngine.CameraClearFlags.SolidColor;
camera.backgroundColor = new UnityEngine.Color(0.025f,0.032f,0.045f,1);
cameraObject.AddComponent<UnityEngine.Rendering.Universal.UniversalAdditionalCameraData>();
if(!UnityEditor.SceneManagement.EditorSceneManager.SaveScene(scene,"Assets/Game/Scenes/HandbookConformance.unity")) throw new System.InvalidOperationException("Scene save failed.");
UnityEditor.Selection.activeGameObject = fixture;
return new { project = UnityEngine.Application.dataPath, scene = scene.path, saved = !scene.isDirty, roots = scene.rootCount };
