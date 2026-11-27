#ifndef BOM_CLAY_INPUT_INCLUDED
#define BOM_CLAY_INPUT_INCLUDED

// URP's Simple Lit inputs, plus the clay detail settings. URP's own Simple Lit
// pass files are reused with this, so it also defines Simple Lit's guard and
// helper functions.
#define UNIVERSAL_SIMPLE_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/DebugMipmapStreamingMacros.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    float4 _BaseMap_TexelSize;
    half4 _BaseColor;
    half4 _SpecColor;
    half4 _EmissionColor;
    half _Cutoff;
    half _Surface;
    // Clay detail: large soft blotches, fine grain, lighter tops, faint layers.
    half _Mottle;
    float _MottleScale;
    half _Grain;
    float _GrainScale;
    half _TopLight;
    half _Bands;
    float _BandScale;
    UNITY_TEXTURE_STREAMING_DEBUG_VARS;
CBUFFER_END

TEXTURE2D(_SpecGlossMap);       SAMPLER(sampler_SpecGlossMap);

half4 SampleSpecularSmoothness(float2 uv, half alpha, half4 specColor, TEXTURE2D_PARAM(specMap, sampler_specMap))
{
    half4 specularSmoothness = half4(0, 0, 0, 1);
#ifdef _SPECGLOSSMAP
    specularSmoothness = SAMPLE_TEXTURE2D(specMap, sampler_specMap, uv) * specColor;
#elif defined(_SPECULAR_COLOR)
    specularSmoothness = specColor;
#endif
#ifdef _GLOSSINESS_FROM_BASE_ALPHA
    specularSmoothness.a = alpha;
#endif
    return specularSmoothness;
}

inline void InitializeSimpleLitSurfaceData(float2 uv, out SurfaceData outSurfaceData)
{
    outSurfaceData = (SurfaceData)0;

    half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
    outSurfaceData.alpha = albedoAlpha.a * _BaseColor.a;
    outSurfaceData.alpha = AlphaDiscard(outSurfaceData.alpha, _Cutoff);

    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    outSurfaceData.albedo = AlphaModulate(outSurfaceData.albedo, outSurfaceData.alpha);

    half4 specularSmoothness = SampleSpecularSmoothness(uv, outSurfaceData.alpha, _SpecColor, TEXTURE2D_ARGS(_SpecGlossMap, sampler_SpecGlossMap));
    outSurfaceData.metallic = 0.0;
    outSurfaceData.specular = specularSmoothness.rgb;
    outSurfaceData.smoothness = specularSmoothness.a;
    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap));
    outSurfaceData.occlusion = 1.0;
    outSurfaceData.emission = SampleEmission(uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));
}

// ---------- Clay detail ----------
// Solid 3D noise from the world position, so it needs no UVs and runs
// seamlessly across cut and carved surfaces.

float BomHash(float3 p)
{
    p = frac(p * 0.3183099 + 0.1);
    p *= 17.0;
    return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float BomNoise(float3 x)
{
    float3 i = floor(x);
    float3 f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(lerp(BomHash(i + float3(0, 0, 0)), BomHash(i + float3(1, 0, 0)), f.x),
                     lerp(BomHash(i + float3(0, 1, 0)), BomHash(i + float3(1, 1, 0)), f.x), f.y),
                lerp(lerp(BomHash(i + float3(0, 0, 1)), BomHash(i + float3(1, 0, 1)), f.x),
                     lerp(BomHash(i + float3(0, 1, 1)), BomHash(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

// Brightness multiplier for the clay look at this point and facing.
half BomClayShade(float3 positionWS, half3 normalWS)
{
    float3 p = positionWS * _MottleScale;
    float mottle = BomNoise(p) * 0.65 + BomNoise(p * 2.13 + 7.1) * 0.35;
    float grain = BomNoise(positionWS * _GrainScale);
    float band = sin(positionWS.y * _BandScale + BomNoise(positionWS * 0.7) * 3.0);
    half shade = 1.0
        + _Mottle * (mottle - 0.5) * 2.0
        + _Grain * (grain - 0.5) * 2.0
        + _Bands * band
        + _TopLight * saturate(normalWS.y);
    return max(shade, 0.0);
}

#endif
