using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;

static class RoundUnityHost {
 static double Now=>(double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Ok(uint code,string name){if(code!=0)throw new Exception(name+" native status="+code);}
 public static void Run(uint port,double seconds){
  string folder=Environment.GetEnvironmentVariable("BOM_ROUND_SIGNAL_DIR")??throw new Exception("round signal directory required");
  bool Marked(string role,string stage)=>File.Exists(Path.Combine(folder,role+"-"+stage+".signal"));
  var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};ulong handle=0;Ok(BomNative.bom_client_create(ref create,ref handle),"round host create");
  try{
   Ok(BomNative.bom_client_set_prediction(handle,0),"round host prediction");Ok(BomNative.bom_client_set_join_options(handle,1),"round host spectator");
   string key=Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"";IntPtr token=Marshal.StringToCoTaskMemUTF8(key);
   try{var info=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=token,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(key)};Ok(BomNative.bom_client_connect(handle,ref info),"round host connect");}finally{Marshal.FreeCoTaskMem(token);}
   bool mode=false,restarted=false,interrupted=false;ulong first=0,lastRound=0;uint lastState=uint.MaxValue;double start=Now;
   while(Now-start<seconds){
    Ok(BomNative.bom_client_update(handle,Now),"round host poll");var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(handle,ref sample),"round host sample");
    var round=new BomRoundInfo{struct_size=(uint)Marshal.SizeOf<BomRoundInfo>(),version=1};
    try{if(sample.error_length>0)throw new Exception(Marshal.PtrToStringUTF8(sample.error_text,(int)sample.error_length));Ok(BomNative.bom_client_get_round(handle,sample.sample_sequence,ref round),"round host view");}
    finally{Ok(BomNative.bom_client_release_sample(handle,sample.sample_sequence),"round host release");}
    Ok(BomNative.bom_client_ack_sample(handle,sample.sample_sequence),"round host ack");
    if((round.flags&1)!=0&&(round.round_id!=lastRound||round.state!=lastState)){
     lastRound=round.round_id;lastState=round.state;Console.WriteLine($"ROUND HOST round={round.round_id} state={round.state} tick={round.tick} winner={round.winner} draw={round.draw}");
    }
    if(!mode&&Marked("primary","ready")&&Marked("guest","ready")){Ok(BomNative.bom_client_host_command(handle,5,1,0),"select elimination");mode=true;}
    if(mode&&round.mode==1&&first==0)first=round.round_id;
    if(first!=0&&round.round_id==first&&round.state==0&&Marked("guest","interrupted"))interrupted=true;
    if(first!=0&&round.round_id==first&&round.state==3&&Marked("primary","finished-"+first)&&Marked("guest","finished-"+first)&&!restarted){
     if(!interrupted||round.winner==0||round.draw!=0)throw new Exception("first round did not demonstrate countdown interruption and forfeit");
     Ok(BomNative.bom_client_host_command(handle,1,0,0),"host restart");restarted=true;
    }
    if(restarted&&round.round_id==first+1&&round.state==3&&Marked("primary","passed")&&Marked("guest","passed")){
     Console.WriteLine($"PASS two Unity rounds host observer round={round.round_id} winner={round.winner} interrupted_countdown=1 authorized_restart=1");return;
    }
    Thread.Sleep(3);
   }
   throw new TimeoutException($"Unity round host timed out: round={lastRound} state={lastState} modeRequested={mode} restarted={restarted}");
  }finally{Ok(BomNative.bom_client_destroy(handle),"round host destroy");}
 }
}
