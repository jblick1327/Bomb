// Unlit glow for particles, auras and the blast ring. The soft round shape is
// drawn from the UVs, so no texture is needed. _Intensity lifts colours above
// 1 so the bloom picks them up (particle colours themselves stop at 1).
// _Strip 1 fades only across the width, for line renderers (the blast ring).
// Blend is set per material: additive (One One) or soft (SrcAlpha OneMinusSrcAlpha).
Shader "Bom/FX Particle"
{
    Properties
    {
        _TintColor("Tint", Color) = (1, 1, 1, 1)
        _Intensity("Intensity", Float) = 1
        _Softness("Edge Softness", Range(0.5, 4)) = 1.5
        _Strip("Strip (line renderers)", Range(0, 1)) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Dst Blend", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
            "PreviewType" = "Plane"
        }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _TintColor;
                half _Intensity;
                half _Softness;
                half _Strip;
                half _SrcBlend;
                half _DstBlend;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                half4 color : COLOR;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half4 color : COLOR;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.color = input.color * _TintColor;
                output.uv = input.uv;
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 d = input.uv * 2.0 - 1.0;
                half round = saturate(1.0 - dot(d, d));
                half strip = saturate(1.0 - abs(d.y));
                half shape = pow(lerp(round, strip, _Strip), _Softness);
                half alpha = input.color.a * shape;
                // Additive materials use the colour times alpha; soft ones use alpha.
                return half4(input.color.rgb * _Intensity * (_DstBlend == 1 ? alpha : 1.0), alpha);
            }
            ENDHLSL
        }
    }
}
