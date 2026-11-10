using System.Runtime.InteropServices;
using Bom.Native;
using Bom.Unity;

if(args.Length<1)throw new ArgumentException("Supply an actual bomcore.dll path and optionally --expect-reject.");
var path=Path.GetFullPath(args[0]);bool expectedRejection=args.Contains("--expect-reject");
NativeLibrary.SetDllImportResolver(typeof(BomNative).Assembly,(name,assembly,search)=>name=="bomcore"?NativeLibrary.Load(path):IntPtr.Zero);
try {
 BomNativeIdentity.Verify();
 if(expectedRejection)throw new Exception("An incompatible native library was accepted.");
 Console.WriteLine("IDENTITY PASS: actual native ABI/tag/protocol and loaded DLL SHA-256 match before connection.");
 return 0;
}catch(InvalidOperationException error) {
 Console.WriteLine("IDENTITY REJECTED: "+error.Message);
 return expectedRejection?0:1;
}
