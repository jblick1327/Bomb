using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Bom.Native;
using UnityEngine;
using UnityEngine.Rendering;

namespace Bom.Unity {
// Explicit test driver: native networking/physics and the actual URP camera.
[DefaultExecutionOrder(-100)]public sealed class BomPresentationProfile:MonoBehaviour {
 BomClientBehaviour client;RenderTexture target;double launched,ready,started,inputAt,seconds;int fps,frames,predicted,fallback,expired,lastJump=-1,lastFrame=-1;float held=float.NaN,origin;bool waiting,finished;string output;
 readonly List<double> responses=new List<double>();
 [Serializable]class Stats{public uint status,reason;public ulong correction_count,snap_count;public float correction_p95,correction_p99,correction_max;public double conservative_seconds;}
 [Serializable]class Result{public string status,measurement;public double seconds,warmupSeconds,actualRenderFps,inputToPresentationP95Ms,inputResponseBudgetMs;public int fps,frames,predictedFrames,fallbackFrames,inputResponseSamples,inputResponseExpired;public Stats stats;}
 [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]static void Install(){var args=Environment.GetCommandLineArgs();if(Array.IndexOf(args,"--bom-profile-seconds")<0)return;var scene=FindFirstObjectByType<BomClientBehaviour>();if(scene!=null)scene.gameObject.AddComponent<BomPresentationProfile>();}
 static string Arg(string key,string fallback){var args=Environment.GetCommandLineArgs();int i=Array.IndexOf(args,key);return i>=0&&i+1<args.Length?args[i+1]:fallback;}
 void Awake(){client=GetComponent<BomClientBehaviour>();launched=BomSession.Now;seconds=double.Parse(Arg("--bom-profile-seconds","30"),CultureInfo.InvariantCulture);fps=int.Parse(Arg("--bom-profile-fps","60"));output=Arg("--bom-profile-out","");QualitySettings.vSyncCount=0;Application.targetFrameRate=fps;target=new RenderTexture(1280,720,24,RenderTextureFormat.ARGB32);target.Create();RenderPipelineManager.endCameraRendering+=Rendered;}
 void Update(){if(finished||client.Session==null)return;try{
  double now=BomSession.Now;if(started==0&&now-launched>45)throw new TimeoutException("Unity profile did not synchronize");var session=client.Session;
  if(started==0&&(session.Owner.flags&3)==3&&(!client.Prediction||session.Prediction.status==1)){if(ready==0)ready=now;if(now-ready>=20){BomSession.Check(BomNative.bom_client_reset_prediction_metrics(session.Handle));started=now;held=float.NaN;Debug.Log("PROFILE READY Unity rendered-pose measurement");}}
  double elapsed=started==0?0:now-started;if(started!=0&&elapsed>=seconds){Finish();return;}
  float requested=started==0?0:(elapsed%4<1?1:elapsed%4<2?0:elapsed%4<3?-1:0);
  if(requested!=held){if(waiting){expired++;waiting=false;}held=requested;if(requested!=0&&client.TryLocalVisualPosition(out var position)){origin=position.x;inputAt=now;waiting=true;}}
  BomSession.Check(BomNative.bom_client_set_held_input(session.Handle,now,requested));
  int jump=(int)(elapsed/4);if(started!=0&&elapsed%4>.5&&elapsed%4<1&&jump!=lastJump){BomSession.Check(BomNative.bom_client_enqueue_jump(session.Handle,now));lastJump=jump;}
 }catch(Exception error){Debug.LogError(error);finished=true;Application.Quit(4);}}
 void LateUpdate(){if(finished||client.View==null)return;var request=new RenderPipeline.StandardRequest{destination=target};RenderPipeline.SubmitRenderRequest(client.View,request);}
 void Rendered(ScriptableRenderContext context,Camera camera){if(finished||started==0||camera!=client.View||lastFrame==Time.frameCount||client.Session==null)return;lastFrame=Time.frameCount;frames++;if(client.Session.Prediction.status==1)predicted++;if(client.Session.Prediction.status==2)fallback++;if(waiting&&client.TryLocalVisualPosition(out var position)&&Math.Abs(position.x-origin)>.0001){responses.Add((BomSession.Now-inputAt)*1000);waiting=false;}}
 void Finish(){finished=true;var value=client.Session.Prediction;responses.Sort();double actualFps=frames/seconds,p95=responses.Count==0?0:responses[Math.Max(0,(int)Math.Ceiling(responses.Count*.95)-1)],budget=1000.0/60+1000.0/Math.Max(fps,actualFps)+2;bool lossy=Environment.GetEnvironmentVariable("BOM_TEST_LOSSY")=="1";
  bool passed=frames>seconds*10&&expired==0&&responses.Count>seconds/4&&(!client.Prediction||(predicted>frames*.9&&value.conservative_seconds<1&&value.correction_count>seconds*10&&value.correction_p99<=(lossy?.2f:.1f)&&(lossy||(value.correction_p95<=.03f&&value.snap_count==0))&&p95<=budget));
  var result=new Result{status=passed?"passed":"failed",measurement="actual URP end-camera callback after native actor transform",seconds=seconds,warmupSeconds=started-launched,actualRenderFps=actualFps,fps=fps,frames=frames,predictedFrames=predicted,fallbackFrames=fallback,inputResponseSamples=responses.Count,inputResponseExpired=expired,inputToPresentationP95Ms=p95,inputResponseBudgetMs=budget,stats=new Stats{status=value.status,reason=value.reason,correction_count=value.correction_count,snap_count=value.snap_count,correction_p95=value.correction_p95,correction_p99=value.correction_p99,correction_max=value.correction_max,conservative_seconds=value.conservative_seconds}};
  Debug.Log("PROFILE_RESULT "+JsonUtility.ToJson(result));if(!string.IsNullOrEmpty(output)){var previous=RenderTexture.active;RenderTexture.active=target;var image=new Texture2D(target.width,target.height,TextureFormat.RGB24,false);image.ReadPixels(new Rect(0,0,target.width,target.height),0,0);image.Apply();File.WriteAllBytes(output,image.EncodeToPNG());Destroy(image);RenderTexture.active=previous;}
  client.Close();Application.Quit(passed?0:5);
 }
 void OnDestroy(){RenderPipelineManager.endCameraRendering-=Rendered;if(target!=null){target.Release();Destroy(target);}}
}
}
