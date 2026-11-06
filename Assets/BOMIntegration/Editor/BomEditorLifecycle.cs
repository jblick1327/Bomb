using System;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// Runs only when explicitly requested in the isolated validation Editor.
[InitializeOnLoad]public static class BomEditorLifecycle {
 const string Active="BOM.Lifecycle.Active",Cycle="BOM.Lifecycle.Cycle",Deadline="BOM.Lifecycle.Deadline";
 static BomEditorLifecycle(){EditorApplication.update+=Update;EditorApplication.playModeStateChanged+=Changed;}
 public static void Run(){SessionState.SetBool(Active,true);SessionState.SetInt(Cycle,0);EditorSceneManager.OpenScene("Assets/BOMIntegration/NativeSlice.unity");SessionState.SetString(Deadline,"0");EditorApplication.isPlaying=true;}
 static void Changed(PlayModeStateChange change){
  if(!SessionState.GetBool(Active,false))return;
  if(change==PlayModeStateChange.EnteredPlayMode)SessionState.SetString(Deadline,(EditorApplication.timeSinceStartup+6).ToString("R",System.Globalization.CultureInfo.InvariantCulture));
  if(change==PlayModeStateChange.EnteredEditMode){
   int cycle=SessionState.GetInt(Cycle,0)+1;SessionState.SetInt(Cycle,cycle);
   if(cycle>=3){Debug.Log("BOM EDITOR LIFECYCLE PASS: three live play/stop cycles, including disabled domain reload");SessionState.SetBool(Active,false);EditorSettings.enterPlayModeOptionsEnabled=false;EditorApplication.Exit(0);return;}
   EditorSettings.enterPlayModeOptionsEnabled=true;EditorSettings.enterPlayModeOptions=EnterPlayModeOptions.DisableDomainReload;
   SessionState.SetString(Deadline,(EditorApplication.timeSinceStartup+1).ToString("R",System.Globalization.CultureInfo.InvariantCulture));
  }
 }
 static void Update(){
  if(!SessionState.GetBool(Active,false)||EditorApplication.isCompiling||EditorApplication.isPlayingOrWillChangePlaymode!=EditorApplication.isPlaying)return;
  if(!double.TryParse(SessionState.GetString(Deadline,"0"),System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out double deadline)||deadline<=0||EditorApplication.timeSinceStartup<deadline)return;
  SessionState.SetString(Deadline,"0");EditorApplication.isPlaying=!EditorApplication.isPlaying;
 }
}
