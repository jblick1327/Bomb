using System;
using Bom.Native;
using UnityEngine;

namespace Bom.Unity {
// Opt-in process-test input only. Native code still schedules and simulates all
// commands, reconnects, collision, topology and authority decisions.
[DefaultExecutionOrder(900)]
public sealed class BomSoakDriver:MonoBehaviour {
 public string Role;public double JoinDelay;
 BomClientBehaviour client;double started,nextReconnect,resumeAt,nextJump;bool joined;
 void Start(){started=BomSession.Now;nextReconnect=started+(Role=="guest"?45:75);nextJump=started+7;}
 void Update(){
  if(client==null)client=FindFirstObjectByType<BomClientBehaviour>();if(client==null||client.Session==null)return;
  client.DrivenByRoundScenario=true;double now=BomSession.Now;
  if(!joined){if(now-started<JoinDelay)return;client.Reconnect();joined=true;Debug.Log("BOM SOAK JOIN role="+Role);}
  if(resumeAt>0){if(now<resumeAt)return;client.Reconnect();resumeAt=0;Debug.Log("BOM SOAK RECONNECT role="+Role);}
  if(now>=nextReconnect){client.Disconnect();resumeAt=now+1;nextReconnect=now+(Role=="guest"?90:120);Debug.Log("BOM SOAK DISCONNECT role="+Role);return;}
  if(!client.ConnectionRequested)return;
  BomSession.Check(BomNative.bom_client_set_held_input(client.Session.Handle,now,Math.Floor((now-started)/3)%2==0?.2f:-.2f));
  if(now>=nextJump){BomSession.Check(BomNative.bom_client_enqueue_jump(client.Session.Handle,now));nextJump=now+7;}
 }
}
}
