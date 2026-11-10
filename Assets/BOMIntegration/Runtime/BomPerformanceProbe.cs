using System;
using System.Collections.Generic;
using System.Collections;
using System.IO;
using System.Globalization;
using System.Runtime.InteropServices;
using Bom.Native;
using UnityEngine;
using UnityEngine.SceneManagement;
using Unity.Profiling;

namespace Bom.Unity {
[DefaultExecutionOrder(1000)]
public sealed class BomPerformanceProbe:MonoBehaviour {
 [Serializable]public struct Row {
  public double elapsed,frame_ms,cpu_ms,gpu_ms,native_ms,copy_ms,present_ms,geometry_ms,source_read_ms,upload_ms;
  public long copy_gc,present_gc,geometry_gc,frame_gc;
  public ulong native_owned,native_live,revision,connection_generation;public uint epoch,cells,poses,moving,prediction;
  public bool transition,stable_pose;public int pooled_actors,idle_actors;public int source_intact,source_fragments,source_fallback,jobs_active,jobs_pending;public long cache_cpu,cache_gpu,buffers;
 }
 [Serializable]public sealed class Metric {public int samples;public double min,p50,p95,p99,max,mean;}
 [Serializable]sealed class Report {
  public string status="measured",scene,os,cpu,gpu,backend="Mono",native_build_tag;
  public int cpu_threads,system_ram_mb,gpu_ram_mb,width,height,frames,max_cells,max_poses,max_moving;
  public double seconds,warmup_seconds,max_source_read_ms,max_mesh_upload_ms,max_measured_source_read_ms,max_measured_upload_ms;public int max_pooled_actors;
  public Metric native_update,copy,presentation,geometry,cpu_frame,gpu_frame,wall_frame;
  public int stable_pose_frames;public long stable_copy_max_gc,stable_present_max_gc,stable_geometry_max_gc;public bool stable_pose_zero_allocation;
  public long max_copy_gc,max_present_gc,max_geometry_gc,total_frame_gc,thread_api_control_bytes,profiler_control_events;public bool allocation_counter_valid,frame_allocation_counter_valid;public string allocation_counter_method,allocation_counter_unit;
  public long stale_results,stale_applications;public bool resources_drained;public long final_job_buffers,final_cpu_cache,final_gpu_cache;public int final_active_jobs,final_actor_views,final_runtime_meshes;
  public Row[] rows;
 }
 static string Arg(string[] args,string name,string fallback=""){int i=Array.IndexOf(args,name);return i>=0&&i+1<args.Length?args[i+1]:fallback;}
 [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]static void Install(){
  var args=Environment.GetCommandLineArgs();string path=Arg(args,"--bom-perf-out");if(string.IsNullOrEmpty(path))return;
  string target=Arg(args,"--bom-perf-scene");if(target!=""&&target!="PerformanceReference"&&target!="PerformanceStress")throw new InvalidOperationException("Unknown performance scene");
  BomAllocationCounter.Initialize();Application.SetStackTraceLogType(LogType.Log,StackTraceLogType.None);
  var probe=new GameObject("BOM measured performance probe").AddComponent<BomPerformanceProbe>();probe.path=path;probe.seconds=double.Parse(Arg(args,"--bom-perf-seconds","60"),CultureInfo.InvariantCulture);probe.warmup=double.Parse(Arg(args,"--bom-perf-warmup","10"),CultureInfo.InvariantCulture);
  if(probe.seconds<1||probe.seconds>3600||probe.warmup<0||probe.warmup>300)throw new InvalidOperationException("Invalid measurement duration");
  probe.frameAlloc=ProfilerRecorder.StartNew(ProfilerCategory.Memory,"GC Allocated In Frame");probe.rows=new Row[checked((int)Math.Ceiling(probe.seconds*240)+2048)];probe.started=BomSession.Now;QualitySettings.vSyncCount=0;Application.targetFrameRate=int.Parse(Arg(args,"--bom-perf-fps","60"),CultureInfo.InvariantCulture);
  probe.startFile=Arg(args,"--bom-perf-start-file");probe.soak=Array.IndexOf(args,"--bom-soak")>=0;
  if(probe.soak){var driver=probe.gameObject.AddComponent<BomSoakDriver>();driver.Role=Arg(args,"--bom-soak-role","primary");driver.JoinDelay=double.Parse(Arg(args,"--bom-soak-join-delay","0"),CultureInfo.InvariantCulture);}
  DontDestroyOnLoad(probe.gameObject);if(target!=""&&SceneManager.GetActiveScene().name!=target)SceneManager.LoadScene(target);
 }
 string path,startFile;bool soak;double measuredAt=-1,unusableSince=-1;double seconds,warmup,started,readyAt=-1,lastFrame,transitionUntil;long lastGc;int count;uint lastEpoch;bool done;
 ProfilerRecorder frameAlloc;
 void OnDestroy(){if(frameAlloc.Valid)frameAlloc.Dispose();BomAllocationCounter.Dispose();}
 Row[] rows;BomClientBehaviour client;readonly FrameTiming[] timings=new FrameTiming[1];
 readonly Dictionary<(uint,ulong),Vector3> prior=new Dictionary<(uint,ulong),Vector3>();
 void Update(){
  if(soak)return;
  if(client==null)client=FindFirstObjectByType<BomClientBehaviour>();if(client==null||client.Session==null||!client.ConnectionRequested)return;
  client.DrivenByRoundScenario=true;double now=BomSession.Now;
  BomSession.Check(BomNative.bom_client_set_held_input(client.Session.Handle,now,Math.Floor((now-started)/3)%2==0?.2f:-.2f));
 }
 void LateUpdate(){
  if(client==null)client=FindFirstObjectByType<BomClientBehaviour>();
  if(done||rows==null||client==null||client.Session==null||!client.ConnectionRequested)return;double now=BomSession.Now;
  if(!string.IsNullOrEmpty(client.ConnectionError)){Debug.LogError("BOM PERF FAIL "+client.ConnectionError);Application.Quit(5);done=true;return;}
  var session=client.Session;var sample=session.Sample;
  if((sample.flags&6)!=6){if(unusableSince<0)unusableSince=now;if(now-unusableSince>120){Debug.LogError("BOM PERF FAIL no usable baseline");Application.Quit(5);done=true;}return;}
  unusableSince=-1;
  if(readyAt<0){readyAt=now;lastFrame=now;lastGc=GC.GetAllocatedBytesForCurrentThread();Debug.Log("BOM PERF BASELINE READY epoch="+sample.epoch);}
  if(sample.epoch!=lastEpoch){lastEpoch=sample.epoch;transitionUntil=now+1;prior.Clear();}
  FrameTimingManager.CaptureFrameTimings();uint measured=FrameTimingManager.GetLatestTimings(1,timings);
  var stats=new BomStats{struct_size=(uint)Marshal.SizeOf<BomStats>(),version=1};BomSession.Check(BomNative.bom_client_get_stats(session.Handle,ref stats));
  uint moving=0;for(int i=0;i<sample.pose_count;i++){
   var pose=session.Poses[i];if(pose.kind!=0)continue;var key=(pose.kind,pose.id);var value=new Vector3(pose.x,pose.y,pose.angle);
   if(prior.TryGetValue(key,out var old)&&(new Vector2(value.x-old.x,value.y-old.y).sqrMagnitude>.00001f||Mathf.Abs(value.z-old.z)>.001f))moving++;
   prior[key]=value;
  }
  long gc=GC.GetAllocatedBytesForCurrentThread();var source=client.SourcePresentation;
  var row=new Row{elapsed=now-readyAt,frame_ms=(now-lastFrame)*1000,cpu_ms=measured>0?timings[0].cpuFrameTime:-1,gpu_ms=measured>0&&timings[0].gpuFrameTime>0?timings[0].gpuFrameTime:-1,native_ms=session.NativeUpdateMilliseconds,copy_ms=session.CopyMilliseconds,present_ms=client.PresentationMilliseconds,geometry_ms=client.GeometryMilliseconds,copy_gc=session.CopyAllocatedBytes,present_gc=client.PresentationAllocatedBytes,geometry_gc=client.GeometryAllocatedBytes,frame_gc=frameAlloc.Valid?frameAlloc.LastValue:-1,native_owned=stats.owned_bytes,native_live=stats.live_allocations,epoch=sample.epoch,revision=sample.revision,connection_generation=sample.connection_generation,cells=sample.cell_count,poses=sample.pose_count,moving=moving,prediction=session.Prediction.status,transition=now<transitionUntil,stable_pose=now>=transitionUntil&&!client.PresentationHadTopology&&!client.PresentationHadActorChange&&!client.GeometryWorkThisFrame&&sample.event_count==0,pooled_actors=client.PooledActorCount,idle_actors=client.IdleActorCount};
  if(source!=null){row.source_read_ms=source.FrameSourceReadMilliseconds;row.upload_ms=source.FrameUploadMilliseconds;row.source_intact=source.IntactSources;row.source_fragments=source.FragmentSources;row.source_fallback=source.FallbackSources;row.jobs_active=source.Jobs.ActiveCount;row.jobs_pending=source.Jobs.PendingCount;row.cache_cpu=source.Jobs.CacheBytes;row.cache_gpu=source.GpuBytes;row.buffers=source.Jobs.BufferBytes;}
  lastGc=gc;lastFrame=now;
  if(now-readyAt<warmup||(!string.IsNullOrEmpty(startFile)&&!File.Exists(startFile)))return;
  if(measuredAt<0){measuredAt=now;Debug.Log("BOM PERF MEASUREMENT STARTED");}
  if(count==rows.Length){Debug.LogError("BOM PERF FAIL measurement buffer exhausted");Application.Quit(5);done=true;return;}
  rows[count++]=row;if(count==1)ScreenCapture.CaptureScreenshot(Path.ChangeExtension(path,".png"));
  if(now-measuredAt>=seconds)Finish();
 }
 static Metric Quantiles(List<double> values){var result=new Metric{samples=values.Count};if(values.Count==0)return result;values.Sort();double sum=0;foreach(var x in values)sum+=x;result.min=values[0];result.max=values[values.Count-1];result.mean=sum/values.Count;result.p50=values[(int)Math.Ceiling(values.Count*.5)-1];result.p95=values[(int)Math.Ceiling(values.Count*.95)-1];result.p99=values[(int)Math.Ceiling(values.Count*.99)-1];return result;}
 void Finish(){
  done=true;var report=new Report{scene=SceneManager.GetActiveScene().name,os=SystemInfo.operatingSystem,cpu=SystemInfo.processorType,gpu=SystemInfo.graphicsDeviceName,cpu_threads=SystemInfo.processorCount,system_ram_mb=SystemInfo.systemMemorySize,gpu_ram_mb=SystemInfo.graphicsMemorySize,width=Screen.width,height=Screen.height,seconds=seconds,warmup_seconds=warmup,frames=count,native_build_tag=BomNative.bom_build_tag().ToString()};
  report.allocation_counter_valid=BomAllocationCounter.Valid;report.allocation_counter_method=BomAllocationCounter.Method;report.allocation_counter_unit=BomAllocationCounter.Unit;if(!BomAllocationCounter.Valid)report.max_copy_gc=report.max_present_gc=report.max_geometry_gc=-1;report.thread_api_control_bytes=BomAllocationCounter.ThreadApiControlBytes;report.profiler_control_events=BomAllocationCounter.ProfilerControlEvents;report.frame_allocation_counter_valid=frameAlloc.Valid;
  var native=new List<double>();var copy=new List<double>();var present=new List<double>();var geometry=new List<double>();var cpu=new List<double>();var gpu=new List<double>();var wall=new List<double>();
#if ENABLE_IL2CPP
  report.backend="IL2CPP";
#endif
  report.rows=new Row[count];Array.Copy(rows,report.rows,count);
  for(int i=0;i<count;i++){var r=rows[i];report.max_cells=Math.Max(report.max_cells,(int)r.cells);report.max_poses=Math.Max(report.max_poses,(int)r.poses);report.max_moving=Math.Max(report.max_moving,(int)r.moving);if(r.stable_pose){report.stable_pose_frames++;report.stable_copy_max_gc=Math.Max(report.stable_copy_max_gc,r.copy_gc);report.stable_present_max_gc=Math.Max(report.stable_present_max_gc,r.present_gc);report.stable_geometry_max_gc=Math.Max(report.stable_geometry_max_gc,r.geometry_gc);}
   report.total_frame_gc+=r.frame_gc;report.max_measured_source_read_ms=Math.Max(report.max_measured_source_read_ms,r.source_read_ms);report.max_measured_upload_ms=Math.Max(report.max_measured_upload_ms,r.upload_ms);report.max_pooled_actors=Math.Max(report.max_pooled_actors,r.pooled_actors);if(r.cpu_ms>=0)cpu.Add(r.cpu_ms);if(r.gpu_ms>=0)gpu.Add(r.gpu_ms);wall.Add(r.frame_ms);if(r.transition)continue;native.Add(r.native_ms);copy.Add(r.copy_ms);present.Add(r.present_ms);geometry.Add(r.geometry_ms);report.max_copy_gc=Math.Max(report.max_copy_gc,r.copy_gc);report.max_present_gc=Math.Max(report.max_present_gc,r.present_gc);report.max_geometry_gc=Math.Max(report.max_geometry_gc,r.geometry_gc);}
  report.stable_pose_zero_allocation=report.allocation_counter_valid&&report.stable_pose_frames>=300&&report.stable_copy_max_gc==0&&report.stable_present_max_gc==0&&report.stable_geometry_max_gc==0;
  report.native_update=Quantiles(native);report.copy=Quantiles(copy);report.presentation=Quantiles(present);report.geometry=Quantiles(geometry);report.cpu_frame=Quantiles(cpu);report.gpu_frame=Quantiles(gpu);report.wall_frame=Quantiles(wall);
  if(client.SourcePresentation!=null){report.max_source_read_ms=client.SourcePresentation.MaxSourceReadMilliseconds;report.max_mesh_upload_ms=client.SourcePresentation.MaxUploadMilliseconds;}
  StartCoroutine(Shutdown(report));
 }
 IEnumerator Shutdown(Report report){
  var source=client.SourcePresentation;if(source!=null){report.stale_results=source.Jobs.StaleResults;report.stale_applications=source.StaleApplications;}var driver=GetComponent<BomSoakDriver>();if(driver!=null)driver.enabled=false;client.enabled=false;
  double deadline=BomSession.Now+10;
  while(source!=null&&!source.Jobs.Drained.IsCompleted&&BomSession.Now<deadline)yield return null;
  yield return null;yield return null;
  if(source!=null){report.final_job_buffers=source.Jobs.BufferBytes;report.final_cpu_cache=source.Jobs.CacheBytes;report.final_gpu_cache=source.GpuBytes;report.final_active_jobs=source.Jobs.ActiveCount;}
  report.final_actor_views=FindObjectsByType<BomActorView>(FindObjectsInactive.Include,FindObjectsSortMode.None).Length;
  foreach(var mesh in Resources.FindObjectsOfTypeAll<Mesh>())if(mesh.name.StartsWith("BOM source ",StringComparison.Ordinal)||mesh.name=="Native terrain batch")report.final_runtime_meshes++;
  report.resources_drained=client.Session==null&&report.final_job_buffers==0&&report.final_cpu_cache==0&&report.final_gpu_cache==0&&report.final_active_jobs==0&&report.final_actor_views==0&&report.final_runtime_meshes==0;
  if(!report.resources_drained)report.status="resource_failure";
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));File.WriteAllText(path,JsonUtility.ToJson(report,true));Debug.Log("BOM PERF MEASURED frames="+count+" cells="+report.max_cells+" moving="+report.max_moving+" native_p95_ms="+report.native_update.p95+" native_p99_ms="+report.native_update.p99+" resources_drained="+report.resources_drained+" path="+path);Application.Quit(report.resources_drained?0:6);
 }
}
}
