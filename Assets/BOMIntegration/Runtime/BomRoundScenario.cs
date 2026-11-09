using System;
using System.Collections;
using System.IO;
using System.Runtime.InteropServices;
using Bom.Native;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UIElements;

namespace Bom.Unity {
// Opt-in executable acceptance driver. Uses the same menu connection methods
// and native request ABI as a user; never chooses a winner or encodes packets.
public sealed class BomRoundScenario:MonoBehaviour {
 public BomClientBehaviour Client;
 string prefix,role;double started,disconnectedAt;ulong firstRound,lastRound;uint lastState=uint.MaxValue;
 bool connected,ready,interrupted,resultRejoined,guestRestartSent,guestRestartRejected,finished;
 ulong forfeitedRound;
 bool menuCaptured;
 bool drawScenario;ulong drawReconnectedRound,eventRepeatRound;
 ulong jumpRound;bool sawNativeJump;
 [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]static void SelectFixture(){if(Array.IndexOf(Environment.GetCommandLineArgs(),"--bom-round-draw")>=0&&UnityEngine.SceneManagement.SceneManager.GetActiveScene().name=="NetworkMenu")UnityEngine.SceneManagement.SceneManager.LoadScene("RoundDraw");}
 RenderTexture panelTarget,sceneTarget;PanelSettings originalPanel,capturePanel;UIDocument document;
 void OnEnable(){var args=Environment.GetCommandLineArgs();string Arg(string name){int i=Array.IndexOf(args,name);return i>=0&&i+1<args.Length?args[i+1]:"";}prefix=Arg("--bom-round-test");role=Arg("--bom-round-role");if(string.IsNullOrEmpty(prefix)){enabled=false;return;}if(Client==null)Client=GetComponent<BomClientBehaviour>();started=BomSession.Now;QualitySettings.vSyncCount=0;Application.targetFrameRate=60;
  drawScenario=Array.IndexOf(args,"--bom-round-draw")>=0;
  Client.DrivenByRoundScenario=true;
  document=FindFirstObjectByType<BomNetworkHud>()?.GetComponent<UIDocument>();
  if(document==null||document.panelSettings==null)throw new InvalidOperationException("Round capture requires the real network menu panel");
  originalPanel=document.panelSettings;capturePanel=Instantiate(originalPanel);capturePanel.clearColor=true;capturePanel.colorClearValue=Color.clear;panelTarget=new RenderTexture(1280,720,24,RenderTextureFormat.ARGB32);panelTarget.Create();capturePanel.targetTexture=panelTarget;document.panelSettings=capturePanel;
  sceneTarget=new RenderTexture(1280,720,24,RenderTextureFormat.ARGB32);sceneTarget.Create();StartCoroutine(Capture("menu"));}
 static Texture2D Read(RenderTexture target){var old=RenderTexture.active;try{RenderTexture.active=target;var image=new Texture2D(1280,720,TextureFormat.RGBA32,false);image.ReadPixels(new Rect(0,0,1280,720),0,0);image.Apply();return image;}finally{RenderTexture.active=old;}}
 IEnumerator Capture(string name){
  if(name=="menu")yield return new WaitForSecondsRealtime(.5f);
  yield return new WaitForEndOfFrame();string path=prefix+"-"+name+".png";Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
  RenderPipeline.SubmitRenderRequest(Client.View,new RenderPipeline.StandardRequest{destination=sceneTarget});
  var scene=Read(sceneTarget);var ui=Read(panelTarget);
  try{
   File.WriteAllBytes(prefix+"-"+name+"-scene.png",scene.EncodeToPNG());File.WriteAllBytes(prefix+"-"+name+"-ui.png",ui.EncodeToPNG());
   var background=scene.GetPixels32();var foreground=ui.GetPixels32();int visible=0;
   for(int i=0;i<background.Length;i++){var a=foreground[i];var b=background[i];float inverse=1-a.a/255f;background[i]=new Color32((byte)Mathf.Min(255,a.r+b.r*inverse),(byte)Mathf.Min(255,a.g+b.g*inverse),(byte)Mathf.Min(255,a.b+b.b*inverse),255);if(background[i].r+background[i].g+background[i].b>12)visible++;}
   if(visible<1000)throw new InvalidOperationException("Camera/UI capture was unexpectedly black");scene.SetPixels32(background);scene.Apply();File.WriteAllBytes(path,scene.EncodeToPNG());if(name=="menu")menuCaptured=true;Debug.Log("BOM ROUND CAPTURE "+name+" "+path);
  }finally{Destroy(scene);Destroy(ui);}
 }
 void Mark(string name){File.WriteAllText(prefix+"-"+name+".signal",name+"\n");}
 void Update(){
  try{
   if(finished)return;
   double now=BomSession.Now;if(now-started>240)throw new TimeoutException("Round scenario timed out at round="+lastRound+" state="+lastState);
   if(!connected&&menuCaptured&&now-started>2){Client.ConnectTo(Client.Address,Client.Port,"");connected=true;}
   if(!connected||Client.Session==null)return;
   if(!Client.ConnectionRequested){if(role=="guest"&&now-disconnectedAt>1){Client.Reconnect();if(forfeitedRound!=0||drawReconnectedRound!=0)resultRejoined=true;}return;}
   if(!string.IsNullOrEmpty(Client.ConnectionError))throw new InvalidOperationException(Client.ConnectionError);
   var session=Client.Session;var r=session.Round;if((r.flags&1)==0)return;
   if(!ready&&r.mode==0&&(session.Sample.flags&6)==6&&Client.SourcePresentation!=null&&Client.SourcePresentation.FallbackSources<=(drawScenario?0:2)&&Client.SourcePresentation.IntactSources+Client.SourcePresentation.FragmentSources>=(drawScenario?1:14)){ready=true;Mark("ready");StartCoroutine(Capture("sandbox"));Debug.Log("BOM ROUND ART READY role="+role);}
   if(r.mode!=1)return;
   if(!drawScenario){
    bool playing=r.state==2;BomSession.Check(BomNative.bom_client_set_held_input(session.Handle,now,playing?(role=="primary"?.35f:-.35f):0));
    if(playing&&r.tick>=r.start_tick+90&&jumpRound!=r.round_id&&(session.Owner.flags&1)!=0&&session.Owner.state_tick>=r.start_tick){BomSession.Check(BomNative.bom_client_enqueue_jump(session.Handle,now));jumpRound=r.round_id;}
    if(playing&&jumpRound==r.round_id&&session.Owner.last_jump_edge>0&&session.Owner.velocity_y>1)sawNativeJump=true;
   }
   if(firstRound==0)firstRound=r.round_id;
   if(r.round_id!=lastRound||r.state!=lastState){lastRound=r.round_id;lastState=r.state;Debug.Log("BOM ROUND UNITY role="+role+" round="+r.round_id+" state="+r.state+" tick="+r.tick+" winner="+r.winner+" draw="+r.draw+" local="+r.local_session_id+" spectator="+((r.flags&4)!=0));StartCoroutine(Capture("round-"+r.round_id+"-state-"+r.state));}
   if(role=="guest"&&r.round_id==firstRound&&r.state==1&&!interrupted){Client.Disconnect();interrupted=true;disconnectedAt=now;Mark("interrupted");return;}
   if(role=="guest"&&r.state==2){
    if(!guestRestartSent){BomSession.Check(BomNative.bom_client_host_command(session.Handle,1,0,0));guestRestartSent=true;}
    var command=new BomCommandResult{struct_size=(uint)Marshal.SizeOf<BomCommandResult>(),version=1};BomSession.Check(BomNative.bom_client_get_command_result(session.Handle,ref command));if(command.status==3)guestRestartRejected=true;
    if(!drawScenario&&r.tick>=r.start_tick+180&&forfeitedRound!=r.round_id){forfeitedRound=r.round_id;resultRejoined=false;Client.Disconnect();disconnectedAt=now;Mark("forfeit-"+r.round_id);return;}
   }
   if(r.state==3){
    if(drawScenario){if(r.draw==0||r.winner!=0)throw new InvalidOperationException("The shared falling-bomb fixture must kill both capsules on the same tick");
     if(eventRepeatRound!=r.round_id&&session.Sample.event_count>0){bool explosion=false;for(int i=0;i<session.Sample.event_count;i++)if(session.Events[i].radius>0)explosion=true;if(explosion){Client.VerifyRepeatedEventPresentation();eventRepeatRound=r.round_id;Mark("event-repeat-"+r.round_id);StartCoroutine(Capture("round-"+r.round_id+"-blast"));Debug.Log("BOM ROUND EVENT REPEAT PASS round="+r.round_id);}}
     if(eventRepeatRound!=r.round_id)return;
     if(role=="guest"&&drawReconnectedRound!=r.round_id){drawReconnectedRound=r.round_id;Client.Disconnect();disconnectedAt=now;resultRejoined=false;return;}
    }else if(r.draw!=0||r.winner==0)throw new InvalidOperationException("Expected the controlled guest forfeit to leave a winner");
    if(role=="guest"&&(!resultRejoined||(r.flags&4)==0||!guestRestartRejected))return;
    Mark("finished-"+r.round_id);
    if(r.round_id>firstRound&&!finished){finished=true;StartCoroutine(Finish());}
   }
  }catch(Exception error){Debug.LogError("BOM ROUND UNITY FAIL "+error);Application.Quit(4);enabled=false;}
 }
 IEnumerator Finish(){
  yield return new WaitForSecondsRealtime(1);
  Client.Disconnect();StartCoroutine(Capture("disconnected"));yield return new WaitForSecondsRealtime(.5f);
  Client.Reconnect();double deadline=BomSession.Now+30;
  while(BomSession.Now<deadline&&(Client.Session==null||Client.Session.Round.state!=3||Client.Session.Round.round_id<=firstRound||(Client.Session.Sample.flags&6)!=6))yield return null;
  if(Client.Session==null||Client.Session.Round.state!=3||Client.Session.Round.round_id<=firstRound||(Client.Session.Sample.flags&6)!=6){Debug.LogError("BOM ROUND UNITY FAIL final reconnect did not recover the result and baseline within 30 seconds");Application.Quit(4);yield break;}
  if(!drawScenario&&(Client.RunningPresentationFrames==0||!sawNativeJump)){Debug.LogError("BOM ROUND UNITY FAIL native movement/jump did not drive the original Claymate animation");Application.Quit(4);yield break;}
  Debug.Log("BOM ROUND UNITY PASS role="+role+" rounds=2 result_reconnect=1 running_frames="+Client.RunningPresentationFrames+" native_jump="+sawNativeJump);Mark("passed");Application.Quit(0);
 }
 void OnDestroy(){if(document!=null&&originalPanel!=null)document.panelSettings=originalPanel;if(panelTarget!=null){panelTarget.Release();Destroy(panelTarget);}if(sceneTarget!=null){sceneTarget.Release();Destroy(sceneTarget);}if(capturePanel!=null)Destroy(capturePanel);}
}
}
