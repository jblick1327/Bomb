using System.Collections.Generic;
using UnityEngine;

// Tracks a hierarchy of mesh objects, applies blast damage, and restores their states.
[AddComponentMenu("Arena/Destructible Multi Mesh")]
public sealed class DestructibleMultiMesh : MonoBehaviour, IBlastReceiver
{
    private readonly Dictionary<GameObject, bool> rendererStates = new Dictionary<GameObject, bool>();
    private readonly Dictionary<Collider, bool> colliderStates = new Dictionary<Collider, bool>();
    private MeshRenderer[] meshRenderers;
    private Collider[] colliders;

    private void Awake()
    {
        DisableLegacyArenaFloor();
        CacheChildren();
    }

    public void ReceiveBlast(BlastPayload blast)
    {
        CacheChildren();
        foreach (MeshRenderer meshRenderer in meshRenderers)
        {
            if (meshRenderer == null || !meshRenderer.gameObject.activeInHierarchy) continue;
            Bounds bounds = meshRenderer.bounds;
            Vector2 closest = new Vector2(
                Mathf.Clamp(blast.Center.x, bounds.min.x, bounds.max.x),
                Mathf.Clamp(blast.Center.y, bounds.min.y, bounds.max.y));
            float distance = Vector2.Distance(blast.Center, closest);
            if (distance > blast.OuterRadius) continue;

            if (IsTerrainMesh(meshRenderer.gameObject))
            {
                continue;
            }

            DestructibleObject shatter = EnsureShatterReceiver(meshRenderer.gameObject);
            if (shatter != null)
            {
                // Let the mesh's destruction behavior decide whether it carves
                // or breaks. Disabling it here bypassed carving for direct hits.
                shatter.ReceiveBlast(blast);
            }
            else if (distance <= blast.InnerRadius)
            {
                DisableChild(meshRenderer.gameObject);
            }
        }
    }

    public void ResetTarget()
    {
        foreach (KeyValuePair<GameObject, bool> state in rendererStates)
            if (state.Key != null) state.Key.SetActive(state.Value);
        foreach (KeyValuePair<Collider, bool> state in colliderStates)
            if (state.Key != null) state.Key.enabled = state.Value;

        foreach (DestructibleObject shatter in GetComponentsInChildren<DestructibleObject>(true))
            shatter.ResetObject();
    }

    private void CacheChildren()
    {
        foreach (MeshFilter filter in GetComponentsInChildren<MeshFilter>(true))
        {
            if (IsGrassMesh(filter.gameObject))
            {
                DestructibleGround grass = filter.GetComponent<DestructibleGround>();
                if (grass == null) grass = filter.gameObject.AddComponent<DestructibleGround>();
                grass.SetCollisionEnabled(true);
                continue;
            }
            if (filter.GetComponent<ArenaGameplayGround>() != null)
                continue;
            if (IsTerrainMesh(filter.gameObject))
            {
                foreach (DestructibleObject rock in filter.GetComponents<DestructibleObject>())
                    rock.enabled = false;
            }
            if (filter.sharedMesh == null) continue;
            MeshCollider meshCollider = filter.GetComponent<MeshCollider>();
            if (meshCollider == null) meshCollider = filter.gameObject.AddComponent<MeshCollider>();
            if (meshCollider.sharedMesh == null) meshCollider.sharedMesh = filter.sharedMesh;
        }
        meshRenderers = GetComponentsInChildren<MeshRenderer>(true);
        colliders = GetComponentsInChildren<Collider>(true);
        foreach (MeshRenderer meshRenderer in meshRenderers)
        {
            if (meshRenderer != null && !rendererStates.ContainsKey(meshRenderer.gameObject))
                rendererStates.Add(meshRenderer.gameObject, meshRenderer.gameObject.activeSelf);
        }
        foreach (Collider collider in colliders)
        {
            if (collider != null && !colliderStates.ContainsKey(collider))
                colliderStates.Add(collider, collider.enabled);
        }
    }

    private void DisableLegacyArenaFloor()
    {
        if (UnityEngine.SceneManagement.SceneManager.GetActiveScene().name != "YardLevel") return;
        ArenaLayout layout = FindFirstObjectByType<ArenaLayout>(FindObjectsInactive.Include);
        if (layout == null) return;
        Transform floor = layout.transform.Find("Floor");
        if (floor == null || floor.IsChildOf(transform)) return;
        MeshRenderer renderer = floor.GetComponent<MeshRenderer>();
        if (renderer != null) renderer.enabled = false;
        foreach (Collider collider in floor.GetComponentsInChildren<Collider>(true))
            collider.enabled = false;
    }

    private void DisableChild(GameObject child)
    {
        if (child == gameObject) return;
        child.SetActive(false);
        foreach (Collider collider in child.GetComponentsInChildren<Collider>(true))
        {
            if (collider == null) continue;
            colliderStates[collider] = collider.enabled;
            collider.enabled = false;
        }
    }

    private static DestructibleObject EnsureShatterReceiver(GameObject child)
    {
        DestructibleObject existing = child.GetComponent<DestructibleObject>();
        if (existing != null) return existing;
        MeshFilter filter = child.GetComponent<MeshFilter>();
        if (filter == null || filter.sharedMesh == null) return null;
        MeshCollider collider = child.GetComponent<MeshCollider>();
        if (collider == null) collider = child.AddComponent<MeshCollider>();
        if (collider.sharedMesh == null) collider.sharedMesh = filter.sharedMesh;
        return child.AddComponent<DestructibleObject>();
    }

    private static bool IsTerrainMesh(GameObject child)
    {
        return child.name == "Grass_Mesh" || child.name == "Ground_Mesh";
    }

    private static bool IsGrassMesh(GameObject child)
    {
        return child.name == "Grass_Mesh";
    }

}
