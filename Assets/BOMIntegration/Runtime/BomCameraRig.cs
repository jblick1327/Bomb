using System.Collections.Generic;
using UnityEngine;

namespace Bom.Unity
{
    // Presentation only. Frames the native positions it is given and shakes on native explosion events.
    // It reads copied native state and never decides an outcome.
    [DisallowMultipleComponent, RequireComponent(typeof(Camera))]
    public sealed class BomCameraRig : MonoBehaviour
    {
        [Header("Framing")]
        [SerializeField, Min(0f)]
        float padding = 0.5f;

        [SerializeField, Min(0.01f)]
        float smoothTime = 0.12f;

        [SerializeField, Min(1f), Tooltip("Smallest visible height in world units.")]
        float minViewHeight = 16f;

        [SerializeField, Range(0f, 45f), Tooltip("Downward camera angle in degrees.")]
        float tiltDegrees = 10f;

        [SerializeField, Min(0f), Tooltip("Half the height of a player, kept inside the frame.")]
        float playerHalfSize = 0.5f;

        [
            SerializeField,
            Min(0f),
            Tooltip("Half the depth of the scene, so a tilted view keeps it.")
        ]
        float sceneHalfDepth = 1f;

        [SerializeField, Min(1f)]
        float cameraDistance = 40f;

        [Header("Explosion shake")]
        [SerializeField, Min(0f)]
        float maxShakeAmplitude = 0.35f;

        [SerializeField, Min(0.01f)]
        float shakeSeconds = 0.25f;

        [
            SerializeField,
            Min(0.1f),
            Tooltip("No shake beyond this many blast radii from the local player.")
        ]
        float shakeRangeInBlastRadii = 3f;

        // Filled by BomClientBehaviour with the position of every living player.
        public readonly List<Vector2> Targets = new List<Vector2>(4);
        public Vector2 Center => center;
        public float OrthographicSize => size;
        public float ShakeAmplitudeNow => ShakeAmplitudeAt(Time.time);

        Camera view;
        bool hasBounds,
            snap;
        Vector2 boundsLo,
            boundsHi,
            center,
            centerVelocity;
        float size,
            sizeVelocity;
        float shakeStart = float.NegativeInfinity,
            shakePeak;

        public void Configure(Vector2 lo, Vector2 hi)
        {
            boundsLo = lo;
            boundsHi = hi;
            hasBounds = true;
            snap = true;
            Targets.Clear();
            shakePeak = 0;
            Debug.Log(
                "BOM UNITY CAMERA RIG bounds="
                    + lo
                    + ".."
                    + hi
                    + " min_view_height="
                    + minViewHeight
                    + " padding="
                    + padding
                    + " smooth_time="
                    + smoothTime
                    + " tilt="
                    + tiltDegrees
            );
        }

        // Amplitude for a native explosion, given the local player's position. Zero beyond the range.
        public float ShakeFor(Vector2 blast, float blastRadius, Vector2 local)
        {
            float range = Mathf.Max(0.0001f, blastRadius) * shakeRangeInBlastRadii;
            float distance = Vector2.Distance(blast, local);
            return distance >= range ? 0 : maxShakeAmplitude * (1 - distance / range);
        }

        public void Shake(Vector2 blast, float blastRadius, bool hasLocal, Vector2 local)
        {
            float amplitude = ShakeFor(blast, blastRadius, hasLocal ? local : center);
            // A stronger shake replaces a weaker one that is still running; shakes never add up.
            if (amplitude > 0 && amplitude >= ShakeAmplitudeAt(Time.time))
            {
                shakeStart = Time.time;
                shakePeak = amplitude;
            }
        }

        float ShakeAmplitudeAt(float now)
        {
            float age = now - shakeStart;
            return age < 0 || age >= shakeSeconds ? 0 : shakePeak * (1 - age / shakeSeconds);
        }

        void LateUpdate()
        {
            if (!hasBounds)
                return;
            if (view == null)
                view = GetComponent<Camera>();
            float cos = Mathf.Cos(tiltDegrees * Mathf.Deg2Rad),
                sin = Mathf.Sin(tiltDegrees * Mathf.Deg2Rad),
                aspect = Mathf.Max(0.1f, view.aspect),
                minSize = minViewHeight / 2;
            Vector2 boundsCenter = (boundsLo + boundsHi) / 2,
                boundsHalf = (boundsHi - boundsLo) / 2;
            // The whole of camera_bounds is the widest view.
            float maxSize = Mathf.Max(
                minSize,
                (boundsHalf.y + padding) * cos + sceneHalfDepth * sin,
                (boundsHalf.x + padding) / aspect
            );
            Vector2 wantCenter = boundsCenter;
            float wantSize = maxSize;
            if (Targets.Count > 0)
            {
                Vector2 lo = Targets[0],
                    hi = Targets[0];
                for (int i = 1; i < Targets.Count; i++)
                {
                    lo = Vector2.Min(lo, Targets[i]);
                    hi = Vector2.Max(hi, Targets[i]);
                }
                float margin = padding + playerHalfSize;
                wantCenter = (lo + hi) / 2;
                float needed = Mathf.Max(
                    ((hi.y - lo.y) / 2 + margin) * cos + sceneHalfDepth * sin,
                    ((hi.x - lo.x) / 2 + margin) / aspect
                );
                wantSize = Mathf.Clamp(needed, minSize, maxSize);
            }
            // Keep the view inside camera_bounds. A view wider than the bounds is centred on them.
            float halfWidth = wantSize * aspect,
                halfHeight = Mathf.Max(0, wantSize - sceneHalfDepth * sin) / cos;
            wantCenter.x = ClampAround(wantCenter.x, boundsCenter.x, boundsHalf.x - halfWidth);
            wantCenter.y = ClampAround(wantCenter.y, boundsCenter.y, boundsHalf.y - halfHeight);
            if (snap)
            {
                center = wantCenter;
                size = wantSize;
                centerVelocity = Vector2.zero;
                sizeVelocity = 0;
                snap = false;
            }
            else
            {
                center = Vector2.SmoothDamp(
                    center,
                    wantCenter,
                    ref centerVelocity,
                    smoothTime,
                    Mathf.Infinity,
                    Time.deltaTime
                );
                size = Mathf.SmoothDamp(
                    size,
                    wantSize,
                    ref sizeVelocity,
                    smoothTime,
                    Mathf.Infinity,
                    Time.deltaTime
                );
            }
            var rotation = Quaternion.Euler(tiltDegrees, 0, 0);
            Vector3 position =
                new Vector3(center.x, center.y, 0) - rotation * Vector3.forward * cameraDistance;
            float shake = ShakeAmplitudeAt(Time.time);
            if (shake > 0)
            {
                Vector2 jitter = Random.insideUnitCircle * shake;
                position += rotation * new Vector3(jitter.x, jitter.y, 0);
            }
            view.orthographic = true;
            view.orthographicSize = size;
            transform.SetPositionAndRotation(position, rotation);
        }

        static float ClampAround(float value, float middle, float limit) =>
            Mathf.Clamp(value, middle - Mathf.Max(0, limit), middle + Mathf.Max(0, limit));
    }
}
