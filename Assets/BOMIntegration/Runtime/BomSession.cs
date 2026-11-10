using System;
using System.Diagnostics;
using System.Reflection;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Bom.Native;

namespace Bom.Unity {
public sealed class BomSourceState {
 public BomSourceBinding Binding;
 public string AssetKey="",CapKey="",VisualHash="";
}
// No managed networking or simulation. All borrowed native memory is copied
// before release; presenters accept the complete snapshot before acknowledgement.
public sealed class BomSession : IDisposable {
 public ulong Handle { get; private set; }
 public BomSample Sample;
 public BomOwnerState Owner;
 public BomPredictionStats Prediction;
 public BomCatalogInfo Catalog;
 public BomRoundInfo Round;
 public BomRoundPlayer[] RoundPlayers=Array.Empty<BomRoundPlayer>();
 public BomRoundConnection[] RoundConnections=Array.Empty<BomRoundConnection>();
 public BomCellBinding[] CellBindings=Array.Empty<BomCellBinding>();
 public readonly Dictionary<ulong,BomSourceState> Sources=new Dictionary<ulong,BomSourceState>();
 ulong catalogConnection,catalogTopologyRevision;uint catalogEpoch;
 public readonly List<BomRequestResult> RequestResults=new List<BomRequestResult>();
 ulong requestCursor,requestGeneration;
 public BomCell[] Cells=Array.Empty<BomCell>();
 public BomVertex[] Vertices=Array.Empty<BomVertex>();
 public BomPose[] Poses=Array.Empty<BomPose>();
 public BomEvent[] Events=Array.Empty<BomEvent>();
 public string Error="";
 public double NativeUpdateMilliseconds,CopyMilliseconds;
 public long CopyAllocatedBytes;
 public static double Now => (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 public static void Check(uint result) { if(result!=0)throw new InvalidOperationException("Native client status "+result); }
 public static void VerifyLayouts() {
  Type[] types={typeof(BomCreateInfo),typeof(BomConnectInfo),typeof(BomVertex),typeof(BomCell),typeof(BomPose),typeof(BomEvent),typeof(BomSample),typeof(BomBuildInfo),typeof(BomStats),typeof(BomError),typeof(BomHostCommand),typeof(BomCommandResult),typeof(BomActorShapeInfo),typeof(BomOwnerState),typeof(BomPredictionStats),typeof(BomRequestResult),typeof(BomLevelInfo),typeof(BomCellBinding),typeof(BomSourceBinding),typeof(BomCatalogInfo),typeof(BomRoundPlayer),typeof(BomRoundConnection),typeof(BomRoundInfo)};
  for(uint i=0;i<types.Length;i++) {
   Type t=types[i];if(Marshal.SizeOf(t)!=BomNative.bom_debug_layout(i,0))throw new InvalidOperationException(t.Name+" size differs");
   var fields=t.GetFields(BindingFlags.Instance|BindingFlags.Public);uint alignment=1;
   for(uint f=0;f<fields.Length;f++) {
    alignment=Math.Max(alignment,(uint)Math.Min(8,Marshal.SizeOf(fields[f].FieldType)));
    if((uint)Marshal.OffsetOf(t,fields[f].Name)!=BomNative.bom_debug_layout(i,f+2))throw new InvalidOperationException(t.Name+" field differs: "+fields[f].Name);
   }
   if(alignment!=BomNative.bom_debug_layout(i,1))throw new InvalidOperationException(t.Name+" alignment differs");
  }
 }
 public BomSession() {
  VerifyLayouts();var info=new BomCreateInfo{struct_size=(uint)Marshal.SizeOf<BomCreateInfo>(),version=1};ulong value=0;
  Check(BomNative.bom_client_create(ref info,ref value));Handle=value;
 }
 public void Connect(uint ipv4,uint port,string token="") {
  IntPtr text=IntPtr.Zero;
  try {
   byte[] bytes=System.Text.Encoding.UTF8.GetBytes(token);if(bytes.Length>0){text=Marshal.AllocHGlobal(bytes.Length);Marshal.Copy(bytes,0,text,bytes.Length);}
   var info=new BomConnectInfo{struct_size=(uint)Marshal.SizeOf<BomConnectInfo>(),version=1,ipv4=ipv4,port=port,token=text,token_length=(uint)bytes.Length};
   Check(BomNative.bom_client_connect(Handle,ref info));
  } finally {if(text!=IntPtr.Zero)Marshal.FreeHGlobal(text);}
 }
 public void ExpectGameplayManifest(string hex) {
  if(string.IsNullOrEmpty(hex)){Check(BomNative.bom_client_expect_gameplay_manifest(Handle,IntPtr.Zero,0));return;}
  if(hex.Length!=64)throw new ArgumentException("Expected gameplay manifest must contain 64 hexadecimal characters");
  var bytes=new byte[32];for(int i=0;i<32;i++)bytes[i]=byte.Parse(hex.Substring(i*2,2),System.Globalization.NumberStyles.HexNumber,System.Globalization.CultureInfo.InvariantCulture);
  IntPtr data=Marshal.AllocHGlobal(32);try{Marshal.Copy(bytes,0,data,32);Check(BomNative.bom_client_expect_gameplay_manifest(Handle,data,32));}finally{Marshal.FreeHGlobal(data);}
 }
 static string Utf8(IntPtr pointer,uint length){if(length>256||(length>0&&pointer==IntPtr.Zero))throw new InvalidOperationException("Invalid native catalog string");var bytes=new byte[length];if(length>0)Marshal.Copy(pointer,bytes,0,bytes.Length);return System.Text.Encoding.UTF8.GetString(bytes);}
 public static string HashText(ulong a,ulong b,ulong c,ulong d){var bytes=new byte[32];Buffer.BlockCopy(new[]{a,b,c,d},0,bytes,0,32);return BitConverter.ToString(bytes).Replace("-","").ToLowerInvariant();}
 void CopyCatalog(BomSample sample){
  if(catalogConnection==sample.connection_generation&&catalogEpoch==sample.epoch&&catalogTopologyRevision==sample.revision)return;
  var info=new BomCatalogInfo{struct_size=(uint)Marshal.SizeOf<BomCatalogInfo>(),version=1};Check(BomNative.bom_client_acquire_catalog(Handle,sample.sample_sequence,ref info));
  if(info.epoch!=sample.epoch||info.binding_count!=sample.cell_count||info.source_count>512)throw new InvalidOperationException("Catalog/topology sample is incoherent");
  Copy(info.bindings,info.binding_count,ref CellBindings);
  var sources=new Dictionary<ulong,BomSourceState>();int stride=Marshal.SizeOf<BomSourceBinding>();
  if(info.source_count>0&&info.sources==IntPtr.Zero)throw new InvalidOperationException("Missing native catalog array");
  for(int i=0;i<info.source_count;i++){
   var binding=Marshal.PtrToStructure<BomSourceBinding>(IntPtr.Add(info.sources,checked(i*stride)));
   var source=new BomSourceState{AssetKey=Utf8(binding.asset_key,binding.asset_key_length),CapKey=Utf8(binding.cap_key,binding.cap_key_length),VisualHash=HashText(binding.visual_hash0,binding.visual_hash1,binding.visual_hash2,binding.visual_hash3)};
   binding.asset_key=binding.cap_key=IntPtr.Zero;source.Binding=binding;sources.Add(binding.source_identity,source);
  }
  info.sources=info.bindings=IntPtr.Zero;Catalog=info;Sources.Clear();foreach(var source in sources)Sources.Add(source.Key,source.Value);
  catalogConnection=sample.connection_generation;catalogEpoch=sample.epoch;catalogTopologyRevision=sample.revision;
 }
 static void Copy<T>(IntPtr source,uint count,ref T[] target) where T:unmanaged=>BomNativeBuffer.Copy(source,count,ref target);
 public void Poll(double now,Action<BomSession> accept) {
  long nativeStart=Stopwatch.GetTimestamp();
  uint status=BomNative.bom_client_update(Handle,now);
  NativeUpdateMilliseconds=(Stopwatch.GetTimestamp()-nativeStart)*1000.0/Stopwatch.Frequency;
  if(status!=0) {
   var error=new BomError{struct_size=(uint)Marshal.SizeOf<BomError>(),version=1};string reason="";
   if(BomNative.bom_client_last_error(Handle,ref error)==0&&error.message_length>0&&error.message_length<=65536){var text=new byte[error.message_length];Marshal.Copy(error.message,text,0,text.Length);reason=System.Text.Encoding.UTF8.GetString(text);}
   throw new InvalidOperationException(reason=="host left"?"The host left. Start or join a new server.":!string.IsNullOrEmpty(reason)?reason:"Connection interrupted. Reconnect to try again.");
  }
  var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Check(BomNative.bom_client_acquire_sample(Handle,ref sample));
  long copyStart=Stopwatch.GetTimestamp(),copyBytes=BomAllocationCounter.Read();
  try {
   // Cell geometry is immutable for a native topology transaction. Copy it
   // once; poses and events continue to be copied on every sample.
   if(Sample.connection_generation!=sample.connection_generation||Sample.epoch!=sample.epoch||Sample.revision!=sample.revision||Sample.transaction_id!=sample.transaction_id||Sample.cell_count!=sample.cell_count||Sample.vertex_count!=sample.vertex_count){
    Copy(sample.cells,sample.cell_count,ref Cells);Copy(sample.vertices,sample.vertex_count,ref Vertices);
   }
   Copy(sample.poses,sample.pose_count,ref Poses);Copy(sample.events,sample.event_count,ref Events);
   CopyCatalog(sample);
   var round=new BomRoundInfo{struct_size=(uint)Marshal.SizeOf<BomRoundInfo>(),version=1};Check(BomNative.bom_client_get_round(Handle,sample.sample_sequence,ref round));
   if(round.player_count>2||round.connection_count>4)throw new InvalidOperationException("Invalid native round roster");
   Copy(round.players,round.player_count,ref RoundPlayers);Copy(round.connections,round.connection_count,ref RoundConnections);
   round.players=round.connections=IntPtr.Zero;Round=round;
   if(sample.error_length>65536)throw new InvalidOperationException("Invalid error length");
   if(sample.error_length==0)Error="";else{byte[] error=new byte[sample.error_length];Marshal.Copy(sample.error_text,error,0,error.Length);Error=System.Text.Encoding.UTF8.GetString(error);}
   // Clear pointer fields: managed users receive only the owned copies above.
   sample.cells=sample.vertices=sample.poses=sample.events=sample.error_text=IntPtr.Zero;Sample=sample;
  } finally {CopyMilliseconds=(Stopwatch.GetTimestamp()-copyStart)*1000.0/Stopwatch.Frequency;CopyAllocatedBytes=BomAllocationCounter.Since(copyBytes);Check(BomNative.bom_client_release_sample(Handle,sample.sample_sequence));}
  Owner=new BomOwnerState{struct_size=(uint)Marshal.SizeOf<BomOwnerState>(),version=1};Check(BomNative.bom_client_get_owner_state(Handle,ref Owner));
  Prediction=new BomPredictionStats{struct_size=(uint)Marshal.SizeOf<BomPredictionStats>(),version=1};Check(BomNative.bom_client_get_prediction_stats(Handle,ref Prediction));
  if(requestGeneration!=Sample.connection_generation){requestGeneration=Sample.connection_generation;requestCursor=0;}
  RequestResults.Clear();
  for(int i=0;i<1024;i++){var result=new BomRequestResult{struct_size=(uint)Marshal.SizeOf<BomRequestResult>(),version=1};Check(BomNative.bom_client_next_request_result(Handle,requestCursor,ref result));if((result.flags&1)==0)break;RequestResults.Add(result);requestCursor=result.request_id;}
  accept(this);Check(BomNative.bom_client_ack_sample(Handle,sample.sample_sequence));
 }
 public void Dispose(){if(Handle==0)return;Check(BomNative.bom_client_destroy(Handle));Handle=0;}
}
}
