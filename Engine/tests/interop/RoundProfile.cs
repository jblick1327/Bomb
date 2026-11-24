using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;

// Diagnostic real-UDP gate. The separate two-Unity M8 gate remains required.
static class RoundProfile {
 static double Now=>(double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Need(bool value,string text){if(!value)throw new Exception(text);}
 static void Ok(uint code,string text)=>Need(code==0,text+" status="+code);
 sealed class Client:IDisposable {
  public ulong Handle;public bool Connected;public BomRoundInfo Round;
  public BomRoundPlayer[] Players=Array.Empty<BomRoundPlayer>();public BomRoundConnection[] Connections=Array.Empty<BomRoundConnection>();
  public bool Baseline;public string Token="";public ulong LastRound,LastTick;
  public Client(bool spectator=false){var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};Ok(BomNative.bom_client_create(ref create,ref Handle),"create round client");Ok(BomNative.bom_client_set_prediction(Handle,0),"diagnostic prediction off");Ok(BomNative.bom_client_set_join_options(Handle,spectator?1u:0u),"join role");}
  public void Connect(uint port){IntPtr token=Marshal.StringToCoTaskMemUTF8(Token);try{var info=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=token,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(Token)};Ok(BomNative.bom_client_connect(Handle,ref info),"connect rounds");Connected=true;Baseline=false;Round=default;LastRound=LastTick=0;}finally{Marshal.FreeCoTaskMem(token);}}
  public void Disconnect(){Ok(BomNative.bom_client_disconnect(Handle),"disconnect rounds");Connected=false;}
  public void Poll(double now){if(!Connected)return;Ok(BomNative.bom_client_update(Handle,now),"round pump");var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(Handle,ref sample),"round acquire");try{
   Need(sample.error_length==0,"native error: "+(sample.error_length>0?Marshal.PtrToStringUTF8(sample.error_text,(int)sample.error_length):""));Baseline=(sample.flags&3)==3;
   var round=new BomRoundInfo{struct_size=(uint)Marshal.SizeOf<BomRoundInfo>(),version=1};Ok(BomNative.bom_client_get_round(Handle,sample.sample_sequence,ref round),"round snapshot");
   if((round.flags&1)!=0){Need((round.player_count==0||(round.player_count>=2&&round.player_count<=4))&&round.connection_count==4,"bounded round roster");Need(round.round_id>=LastRound&&round.tick>=LastTick,"monotonic round stream");LastRound=round.round_id;LastTick=round.tick;Players=Copy<BomRoundPlayer>(round.players,round.player_count);Connections=Copy<BomRoundConnection>(round.connections,round.connection_count);round.players=round.connections=IntPtr.Zero;Round=round;}
  }finally{Ok(BomNative.bom_client_release_sample(Handle,sample.sample_sequence),"round release");}Ok(BomNative.bom_client_ack_sample(Handle,sample.sample_sequence),"round ack");}
  static T[] Copy<T>(IntPtr data,uint count) where T:struct {var result=new T[count];for(int i=0;i<count;i++)result[i]=Marshal.PtrToStructure<T>(IntPtr.Add(data,i*Marshal.SizeOf<T>()));return result;}
  public void Command(uint op,uint mode=0)=>Ok(BomNative.bom_client_host_command(Handle,op,mode,0),"host intent "+op);
  public uint CommandStatus(){var result=new BomCommandResult{struct_size=(uint)Marshal.SizeOf<BomCommandResult>(),version=1};Ok(BomNative.bom_client_get_command_result(Handle,ref result),"command result");return result.status;}
  public BomRoundConnection Profile(ulong id)=>Connections.First(c=>c.session_id==id);
  public bool Rejected(uint kind,uint reason){ulong cursor=0;for(int i=0;i<10;i++){var result=new BomRequestResult{struct_size=(uint)Marshal.SizeOf<BomRequestResult>(),version=1};Ok(BomNative.bom_client_next_request_result(Handle,cursor,ref result),"authority result");if((result.flags&1)==0)break;cursor=result.request_id;if(result.kind==kind&&result.status==2&&result.reason==reason)return true;}return false;}
  public void Dispose(){if(Handle!=0){Ok(BomNative.bom_client_destroy(Handle),"round destroy");Handle=0;}}
 }
 public static void Run(uint port,double seconds){
  using var host=new Client();using var guest=new Client();using var observer=new Client(true);using var late=new Client();
  host.Token=Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"";host.Connect(port);guest.Connect(port);observer.Connect(port);
  int phase=0;double start=Now,at=start;ulong guestId=0,firstTotal=0,secondTotal=0;bool manualRejected=false,manualSent=false,guestRejected=false;ulong firstRound=0;
  while(Now-start<seconds){double now=Now;foreach(var c in new[]{host,guest,observer,late})c.Poll(now);
   if(phase==0&&host.Baseline&&guest.Baseline&&observer.Baseline&&guest.Round.local_session_id!=0&&now-start>1.5){guestId=guest.Round.local_session_id;Ok(BomNative.bom_client_enqueue_action(guest.Handle,now,0,3),"sandbox guest blast intent");phase=100;}
   else if(phase==100&&guest.Rejected(1,1)){guest.Command(5,1);phase=1;}
   else if(phase==1&&guest.CommandStatus()==3){guestRejected=true;host.Command(5,1);phase=2;}
   else if(phase==2&&host.Round.mode==1&&host.Round.state==1){firstRound=host.Round.round_id;guest.Disconnect();phase=3;}
   else if(phase==3&&host.Round.state==0){guest.Connect(port);phase=4;}
   else if(phase==4&&host.Round.state==2&&guest.Round.state==2){Need(guest.Round.local_session_id==guestId,"resume session after countdown interruption");Need((observer.Round.flags&4)!=0,"explicit spectator never joins round");late.Connect(port);guest.Command(1);at=now;phase=5;}
   else if(phase==5){
    Need(host.Round.state==2,"fixture must remain live long enough to test late join and forfeit");
    var owner=new BomOwnerState{struct_size=(uint)Marshal.SizeOf<BomOwnerState>(),version=1};Ok(BomNative.bom_client_get_owner_state(host.Handle,ref owner),"round owner ready");
    if(!manualSent&&(owner.flags&5)==5&&owner.state_tick>=host.Round.start_tick&&now-at>1){Ok(BomNative.bom_client_enqueue_action(host.Handle,now,0,3),"elimination manual blast intent");manualSent=true;}
    ulong cursor=0;for(int n=0;n<10;n++){var result=new BomRequestResult{struct_size=(uint)Marshal.SizeOf<BomRequestResult>(),version=1};Ok(BomNative.bom_client_next_request_result(host.Handle,cursor,ref result),"round action result");if((result.flags&1)==0)break;cursor=result.request_id;if(result.kind==1&&result.status==2&&result.reason==6)manualRejected=true;}
    if(guest.CommandStatus()==3&&late.Baseline&&(late.Round.flags&4)!=0&&manualRejected&&now-at>3){
     // This diagnostic deliberately exercises two-player forfeits again on
     // restart. The separately tested late join must not become player three.
     late.Disconnect();guest.Disconnect();phase=6;
    }
   }
   else if(phase==6&&host.Round.state==3){Need(host.Round.draw==0&&host.Round.winner==host.Round.local_session_id&&host.Round.reason==2,"disconnect resolved as forfeit");firstTotal=host.Profile(host.Round.local_session_id).total_xp;Need(host.Profile(host.Round.local_session_id).wins==1,"server awarded first win once");guest.Connect(port);phase=7;}
   else if(phase==7&&guest.Round.state==3){Need(guest.Round.local_session_id==guestId&&(guest.Round.flags&4)!=0,"reconnect recovers result but stays spectator");Need(guest.Round.winner==host.Round.winner&&observer.Round.winner==host.Round.winner,"observers agree on result");Need(host.Profile(host.Round.local_session_id).total_xp==firstTotal,"repeated result did not duplicate XP");host.Command(1);phase=8;}
   else if(phase==8&&host.Round.round_id==firstRound+1&&host.Round.state==2){Need(guest.Round.local_session_id==guestId,"session retained across restart");at=now;phase=9;}
   else if(phase==9&&now-at>3){Need(host.Round.state==2,"second fixture round still playing");guest.Disconnect();phase=10;}
   else if(phase==10&&host.Round.state==3){Need(host.Profile(host.Round.local_session_id).wins==2,"exactly two server wins");secondTotal=host.Profile(host.Round.local_session_id).total_xp;Need(secondTotal>=firstTotal,"session totals accumulate");at=now;phase=11;}
   else if(phase==11&&now-at>1){Need(host.Profile(host.Round.local_session_id).total_xp==secondTotal,"stable persistent result");Need(guestRejected&&manualRejected,"authority rejection checks");Console.WriteLine($"PASS real UDP round rules rounds=2 interrupted_countdown=1 resumed_session={guestId} late_spectator=1 forfeit=2 manual_rejected=1 guest_host_rejected=1 winner={host.Round.winner} wins=2 xp={secondTotal}");return;}
   Thread.Sleep(2);
  }
  throw new TimeoutException($"round integration phase={phase} host={host.Round.round_id}/{host.Round.state} guest={guest.Round.round_id}/{guest.Round.state}");
 }
 public static void RunFour(uint port,double seconds){
  using var host=new Client();using var second=new Client();using var third=new Client();using var fourth=new Client();
  var clients=new[]{host,second,third,fourth};host.Token=Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"";
  foreach(var client in clients)client.Connect(port);
  double started=Now,finished=0;int phase=0;ulong winner=0,total=0;
  while(Now-started<seconds){double now=Now;foreach(var client in clients)client.Poll(now);
   if(phase==0&&clients.All(c=>c.Baseline&&c.Round.local_session_id!=0)&&now-started>1.5){host.Command(5,1);phase=1;}
   else if(phase==1&&clients.All(c=>c.Round.mode==1&&c.Round.state==2)){
    var expected=clients.Select(c=>c.Round.local_session_id).OrderBy(id=>id).ToArray();
    foreach(var client in clients){Need(client.Players.Length==4,"all four validated ready players admitted");Need(client.Players.Select(p=>p.session_id).OrderBy(id=>id).SequenceEqual(expected),"four-player roster agrees across clients");}
    winner=host.Round.local_session_id;second.Disconnect();third.Disconnect();fourth.Disconnect();phase=2;
   }else if(phase==2&&host.Round.state==3){
    Need(host.Round.winner==winner&&host.Round.draw==0&&host.Round.reason==2,"last of four alive wins by forfeit");
    Need(host.Profile(winner).wins==1,"four-player winner awarded once");total=host.Profile(winner).total_xp;finished=now;phase=3;
   }else if(phase==3&&now-finished>1){Need(host.Profile(winner).total_xp==total&&host.Profile(winner).wins==1,"four-player persistent result is idempotent");Console.WriteLine($"PASS real UDP four-player round roster=4 last_alive_wins=1 exactly_once_award=1 winner={winner}");return;}
   Thread.Sleep(2);
  }
  throw new TimeoutException($"four-player integration phase={phase} round={host.Round.round_id}/{host.Round.state} roster={host.Players.Length}");
 }
}
