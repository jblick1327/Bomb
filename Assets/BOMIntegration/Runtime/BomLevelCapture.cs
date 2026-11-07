using System;
using System.IO;
using UnityEngine;
using UnityEngine.Rendering;
namespace Bom.Unity {
public sealed class BomLevelCapture:MonoBehaviour {
 string prefix;BomClientBehaviour client;RenderTexture target;uint firstEpoch;ulong firstRevision;bool joined,fractured,reset;
 [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]static void Install(){var args=Environment.GetCommandLineArgs();int i=Array.IndexOf(args,"--bom-level-capture");if(i>=0&&i+1<args.Length){var capture=new GameObject("BOM evidence camera capture").AddComponent<BomLevelCapture>();capture.prefix=args[i+1];}}
 void LateUpdate(){
  if(client==null)client=FindFirstObjectByType<BomClientBehaviour>();if(client==null||client.View==null||client.Session==null||(client.Session.Sample.flags&6)!=6)return;
  var sample=client.Session.Sample;string suffix=null;
  if(!joined){suffix="joined";firstEpoch=sample.epoch;firstRevision=sample.revision;joined=true;}
  else if(!fractured&&sample.epoch==firstEpoch&&sample.revision>firstRevision){suffix="fractured";fractured=true;}
  else if(!reset&&sample.epoch!=firstEpoch){suffix="reset";reset=true;}
  if(suffix==null)return;
  if(target==null){target=new RenderTexture(1280,720,24,RenderTextureFormat.ARGB32);target.Create();}
  RenderPipeline.SubmitRenderRequest(client.View,new RenderPipeline.StandardRequest{destination=target});var old=RenderTexture.active;Texture2D image=null;
  try{RenderTexture.active=target;image=new Texture2D(1280,720,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,1280,720),0,0);image.Apply();string path=Path.GetFullPath(prefix+"-"+suffix+".png");Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllBytes(path,image.EncodeToPNG());Debug.Log("BOM LEVEL FRAME "+suffix+" epoch="+sample.epoch+" revision="+sample.revision+" path="+path);}
  finally{RenderTexture.active=old;if(image!=null)Destroy(image);}
 }
 void OnDestroy(){if(target!=null){target.Release();Destroy(target);}}
}
}
