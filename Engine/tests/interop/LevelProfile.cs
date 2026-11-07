using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;

static class LevelProfile {
 static double Now=>(double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Check(bool value,string text){if(!value)throw new InvalidOperationException(text);}
 static void Ok(uint code,string text)=>Check(code==0,text+": "+code);
 static string Env(string key)=>Environment.GetEnvironmentVariable(key)??"";
 static string Hash(ulong a,ulong b,ulong c,ulong d){var bytes=new byte[32];Buffer.BlockCopy(new[]{a,b,c,d},0,bytes,0,32);return Convert.ToHexString(bytes).ToLowerInvariant();}
 public static void Run(uint port,double seconds){
  ulong handle=0;var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};Ok(BomNative.bom_client_create(ref create,ref handle),"create level host");
  IntPtr token=IntPtr.Zero,manifest=IntPtr.Zero;double started=Now,measurement=0,lateAt=0,lastReport=started;bool ready=false,blasted=false,reset=false,resetAccepted=false,actionAccepted=false;int samples=0,events=0,predicted=0,conservative=0,maxCells=0;ulong cursor=0;
  var epochs=new HashSet<uint>();var revisions=new HashSet<(uint,ulong)>();var eventIds=new HashSet<ulong>();var reasons=new Dictionary<uint,int>();
  try{
   string expected=Env("BOM_EXPECT_LEVEL_HASH");byte[] hash=Convert.FromHexString(expected);Check(hash.Length==32,"level expectation length");manifest=Marshal.AllocHGlobal(32);Marshal.Copy(hash,0,manifest,32);Ok(BomNative.bom_client_expect_gameplay_manifest(handle,manifest,32),"configure level expectation");
   string secret=Env("BOM_TEST_HOST_TOKEN");token=Marshal.StringToCoTaskMemUTF8(secret);var connect=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=token,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(secret)};Ok(BomNative.bom_client_connect(handle,ref connect),"connect level host");
   while(true){
    double now=Now,elapsed=measurement==0?0:now-measurement;if(now-started>240+seconds)throw new TimeoutException("Level live scenario exceeded readiness/late-join budget");
    if(ready&&measurement==0&&File.Exists(Env("BOM_LEVEL_START_FILE"))){measurement=now;Console.WriteLine("LEVEL HOST START");}
    float held=measurement==0?0:(elapsed%4<2?.1f:-.1f);Ok(BomNative.bom_client_set_held_input(handle,now,held),"level held");
    if(measurement!=0&&elapsed>5&&!blasted){Ok(BomNative.bom_client_enqueue_action(handle,now,-12,7.25f),"level blast");blasted=true;}
    if(measurement!=0&&lateAt==0&&File.Exists(Env("BOM_LEVEL_LATE_READY_FILE"))){lateAt=now;Console.WriteLine("LEVEL LATE JOIN READY");}
    if(lateAt!=0&&now-lateAt>5&&!reset){Ok(BomNative.bom_client_host_command(handle,1,0,0),"level reset");reset=true;}
    Ok(BomNative.bom_client_update(handle,now),"level update");
    var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"level sample");
    try{
     if((sample.flags&6)==6){
      var catalog=new BomCatalogInfo{struct_size=(uint)Marshal.SizeOf<BomCatalogInfo>(),version=1};Ok(BomNative.bom_client_acquire_catalog(handle,sample.sample_sequence,ref catalog),"level catalog");
      Check(catalog.flags==1&&catalog.epoch==sample.epoch&&catalog.binding_count==sample.cell_count&&catalog.source_count==16,"coherent exported yard catalog");
      Check(Hash(catalog.gameplay_hash0,catalog.gameplay_hash1,catalog.gameplay_hash2,catalog.gameplay_hash3)==expected,"actual authoritative level/config identity");
      for(int i=0;i<catalog.binding_count;i++){var binding=Marshal.PtrToStructure<BomCellBinding>(IntPtr.Add(catalog.bindings,checked(i*Marshal.SizeOf<BomCellBinding>())));Check(binding.source_identity>9007199254740992UL&&binding.source_part_id!=0,"exact source/part IDs on every live cell");}
      maxCells=Math.Max(maxCells,(int)sample.cell_count);epochs.Add(sample.epoch);revisions.Add((sample.epoch,sample.revision));samples++;
      for(int i=0;i<sample.event_count;i++){var e=Marshal.PtrToStructure<BomEvent>(IntPtr.Add(sample.events,checked(i*Marshal.SizeOf<BomEvent>())));if(eventIds.Add(e.id))events++;}
      if(!ready){ready=true;Console.WriteLine("LEVEL HOST READY cells="+sample.cell_count+" sources="+catalog.source_count+" epoch="+sample.epoch+" revision="+sample.revision);}
     }
    }finally{Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"release level sample");}
    Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"ack level sample");
    var stats=new BomPredictionStats{struct_size=(uint)Marshal.SizeOf<BomPredictionStats>(),version=1};Ok(BomNative.bom_client_get_prediction_stats(handle,ref stats),"level prediction stats");if(stats.status==1)predicted++;if(stats.status==2){conservative++;reasons.TryGetValue(stats.reason,out int count);reasons[stats.reason]=count+1;}Check(stats.pending_commands<=256,"bounded level command backlog");
    for(int i=0;i<1024;i++){var result=new BomRequestResult{struct_size=(uint)Marshal.SizeOf<BomRequestResult>(),version=1};Ok(BomNative.bom_client_next_request_result(handle,cursor,ref result),"level request result");if((result.flags&1)==0)break;cursor=result.request_id;Console.WriteLine("LEVEL REQUEST kind="+result.kind+" status="+result.status+" id="+result.request_id+" effect="+result.effect_tick);if(result.kind==1&&result.status==1)actionAccepted=true;}
    if(reset&&!resetAccepted){var result=new BomCommandResult{struct_size=(uint)Marshal.SizeOf<BomCommandResult>(),version=1};Ok(BomNative.bom_client_get_command_result(handle,ref result),"level reset result");if(result.status>=2){Check(result.status==2,"level reset authorized");resetAccepted=true;}}
    if(now-lastReport>=10){Console.WriteLine("LEVEL progress="+elapsed.ToString("F1",System.Globalization.CultureInfo.InvariantCulture)+" cells="+sample.cell_count+" prediction="+stats.status+" reason="+stats.reason+" pending="+stats.pending_commands);lastReport=now;}
    if(lateAt!=0&&now-lateAt>=seconds)break;Thread.Sleep(1);
   }
   Check(samples>10&&maxCells>=4000&&epochs.Count>=2&&revisions.Count>=3&&events>0&&actionAccepted&&resetAccepted&&predicted>0,"level baseline/fracture/reset/prediction gates");
   Console.WriteLine("LEVEL_RESULT "+System.Text.Json.JsonSerializer.Serialize(new{status="passed",samples,maxCells,epochs=epochs.Count,revisions=revisions.Count,events,actionAccepted,resetAccepted,predicted,conservative,conservativeReasons=reasons}));
   File.WriteAllText(Env("BOM_LEVEL_STOP_FILE"),"complete\n");
  }finally{if(token!=IntPtr.Zero)Marshal.FreeCoTaskMem(token);if(manifest!=IntPtr.Zero)Marshal.FreeHGlobal(manifest);Ok(BomNative.bom_client_destroy(handle),"destroy level host");}
 }
}
