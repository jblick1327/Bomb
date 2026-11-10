using System;
using Unity.Profiling;

namespace Bom.Unity {
// A zero from an unsupported runtime API is not evidence of zero allocation.
// Profiling explicitly validates its counter with an escaped allocation first.
public static class BomAllocationCounter {
 static ProfilerRecorder recorder;static bool profiler,initialized;static byte[] control;
 public static bool Valid{get;private set;}public static long ThreadApiControlBytes{get;private set;}public static long ProfilerControlEvents{get;private set;}
 public static string Method=>!initialized?"unvalidated":profiler?"GC.Alloc current-thread event count":Valid?"GC.GetAllocatedBytesForCurrentThread":"unavailable";
 public static void Initialize(){
  if(initialized)return;initialized=true;
  long before=0;try{before=GC.GetAllocatedBytesForCurrentThread();control=new byte[4096];ThreadApiControlBytes=GC.GetAllocatedBytesForCurrentThread()-before;GC.KeepAlive(control);}catch(Exception error)when(error is NotSupportedException||error is NotImplementedException){ThreadApiControlBytes=-1;}
  if(ThreadApiControlBytes>=4096){Valid=true;return;}
  recorder=ProfilerRecorder.StartNew(ProfilerCategory.Memory,"GC.Alloc",65536,ProfilerRecorderOptions.StartImmediately|ProfilerRecorderOptions.CollectOnlyOnCurrentThread|ProfilerRecorderOptions.WrapAroundWhenCapacityReached);
  if(recorder.Valid){before=recorder.Count;control=new byte[8192];GC.KeepAlive(control);ProfilerControlEvents=recorder.Count-before;recorder.Stop();profiler=ProfilerControlEvents==1;Valid=profiler;}
 }
 public static string Unit=>profiler?"allocation events":"bytes";
 public static long Read(){if(!initialized)return -1;if(!Valid)return -1;if(profiler){recorder.Reset();recorder.Start();return 0;}return GC.GetAllocatedBytesForCurrentThread();}
 public static long Since(long before){if(before<0)return -1;if(profiler){recorder.Stop();return recorder.WrappedAround?-1:recorder.Count;}long after=Read();return after<before?-1:after-before;}
 public static void Dispose(){if(recorder.Valid)recorder.Dispose();control=null;}
}
}
