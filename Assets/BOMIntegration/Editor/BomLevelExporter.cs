using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Bom.Unity;
using UnityEditor;
using UnityEngine;

public static class BomLevelExporter {
 [Serializable]sealed class TextValue{public string v;}
 [Serializable]sealed class LocalConfig{public string OdinRoot;}
 [Serializable]sealed class NativeSourceReport{public string identity_text;public string[] initial_cell_ids;public int cells;}
 [Serializable]sealed class NativeReport{public NativeSourceReport[] sources;public string status,level_id,gameplay_manifest_hash,gameplay_config_hash,catalog_hash;public int game_protocol,canonical_version,source_count,part_count,cell_count;}
 [Serializable]public sealed class InventoryRow{public string object_path,classification,approximation,visual_fallback;public string source_identity;}
 [Serializable]public sealed class VisualPreflightRow{public string source_identity,object_path,asset_key,classification,expected_fallback,remedy;public int triangles,materials;public Vector3 minimum,maximum;}
 [Serializable]sealed class ExportReport{public string level_id,layout,native_report;public InventoryRow[] inventory;public VisualPreflightRow[] visual_geometry;}
 static VisualPreflightRow InspectVisual(BomAssetInstance source,BomVisualEntry entry){
  var row=new VisualPreflightRow{source_identity=U(source.Identity),object_path=source.OriginalObjectPath,asset_key=source.AssetKey,classification="unsupported",expected_fallback="native extrusion",remedy="Author closed visual solids or explicitly separate decorative open surfaces; physics proxies remain independent."};
  var fallback=AssetDatabase.LoadAssetAtPath<Material>("Assets/BOMIntegration/NativeFallback.mat");var arrays=BomSourceMeshData.Read(entry,source.Group.localToWorldMatrix,fallback,64L*1024*1024);
  if(arrays.Failure!=null){row.classification=arrays.Failure;return row;}
  row.triangles=arrays.Triangles.Length;row.materials=arrays.Materials.Length-1;row.minimum=new Vector3(float.MaxValue,float.MaxValue,float.MaxValue);row.maximum=-row.minimum;foreach(var triangle in arrays.Triangles)foreach(var vertex in new[]{triangle.A,triangle.B,triangle.C}){row.minimum=Vector3.Min(row.minimum,vertex.Position);row.maximum=Vector3.Max(row.maximum,vertex.Position);}
  var prepared=BomPrismClipper.Prepare(arrays.Triangles,row.materials);row.classification=prepared.Failure??prepared.Classification;if(prepared.Failure==null){row.expected_fallback="extrusion while asynchronous cuts load, or for an explicitly failed cut";row.remedy="None for closed-solid preprocessing; individual native regions still require clipped-shell validation.";}return row;
 }
 static string Q(string text){string json=JsonUtility.ToJson(new TextValue{v=text??""});return json.Substring(5,json.Length-6);}
 static string F(float value){if(float.IsNaN(value)||float.IsInfinity(value))throw new InvalidOperationException("Nonfinite authoring number");return value.ToString("R",CultureInfo.InvariantCulture);}
 static string U(ulong value)=>value.ToString(CultureInfo.InvariantCulture);
 static string V(Vector2 p)=>"{\"x\":"+F(p.x)+",\"y\":"+F(p.y)+"}";
 static string B(BomBounds2 b)=>"{\"lo\":"+V(b.Minimum)+",\"hi\":"+V(b.Maximum)+"}";
 static void Folder(string path){if(AssetDatabase.IsValidFolder(path))return;string parent=path.Substring(0,path.LastIndexOf('/'));Folder(parent);AssetDatabase.CreateFolder(parent,path.Substring(path.LastIndexOf('/')+1));}
 static string ObjectPath(Transform transform){return transform.parent==null?transform.name:ObjectPath(transform.parent)+"/"+transform.name;}
 static string InventoryPath(Transform transform,BomLevelAuthoring level){string path=ObjectPath(transform),prefix=ObjectPath(level.transform)+"/";return path.StartsWith(prefix,StringComparison.Ordinal)?path.Substring(prefix.Length):path;}
 static string Digest(string text){using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-","").ToLowerInvariant();}
 static Matrix4x4 ToGroup(Transform child,Transform group){var matrix=Matrix4x4.identity;while(child!=group){if(child==null)throw new InvalidOperationException("Visual mesh is outside its canonical group");matrix=Matrix4x4.TRS(child.localPosition,child.localRotation,child.localScale)*matrix;child=child.parent;}return matrix;}
 static Mesh StoreMesh(Mesh mesh,string path){var old=AssetDatabase.LoadAssetAtPath<Mesh>(path);if(old!=null){EditorUtility.CopySerialized(mesh,old);UnityEngine.Object.DestroyImmediate(mesh);EditorUtility.SetDirty(old);return old;}AssetDatabase.CreateAsset(mesh,path);return mesh;}
 static BomVisualEntry Preprocess(BomAssetInstance instance,string folder,out string fallback){
  fallback="";var groups=new List<BomVisualMeshGroup>();var fingerprints=new StringBuilder("bom-visual-builder-"+BomMeshPreprocessor.BuilderVersion+"\n");
  int index=0;foreach(var filter in instance.Group.GetComponentsInChildren<MeshFilter>(true)){
   var owner=filter.GetComponentInParent<BomAssetInstance>(true);if(owner!=null&&owner!=instance)continue;
   var renderer=filter.GetComponent<MeshRenderer>();if(renderer==null)continue;
   try{
    Matrix4x4 meshToGroup=ToGroup(filter.transform,instance.Group);
    var baked=BomMeshPreprocessor.Bake(filter.sharedMesh,meshToGroup,ObjectPath(filter.transform));
    string fingerprint=BomMeshPreprocessor.ContentHash(baked,renderer.sharedMaterials);fingerprints.Append(fingerprint).Append('\n');
    var stored=StoreMesh(baked,folder+"/Source_"+U(instance.Identity)+"_Mesh_"+(index++)+".asset");groups.Add(new BomVisualMeshGroup{Mesh=stored,MeshToGroup=Matrix4x4.identity,SurfaceMaterials=renderer.sharedMaterials});
   }catch(InvalidOperationException error){fallback+=(fallback.Length==0?"":"; ")+error.Message;}
  }
  if(instance.Group.GetComponentsInChildren<SkinnedMeshRenderer>(true).Length>0)fallback+="; skinned source mesh requires extrusion";
  if(groups.Count==0&&fallback.Length==0)fallback="No usable source mesh; explicit physics proxy uses extrusion";
  string cap=AssetDatabase.GetAssetPath(instance.CapMaterial);fingerprints.Append(cap).Append('\n').Append(string.IsNullOrEmpty(cap)?"missing":AssetDatabase.GetAssetDependencyHash(cap).ToString());
  if(fallback.Length>0){groups.Clear();fingerprints.Append("\nextrusion-only\n").Append(fallback);}
  var entry=new BomVisualEntry{AssetKey=instance.AssetKey,ContentHash=Digest(fingerprints.ToString()),BuilderVersion=BomMeshPreprocessor.BuilderVersion,Groups=groups.ToArray(),CapMaterial=instance.CapMaterial,FallbackDepth=instance.FallbackDepth};
  if(groups.Count>0){
   var root=new GameObject("BOM intact source");try{for(int i=0;i<groups.Count;i++){var child=new GameObject("Mesh "+i);child.transform.SetParent(root.transform,false);child.AddComponent<MeshFilter>().sharedMesh=groups[i].Mesh;child.AddComponent<MeshRenderer>().sharedMaterials=groups[i].SurfaceMaterials;}entry.IntactPrefab=PrefabUtility.SaveAsPrefabAsset(root,folder+"/Source_"+U(instance.Identity)+"_Intact.prefab");}finally{UnityEngine.Object.DestroyImmediate(root);}
  }
  return entry;
 }
 static string NativeServer(){string path=Environment.GetEnvironmentVariable("BOM_NATIVE_SERVER_EXE");if(!string.IsNullOrEmpty(path))return Path.GetFullPath(path);string root=Path.GetDirectoryName(Application.dataPath);var config=JsonUtility.FromJson<LocalConfig>(File.ReadAllText(Path.Combine(root,"integration/local.config.json")));return Path.Combine(config.OdinRoot,"build/BOM-server.exe");}
 public static BomVisualRegistry Export(BomLevelAuthoring level,string outputPath){
  BomAuthoringIdentity.Assign(level);if(string.IsNullOrEmpty(level.LevelId))throw new InvalidOperationException("Save the authored scene before exporting");
  if(level.Spawns==null||level.Spawns.Length!=4)throw new InvalidOperationException("Exactly four explicit spawn points are required");
  string folder="Assets/BOMIntegration/Levels/"+level.LevelId;Folder(folder);
  var visualGeometry=new List<VisualPreflightRow>();var inventory=new List<InventoryRow>();foreach(var root in level.gameObject.scene.GetRootGameObjects())foreach(var transform in root.GetComponentsInChildren<Transform>(true))inventory.Add(new InventoryRow{object_path=InventoryPath(transform,level),classification="decorative"});
  var sources=new List<BomAssetInstance>();foreach(var instance in level.GetComponentsInChildren<BomAssetInstance>(true))if(instance.IncludeInExport)sources.Add(instance);
  sources.Sort((a,b)=>a.Identity.CompareTo(b.Identity));var ids=new HashSet<ulong>();var entries=new Dictionary<string,BomVisualEntry>();var json=new StringBuilder();
  json.Append("{\"kind\":\"bom-layout\",\"version\":4,\"seed\":").Append(level.Seed).Append(",\"next_identity\":").Append(U(BomAuthoringIdentity.Parse(level.NextIdentityDecimal))).Append(",\"level_id\":").Append(Q(level.LevelId)).Append(",\"gameplay_config_id\":").Append(Q(level.GameplayConfigId)).Append(",\"catalog_id\":").Append(Q(level.LevelId+"-visual-v1"));
  json.Append(",\"simulation_bounds\":").Append(B(level.SimulationBounds)).Append(",\"kill_bounds\":").Append(B(level.KillBounds)).Append(",\"camera_bounds\":").Append(B(level.CameraBounds)).Append(",\"aim_bounds\":").Append(B(level.AimBounds)).Append(",\"fragment_cull_bounds\":").Append(B(level.FragmentCullBounds));
  json.Append(",\"materials\":[");for(int i=0;i<level.Materials.Count;i++){var m=level.Materials[i];if(i>0)json.Append(',');json.Append("{\"name\":").Append(Q(m.Name)).Append(",\"base\":").Append(Q(m.Base)).Append(",\"toughness\":").Append(F(m.Toughness)).Append(",\"blast_resistance\":").Append(F(m.BlastResistance)).Append(",\"strip_thickness\":").Append(F(m.StripThickness)).Append(",\"shock_loss\":").Append(F(m.ShockLoss)).Append(",\"flexibility\":").Append(F(m.Flexibility)).Append(",\"color\":[").Append(m.Color.r).Append(',').Append(m.Color.g).Append(',').Append(m.Color.b).Append("]}");}json.Append(']');
  json.Append(",\"spawns\":[");for(int i=0;i<4;i++){if(i>0)json.Append(',');json.Append(V(level.Spawns[i]));}json.Append("],\"bombs\":{\"spawn_x\":").Append(V(level.BombSpawnX)).Append(",\"spawn_height\":").Append(F(level.BombSpawnHeight)).Append(",\"cleanup_bounds\":").Append(B(level.BombCleanupBounds)).Append("},\"sources\":[");
  for(int sourceIndex=0;sourceIndex<sources.Count;sourceIndex++){
   var source=sources[sourceIndex];if(source.Identity==0||!ids.Add(source.Identity)||string.IsNullOrWhiteSpace(source.AssetKey))throw new InvalidOperationException(ObjectPath(source.transform)+": missing/duplicate source ID or asset key");
   var entry=Preprocess(source,folder,out string fallback);if(entries.TryGetValue(entry.AssetKey,out var previous)&&previous.ContentHash!=entry.ContentHash)throw new InvalidOperationException("One asset key resolves to differing visual content: "+entry.AssetKey);entries[entry.AssetKey]=entry;
   string sourcePath=InventoryPath(source.transform,level);foreach(var row in inventory)if(row.object_path==sourcePath){row.classification="physics source";row.source_identity=U(source.Identity);row.approximation=source.ApproximationNote;row.visual_fallback=fallback;}
   visualGeometry.Add(InspectVisual(source,entry));
   if(sourceIndex>0)json.Append(',');json.Append("{\"identity\":").Append(U(source.Identity)).Append(",\"asset_key\":").Append(Q(source.AssetKey)).Append(",\"visual_hash\":").Append(Q(entry.ContentHash)).Append(",\"cap_key\":").Append(Q(AssetDatabase.GetAssetPath(source.CapMaterial))).Append(",\"group_to_rest\":[");
   Matrix4x4 matrix=source.Group.localToWorldMatrix;for(int i=0;i<16;i++){if(i>0)json.Append(',');json.Append(F(matrix[i]));}
   json.Append("],\"depth\":").Append(V(source.FallbackDepth)).Append(",\"motion\":").Append(Q(source.Motion.ToString().ToLowerInvariant())).Append(",\"damage\":").Append(Q(source.Damage.ToString().ToLowerInvariant())).Append(",\"parts\":[");
   var parts=new List<BomPhysicsPart>();foreach(var part in source.GetComponentsInChildren<BomPhysicsPart>(true))if(part.GetComponentInParent<BomAssetInstance>(true)==source)parts.Add(part);parts.Sort((a,b)=>a.PartId.CompareTo(b.PartId));
   for(int partIndex=0;partIndex<parts.Count;partIndex++){
    var part=parts[partIndex];if(partIndex>0)json.Append(',');json.Append("{\"part_id\":").Append(U(part.PartId)).Append(",\"material\":").Append(Q(part.MaterialKey)).Append(",\"outline\":[");
    var outline=part.WorldOutline();double signed=0;for(int i=0;i<outline.Length;i++)signed+=(double)outline[i].x*outline[(i+1)%outline.Length].y-(double)outline[i].y*outline[(i+1)%outline.Length].x;if(signed<0)Array.Reverse(outline);
    for(int i=0;i<outline.Length;i++){if(i>0)json.Append(',');json.Append(V(outline[i]));}json.Append("],\"anchors\":[");var anchors=part.WorldAnchors();for(int i=0;i<anchors.Length;i++){if(i>0)json.Append(',');json.Append("{\"a\":").Append(V(anchors[i].A)).Append(",\"b\":").Append(V(anchors[i].B)).Append('}');}json.Append("]}");
    if(!string.IsNullOrEmpty(part.ApproximationNote))inventory.Add(new InventoryRow{object_path=InventoryPath(part.transform,level),classification="explicit physics approximation",source_identity=U(source.Identity),approximation=part.ApproximationNote});
   }json.Append("]}");
  }
  json.Append("],\"glue\":[");for(int i=0;i<level.Glue.Count;i++){var link=level.Glue[i];if(link.A==null||link.B==null)throw new InvalidOperationException("Glue endpoint is missing");if(i>0)json.Append(',');json.Append("{\"a\":").Append(PartKey(link.A)).Append(",\"b\":").Append(PartKey(link.B)).Append('}');}json.Append("],\"allowed_overlaps\":[");
  for(int i=0;i<level.AllowedOverlaps.Count;i++){var overlap=level.AllowedOverlaps[i];if(overlap.A==null||overlap.B==null||string.IsNullOrWhiteSpace(overlap.Reason))throw new InvalidOperationException("Intended XY overlaps require two parts and an explanation");if(i>0)json.Append(',');json.Append("{\"a\":").Append(PartKey(overlap.A)).Append(",\"b\":").Append(PartKey(overlap.B)).Append(",\"reason\":").Append(Q(overlap.Reason)).Append('}');}json.Append("]}");
  string layout=Path.GetFullPath(outputPath);Directory.CreateDirectory(Path.GetDirectoryName(layout));byte[] bytes=Encoding.UTF8.GetBytes(json.ToString());if(bytes.Length>200000)throw new InvalidOperationException("Layout exceeds the native 200000-byte upload bound");File.WriteAllBytes(layout,bytes);
  string nativeReport=layout+".native-report.json";var start=new System.Diagnostics.ProcessStartInfo(NativeServer(),"--validate-layout \""+layout+"\" --report \""+nativeReport+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
  using(var process=System.Diagnostics.Process.Start(start)){var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();if(!process.WaitForExit(120000)){process.Kill();throw new TimeoutException("Native level validation exceeded its time budget");}System.Threading.Tasks.Task.WaitAll(stdout,stderr);File.WriteAllText(layout+".validation.log",stdout.Result+stderr.Result);if(process.ExitCode!=0)throw new InvalidOperationException("Native level validation failed: "+stderr.Result);}
  var build=new Bom.Native.BomBuildInfo{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<Bom.Native.BomBuildInfo>(),version=1};BomSession.Check(Bom.Native.BomNative.bom_build_info(ref build));
  var report=JsonUtility.FromJson<NativeReport>(File.ReadAllText(nativeReport));if(report.status!="passed"||report.game_protocol!=build.game_protocol||report.canonical_version!=build.canonical_version||report.level_id!=level.LevelId)throw new InvalidOperationException("Wrong or incomplete native export report");
  string registryPath=folder+"/VisualRegistry.asset";var registry=AssetDatabase.LoadAssetAtPath<BomVisualRegistry>(registryPath);if(registry==null){registry=ScriptableObject.CreateInstance<BomVisualRegistry>();AssetDatabase.CreateAsset(registry,registryPath);}
  if(report.sources==null||report.sources.Length!=report.source_count)throw new InvalidOperationException("Native export report lacks initial source membership; rebuild the native validator");
  var initial=new List<BomInitialSourceRegion>();foreach(var row in report.sources){if(!ulong.TryParse(row.identity_text,NumberStyles.None,CultureInfo.InvariantCulture,out ulong id)||id==0||row.initial_cell_ids==null||row.initial_cell_ids.Length!=row.cells)throw new InvalidOperationException("Invalid native initial source membership");var initialIds=new HashSet<ulong>();foreach(string text in row.initial_cell_ids)if(!ulong.TryParse(text,NumberStyles.None,CultureInfo.InvariantCulture,out ulong cell)||cell==0||!initialIds.Add(cell))throw new InvalidOperationException("Invalid or repeated native initial cell ID");initial.Add(new BomInitialSourceRegion{SourceIdentity=row.identity_text,InitialCellIds=row.initial_cell_ids});}registry.InitialSources=initial.ToArray();
  registry.LevelId=level.LevelId;registry.GameplayManifestHash=report.gameplay_manifest_hash;registry.CatalogHash=report.catalog_hash;var keys=new List<string>(entries.Keys);keys.Sort(StringComparer.Ordinal);var sorted=new List<BomVisualEntry>();foreach(string key in keys)sorted.Add(entries[key]);registry.Entries=sorted.ToArray();EditorUtility.SetDirty(registry);level.VisualRegistry=registry;EditorUtility.SetDirty(level);AssetDatabase.SaveAssets();
  File.WriteAllText(layout+".preprocessing.json",JsonUtility.ToJson(new ExportReport{level_id=level.LevelId,layout=layout,native_report=nativeReport,inventory=inventory.ToArray(),visual_geometry=visualGeometry.ToArray()},true));Debug.Log("BOM LEVEL EXPORT PASS sources="+report.source_count+" parts="+report.part_count+" cells="+report.cell_count+" gameplay="+report.gameplay_manifest_hash);return registry;
 }
 static string PartKey(BomPhysicsPart part){var source=part.GetComponentInParent<BomAssetInstance>(true);if(source==null)throw new InvalidOperationException("Glue part has no source instance");return "{\"source_identity\":"+U(source.Identity)+",\"part_id\":"+U(part.PartId)+"}";}
}
