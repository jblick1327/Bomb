using System;
using System.Collections.Generic;
using System.IO;
using Bom.Native;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.LowLevel;

namespace Bom.Unity {
public sealed class BomClientBehaviour : MonoBehaviour {
 public Material Material;
 public Camera View;
 public GameObject PlayerPrefab,BombPrefab;
 public uint Port=32000;
 public string Address="127.0.0.1";
 BomSession session;
 BomActorShapeInfo shapeInfo;
 InputAction move,jump,blast;
 double inputOffset,start;
 GameObject terrain;
 readonly Dictionary<(uint,ulong),Transform> bodies=new Dictionary<(uint,ulong),Transform>();
 readonly Dictionary<(uint,ulong),GameObject> actors=new Dictionary<(uint,ulong),GameObject>();
 readonly List<Mesh> meshes=new List<Mesh>();
 ulong generation,revision=ulong.MaxValue,lastEvent,acceptedTopology;uint epoch;
 bool smoke,reset,reconnected,blasted;double smokeSeconds;
 string smokeStartFile="";bool smokeActive;
 float smokeMove=float.NaN;
 double smokeElapsed;float traveled,jumpRise;Vector2 lastLocal;bool hasLocal;ulong metricGeneration;uint metricEpoch;
 int snapshots,events;string failure="",identity="";
 public void Close() {session?.Dispose();session=null;generation=0;epoch=0;lastEvent=0;acceptedTopology=0;}
 void OnEnable() {
  try {
   Application.runInBackground=true;start=BomSession.Now;inputOffset=start-InputState.currentTime;
   var args=Environment.GetCommandLineArgs();
   string Arg(string key,string value){int i=Array.IndexOf(args,key);return i>=0&&i+1<args.Length?args[i+1]:value;}
   Port=uint.Parse(Arg("--bom-port",Port.ToString()));smokeSeconds=double.Parse(Arg("--bom-smoke-seconds","0"),System.Globalization.CultureInfo.InvariantCulture);smoke=smokeSeconds>0;
   smokeStartFile=Arg("--bom-smoke-start-file","");smokeActive=string.IsNullOrEmpty(smokeStartFile);
   Time.timeScale=float.Parse(Arg("--bom-time-scale",Time.timeScale.ToString(System.Globalization.CultureInfo.InvariantCulture)),System.Globalization.CultureInfo.InvariantCulture);
   int legacy=0;foreach(var behavior in FindObjectsByType<MonoBehaviour>(FindObjectsSortMode.None)){string name=behavior.GetType().Name;if(behavior.enabled&&(name=="ArenaSession"||name=="ArenaPlayerController"||name=="BombDropper"||name=="DestructibleGround"||name=="ArenaGameplayGround"))legacy++;}
   if(legacy!=0||FindObjectsByType<Rigidbody>(FindObjectsSortMode.None).Length!=0||FindObjectsByType<CharacterController>(FindObjectsSortMode.None).Length!=0)throw new InvalidOperationException("Legacy gameplay authority exists in the native network scene");
   Debug.Log("BOM UNITY AUTHORITY PASS: no enabled legacy gameplay, local rigidbodies or character controllers; timeScale="+Time.timeScale);
   session=new BomSession();Connect();
   shapeInfo=new BomActorShapeInfo{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<BomActorShapeInfo>(),version=1};BomSession.Check(BomNative.bom_actor_shape_info(ref shapeInfo));
   var build=new BomBuildInfo{struct_size=(uint)System.Runtime.InteropServices.Marshal.SizeOf<BomBuildInfo>(),version=1};BomSession.Check(BomNative.bom_build_info(ref build));identity="Native "+build.source_build_tag+" / protocol "+build.game_protocol;
   Debug.Log("BOM UNITY ABI PASS: thirteen layouts, offsets, alignment; "+identity);
   move=new InputAction("Move",InputActionType.Value);move.AddCompositeBinding("1DAxis").With("Negative","<Keyboard>/a").With("Positive","<Keyboard>/d");move.AddCompositeBinding("1DAxis").With("Negative","<Keyboard>/leftArrow").With("Positive","<Keyboard>/rightArrow");
   move.performed+=OnMove;move.canceled+=OnMove;
   jump=new InputAction("Jump",InputActionType.Button,"<Keyboard>/space");jump.performed+=c=>SendInput(()=>BomSession.Check(BomNative.bom_client_enqueue_jump(session.Handle,c.time+inputOffset)));
   blast=new InputAction("Blast",InputActionType.Button,"<Mouse>/leftButton");blast.performed+=c=>SendInput(()=>{
    if(View==null||Mouse.current==null)return;var ray=View.ScreenPointToRay(Mouse.current.position.ReadValue());if(new Plane(Vector3.forward,Vector3.zero).Raycast(ray,out float distance)){Vector3 point=ray.GetPoint(distance);BomSession.Check(BomNative.bom_client_enqueue_action(session.Handle,c.time+inputOffset,point.x,point.y));}
   });
   move.Enable();jump.Enable();blast.Enable();
  } catch(Exception e){Fail(e);}
 }
 void SendInput(Action send){if(session==null)return;try{send();}catch(Exception error){Fail(error);}}
 void OnMove(InputAction.CallbackContext context)=>SendInput(()=>BomSession.Check(BomNative.bom_client_set_held_input(session.Handle,context.time+inputOffset,context.ReadValue<float>())));
 void Connect(){var octets=Address.Split('.');if(octets.Length!=4)throw new ArgumentException("Enter a numeric IPv4 address");uint ip=0;foreach(string octet in octets)ip=(ip<<8)|byte.Parse(octet);session.Connect(ip,Port,Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN")??"");}
 void Update() {
  if(session==null)return;
  try {
   double now=BomSession.Now,elapsed=now-start;
   if(smoke&&!smokeActive){if(File.Exists(smokeStartFile)){smokeActive=true;start=now;elapsed=0;hasLocal=false;Debug.Log("BOM UNITY SYNCHRONIZED START");}else if(elapsed>120)throw new TimeoutException("Live test start signal did not arrive");}
   smokeElapsed=elapsed;
   if(smoke&&smokeActive){float requested=elapsed%4<2?1:-1;if(requested!=smokeMove){BomSession.Check(BomNative.bom_client_set_held_input(session.Handle,now,requested));smokeMove=requested;}if(elapsed>3&&!blasted){BomSession.Check(BomNative.bom_client_enqueue_action(session.Handle,now,-6.4f,2.3f));BomSession.Check(BomNative.bom_client_enqueue_jump(session.Handle,now));blasted=true;}}
   session.Poll(now,Accept);
   if(smoke && smokeActive && elapsed>5&&!reset&&(session.Sample.flags&2)!=0&&!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("BOM_TEST_HOST_TOKEN"))){BomSession.Check(BomNative.bom_client_host_command(session.Handle,1,0,0));reset=true;}
   if(smoke && smokeActive && elapsed>8&&!reconnected){BomSession.Check(BomNative.bom_client_disconnect(session.Handle));Connect();reconnected=true;smokeMove=float.NaN;}
   if(smoke && smokeActive && elapsed>=smokeSeconds){bool passed=snapshots>1&&events>0&&reconnected&&session.Sample.input_count>60&&traveled>0.25f&&jumpRise>0.03f;Debug.Log("BOM UNITY LIVE "+(passed?"PASS":"FAIL")+" snapshots="+snapshots+" events="+events+" epoch="+epoch+" generation="+generation+" inputs="+session.Sample.input_count+" traveled="+traveled+" jumpRise="+jumpRise);Application.Quit(passed?0:2);Close();}
  } catch(Exception e){Fail(e);}
 }
 void Fail(Exception error){failure=error.ToString();Debug.LogError(failure);Close();ClearScene();if(smoke)Application.Quit(3);}
 void OnApplicationFocus(bool focused){if(!focused)SendInput(()=>BomSession.Check(BomNative.bom_client_set_held_input(session.Handle,BomSession.Now,0)));}
 void OnDisable(){move?.Dispose();jump?.Dispose();blast?.Dispose();move=jump=blast=null;Close();ClearScene();}
 void OnApplicationQuit(){Close();}
 void ClearScene(){if(terrain!=null){terrain.SetActive(false);Destroy(terrain);terrain=null;}foreach(var actor in actors.Values)Destroy(actor);actors.Clear();bodies.Clear();foreach(var mesh in meshes)Destroy(mesh);meshes.Clear();revision=ulong.MaxValue;}
 GameObject Visual(string name,Transform parent,Mesh mesh,uint rgba,List<Mesh> owned) {
  var obj=new GameObject(name);obj.transform.SetParent(parent,false);obj.AddComponent<MeshFilter>().sharedMesh=mesh;var renderer=obj.AddComponent<MeshRenderer>();renderer.sharedMaterials=new[]{Material,Material};
  Color color=new Color32((byte)rgba,(byte)(rgba>>8),(byte)(rgba>>16),255);var properties=new MaterialPropertyBlock();properties.SetColor("_BaseColor",color);renderer.SetPropertyBlock(properties,0);properties.SetColor("_BaseColor",new Color(color.r*0.7f,color.g*0.7f,color.b*0.7f,1));renderer.SetPropertyBlock(properties,1);owned.Add(mesh);return obj;
 }
 void Accept(BomSession client) {
  var s=client.Sample;
  if((s.flags&6)!=6){if(terrain!=null)ClearScene();return;}
  if(s.to_revision!=s.revision||s.effective_tick>s.presentation_tick+0.00001)throw new InvalidOperationException("Native topology is not due at this presentation tick");
  if(generation!=s.connection_generation||epoch!=s.epoch||revision!=s.revision||((s.transaction_flags&1)!=0&&s.transaction_id!=acceptedTopology)) {
   var next=new GameObject("Native geometry "+s.epoch+":"+s.revision);next.SetActive(false);
   var nextBodies=new Dictionary<(uint,ulong),Transform>();var nextMeshes=new List<Mesh>();
   try {
    for(int i=0;i<s.cell_count;i++) {
     var cell=client.Cells[i];if(cell.vertex_count<3||cell.vertex_start+cell.vertex_count>s.vertex_count)throw new InvalidOperationException("Cell outline out of bounds");
     var key=(cell.pose_kind,cell.pose_kind==1?cell.id:cell.piece_id);
     if(!nextBodies.TryGetValue(key,out var body)){body=new GameObject("Body "+key).transform;body.SetParent(next.transform,false);body.position=new Vector3(cell.pivot_x,cell.pivot_y,0);nextBodies.Add(key,body);}
     var outline=new Vector2[cell.vertex_count];for(uint j=0;j<cell.vertex_count;j++)outline[j]=BomUnityCoordinates.RestVertex(client.Vertices[cell.vertex_start+j],cell);
     Visual("Cell "+cell.id,body,BomExtrusion.Build(outline,0.6f,new Vector2(cell.pivot_x,cell.pivot_y)),cell.color_rgba,nextMeshes);
    }
   } catch {Destroy(next);foreach(var mesh in nextMeshes)Destroy(mesh);throw;}
   bool newSession=generation!=s.connection_generation||epoch!=s.epoch;
   if(newSession && s.vertex_count>0 && View!=null) {
    Vector2 min=new Vector2(float.MaxValue,float.MaxValue),max=new Vector2(float.MinValue,float.MinValue);
    for(int i=0;i<s.vertex_count;i++){var v=client.Vertices[i];min=Vector2.Min(min,new Vector2(v.x,v.y));max=Vector2.Max(max,new Vector2(v.x,v.y));}
    Vector2 center=(min+max)/2;View.transform.position=new Vector3(center.x,center.y,-40);View.orthographicSize=Mathf.Max(6,(max.y-min.y)/2+2,(max.x-min.x)/2/Mathf.Max(0.1f,View.aspect)+2);
   }
   ClearScene();terrain=next;meshes.AddRange(nextMeshes);foreach(var pair in nextBodies)bodies.Add(pair.Key,pair.Value);
   terrain.SetActive(true);generation=s.connection_generation;epoch=s.epoch;revision=s.revision;acceptedTopology=s.transaction_id;if(newSession)lastEvent=0;snapshots++;
   Debug.Log("BOM UNITY SNAPSHOT generation="+generation+" epoch="+epoch+" revision="+revision+" cells="+s.cell_count+" hash="+s.canonical_hash);
  }
  var seen=new HashSet<(uint,ulong)>();
  for(int i=0;i<s.pose_count;i++) {
   var pose=client.Poses[i];var key=(pose.kind,pose.id);Transform body;
   if(pose.kind<2){if(!bodies.TryGetValue(key,out body))continue;}
   else {
    seen.Add(key);if(!actors.TryGetValue(key,out var actor)){
     var prefab=pose.kind==2?PlayerPrefab:BombPrefab;
     if(prefab!=null){actor=Instantiate(prefab);actor.name=(pose.kind==2?"Player ":"Bomb ")+pose.id;var properties=new MaterialPropertyBlock();Color color=pose.kind==2?new Color32(66,174,231,255):new Color32(234,72,72,255);properties.SetColor("_BaseColor",color);actor.GetComponent<MeshRenderer>().SetPropertyBlock(properties,0);}
     else{actor=Visual((pose.kind==2?"Player ":"Bomb ")+pose.id,null,BomExtrusion.Build(BomUnityCoordinates.ActorOutline(pose.kind==2,shapeInfo)),pose.kind==2?0xffe7ae42u:0xff4848eau,meshes);actor.AddComponent<BomActorView>();}
     actors.Add(key,actor);
    }body=actor.transform;
   }
   if(body.TryGetComponent<BomActorView>(out var actorView))actorView.Apply(pose);else body.SetPositionAndRotation(new Vector3(pose.x,pose.y,0),BomUnityCoordinates.Rotation(pose.angle));
   if(smoke&&smokeActive&&pose.kind==2&&pose.id==s.local_player_id){
    if(hasLocal&&metricGeneration==s.connection_generation&&metricEpoch==s.epoch){traveled+=Mathf.Abs(pose.x-lastLocal.x);if(smokeElapsed>=3&&smokeElapsed<=5)jumpRise+=Mathf.Max(0,pose.y-lastLocal.y);}
    lastLocal=new Vector2(pose.x,pose.y);hasLocal=true;metricGeneration=s.connection_generation;metricEpoch=s.epoch;
   }
  }
  var gone=new List<(uint,ulong)>();foreach(var pair in actors)if(!seen.Contains(pair.Key))gone.Add(pair.Key);foreach(var key in gone){var filter=actors[key].GetComponent<MeshFilter>();if(meshes.Remove(filter.sharedMesh))Destroy(filter.sharedMesh);Destroy(actors[key]);actors.Remove(key);}
  for(int i=0;i<s.event_count;i++){var e=client.Events[i];if(e.tick>s.presentation_tick+0.00001)throw new InvalidOperationException("Native event is ahead of presentation");if(e.id<=lastEvent)continue;lastEvent=e.id;events++;if(e.radius>0){var effect=new GameObject("Native explosion "+e.id);effect.transform.SetParent(terrain.transform,false);effect.AddComponent<BomExplosionView>().Show(Material,new Vector3(e.x,e.y,-0.5f),e.radius);}Debug.Log("BOM UNITY EVENT id="+e.id+" tick="+e.tick+" presentation="+s.presentation_tick);}
 }
 void OnGUI(){GUI.Box(new Rect(12,12,700,86),"BOM native client — A/D move · Space jump · Click blast\n"+identity+"\n"+(session!=null?"Epoch "+epoch+" · revision "+revision+" · events "+events+" "+session.Error:failure));}
}
}
