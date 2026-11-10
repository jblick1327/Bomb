using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using Bom.Native;
using UnityEngine;
using Debug=UnityEngine.Debug;
namespace Bom.Unity {
// Read-only native topology/pose presentation. This class owns no collider,
// Rigidbody, player tuning, network decoder or authoritative gameplay state.
public sealed class BomSourcePresentation:IDisposable {
 const long MiB=1024*1024,TotalCacheLimit=256*MiB,GpuCacheLimit=128*MiB;
 readonly BomVisualRegistry registry;readonly Material fallback;readonly bool enabled;
 readonly Dictionary<ulong,Source> sources=new Dictionary<ulong,Source>();readonly Dictionary<ulong,Cell> cells=new Dictionary<ulong,Cell>();readonly Dictionary<ulong,HashSet<ulong>> initial=new Dictionary<ulong,HashSet<ulong>>();
 readonly Dictionary<string,Gpu> gpu=new Dictionary<string,Gpu>();long gpuBytes,fallbackBytes,use;int sourceCursor;ulong session,revision;uint epoch;bool disposed;string failureDirectory;readonly HashSet<ulong> dumpedFailures=new HashSet<ulong>();
 readonly List<Source> sourceOrder=new List<Source>();bool sourceOrderDirty=true;
 [Serializable]sealed class FailureFixture{public string asset,reason,source;public ulong cell;public Vector2[] outline;public float[] matrix;}
 sealed class TestGateState {public readonly ManualResetEventSlim Ready=new ManualResetEventSlim(false);public int Waiters;}
 readonly TestGateState testGate=new TestGateState();string testJobGatePath,testJobGateAsset="source-fixture/Closed box";bool testGateReleased;long reportedStaleDrops;ulong reportedGateSession;uint reportedGateEpoch;bool reportedGateWaiting;
 bool membershipTrusted;Dictionary<(uint,ulong),Transform> bodies;Dictionary<ulong,List<Renderer>> fallbackViews;
 public readonly BomGeometryJobs Jobs=new BomGeometryJobs(cacheBytes:112*MiB);
 public int IntactSources{get;private set;}public int FragmentSources{get;private set;}public int FallbackSources{get;private set;}public long StaleApplications{get;private set;}public long GpuCacheHits{get;private set;}public long GpuEvictions{get;private set;}public long GpuBytes=>gpuBytes;public double FrameUploadMilliseconds{get;private set;}public double FrameSourceReadMilliseconds{get;private set;}public double MaxUploadMilliseconds{get;private set;}public double MaxSourceReadMilliseconds{get;private set;}
 sealed class Cell:BomVisualCellRegion {public BomCell Native;public BomCellBinding Binding;public Source Owner;public string Key;public bool Lease,Requested,Seen;}
 sealed class Source {
  public ulong Id;public BomSourceState Native;public BomVisualEntry Entry;public Matrix4x4 Matrix;public string Key,Failure,RenderFailure,LastMessage;public BomClipSource Prepared;public bool Lease,Requested,Changed,Intact;public Material[] Palette;public readonly List<Material> OwnedMaterials=new List<Material>();public List<Cell> Cells=new List<Cell>();public List<Plan> Plans;public BomSourceEdgeIndex Edges;public int QueueCursor,PlanCursor;public string Mode="fallback";
 }
 sealed class Plan {public List<Cell> Cells;public ulong Representative;public bool Intact;public string Key;public Gpu Data;public readonly List<GameObject> Objects=new List<GameObject>();}
 sealed class Gpu {public string Key;public BomClipTriangle[] Raw;public int Cursor,References,Materials;public long Bytes,Used;public bool Complete;public readonly List<Mesh> Meshes=new List<Mesh>();public readonly List<int[]> MaterialSlots=new List<int[]>();}
 static double Milliseconds(long start)=>(Stopwatch.GetTimestamp()-start)*1000.0/Stopwatch.Frequency;
 static void Destroy(UnityEngine.Object value){if(value!=null)UnityEngine.Object.Destroy(value);}
 static string Digest(Action<BinaryWriter> write){using(var bytes=new MemoryStream())using(var writer=new BinaryWriter(bytes)){write(writer);writer.Flush();using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(bytes.ToArray())).Replace("-","").ToLowerInvariant();}}
 static Matrix4x4 Matrix(BomSourceBinding b)=>new Matrix4x4(new Vector4(b.m00,b.m10,b.m20,b.m30),new Vector4(b.m01,b.m11,b.m21,b.m31),new Vector4(b.m02,b.m12,b.m22,b.m32),new Vector4(b.m03,b.m13,b.m23,b.m33));
 public BomSourcePresentation(BomVisualRegistry registry,Material fallback,bool enabled){var args=Environment.GetCommandLineArgs();int failureArg=Array.IndexOf(args,"--bom-source-failure-dir");if(failureArg>=0&&failureArg+1<args.Length)failureDirectory=args[failureArg+1];int gateArg=Array.IndexOf(args,"--bom-source-job-gate");if(gateArg>=0&&gateArg+1<args.Length)testJobGatePath=args[gateArg+1];int gateAsset=Array.IndexOf(args,"--bom-source-job-gate-asset");if(gateAsset>=0&&gateAsset+1<args.Length)testJobGateAsset=args[gateAsset+1];this.registry=registry;this.fallback=fallback;this.enabled=enabled&&registry!=null;Debug.Log("BOM SOURCE ART "+(this.enabled?"ON":"OFF"));if(registry!=null)foreach(var source in registry.InitialSources){if(!ulong.TryParse(source.SourceIdentity,NumberStyles.None,CultureInfo.InvariantCulture,out ulong id))continue;var ids=new HashSet<ulong>();foreach(string text in source.InitialCellIds)if(ulong.TryParse(text,NumberStyles.None,CultureInfo.InvariantCulture,out ulong cell))ids.Add(cell);initial[id]=ids;}}
 public bool HasMode(string asset,string mode){foreach(var source in sources.Values)if(source.Native.AssetKey==asset&&source.Mode==mode)return true;return false;}
 public bool TrySourcePose(string asset,out Vector3 position){position=default;foreach(var source in sources.Values)if(source.Native.AssetKey==asset&&source.Cells.Count>0){var cell=source.Cells[0];var key=(cell.Native.pose_kind,cell.Native.pose_kind==1?cell.Id:cell.Native.piece_id);if(bodies!=null&&bodies.TryGetValue(key,out var body)){position=body.position;return true;}}return false;}
 public static void AttachRestGeometry(Transform visual,Transform body,Vector2 nativePivot){visual.SetParent(body,false);visual.localPosition=new Vector3(-nativePivot.x,-nativePivot.y,0);visual.localRotation=Quaternion.identity;visual.localScale=Vector3.one;}
 public void SetFallbackBytes(long bytes){fallbackBytes=bytes;}
 public void BeforeTopology(){foreach(var source in sources.Values)if(source.Plans!=null)foreach(var plan in source.Plans)foreach(var obj in plan.Objects)if(obj!=null)obj.transform.SetParent(null,true);}
 void ClearPlans(Source source){if(source.Plans!=null)foreach(var plan in source.Plans){foreach(var obj in plan.Objects)Destroy(obj);if(plan.Data!=null){plan.Data.References--;plan.Data.Used=++use;}}source.Plans=null;source.Edges=null;source.PlanCursor=0;source.Mode="fallback";}
 public void Clear(){foreach(var source in sources.Values){ClearPlans(source);if(source.Lease)Jobs.Release(source.Key);foreach(var material in source.OwnedMaterials)Destroy(material);}foreach(var cell in cells.Values)if(cell.Lease)Jobs.Release(cell.Key);sources.Clear();sourceOrder.Clear();sourceOrderDirty=true;cells.Clear();session=0;epoch=0;revision=0;if(!disposed)Jobs.Reset(0,0);IntactSources=FragmentSources=FallbackSources=0;}
 public void SetTopology(BomSession client,Dictionary<(uint,ulong),Transform> nativeBodies,Dictionary<ulong,List<Renderer>> nativeFallback){
  sourceOrderDirty=true;
  if(!enabled||disposed)return;var sample=client.Sample;bool fresh=session!=sample.connection_generation||epoch!=sample.epoch;if(fresh){Clear();session=sample.connection_generation;epoch=sample.epoch;Jobs.Reset(session,epoch);}revision=sample.revision;membershipTrusted=registry.GameplayManifestHash==BomSession.HashText(client.Catalog.gameplay_hash0,client.Catalog.gameplay_hash1,client.Catalog.gameplay_hash2,client.Catalog.gameplay_hash3);bodies=nativeBodies;fallbackViews=nativeFallback;
  foreach(var source in sources.Values){source.Changed=false;source.Cells.Clear();}foreach(var cell in cells.Values)cell.Seen=false;
  for(int i=0;i<sample.cell_count;i++){
   var native=client.Cells[i];var binding=client.CellBindings[i];if(binding.cell_id!=native.id)throw new InvalidOperationException("Source presentation binding differs from native cell");
   if(!client.Sources.TryGetValue(binding.source_identity,out var metadata))continue;
   if(!sources.TryGetValue(binding.source_identity,out var source)){
    source=new Source{Id=binding.source_identity,Native=metadata,Matrix=Matrix(metadata.Binding),Changed=true};if(registry.TryFind(metadata.AssetKey,metadata.VisualHash,out var entry)){source.Entry=entry;source.Key="source:"+BomSourceMeshData.MatrixKey(entry.ContentHash,source.Matrix);}else source.Failure="missing or mismatched local source art";sources.Add(source.Id,source);
   }
   if(!cells.TryGetValue(native.id,out var cell)){var outline=new Vector2[native.vertex_count];for(uint v=0;v<native.vertex_count;v++){var p=client.Vertices[native.vertex_start+v];outline[v]=new Vector2(p.x,p.y);}cell=new Cell{Id=native.id,Source=source.Id,Outline=outline,Owner=source};cells.Add(cell.Id,cell);source.Changed=true;}else if(cell.Source!=source.Id||cell.Binding.source_part_id!=binding.source_part_id)throw new InvalidOperationException("Immutable native source binding changed within an epoch");
   if(cell.Piece!=native.piece_id||cell.PoseKind!=native.pose_kind||cell.Native.pivot_x!=native.pivot_x||cell.Native.pivot_y!=native.pivot_y||cell.Native.material!=native.material||cell.Native.color_rgba!=native.color_rgba)source.Changed=true;
   cell.Native=native;cell.Binding=binding;cell.Piece=native.piece_id;cell.PoseKind=native.pose_kind;cell.Seen=true;source.Cells.Add(cell);
  }
  var removed=new List<ulong>();foreach(var pair in cells)if(!pair.Value.Seen){var cell=pair.Value;cell.Owner.Changed=true;if(cell.Lease)Jobs.Release(cell.Key);removed.Add(pair.Key);}foreach(ulong id in removed)cells.Remove(id);
  foreach(var source in sources.Values){source.Cells.Sort((a,b)=>a.Id.CompareTo(b.Id));if(source.Changed){ClearPlans(source);source.RenderFailure=null;source.QueueCursor=0;}source.Intact=Eligible(source);if(!source.Changed&&source.Plans!=null)foreach(var plan in source.Plans)Attach(source,plan);Visibility(source);}
 }
 bool Eligible(Source source){if(!membershipTrusted||source.Cells.Count==0||!initial.TryGetValue(source.Id,out var expected)||source.Cells.Count!=expected.Count)return false;ulong piece=source.Cells[0].Piece;foreach(var cell in source.Cells)if(cell.PoseKind!=0||cell.Piece!=piece||!expected.Contains(cell.Id))return false;return true;}
 void Visibility(Source source){bool show=source.Mode=="intact"||source.Mode=="fragments";if(fallbackViews!=null&&fallbackViews.TryGetValue(source.Id,out var renderers))foreach(var renderer in renderers)if(renderer!=null)renderer.enabled=!show;if(source.Plans!=null)foreach(var plan in source.Plans)foreach(var obj in plan.Objects)if(obj!=null)obj.SetActive(show);}
 void Warn(Source source,string reason){string message="fallback: "+reason;if(source.LastMessage==message)return;source.LastMessage=message;Debug.LogWarning("BOM SOURCE FALLBACK source="+source.Id+" asset="+source.Native.AssetKey+" reason="+reason);}
 void Palette(Source source,Material[] surface=null){if(source.Palette==null){var list=new List<Material>();if(surface!=null){for(int i=0;i<surface.Length-1;i++)list.Add(surface[i]);}else foreach(var group in source.Entry.Groups)for(int sub=0;sub<group.Mesh.subMeshCount;sub++)list.Add(sub<group.SurfaceMaterials.Length&&group.SurfaceMaterials[sub]!=null?group.SurfaceMaterials[sub]:fallback);int count=list.Count;for(int i=0;i<8;i++){if(source.Entry.CapMaterial!=null)list.Add(source.Entry.CapMaterial);else{var material=new Material(fallback){name="BOM interior "+source.Id+":"+i};source.OwnedMaterials.Add(material);list.Add(material);}}source.Palette=list.ToArray();}
  int first=source.Palette.Length-8;if(source.Entry.CapMaterial==null)foreach(var cell in source.Cells){uint color=cell.Native.color_rgba;source.Palette[first+checked((int)cell.Native.material)].SetColor("_BaseColor",new Color((byte)color/255f*.7f,(byte)(color>>8)/255f*.7f,(byte)(color>>16)/255f*.7f,1));}
 }
 bool Prepare(Source source){
  if(source.Failure!=null){Warn(source,source.Failure);return false;}if(source.Prepared!=null)return true;
  if(Jobs.TryGet(source.Key,out var cached)){if(!cached.Supported||cached.PreparedSource==null){source.Failure=cached.Reason;Warn(source,source.Failure);return false;}if(!Jobs.Acquire(source.Key,out cached))return false;source.Lease=true;source.Prepared=cached.PreparedSource;Palette(source);Debug.Log("BOM SOURCE PREPARED source="+source.Id+" triangles="+source.Prepared.Triangles.Length+" bytes="+source.Prepared.Bytes);return true;}
  if(source.Requested)return false;long estimate=BomSourceMeshData.Estimate(source.Entry);if(estimate>Jobs.BufferLimit){source.Failure="source normalization exceeds buffer budget; simplify or split the visual group";Warn(source,source.Failure);return false;}if(Jobs.PendingCount>=Jobs.PendingLimit||Jobs.BufferBytes>Jobs.BufferLimit-estimate)return false;
  long start=Stopwatch.GetTimestamp();var arrays=BomSourceMeshData.Read(source.Entry,source.Matrix,fallback,Jobs.BufferLimit);FrameSourceReadMilliseconds=Math.Max(FrameSourceReadMilliseconds,Milliseconds(start));MaxSourceReadMilliseconds=Math.Max(MaxSourceReadMilliseconds,FrameSourceReadMilliseconds);if(arrays.Failure!=null){source.Failure=arrays.Failure;Warn(source,source.Failure);return false;}Palette(source,arrays.Materials);var triangles=arrays.Triangles;int materials=arrays.Materials.Length-1;source.Requested=Jobs.RequestBuild(new BomGeometryTicket(session,epoch,0),source.Key,estimate,1000,token=>{var prepared=BomPrismClipper.Prepare(triangles,materials,token);return prepared.Failure==null?new BomClipResult{Supported=true,PreparedSource=prepared,Bytes=prepared.Bytes}:new BomClipResult{Reason=prepared.Failure};});return false;
 }
 string CellKey(Cell cell)=>"cell:"+Digest(writer=>{writer.Write(BomPrismClipper.BuilderVersion);writer.Write(cell.Owner.Key);writer.Write(cell.Source);writer.Write(cell.Binding.source_part_id);writer.Write(cell.Owner.Native.Binding.depth_lo);writer.Write(cell.Owner.Native.Binding.depth_hi);writer.Write(cell.Outline.Length);foreach(var p in cell.Outline){writer.Write(p.x);writer.Write(p.y);}});
 void DumpFailure(Cell cell){if(string.IsNullOrEmpty(failureDirectory)||!dumpedFailures.Add(cell.Id))return;Directory.CreateDirectory(failureDirectory);var matrix=new float[16];for(int i=0;i<16;i++)matrix[i]=cell.Owner.Matrix[i];File.WriteAllText(Path.Combine(failureDirectory,cell.Source+"-"+cell.Id+".json"),JsonUtility.ToJson(new FailureFixture{asset=cell.Owner.Native.AssetKey,source=cell.Source.ToString(CultureInfo.InvariantCulture),cell=cell.Id,outline=cell.Outline,matrix=matrix,reason=cell.Geometry.Reason},true));}
 bool PrepareCells(Source source){bool ready=true;int queued=0;for(int i=0;i<source.Cells.Count;i++){var cell=source.Cells[(source.QueueCursor+i)%source.Cells.Count];if(cell.Geometry!=null){if(!cell.Geometry.Supported){DumpFailure(cell);Warn(source,cell.Geometry.Reason);return false;}continue;}ready=false;if(cell.Key==null){if(queued>=8)continue;cell.Key=CellKey(cell);}if(Jobs.TryGet(cell.Key,out var cached)){if(cached.Supported){if(!Jobs.Acquire(cell.Key,out cached))continue;cell.Lease=true;}cell.Geometry=cached;continue;}if(cell.Requested)continue;if(queued>=8)continue;
   var lo=cell.Outline[0];var hi=lo;foreach(var p in cell.Outline){lo=Vector2.Min(lo,p);hi=Vector2.Max(hi,p);}int count=source.Prepared.Candidates(lo,hi).Length;long estimate=Math.Max(65536,(long)Math.Max(1,count)*(cell.Outline.Length+2)*2*576*8);if(estimate>Jobs.BufferLimit){cell.Geometry=new BomClipResult{Reason="native region exceeds the bounded cut work estimate; split its visual source"};Warn(source,cell.Geometry.Reason);return false;}var copied=cell.Outline;var geometry=source.Prepared;var gate=testGate;bool gated=!string.IsNullOrEmpty(testJobGatePath)&&source.Native.AssetKey==testJobGateAsset;cell.Requested=Jobs.RequestBuild(new BomGeometryTicket(session,epoch,cell.Id),cell.Key,estimate,100,token=>{if(gated){Interlocked.Increment(ref gate.Waiters);try{gate.Ready.Wait(token);}finally{Interlocked.Decrement(ref gate.Waiters);}}return BomPrismClipper.Build(geometry,copied,token);});if(cell.Requested)queued++;
  }if(source.Cells.Count>0)source.QueueCursor=(source.QueueCursor+8)%source.Cells.Count;return ready;
 }
 List<BomClipTriangle> PlanGeometry(Source source,Plan plan,out string key){
  if(plan.Intact){key="intact:"+source.Key;return null;}
  var triangles=new List<BomClipTriangle>();key="batch:"+Digest(writer=>{
   writer.Write(BomPrismClipper.BuilderVersion);writer.Write(source.Key);foreach(var cell in plan.Cells){writer.Write(cell.Id);writer.Write(cell.Key);writer.Write(cell.Native.material);writer.Write(cell.Native.color_rgba);triangles.AddRange(cell.Geometry.Exterior);foreach(var patch in cell.Geometry.Caps){var occupied=source.Edges.Occupied(cell,patch,source.Prepared.Epsilon*8);writer.Write(patch.Solid);writer.Write(occupied.Count);foreach(var interval in occupied){writer.Write(interval.Lo);writer.Write(interval.Hi);}foreach(var triangle in BomCapVisibility.Visible(patch,occupied,source.Prepared.Epsilon*4)){triangles.Add(new BomClipTriangle(triangle.A,triangle.B,triangle.C,source.Prepared.MaterialCount+checked((int)cell.Native.material)));if(triangles.Count>10000)throw new InvalidOperationException("cap visibility exceeds a source staging bound");}}}
  });return triangles;
 }
 bool MakePlans(Source source){
  if(source.Plans!=null)return true;if(source.RenderFailure!=null)return false;
  source.Plans=new List<Plan>();
  if(source.Intact){source.Plans.Add(new Plan{Intact=true,Representative=source.Cells[0].Id,Cells=new List<Cell>(source.Cells)});return true;}
  source.Edges=new BomSourceEdgeIndex(source.Cells);if(source.Edges.Failure!=null){source.RenderFailure=source.Edges.Failure;ClearPlans(source);Warn(source,source.RenderFailure);return false;}
  var groups=new Dictionary<(uint,ulong,ulong),List<Cell>>();foreach(var cell in source.Cells){var group=(cell.PoseKind,cell.PoseKind==1?cell.Id:cell.Piece,cell.Id>>6);if(!groups.TryGetValue(group,out var list)){list=new List<Cell>();groups.Add(group,list);}list.Add(cell);}
  foreach(var group in groups.Values){Plan plan=null;int count=0;foreach(var cell in group){int triangles=cell.Geometry.Exterior.Length;foreach(var cap in cell.Geometry.Caps)triangles+=cap.Triangles.Length;if(triangles>4096){source.RenderFailure="one cell exceeds the bounded upload staging size; split the visual group";ClearPlans(source);Warn(source,source.RenderFailure);return false;}if(plan==null||count+triangles>4096){plan=new Plan{Representative=cell.Id,Cells=new List<Cell>()};source.Plans.Add(plan);count=0;}plan.Cells.Add(cell);count+=triangles;}}
  return true;
 }
 bool Space(long required){
  while(gpuBytes+required>GpuCacheLimit||gpuBytes+required+Jobs.CacheBytes+fallbackBytes>TotalCacheLimit){Gpu oldest=null;foreach(var record in gpu.Values)if(record.References==0&&(oldest==null||record.Used<oldest.Used))oldest=record;if(oldest==null)return false;gpu.Remove(oldest.Key);gpuBytes-=oldest.Bytes;foreach(var mesh in oldest.Meshes)Destroy(mesh);oldest.Raw=null;GpuEvictions++;}return true;
 }
 bool Upload(Source source,Plan plan){
  if(plan.Data==null){List<BomClipTriangle> triangles=null;
   try{if(plan.Intact)plan.Key="intact:"+source.Key;else triangles=PlanGeometry(source,plan,out plan.Key);}catch(InvalidOperationException error){source.RenderFailure=error.Message;return false;}
   if(gpu.TryGetValue(plan.Key,out var existing)){existing.References++;existing.Used=++use;plan.Data=existing;GpuCacheHits++;}
   else{var raw=plan.Intact?source.Prepared.Triangles:triangles.ToArray();long bytes=raw.LongLength*576*2;if(!Space(bytes)){source.RenderFailure="source mesh cache budget reached; retaining native extrusion";return false;}var record=new Gpu{Key=plan.Key,Raw=raw,References=1,Bytes=bytes,Materials=source.Palette.Length,Used=++use};gpu.Add(record.Key,record);gpuBytes+=bytes;plan.Data=record;}
  }
  var data=plan.Data;if(data.Complete)return true;
  int count=Math.Min(BomClipMeshUpload.TriangleChunk,data.Raw.Length-data.Cursor);if(count>0){long start=Stopwatch.GetTimestamp();var mesh=BomClipMeshUpload.UploadCompact(data.Raw,data.Cursor,count,Vector2.zero,data.Materials,"BOM source "+source.Id,out var slots);mesh.UploadMeshData(true);data.Meshes.Add(mesh);data.MaterialSlots.Add(slots);data.Cursor+=count;FrameUploadMilliseconds=Math.Max(FrameUploadMilliseconds,Milliseconds(start));MaxUploadMilliseconds=Math.Max(MaxUploadMilliseconds,FrameUploadMilliseconds);}
  if(data.Cursor==data.Raw.Length){long rawBytes=data.Raw.LongLength*576;data.Bytes-=rawBytes;gpuBytes-=rawBytes;data.Raw=null;data.Complete=true;}return data.Complete;
 }
 void Attach(Source source,Plan plan){
  if(!cells.TryGetValue(plan.Representative,out var cell))return;var key=(cell.Native.pose_kind,cell.Native.pose_kind==1?cell.Id:cell.Native.piece_id);if(bodies==null||!bodies.TryGetValue(key,out var body))return;
  foreach(var obj in plan.Objects){if(obj==null)continue;AttachRestGeometry(obj.transform,body,new Vector2(cell.Native.pivot_x,cell.Native.pivot_y));}
 }
 void Commit(Source source){
  if(!Jobs.Current(new BomGeometryTicket(session,epoch,0))){StaleApplications++;throw new InvalidOperationException("A stale source presentation reached commit");}
  foreach(var plan in source.Plans){if(plan.Data==null||!plan.Data.Complete)throw new InvalidOperationException("Incomplete source mesh commit");if(plan.Objects.Count==0)for(int meshIndex=0;meshIndex<plan.Data.Meshes.Count;meshIndex++){var mesh=plan.Data.Meshes[meshIndex];var slots=plan.Data.MaterialSlots[meshIndex];var palette=new Material[slots.Length];for(int slot=0;slot<slots.Length;slot++)palette[slot]=source.Palette[slots[slot]];var obj=new GameObject("BOM source "+source.Id+(plan.Intact?" intact":" fragments"));obj.SetActive(false);obj.AddComponent<MeshFilter>().sharedMesh=mesh;obj.AddComponent<MeshRenderer>().sharedMaterials=palette;plan.Objects.Add(obj);}Attach(source,plan);}
  source.Mode=source.Intact?"intact":"fragments";Visibility(source);string message=source.Mode+":"+revision;if(source.LastMessage!=message){source.LastMessage=message;Debug.Log("BOM SOURCE PRESENTATION source="+source.Id+" mode="+source.Mode+" cells="+source.Cells.Count+" batches="+source.Plans.Count+" epoch="+epoch+" revision="+revision+" cpu_cache="+Jobs.CacheBytes+" gpu_reserved="+gpuBytes);}
 }
 public void Pump(BomSession client){
  FrameUploadMilliseconds=FrameSourceReadMilliseconds=0;
  if(disposed||!enabled||session!=client.Sample.connection_generation||epoch!=client.Sample.epoch||(client.Sample.flags&6)!=6)return;
  if(!testGateReleased&&!string.IsNullOrEmpty(testJobGatePath)&&File.Exists(testJobGatePath)){testGate.Ready.Set();testGateReleased=true;}Jobs.Pump();int waiters=Volatile.Read(ref testGate.Waiters);if(waiters>0&&(!reportedGateWaiting||reportedGateSession!=session||reportedGateEpoch!=epoch)){reportedGateSession=session;reportedGateEpoch=epoch;Debug.Log("BOM SOURCE JOB GATE WAIT epoch="+epoch+" session="+session+" waiters="+waiters);reportedGateWaiting=true;}if(waiters==0)reportedGateWaiting=false;if(Jobs.StaleResults!=reportedStaleDrops){reportedStaleDrops=Jobs.StaleResults;Debug.Log("BOM SOURCE STALE DROP count="+reportedStaleDrops+" applies="+StaleApplications+" epoch="+epoch+" session="+session);}while(Jobs.TryDequeue(out _)){}
  long start=Stopwatch.GetTimestamp();var ordered=sourceOrder;if(sourceOrderDirty){ordered.Clear();ordered.AddRange(sources.Values);ordered.Sort((a,b)=>a.Id.CompareTo(b.Id));sourceOrderDirty=false;}
  for(int n=0;n<ordered.Count&&Milliseconds(start)<1.5;n++){
   var source=ordered[(sourceCursor+n)%ordered.Count];if(source.Cells.Count==0)continue;if(source.Mode=="intact"||source.Mode=="fragments")continue;if(!Prepare(source))continue;Palette(source);if(source.RenderFailure!=null){Warn(source,source.RenderFailure);continue;}
   if(!source.Intact&&source.Plans==null&&!PrepareCells(source))continue;if(!MakePlans(source))continue;
   while(source.PlanCursor<source.Plans.Count&&Milliseconds(start)<1.5){if(Upload(source,source.Plans[source.PlanCursor]))source.PlanCursor++;else break;}
   if(source.RenderFailure!=null){string reason=source.RenderFailure;ClearPlans(source);source.RenderFailure=reason;Warn(source,reason);continue;}
   if(source.PlanCursor==source.Plans.Count)Commit(source);
  }
  if(ordered.Count>0)sourceCursor=(sourceCursor+1)%ordered.Count;IntactSources=FragmentSources=FallbackSources=0;foreach(var source in sources.Values){if(source.Cells.Count==0)continue;if(source.Mode=="intact")IntactSources++;else if(source.Mode=="fragments")FragmentSources++;else FallbackSources++;}
 }
 public void Dispose(){if(disposed)return;Clear();disposed=true;foreach(var record in gpu.Values)foreach(var mesh in record.Meshes)Destroy(mesh);gpu.Clear();gpuBytes=0;Jobs.Dispose();var gate=testGate;Jobs.Drained.ContinueWith(_=>gate.Ready.Dispose());}
}
}
