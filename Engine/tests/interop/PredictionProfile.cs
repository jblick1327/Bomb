using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;

static class PredictionProfile {
 static double Now => (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Check(bool value,string text){if(!value)throw new Exception(text);}
 static void Ok(uint code,string text)=>Check(code==0,text+": "+code);
 static double Quantile(List<double> values,double fraction){if(values.Count==0)return 0;values.Sort();return values[Math.Clamp((int)Math.Ceiling(values.Count*fraction)-1,0,values.Count-1)];}
 public static void Run(uint port,double seconds){
  int fps=int.Parse(Environment.GetEnvironmentVariable("BOM_TEST_FPS")??"60");bool enabled=Environment.GetEnvironmentVariable("BOM_TEST_PREDICTION")!="0";
  var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};ulong handle=0;Ok(BomNative.bom_client_create(ref create,ref handle),"create profile");
  IntPtr token=IntPtr.Zero;double started=Now,measurement=0,readyAt=0,next=started,lastReport=started;float held=float.NaN,lastX=0,motionOrigin=0;bool hasPosition=false,awaitMotion=false;double inputAt=0;int predictedFrames=0,fallbackFrames=0,frames=0,expiredResponses=0;var latencies=new List<double>();
  var stats=new BomPredictionStats{struct_size=(uint)Marshal.SizeOf<BomPredictionStats>(),version=1};
  try {
   Ok(BomNative.bom_client_set_prediction(handle,enabled?1u:0u),"profile prediction switch");
   string secret=Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"";if(secret.Length>0)token=Marshal.StringToCoTaskMemUTF8(secret);
   var connect=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=token,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(secret)};
   Ok(BomNative.bom_client_connect(handle,ref connect),"connect profile");int lastJump=-1;
   while(true){
    double now=Now;if(now<next){Thread.Sleep(1);continue;}next+=1.0/fps;if(now-next>0.05)next=now;
    if(measurement==0&&now-started>45)throw new TimeoutException("Static prediction did not become ready");
    double elapsed=measurement==0?0:now-measurement;
    if(measurement!=0&&elapsed>=seconds)break;
    float requested=measurement==0?0:(elapsed%4<1?1:elapsed%4<2?0:elapsed%4<3?-1:0);
    if(requested!=held){
     if(awaitMotion){expiredResponses++;awaitMotion=false;}
     held=requested;
     if(requested!=0&&hasPosition){awaitMotion=true;motionOrigin=lastX;inputAt=now;}
    }
    Ok(BomNative.bom_client_set_held_input(handle,now,requested),"profile held snapshot");
    int jump=(int)(elapsed/4);
    if(measurement!=0&&elapsed%4>.5&&elapsed%4<1&&jump!=lastJump){Ok(BomNative.bom_client_enqueue_jump(handle,now),"profile jump");lastJump=jump;}
    Ok(BomNative.bom_client_update(handle,now),"profile update");
    var owner=new BomOwnerState{struct_size=(uint)Marshal.SizeOf<BomOwnerState>(),version=1};Ok(BomNative.bom_client_get_owner_state(handle,ref owner),"profile owner");
    Ok(BomNative.bom_client_get_prediction_stats(handle,ref stats),"profile stats");
    var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"profile sample");
    try {
     for(uint i=0;i<sample.pose_count;i++){
      var pose=Marshal.PtrToStructure<BomPose>(IntPtr.Add(sample.poses,checked((int)i*Marshal.SizeOf<BomPose>())));
      if(pose.kind!=2||pose.id!=sample.local_player_id)continue;
      Check(float.IsFinite(pose.x)&&float.IsFinite(pose.y),"finite profile presentation");
      if(awaitMotion&&Math.Abs(pose.x-motionOrigin)>.0001){latencies.Add((now-inputAt)*1000);awaitMotion=false;}
      lastX=pose.x;hasPosition=true;
     }
    }finally{Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"release profile");}
    Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"ack profile");
    if(measurement==0&&(owner.flags&3)==3&&(!enabled||stats.status==1)){
     if(readyAt==0)readyAt=now;
     if(now-readyAt>=20){Ok(BomNative.bom_client_reset_prediction_metrics(handle),"start measured prediction window");measurement=now;held=float.NaN;Console.WriteLine("PROFILE READY after clock warmup="+(now-started).ToString("F3",System.Globalization.CultureInfo.InvariantCulture));}
    }
    if(measurement!=0){frames++;if(stats.status==1)predictedFrames++;if(stats.status==2)fallbackFrames++;}
    if(now-lastReport>=10){Console.WriteLine("PROFILE progress="+elapsed.ToString("F2",System.Globalization.CultureInfo.InvariantCulture)+" "+System.Text.Json.JsonSerializer.Serialize(stats,new System.Text.Json.JsonSerializerOptions{IncludeFields=true}));lastReport=now;}
   }
   Ok(BomNative.bom_client_get_prediction_stats(handle,ref stats),"final profile stats");
   double latency95=Quantile(latencies,.95),budget=1000.0/60+1000.0/fps+2;
   bool lossy=Environment.GetEnvironmentVariable("BOM_TEST_LOSSY")=="1";
   var failures=new List<string>();void Require(bool condition,string text){if(!condition)failures.Add(text);}
   Require(measurement!=0&&hasPosition&&stats.pending_commands<=256,"profile readiness/bounded backlog");
   if(enabled){Require(predictedFrames>frames*.9&&stats.conservative_seconds<1,"static fixture must use genuine prediction");Require(stats.correction_count>seconds*10,"enough owner correction samples");Require(stats.correction_p99<=(lossy?.20f:.10f),"p99 correction bound");if(!lossy)Require(stats.correction_p95<=.03f&&stats.snap_count==0,"p95 correction and no static snaps");Require(expiredResponses==0&&latencies.Count>seconds/4&&latency95<=budget,"native presentation response budget");}
   Console.WriteLine("PROFILE_RESULT "+System.Text.Json.JsonSerializer.Serialize(new {status=failures.Count==0?"passed":"failed",failures,seconds,fps,prediction=enabled,warmupSeconds=measurement-started,frames,predictedFrames,fallbackFrames,inputResponseSamples=latencies.Count,inputResponseExpired=expiredResponses,inputToPresentationP95Ms=latency95,inputResponseBudgetMs=budget,stats},new System.Text.Json.JsonSerializerOptions{IncludeFields=true}));
   Check(failures.Count==0,string.Join(", ",failures));
  } finally {if(token!=IntPtr.Zero)Marshal.FreeCoTaskMem(token);Ok(BomNative.bom_client_destroy(handle),"destroy profile");}
 }
}
