using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;

static class PerformanceHost {
 static double Now=>(double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Ok(uint result,string action){if(result!=0)throw new Exception(action+" status="+result);}
 static void Main(string[] args){
  uint port=uint.Parse(args[0]);double seconds=double.Parse(args[1],System.Globalization.CultureInfo.InvariantCulture);ulong handle=0;
  var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};Ok(BomNative.bom_client_create(ref create,ref handle),"create");
  try{
   Ok(BomNative.bom_client_set_prediction(handle,0),"prediction");Ok(BomNative.bom_client_set_join_options(handle,1),"spectator");
   string key=Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??throw new Exception("Host token required");var token=Marshal.StringToCoTaskMemUTF8(key);
   try{var connect=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=token,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(key)};Ok(BomNative.bom_client_connect(handle,ref connect),"connect");}finally{Marshal.FreeCoTaskMem(token);}
   var rng=new Random(int.Parse(Environment.GetEnvironmentVariable("BOM_PERF_SEED")??"42"));double started=Now,lastReset=started,lastBlast=started;uint epoch=0;int resets=0;bool ready=false;ulong cursor=0;string stopFile=Environment.GetEnvironmentVariable("BOM_PERF_STOP_FILE")??"";
   while(Now-started<seconds&&!File.Exists(stopFile)){
    double now=Now;Ok(BomNative.bom_client_update(handle,now),"update");var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"acquire");
    try{
     if(sample.error_length>0)throw new Exception(Marshal.PtrToStringUTF8(sample.error_text,(int)sample.error_length));
     if((sample.flags&6)==6){if(!ready){ready=true;Console.WriteLine("PERF HOST READY");}if(epoch!=sample.epoch){epoch=sample.epoch;Console.WriteLine($"PERF EPOCH elapsed={now-started:F3} epoch={epoch} cells={sample.cell_count} poses={sample.pose_count}");}}
    }finally{Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"release");}
    Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"ack");
    for(int i=0;i<1024;i++){var result=new BomRequestResult{struct_size=(uint)Marshal.SizeOf<BomRequestResult>(),version=1};Ok(BomNative.bom_client_next_request_result(handle,cursor,ref result),"result");if((result.flags&1)==0)break;cursor=result.request_id;Console.WriteLine($"PERF REQUEST id={cursor} kind={result.kind} status={result.status} effect_tick={result.effect_tick} event={result.event_id}");}
    if(ready&&now-lastReset>=10){Ok(BomNative.bom_client_host_command(handle,1,0,0),"reset");lastReset=now;resets++;Console.WriteLine($"PERF RESET requested={resets} elapsed={now-started:F3}");}
    if(ready&&now-lastBlast>=3&&now-lastReset>1){float x=(float)(rng.NextDouble()*20-10);Ok(BomNative.bom_client_enqueue_action(handle,now,x,1),"overlap blast");Ok(BomNative.bom_client_enqueue_action(handle,now,x+.1f,1),"overlap blast two");lastBlast=now;}
    Thread.Sleep(3);
   }
   if(!ready)throw new Exception("No native baseline");Console.WriteLine($"PERF HOST MEASURED resets={resets} epoch={epoch}");
  }finally{Ok(BomNative.bom_client_destroy(handle),"destroy");}
 }
}
