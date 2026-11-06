using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using Bom.Native;

static class Program {
 static void Check(bool value,string description) { if(!value) throw new Exception(description); }
 static void Ok(uint code,string description) { Check(code==0,$"{description}: status {code}"); }
 static double Now => (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static ulong Create() {
  var info=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};ulong handle=0;
  Ok(BomNative.bom_client_create(ref info,ref handle),"create");return handle;
 }
 static void Connect(ulong handle,uint port,string token="") {
  IntPtr memory=IntPtr.Zero;
  try {
   if(token.Length>0)memory=Marshal.StringToCoTaskMemUTF8(token);
   var info=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=memory,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(token)};
   Ok(BomNative.bom_client_connect(handle,ref info),"connect");
  } finally { if(memory!=IntPtr.Zero)Marshal.FreeCoTaskMem(memory); }
 }
 static T Read<T>(IntPtr pointer,uint index) where T:struct => Marshal.PtrToStructure<T>(IntPtr.Add(pointer,checked((int)index*Marshal.SizeOf<T>())));
 static void Layouts() {
  Type[] types={typeof(BomCreateInfo),typeof(BomConnectInfo),typeof(BomVertex),typeof(BomCell),typeof(BomPose),typeof(BomEvent),typeof(BomSample),typeof(BomBuildInfo),typeof(BomStats),typeof(BomError),typeof(BomHostCommand),typeof(BomCommandResult)};
  for(uint i=0;i<types.Length;i++) {
   Type type=types[i];Check((uint)Marshal.SizeOf(type)==BomNative.bom_debug_layout(i,0),type.Name+" sizeof");
   FieldInfo[] fields=type.GetFields(BindingFlags.Public|BindingFlags.Instance);
   uint alignment=(uint)fields.Max(f=>Math.Min(8,Marshal.SizeOf(f.FieldType)));
   Check(alignment==BomNative.bom_debug_layout(i,1),type.Name+" alignment");
   for(uint j=0;j<fields.Length;j++)Check((uint)Marshal.OffsetOf(type,fields[j].Name)==BomNative.bom_debug_layout(i,j+2),type.Name+"."+fields[j].Name);
  }
  Check(BomNative.bom_debug_layout(999,0)==uint.MaxValue,"unknown layout rejected");
 }
 static void Lifetimes() {
  for(int i=0;i<100;i++) {
   ulong a=Create(),b=Create();Check(a!=b,"independent handles");Ok(BomNative.bom_client_destroy(a),"destroy");
   Check(BomNative.bom_client_update(a,Now)==1,"stale handle rejected");
   ulong replacement=Create();Check(a!=replacement,"generation changed");Ok(BomNative.bom_client_destroy(b),"second destroy");Ok(BomNative.bom_client_destroy(replacement),"replacement destroy");
  }
  ulong handle=Create();
  try {
   Check(Task.Run(()=>BomNative.bom_client_update(handle,0)).Result==4,"wrong owner thread rejected");
   var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};
   Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"empty sample");
   Check(BomNative.bom_client_destroy(handle)==3,"destroy while acquired is BUSY");
   Check(BomNative.bom_client_update(handle,Now)==3,"update while acquired is BUSY");
   Check(BomNative.bom_client_disconnect(handle)==3,"disconnect while acquired is BUSY");
   Check(BomNative.bom_client_release_sample(handle,sample.sample_sequence+1)==2,"bad sample sequence rejected");
   var stats=new BomStats{struct_size=(uint)Marshal.SizeOf<BomStats>(),version=1};
   Ok(BomNative.bom_client_get_stats(handle,ref stats),"stats while acquired");
   var error=new BomError{struct_size=(uint)Marshal.SizeOf<BomError>(),version=1};
   Ok(BomNative.bom_client_last_error(handle,ref error),"last error while acquired");
   Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"release");
   Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"ack");
  } finally { Ok(BomNative.bom_client_destroy(handle),"final destroy"); }
 }
 static void RunSingleHost(uint port,double seconds,double resetAfter) {
  ulong handle=Create();bool ready=false,reset=false,firstBlast=false,secondBlast=false;double start=Now;
  try {
   Connect(handle,port,Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"");
   while(Now-start<seconds) {
    double now=Now,elapsed=now-start;Ok(BomNative.bom_client_update(handle,now),"single host update");
    var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"single host acquire");
    try {if(sample.error_length>0)throw new Exception(Marshal.PtrToStringUTF8(sample.error_text,(int)sample.error_length));if((sample.flags&3)==3)ready=true;}
    finally {Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"single host release");}
    Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"single host ack");
    if(ready&&elapsed>3&&!firstBlast){Ok(BomNative.bom_client_enqueue_action(handle,now,-6.4f,2.3f),"host first blast");firstBlast=true;}
    if(ready&&elapsed>10&&!secondBlast){Ok(BomNative.bom_client_enqueue_action(handle,now,0,0.5f),"host second blast");secondBlast=true;}
    if(ready&&elapsed>resetAfter&&!reset){Ok(BomNative.bom_client_host_command(handle,1,0,0),"single host reset");reset=true;}
    Thread.Sleep(5);
   }
   Check(ready,"single host received baseline");Console.WriteLine("PASS single real native host");
  } finally {Ok(BomNative.bom_client_destroy(handle),"single host destroy");}
 }
 static void Main(string[] args) {
  var identity=new BomBuildInfo{struct_size=(uint)Marshal.SizeOf<BomBuildInfo>(),version=1};Ok(BomNative.bom_build_info(ref identity),"build identity");
  Check(identity.abi_major==1 && identity.source_build_tag==BomNative.bom_build_tag(),"native identity matches ABI");
  string expected=Environment.GetEnvironmentVariable("BOM_EXPECT_BUILD_TAG");if(!string.IsNullOrEmpty(expected))Check(ulong.Parse(expected)==identity.source_build_tag,"loaded DLL source identity");
  Console.WriteLine($"NATIVE ID tag={identity.source_build_tag} protocol={identity.game_protocol} canonical={identity.canonical_version} compiler={Marshal.PtrToStringUTF8(identity.compiler_version,(int)identity.compiler_version_length)}:{Marshal.PtrToStringUTF8(identity.compiler_hash,(int)identity.compiler_hash_length)}");
  Layouts();Lifetimes();Console.WriteLine("PASS ABI layouts/offsets, owner thread, BUSY sample, 100 lifecycle cycles, stale handles");
  if(args.Length==0)return;
  uint port=uint.Parse(args[0]);double seconds=args.Length>1?double.Parse(args[1]):20;double resetAfter=args.Length>2?double.Parse(args[2]):5;
  if(args.Length>3&&args[3]=="single"){RunSingleHost(port,seconds,resetAfter);return;}
  ulong[] handles={Create(),Create()};ulong[] epochs={0,0},revisions={ulong.MaxValue,ulong.MaxValue};bool[] ready={false,false};
  ulong[] maxGeneration={0,0};int snapshots=0,events=0;var seen=new HashSet<(int,ulong,uint,ulong)>();
  bool reset=false,reconnected=false,jumped=false,blasted=false;ulong hostRequest=0,guestRequest=0;bool hostResult=false,guestResult=false;double started=Now,lastReport=started;
  try {
   Connect(handles[0],port,Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"");Connect(handles[1],port);
   while(Now-started<seconds) {
    double now=Now,elapsed=now-started;
    for(int i=0;i<handles.Length;i++) {
     ulong handle=handles[i];float move=i==0?(elapsed%4<2?1:-1):0;
     Ok(BomNative.bom_client_set_held_input(handle,now,move),"held input");
     if(i==0 && elapsed>2 && !jumped){Ok(BomNative.bom_client_enqueue_jump(handle,now),"jump");jumped=true;}
     if(i==0 && elapsed>3 && !blasted){Ok(BomNative.bom_client_enqueue_action(handle,now,-6.4f,2.3f),"action");blasted=true;}
     Ok(BomNative.bom_client_update(handle,now),"update");
     var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"acquire");
     try {
      Check(sample.cell_count<100000 && sample.vertex_count<1000000 && sample.pose_count<100000,"bounded sample counts");
      if(sample.error_length>0)throw new Exception(Marshal.PtrToStringUTF8(sample.error_text,(int)sample.error_length));
      if((sample.flags&3)==3) {
       ready[i]=true;maxGeneration[i]=Math.Max(maxGeneration[i],sample.connection_generation);
       Check(sample.cell_count>0,"live baseline has cells");
       if(epochs[i]!=sample.epoch || revisions[i]!=sample.revision) {
        var ids=new HashSet<ulong>();
        for(uint cellIndex=0;cellIndex<sample.cell_count;cellIndex++) {
         var cell=Read<BomCell>(sample.cells,cellIndex);Check(ids.Add(cell.id),"unique full-width cell ids");
         Check((ulong)cell.vertex_start+cell.vertex_count<=sample.vertex_count && cell.vertex_count>=3,"valid outline span");
        }
        for(uint vertexIndex=0;vertexIndex<sample.vertex_count;vertexIndex++) {
         var vertex=Read<BomVertex>(sample.vertices,vertexIndex);Check(float.IsFinite(vertex.x)&&float.IsFinite(vertex.y),"finite rest geometry");
        }
        epochs[i]=sample.epoch;revisions[i]=sample.revision;snapshots++;
        Console.WriteLine($"HASH client={i} generation={sample.connection_generation} epoch={sample.epoch} revision={sample.revision} hash={sample.canonical_hash}");
       }
       for(uint poseIndex=0;poseIndex<sample.pose_count;poseIndex++) {
        var pose=Read<BomPose>(sample.poses,poseIndex);Check(float.IsFinite(pose.x)&&float.IsFinite(pose.y)&&float.IsFinite(pose.angle),"finite native poses");
       }
       for(uint eventIndex=0;eventIndex<sample.event_count;eventIndex++) {
        var e=Read<BomEvent>(sample.events,eventIndex);Check(seen.Add((i,sample.connection_generation,sample.epoch,e.id)),"acknowledged event did not replay");events++;
       }
      }
     } finally { Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"release"); }
     Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"ack copied sample");
    }
    if(elapsed>1 && ready.All(x=>x) && guestRequest==0) {
     var command=new BomHostCommand{struct_size=(uint)Marshal.SizeOf<BomHostCommand>(),version=1,op=1};
     Ok(BomNative.bom_client_request_host_command(handles[1],ref command,ref guestRequest),"guest request sent to authorization path");
     ulong duplicate=0;Check(BomNative.bom_client_request_host_command(handles[1],ref command,ref duplicate)==3,"second outstanding command is BUSY");
    }
    if(elapsed>1.5 && ready.All(x=>x) && hostRequest==0 && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN"))) {
     var command=new BomHostCommand{struct_size=(uint)Marshal.SizeOf<BomHostCommand>(),version=1,op=3,radius=2.4f};
     Ok(BomNative.bom_client_request_host_command(handles[0],ref command,ref hostRequest),"host radius request");
    }
    for(int i=0;i<2;i++) {
     var result=new BomCommandResult{struct_size=(uint)Marshal.SizeOf<BomCommandResult>(),version=1};Ok(BomNative.bom_client_get_command_result(handles[i],ref result),"command result");
     if(i==0 && hostRequest!=0 && result.command_id==hostRequest && result.status>=2){Check(result.status==2,"host command accepted by server");hostResult=true;}
     if(i==1 && guestRequest!=0 && result.command_id==guestRequest && result.status>=2){Check(result.status==3 && result.reason_length>0,"guest command rejected by server with reason");guestResult=true;}
    }
    if(elapsed>resetAfter && ready.All(x=>x) && !reset && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN"))) { Ok(BomNative.bom_client_host_command(handles[0],1,0,0),"host reset");reset=true; }
    if(elapsed>8 && !reconnected) { Ok(BomNative.bom_client_disconnect(handles[1]),"disconnect guest");Connect(handles[1],port);reconnected=true; }
    if(now-lastReport>10){Console.WriteLine($"LIVE seconds={elapsed:F1} snapshots={snapshots} events={events}");lastReport=now;}
    Thread.Sleep(5);
   }
   Check(ready.All(x=>x),"both actual native clients received baselines");Check(snapshots>=2,"topology samples copied");
   if(seconds>10 && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")))Check(hostResult&&guestResult,"server authorization results correlate to native request IDs");
   if(seconds>10)Check(events>0,"actual native explosion events were copied and acknowledged");
   if(seconds>10)Check(maxGeneration[1]>=2,"guest reconnected with a new generation");
   Console.WriteLine($"PASS real native clients seconds={seconds} snapshots={snapshots} events={events} reset={reset} reconnect={reconnected}");
  } finally { foreach(ulong handle in handles)Ok(BomNative.bom_client_destroy(handle),"dispose native session"); }
 }
}
