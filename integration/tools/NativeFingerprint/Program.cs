using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var root=Path.GetFullPath(args[0]);
var comparer=StringComparer.Create(CultureInfo.GetCultureInfo("en-CA"),true);
var paths=new[]{"src/shared","src/netcode","src/ffi","bindings"}.SelectMany(p=>Directory.GetFiles(Path.Combine(root,p),"*",SearchOption.AllDirectories)).OrderBy(p=>p,comparer).ToArray();
using var hasher=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
foreach(var path in paths){hasher.AppendData(Encoding.UTF8.GetBytes(Path.GetRelativePath(root,path).Replace('\\','/')+"\0"));hasher.AppendData(File.ReadAllBytes(path));}
var hash=Convert.ToHexString(hasher.GetHashAndReset()).ToLowerInvariant();
Console.WriteLine(JsonSerializer.Serialize(new{source_sha256=hash,build_tag=Convert.ToInt64(hash[..15],16),source_fingerprint_culture="en-CA",fingerprint_runtime=System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,files=paths.Length}));
