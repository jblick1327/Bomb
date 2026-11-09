using System;
using System.IO;
using UnityEngine;
using UnityEngine.Rendering;
namespace Bom.Unity {
public sealed class BomSourceCapture:MonoBehaviour {
 ulong sourceId,firstRevision;string targetAsset="source-fixture/Closed box";string prefix;BomClientBehaviour client;RenderTexture target;uint firstEpoch;bool intact,fractured,reset,moving,hasMovingPosition;Vector3 movingPosition;
 [Serializable]sealed class Metrics{public uint epoch;public ulong revision,hash;public int intact_sources,fragment_sources,fallback_sources,active_jobs,pending_jobs;public long stale_applies,stale_drops,cpu_cache,gpu_reserved,buffers;public double max_upload_ms,max_source_read_ms;}
 [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]static void Install(){var args=Environment.GetCommandLineArgs();int i=Array.IndexOf(args,"--bom-source-capture");if(i>=0&&i+1<args.Length){var capture=new GameObject("BOM source render evidence").AddComponent<BomSourceCapture>();capture.prefix=args[i+1];int sourceArg=Array.IndexOf(args,"--bom-source-capture-source-id");if(sourceArg>=0&&sourceArg+1<args.Length)capture.sourceId=ulong.Parse(args[sourceArg+1],System.Globalization.CultureInfo.InvariantCulture);}}
 void LateUpdate(){
  if(client==null)client=FindFirstObjectByType<BomClientBehaviour>();if(client==null||client.View==null||client.Session==null||client.SourcePresentation==null||(client.Session.Sample.flags&6)!=6)return;var presentation=client.SourcePresentation;var sample=client.Session.Sample;string suffix=null;
  if(sourceId!=0){if(!client.Session.Sources.TryGetValue(sourceId,out var nativeSource))return;targetAsset=nativeSource.AssetKey;}
  if(firstEpoch==0){firstEpoch=sample.epoch;firstRevision=sample.revision;}
  if(!intact&&sample.epoch==firstEpoch&&(presentation.HasMode(targetAsset,"intact")||sourceId!=0&&presentation.HasMode(targetAsset,"fragments"))){suffix=sourceId==0?"intact":"ready";intact=true;if(sourceId!=0)firstRevision=sample.revision;}
  else if(!fractured&&sample.epoch==firstEpoch&&(sourceId==0||intact&&sample.revision>firstRevision)&&presentation.HasMode(targetAsset,"fragments")){suffix="fractured";fractured=true;}
  else if(!reset&&sample.epoch!=firstEpoch&&(presentation.HasMode(targetAsset,"intact")||sourceId!=0&&presentation.HasMode(targetAsset,"fragments"))){suffix="reset";reset=true;}
  bool moves=false;if(presentation.TrySourcePose("source-fixture/Multi material moving solid",out var current)){moves=hasMovingPosition&&(current-movingPosition).sqrMagnitude>.000001f;hasMovingPosition=true;movingPosition=current;}
  if(suffix==null&&!moving&&moves&&presentation.HasMode("source-fixture/Multi material moving solid","fragments")){suffix="moving";moving=true;}
  if(suffix==null)return;if(target==null){target=new RenderTexture(1280,720,24,RenderTextureFormat.ARGB32);target.Create();}
  var camera=client.View;var position=camera.transform.position;var rotation=camera.transform.rotation;Vector3 center=new Vector3(position.x,position.y,0);
  try{Save(camera,prefix+"-"+suffix+"-front.png");var angle=Quaternion.Euler(0,20,0);camera.transform.SetPositionAndRotation(center+angle*new Vector3(0,0,position.z),angle);Save(camera,prefix+"-"+suffix+"-angle.png");}
  finally{camera.transform.SetPositionAndRotation(position,rotation);}
  string path=prefix+"-"+suffix+".json";File.WriteAllText(path,JsonUtility.ToJson(new Metrics{epoch=sample.epoch,revision=sample.revision,hash=sample.canonical_hash,intact_sources=presentation.IntactSources,fragment_sources=presentation.FragmentSources,fallback_sources=presentation.FallbackSources,active_jobs=presentation.Jobs.ActiveCount,pending_jobs=presentation.Jobs.PendingCount,stale_applies=presentation.StaleApplications,stale_drops=presentation.Jobs.StaleResults,cpu_cache=presentation.Jobs.CacheBytes,gpu_reserved=presentation.GpuBytes,buffers=presentation.Jobs.BufferBytes,max_upload_ms=presentation.MaxUploadMilliseconds,max_source_read_ms=presentation.MaxSourceReadMilliseconds},true));Debug.Log("BOM SOURCE FRAME "+suffix+" epoch="+sample.epoch+" revision="+sample.revision);
 }
 void Save(Camera camera,string path){RenderPipeline.SubmitRenderRequest(camera,new RenderPipeline.StandardRequest{destination=target});var old=RenderTexture.active;Texture2D image=null;try{RenderTexture.active=target;image=new Texture2D(1280,720,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,1280,720),0,0);image.Apply();Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));File.WriteAllBytes(path,image.EncodeToPNG());}finally{RenderTexture.active=old;if(image!=null)Destroy(image);}}
 void OnDestroy(){if(target!=null){target.Release();Destroy(target);}}
}
}
