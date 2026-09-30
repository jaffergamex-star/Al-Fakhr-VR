// General-purpose unlit surface for the MOI experience. No real-time lights are used anywhere
// (mobile VR budget), so "lighting" is a cheap hemisphere term plus an optional fresnel rim.
//
// _MOI_Reveal is a global (0 = darkness, ~0.45 = blue outline state, 1 = museum fully lit)
// driven by MuseumRoom. _RevealMode selects how a surface reacts to it:
//   0 = ignores it, 1 = fades out as the room dims, 2 = light strip (warm -> blue -> off)
Shader "MOI/Unlit"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Color", Color) = (1,1,1,1)
        _Intensity ("Intensity", Float) = 1
        _Fade ("Fade", Range(0,1)) = 1
        _FakeLight ("Fake Hemisphere Light", Range(0,1)) = 0
        _Rim ("Rim Amount", Range(0,4)) = 0
        _RimColor ("Rim Color", Color) = (0.5,0.7,1,1)
        [Enum(None,0,FadeOut,1,LightStrip,2)] _RevealMode ("Museum Reveal Mode", Float) = 0
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 0
        [Enum(Off,0,On,1)] _ZWrite ("ZWrite", Float) = 1
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                half4 _RimColor;
                half _Intensity;
                half _Fade;
                half _FakeLight;
                half _Rim;
                half _RevealMode;
            CBUFFER_END
            half _MOI_Reveal;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                half3 n = normalize(i.normalWS);
                half3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half fres = pow(1.0 - saturate(abs(dot(n, v))), 3.0);

                half3 rgb = tex.rgb * _Color.rgb * _Intensity;
                rgb *= lerp(1.0, 0.35 + 0.65 * saturate(n.y * 0.5 + 0.5), _FakeLight);
                rgb += _RimColor.rgb * fres * _Rim;
                half a = saturate(tex.a * _Color.a + fres * _Rim * _RimColor.a) * _Fade;

                half lit = smoothstep(0.5, 1.0, _MOI_Reveal);
                if (_RevealMode > 1.5)
                {
                    half3 outline = half3(0.12, 0.4, 1.0) * _Intensity * tex.rgb;
                    rgb = lerp(outline, rgb, lit) * smoothstep(0.0, 0.35, _MOI_Reveal);
                }
                else if (_RevealMode > 0.5)
                {
                    rgb *= lit;
                }
                return half4(rgb, a);
            }
            ENDHLSL
        }
    }
}
