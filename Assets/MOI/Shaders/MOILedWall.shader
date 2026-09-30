// The museum's curved LED wall. Follows the storyboard's three states off the global _MOI_Reveal:
// 1 = full picture, ~0.45 = glowing blue outlines of the same picture, 0 = black.
Shader "MOI/LedWall"
{
    Properties
    {
        _MainTex ("Wall Content", 2D) = "black" {}
        _Brightness ("Brightness", Float) = 1
        _OutlineColor ("Outline Color", Color) = (0.15, 0.45, 1, 1)
        _OutlineGain ("Outline Gain", Float) = 7
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                half4 _OutlineColor;
                half _Brightness;
                half _OutlineGain;
            CBUFFER_END
            half _MOI_Reveal;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half Luma(float2 uv)
            {
                return dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, half3(0.299, 0.587, 0.114));
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half3 full = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb * _Brightness;

                float2 d = _MainTex_TexelSize.xy * 1.5;
                half l = Luma(i.uv);
                half edge = saturate((abs(l - Luma(i.uv + float2(d.x, 0))) + abs(l - Luma(i.uv + float2(0, d.y)))) * _OutlineGain);
                half3 outline = _OutlineColor.rgb * edge * 1.6;

                half3 rgb = lerp(outline * smoothstep(0.0, 0.4, _MOI_Reveal), full, smoothstep(0.5, 1.0, _MOI_Reveal));
                return half4(rgb, 1);
            }
            ENDHLSL
        }
    }
}
