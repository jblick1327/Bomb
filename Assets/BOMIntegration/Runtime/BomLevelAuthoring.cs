using System;
using System.Collections.Generic;
using UnityEngine;
namespace Bom.Unity {
[Serializable]public struct BomBounds2 {public Vector2 Minimum,Maximum;public BomBounds2(Vector2 minimum,Vector2 maximum){Minimum=minimum;Maximum=maximum;}}
[Serializable]public sealed class BomIdentityRecord {public string ObjectGlobalId,IdentityDecimal;}
[Serializable]public sealed class BomGlueAuthoring {public BomPhysicsPart A,B;}
[DisallowMultipleComponent]public sealed class BomLevelAuthoring:MonoBehaviour {
 public string LevelId="";
 public string NextIdentityDecimal="1";
 [HideInInspector]public string StoredSceneGuid="",StoredRootGlobalId="";
 [HideInInspector]public List<BomIdentityRecord> IdentityRegistry=new List<BomIdentityRecord>();
 public int Seed=42;
 public string GameplayConfigId="bom-default-v1";
 public BomBounds2 SimulationBounds=new BomBounds2(new Vector2(-8,-3),new Vector2(9,12));
 public BomBounds2 KillBounds=new BomBounds2(new Vector2(-8.5f,-3),new Vector2(9.5f,12));
 public BomBounds2 CameraBounds=new BomBounds2(new Vector2(-9,-4),new Vector2(10,13));
 public BomBounds2 AimBounds=new BomBounds2(new Vector2(-8,-3),new Vector2(9,12));
 public BomBounds2 FragmentCullBounds=new BomBounds2(new Vector2(-20,-5),new Vector2(21,20));
 public Vector2[] Spawns={new Vector2(-4.5f,.565f),new Vector2(4.5f,.565f),new Vector2(-2,.565f),new Vector2(2,.565f)};
 public Vector2 BombSpawnX=new Vector2(-7,8);
 public float BombSpawnHeight=7.3f;
 public BomBounds2 BombCleanupBounds=new BomBounds2(new Vector2(-9,-3),new Vector2(10,20));
 public List<BomGlueAuthoring> Glue=new List<BomGlueAuthoring>();
 public BomVisualRegistry VisualRegistry;
}
}
