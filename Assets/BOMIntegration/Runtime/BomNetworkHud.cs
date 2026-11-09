using System;
using Bom.Native;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UIElements;

namespace Bom.Unity {
// Read-only adapter for the preserved arena UXML/USS. All outcomes and XP are
// supplied by the native server snapshot; buttons send intent through the C ABI.
[RequireComponent(typeof(UIDocument))]
public sealed class BomNetworkHud:MonoBehaviour {
 public BomClientBehaviour Client;
 public VisualTreeAsset ArenaHudTemplate;
 public StyleSheet ArenaHudStyle;
 public StyleSheet NetworkMenuStyle;
 VisualElement root,hud,menu,death;
 Label status,roundState,timer,bombs,winner,resultBombs,resultTime,resultXp,currentLevel,nextLevel;
 VisualElement levelFill;
 TextField address,port,token;Toggle spectator;
 DropdownField mode;
 Button connect,disconnect,reconnect,restart,setMode;
 string message="Connect to a local or LAN server.";ulong displayedRound,displayedTick;double receivedAt;
 bool wasBlocked;
 ulong menuConnection;
 uint serverMode=uint.MaxValue;
 public void SetMenuVisible(bool visible){if(menu==null)return;menu.style.display=visible?DisplayStyle.Flex:DisplayStyle.None;if(!visible)(root.panel?.focusController?.focusedElement as VisualElement)?.Blur();}
 void OnEnable(){
  var doc=GetComponent<UIDocument>();root=doc.rootVisualElement;root.Clear();root.pickingMode=PickingMode.Ignore;
  if(ArenaHudTemplate!=null){hud=ArenaHudTemplate.CloneTree();if(ArenaHudStyle!=null)hud.styleSheets.Add(ArenaHudStyle);root.Add(hud);hud.pickingMode=PickingMode.Ignore;}
  else{hud=new VisualElement();root.Add(hud);}
  hud.style.position=Position.Absolute;hud.style.left=0;hud.style.top=0;hud.style.right=0;hud.style.bottom=0;
  Label L(string name)=>hud.Q<Label>(name);
  timer=L("timer");bombs=L("bomb-counter");winner=L("winner");resultBombs=L("result-bombs");resultTime=L("result-time");resultXp=L("result-xp");currentLevel=L("current-level");nextLevel=L("next-level");levelFill=hud.Q("level-fill");death=hud.Q("death-panel");
  if(L("controls") is Label controls)controls.text="A/D or arrows: move    Space: jump    Esc: connection menu";
  // The legacy subtitle assumes local restart authority. Replace that text in
  // this instantiated tree without editing the original UXML asset.
  if(death!=null)death.Query<Label>().ForEach(label=>{if(label.text=="Press R to restart")label.text="Open the menu (Esc) for the next round.";});
  menu=new VisualElement();menu.name="network-menu";menu.style.position=Position.Absolute;menu.style.right=20;menu.style.top=20;menu.style.width=330;menu.style.paddingLeft=18;menu.style.paddingRight=18;menu.style.paddingTop=16;menu.style.paddingBottom=16;menu.style.backgroundColor=new Color(.035f,.055f,.075f,.96f);menu.style.color=Color.white;root.Add(menu);
  var title=new Label("BOM · NETWORK PLAY");title.style.fontSize=21;title.style.unityFontStyleAndWeight=FontStyle.Bold;menu.Add(title);
  menu.AddToClassList("network-menu");if(NetworkMenuStyle!=null)menu.styleSheets.Add(NetworkMenuStyle);
  status=new Label("Connect to a local or LAN server.");status.style.whiteSpace=WhiteSpace.Normal;status.style.marginTop=8;status.style.marginBottom=8;menu.Add(status);
  address=new TextField("Server"){value=Client!=null?Client.Address:"127.0.0.1"};port=new TextField("Port"){value=Client!=null?Client.Port.ToString():"47380"};token=new TextField("Host key"){isPasswordField=true};spectator=new Toggle("Join as spectator");menu.Add(address);menu.Add(port);menu.Add(token);menu.Add(spectator);
  connect=new Button(()=>Act(()=>{if(!uint.TryParse(port.value,out uint number)||number<1||number>65535)throw new ArgumentException("Enter a port from 1 to 65535.");Client.ConnectTo(address.value.Trim(),number,token.value,spectator.value);message="Connecting…";})){text="Connect"};menu.Add(connect);
  disconnect=new Button(()=>Act(()=>{Client.Disconnect();message="Disconnected. You can reconnect to this session.";})){text="Disconnect"};menu.Add(disconnect);
  reconnect=new Button(()=>Act(()=>{Client.Reconnect();message="Reconnecting…";})){text="Reconnect"};menu.Add(reconnect);
  mode=new DropdownField("Mode",new System.Collections.Generic.List<string>{"Sandbox","Elimination"},0);menu.Add(mode);
  setMode=new Button(()=>Intent(5,(uint)mode.index)){text="Apply mode (host)"};menu.Add(setMode);
  restart=new Button(()=>Intent(1,0)){text="Start next round"};menu.Add(restart);
  menu.Add(new Button(()=>Application.Quit()){text="Quit"});
  roundState=new Label();roundState.style.position=Position.Absolute;roundState.style.left=20;roundState.style.top=20;roundState.style.fontSize=22;roundState.style.color=Color.white;roundState.pickingMode=PickingMode.Ignore;root.Add(roundState);
 }
 void Act(Action action){try{if(Client==null)throw new InvalidOperationException("Network scene is unavailable.");action();}catch(Exception error){message=error.Message;}}
 void Intent(uint op,uint modeValue)=>Act(()=>{if(Client.Session==null)throw new InvalidOperationException("Connect first.");BomSession.Check(BomNative.bom_client_host_command(Client.Session.Handle,op,modeValue,0));message="Request sent to the server.";});
 static void Text(Label label,string value){if(label!=null)label.text=value;}
 static string TimeText(ulong ticks){ulong seconds=ticks/60;return (seconds/60).ToString("00")+":"+(seconds%60).ToString("00");}
 void Update(){
  if(Client==null||root==null)return;
  if(Keyboard.current!=null&&Keyboard.current.escapeKey.wasPressedThisFrame)SetMenuVisible(menu.resolvedStyle.display==DisplayStyle.None);
  var session=Client.Session;bool requested=Client.ConnectionRequested;
  if(!requested)menu.style.display=DisplayStyle.Flex;
  var focus=root.panel?.focusController?.focusedElement as VisualElement;
  bool focused=focus is TextField||focus?.GetFirstAncestorOfType<TextField>()!=null;
  bool pointer=false;
  if(menu.resolvedStyle.display!=DisplayStyle.None&&Mouse.current!=null&&root.panel!=null){Vector2 mouse=Mouse.current.position.ReadValue();pointer=menu.worldBound.Contains(RuntimePanelUtils.ScreenToPanel(root.panel,new Vector2(mouse.x,Screen.height-mouse.y)));}
  Client.InputBlocked=menu.resolvedStyle.display!=DisplayStyle.None||focused||pointer||!requested;
  if(Client.InputBlocked&&!wasBlocked&&requested&&session!=null)Act(()=>BomSession.Check(BomNative.bom_client_clear_intent(session.Handle)));wasBlocked=Client.InputBlocked;
  connect.SetEnabled(!requested&&session!=null);disconnect.SetEnabled(requested);reconnect.SetEnabled(session!=null);
  if(session==null){status.text=Client.ConnectionError;return;}
  var r=session.Round;bool has=(r.flags&1)!=0;
  if(has&&serverMode!=r.mode){serverMode=r.mode;mode.SetValueWithoutNotify(r.mode==1?"Elimination":"Sandbox");}restart.text=has&&r.mode==0?"Reset sandbox":"Start next round";
  if(requested&&has&&(session.Sample.flags&6)==6&&session.Sample.connection_generation!=menuConnection){menuConnection=session.Sample.connection_generation;SetMenuVisible(false);}
  var stats=new BomStats{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<BomStats>(),version=1};bool host=BomNative.bom_client_get_stats(session.Handle,ref stats)==0&&(stats.flags&4)!=0;
  Text(hud.Q<Label>("controls"),host&&r.mode==0?"A/D or arrows: move    Space: jump    Click: blast    Esc: menu":"A/D or arrows: move    Space: jump    Esc: connection menu");
  setMode.SetEnabled(requested&&host&&(!has||r.mode==0||r.state==0||r.state==3));restart.SetEnabled(requested&&has&&(r.flags&2)!=0);
  string error=!string.IsNullOrEmpty(Client.ConnectionError)?Client.ConnectionError:session.Error;
  status.text=!string.IsNullOrEmpty(error)?error:!requested?message:!has?"Connecting and loading the world…":((r.flags&4)!=0?"Spectating":"Connected")+(host?" · Host":"")+"\n"+message;
  hud.style.display=has?DisplayStyle.Flex:DisplayStyle.None;
  if(!has){roundState.text="";return;}
  if(displayedRound!=r.round_id||displayedTick!=r.tick){displayedRound=r.round_id;displayedTick=r.tick;receivedAt=BomSession.Now;}
  double estimatedTick=r.tick+Math.Min(60,Math.Max(0,BomSession.Now-receivedAt)*60);
  string state=r.mode==0?"SANDBOX":r.state==0?"Waiting for two ready players":r.state==1?"Starting in "+Math.Max(0,Math.Ceiling((r.start_tick-estimatedTick)/60)).ToString("0"):r.state==2?"Round "+r.round_id+( (r.flags&4)!=0?" · Spectating":""):r.draw!=0?"DRAW":"Round finished";
  roundState.text=state;
  BomRoundPlayer player=default;for(int i=0;i<r.player_count;i++)if(session.RoundPlayers[i].session_id==r.local_session_id)player=session.RoundPlayers[i];
  BomRoundConnection profile=default;for(int i=0;i<r.connection_count;i++)if(session.RoundConnections[i].session_id==r.local_session_id)profile=session.RoundConnections[i];
  Text(timer,TimeText(player.alive_ticks));Text(bombs,"Bombs faced: "+player.bombs_faced);
  if(death!=null)death.style.display=r.mode==1&&r.state==3?DisplayStyle.Flex:DisplayStyle.None;
  hud.Query<VisualElement>(className:"result-item").ForEach(element=>element.EnableInClassList("shown",r.mode==1&&r.state==3));
  Text(winner,r.draw!=0?"DRAW":r.winner==r.local_session_id?"YOU WIN":"ROUND OVER");Text(resultBombs,"Bombs faced: "+player.bombs_faced);Text(resultTime,"Time survived: "+TimeText(player.alive_ticks));Text(resultXp,"XP gained: "+player.xp_gained+" · Total: "+profile.total_xp);
  Text(currentLevel,"Lvl "+profile.level);Text(nextLevel,"Lvl "+(profile.level+1));if(levelFill!=null)levelFill.style.width=Length.Percent(profile.xp_to_next==0?0:Mathf.Clamp01((float)((double)profile.xp_in_level/profile.xp_to_next))*100);
  foreach(var result in session.RequestResults)if(result.kind!=1)message=result.status==1?"Server accepted the request.":"Server rejected the request.";
 }
 void OnDisable(){if(Client!=null)Client.InputBlocked=false;root?.Clear();}
}
}
