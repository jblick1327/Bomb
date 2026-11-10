using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Bom.Native;

namespace Bom.Unity {
public static class BomNativeIdentity {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr GetModuleHandle(string name);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern uint GetModuleFileName(IntPtr module,StringBuilder fileName,int size);
 public static string LoadedLibraryPath() {
  var module=GetModuleHandle("bomcore.dll");
  if(module==IntPtr.Zero)throw new InvalidOperationException("The loaded bomcore.dll module could not be located.");
  var path=new StringBuilder(32768);uint length=GetModuleFileName(module,path,path.Capacity);
  if(length==0||length>=path.Capacity)throw new InvalidOperationException("The loaded bomcore.dll path could not be read.");
  return path.ToString();
 }
 public static void Verify() {
  try {
   var info=new BomBuildInfo{struct_size=(uint)Marshal.SizeOf<BomBuildInfo>(),version=1};
   uint status=BomNative.bom_build_info(ref info);
   if(status!=0||info.abi_major!=BomExpectedNativeIdentity.AbiMajor||info.abi_minor!=BomExpectedNativeIdentity.AbiMinor||info.source_build_tag!=BomExpectedNativeIdentity.BuildTag||info.game_protocol!=BomExpectedNativeIdentity.GameProtocol||info.canonical_version!=BomExpectedNativeIdentity.CanonicalVersion)
    throw new InvalidOperationException("Native build tag, ABI or protocol differs from these bindings.");
   string actual;
   using(var stream=File.OpenRead(LoadedLibraryPath()))using(var sha=SHA256.Create())actual=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
   if(!string.Equals(actual,BomExpectedNativeIdentity.DllSha256,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Native DLL SHA-256 differs from this client's build identity.");
  } catch(Exception error) {
   throw new InvalidOperationException("Cannot connect: bomcore.dll does not match this client. Run the native rebuild command, rebuild the player if needed, and restart the Unity Editor after changing the DLL. "+error.Message,error);
  }
 }
}
}
