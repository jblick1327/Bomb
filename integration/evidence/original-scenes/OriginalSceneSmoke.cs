using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
#if UNITY_EDITOR
using UnityEditor.SceneManagement;
#endif
using UnityEngine.SceneManagement;

public class OriginalSceneSmoke {
 static readonly string[] Scenes={"Arena","MainMenuScene","YardLevel","menu"};
 const string Report=@"C:\Users\jblic\Downloads\BOM-Windows-Game\review\task3-20261110\original-scenes\playmode-report.txt";
 [UnityTest] public IEnumerator EachOriginalSceneLoadsAndPlays([ValueSource(nameof(Scenes))] string scene){
  LogAssert.ignoreFailingMessages=true;
  var lines=new List<string>();int errors=0,exceptions=0,warnings=0;
  Application.LogCallback hook=(text,stack,type)=>{lines.Add("["+type+"] "+text.Replace("\n"," | "));if(type==LogType.Error||type==LogType.Assert)errors++;else if(type==LogType.Exception){exceptions++;errors++;}else if(type==LogType.Warning)warnings++;};
  Application.logMessageReceived+=hook;
  string path="Assets/Game/Scenes/"+scene+".unity";
  float startFrame=Time.frameCount;
#if UNITY_EDITOR
  var op=EditorSceneManager.LoadSceneAsyncInPlayMode(path,new LoadSceneParameters(LoadSceneMode.Single));
  yield return op;
#endif
  float t0=Time.time;int f0=Time.frameCount;
  yield return new WaitForSecondsRealtime(8f);
  float played=Time.time-t0;int frames=Time.frameCount-f0;
  Application.logMessageReceived-=hook;
  var sb=new StringBuilder();sb.AppendLine("SCENE "+scene+" active="+SceneManager.GetActiveScene().name+" played_seconds="+played.ToString("F2")+" frames="+frames+" errors="+errors+" exceptions="+exceptions+" warnings="+warnings);
  foreach(var l in lines)sb.AppendLine("   "+l);
  File.AppendAllText(Report,sb.ToString());
  Assert.AreEqual(0,exceptions,"Exceptions while playing "+scene);
  Assert.Greater(frames,60,"Scene did not advance frames");
 }
}
