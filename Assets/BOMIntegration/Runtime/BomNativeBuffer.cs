using System;
namespace Bom.Unity {
// Blittable native rows are copied while the sample lease is held. Avoid
// PtrToStructure<T>, which boxes individual rows on some Mono runtimes.
public static class BomNativeBuffer {
 public static unsafe void Copy<T>(IntPtr source,uint count,ref T[] target) where T:unmanaged {
  if(count>1000000||(count>0&&source==IntPtr.Zero))throw new InvalidOperationException("Invalid native array");
  if(target==null)target=Array.Empty<T>();
  if(target.Length<count)Array.Resize(ref target,checked((int)count));
  if(count==0)return;
  fixed(T* destination=target)Buffer.MemoryCopy(source.ToPointer(),destination,checked((long)target.Length*sizeof(T)),checked((long)count*sizeof(T)));
 }
}
}
