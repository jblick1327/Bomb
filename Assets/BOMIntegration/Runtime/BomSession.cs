using System;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using Bom.Native;

namespace Bom.Unity {
// No managed networking or simulation. All borrowed native memory is copied
// before release; presenters accept the complete snapshot before acknowledgement.
public sealed class BomSession : IDisposable {
 public ulong Handle { get; private set; }
 public BomSample Sample;
 public BomCell[] Cells=Array.Empty<BomCell>();
 public BomVertex[] Vertices=Array.Empty<BomVertex>();
 public BomPose[] Poses=Array.Empty<BomPose>();
 public BomEvent[] Events=Array.Empty<BomEvent>();
 public string Error="";
 public static double Now => (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency;
 public static void Check(uint result) { if(result!=0)throw new InvalidOperationException("Native client status "+result); }
 public static void VerifyLayouts() {
  Type[] types={typeof(BomCreateInfo),typeof(BomConnectInfo),typeof(BomVertex),typeof(BomCell),typeof(BomPose),typeof(BomEvent),typeof(BomSample),typeof(BomBuildInfo),typeof(BomStats),typeof(BomError),typeof(BomHostCommand),typeof(BomCommandResult),typeof(BomActorShapeInfo)};
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
 static void Copy<T>(IntPtr source,uint count,ref T[] target) where T:struct {
  if(count>1000000 || (count>0 && source==IntPtr.Zero))throw new InvalidOperationException("Invalid native array");
  if(target.Length<count)Array.Resize(ref target,checked((int)count));
  int stride=Marshal.SizeOf<T>();for(int i=0;i<count;i++)target[i]=Marshal.PtrToStructure<T>(IntPtr.Add(source,checked(i*stride)));
 }
 public void Poll(double now,Action<BomSession> accept) {
  uint status=BomNative.bom_client_update(Handle,now);
  if(status!=0) {
   var error=new BomError{struct_size=(uint)Marshal.SizeOf<BomError>(),version=1};string reason="";
   if(BomNative.bom_client_last_error(Handle,ref error)==0&&error.message_length>0&&error.message_length<=65536){var text=new byte[error.message_length];Marshal.Copy(error.message,text,0,text.Length);reason=System.Text.Encoding.UTF8.GetString(text);}
   throw new InvalidOperationException("Native client status "+status+": "+reason);
  }
  var sample=new BomSample{struct_size=(uint)Marshal.SizeOf<BomSample>(),version=1};Check(BomNative.bom_client_acquire_sample(Handle,ref sample));
  try {
   Copy(sample.cells,sample.cell_count,ref Cells);Copy(sample.vertices,sample.vertex_count,ref Vertices);
   Copy(sample.poses,sample.pose_count,ref Poses);Copy(sample.events,sample.event_count,ref Events);
   if(sample.error_length>65536)throw new InvalidOperationException("Invalid error length");
   byte[] error=new byte[sample.error_length];if(error.Length>0)Marshal.Copy(sample.error_text,error,0,error.Length);Error=System.Text.Encoding.UTF8.GetString(error);
   // Clear pointer fields: managed users receive only the owned copies above.
   sample.cells=sample.vertices=sample.poses=sample.events=sample.error_text=IntPtr.Zero;Sample=sample;
  } finally {Check(BomNative.bom_client_release_sample(Handle,sample.sample_sequence));}
  accept(this);Check(BomNative.bom_client_ack_sample(Handle,sample.sample_sequence));
 }
 public void Dispose(){if(Handle==0)return;Check(BomNative.bom_client_destroy(Handle));Handle=0;}
}
}
