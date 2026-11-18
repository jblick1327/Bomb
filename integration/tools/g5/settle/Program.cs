using System.Diagnostics;
using System.Runtime.InteropServices;
using Bom.Native;
// usage: Settle <port> <seconds> <spectator 0/1> <hostToken or ""> [startRound 0/1]
static class P {
 static double Now=>(double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 static void Ok(uint c,string n){if(c!=0)throw new Exception(n+" status="+c);}
 static void Main(string[] a){
  uint port=uint.Parse(a[0]);double seconds=double.Parse(a[1]);bool spectator=a[2]=="1";string key=a[3];bool startRound=a.Length>4&&a[4]=="1";
  var create=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};ulong h=0;Ok(BomNative.bom_client_create(ref create,ref h),"create");
  Ok(BomNative.bom_client_set_prediction(h,0),"pred");
  if(spectator)Ok(BomNative.bom_client_set_join_options(h,1),"spectator");
  IntPtr tok=Marshal.StringToCoTaskMemUTF8(key);
  var info=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=0x7f000001,port=port,token=tok,token_length=(uint)System.Text.Encoding.UTF8.GetByteCount(key)};Ok(BomNative.bom_client_connect(h,ref info),"connect");
  double start=Now,lastPrint=-10;var first=new Dictionary<ulong,(float x,float y,float ang)>();bool cmdSent=false;uint lastState=uint.MaxValue;
  while(Now-start<seconds){
   Ok(BomNative.bom_client_update(h,Now),"update");var s=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Ok(BomNative.bom_client_acquire_sample(h,ref s),"acquire");
   var round=new BomRoundInfo{struct_size=(uint)Marshal.SizeOf<BomRoundInfo>(),version=1};
   try{
    if(s.error_length>0)throw new Exception(Marshal.PtrToStringUTF8(s.error_text,(int)s.error_length));
    BomNative.bom_client_get_round(h,s.sample_sequence,ref round);
    double t=Now-start;
    if(!cmdSent&&startRound&&t>3){Ok(BomNative.bom_client_host_command(h,5,1,0),"mode");cmdSent=true;Console.WriteLine("t="+t.ToString("F1")+" host cmd select elimination");}
    if(round.state!=lastState){lastState=round.state;Console.WriteLine($"t={t:F1} round state={round.state} mode={round.mode} id={round.round_id} tick={round.tick}");}
    if(s.event_count>0){for(int i=0;i<s.event_count;i++){var e=Marshal.PtrToStructure<BomEvent>(s.events+i*Marshal.SizeOf<BomEvent>());Console.WriteLine($"t={t:F2} EVENT kind={e.kind} id={e.id} tick={e.tick} ({e.x:F2},{e.y:F2}) r={e.radius:F2}");}}
    if(t-lastPrint>=(t<10?0.5:3)&&s.pose_count>0){
     lastPrint=t;double maxd=0;ulong maxId=0;string line="";int moved=0;
     for(int i=0;i<s.pose_count;i++){
      var p=Marshal.PtrToStructure<BomPose>(s.poses+i*Marshal.SizeOf<BomPose>());
      if(!first.ContainsKey(p.id))first[p.id]=(p.x,p.y,p.angle);
      var f=first[p.id];double d=Math.Sqrt((p.x-f.x)*(p.x-f.x)+(p.y-f.y)*(p.y-f.y));double da=Math.Abs(p.angle-f.ang);
      if(p.kind==0&&(d>0.05||da>0.05))moved++;
      if(p.kind==0&&d>maxd){maxd=d;maxId=p.id;}
      if((t<3||d>0.05||da>0.05)&&(p.kind!=0||t<3||d>0.05))line+=$" [{p.id%1000:D3} k{p.kind} ({p.x:F2},{p.y:F2}) a={p.angle:F2} d={d:F2}]";
     }
     Console.WriteLine($"t={t:F1} rev={s.revision} poses={s.pose_count} cells={s.cell_count} moved={moved} maxd={maxd:F2}({maxId%1000:D3}){line}");
    }
   }finally{BomNative.bom_client_release_sample(h,s.sample_sequence);}
   BomNative.bom_client_ack_sample(h,s.sample_sequence);
   Thread.Sleep(3);
  }
  BomNative.bom_client_destroy(h);
 }
}
