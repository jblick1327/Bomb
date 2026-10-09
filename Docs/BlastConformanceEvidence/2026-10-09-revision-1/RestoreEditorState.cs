var project=System.IO.Path.GetFullPath(System.IO.Path.Combine(UnityEngine.Application.dataPath,".."));
if(!string.Equals(project,@"C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe",System.StringComparison.OrdinalIgnoreCase))throw new System.Exception("Wrong project.");
if(UnityEditor.EditorApplication.isPlaying||UnityEditor.EditorApplication.isCompiling)throw new System.Exception("Editor not stopped/settled.");
var evidence=System.IO.Path.Combine(project,"Docs/BlastConformanceEvidence/2026-10-09-revision-1");
var manifest=Newtonsoft.Json.Linq.JObject.Parse(System.IO.File.ReadAllText(System.IO.Path.Combine(evidence,"generated-scenes-to-preserve.json")));
string Hash(string path)
{
    using(var sha=System.Security.Cryptography.SHA256.Create())
        return System.BitConverter.ToString(sha.ComputeHash(System.IO.File.ReadAllBytes(path))).Replace("-","");
}
foreach(var entry in manifest.Properties())
{
    var original=System.IO.Path.GetFullPath(System.IO.Path.Combine(project,entry.Name));
    if(!original.StartsWith(project+System.IO.Path.DirectorySeparatorChar,System.StringComparison.OrdinalIgnoreCase))throw new System.Exception("Path escapes project.");
    var copy=System.IO.Path.Combine(evidence,"generated-scene-backups",entry.Name);
    if(Hash(original)!=(string)entry.Value||Hash(copy)!=(string)entry.Value)throw new System.Exception("Changed/unpreserved generated scene: "+entry.Name);
}
var recovery=System.IO.Path.GetFullPath(System.IO.Path.Combine(project,"Assets/_Recovery"));
if(!recovery.StartsWith(project+System.IO.Path.DirectorySeparatorChar,System.StringComparison.OrdinalIgnoreCase))throw new System.Exception("Unsafe recovery path.");
foreach(var file in System.IO.Directory.GetFiles(recovery,"*",System.IO.SearchOption.AllDirectories))
{
    string relative=file.Substring(project.Length+1).Replace('\\','/');
    if(manifest[relative]==null)throw new System.Exception("Unknown recovery asset: "+relative);
}
var owned=new[]{"Assets/InitTestScened983ee50-2489-480e-8cdc-7293582521a0.unity","Assets/InitTestScene7638c5ba-319d-4793-9c8e-72c54a198dd6.unity"};
for(int i=0;i<UnityEngine.SceneManagement.SceneManager.sceneCount;i++)
{
    var scene=UnityEngine.SceneManagement.SceneManager.GetSceneAt(i);
    if(scene.isDirty||!System.Linq.Enumerable.Contains(owned,scene.path))throw new System.Exception("Unexpected/dirty open scene.");
}
UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.DefaultGameObjects,UnityEditor.SceneManagement.NewSceneMode.Single);
var removed=new System.Collections.Generic.List<string>();
foreach(var path in owned)
{
    var absolute=System.IO.Path.GetFullPath(System.IO.Path.Combine(project,path));
    if(!absolute.StartsWith(project+System.IO.Path.DirectorySeparatorChar,System.StringComparison.OrdinalIgnoreCase))throw new System.Exception("Unsafe scene path.");
    if(!UnityEditor.AssetDatabase.DeleteAsset(path))throw new System.Exception("Could not remove preserved generated scene.");
    removed.Add(path);
}
if(!UnityEditor.AssetDatabase.DeleteAsset("Assets/_Recovery"))throw new System.Exception("Could not remove preserved recovery copy.");
removed.Add("Assets/_Recovery");
UnityEditor.PlayerSettings.runInBackground=false;
UnityEditor.AssetDatabase.SaveAssets();
var benchmark=Newtonsoft.Json.Linq.JArray.Parse(System.IO.File.ReadAllText(System.IO.Path.Combine(evidence,"benchmark.json")));
if(benchmark.Count!=48||System.Linq.Enumerable.Any(benchmark,r=>!(bool)r["ok"]))throw new System.Exception("Incomplete benchmark.");
return new{removedPreservedGeneratedAssets=removed,runInBackground=UnityEditor.PlayerSettings.runInBackground,
    completedBenchmarkRecords=benchmark.Count,scene=UnityEngine.SceneManagement.SceneManager.GetActiveScene().path,
    dirty=UnityEngine.SceneManagement.SceneManager.GetActiveScene().isDirty,roots=UnityEngine.SceneManagement.SceneManager.GetActiveScene().rootCount};
