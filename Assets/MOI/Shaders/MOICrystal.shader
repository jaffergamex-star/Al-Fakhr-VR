// The guide crystal. Faceted (mesh has per-face normals), premultiplied-alpha, no scene lights.
// _Glow is animated by CrystalGuide: ~1 resting pulse, up to ~6 for the white-out in beat 5.
Shader "MOI/Crystal"
{
    Properties
    {
        _CoreColor ("Core Color", Color) = (0.1, 0.35, 1, 1)
        _RimColor ("Rim Color", Color) = (0.75, 0.9, 1, 1)
        _Glow ("Glow", Range(0, 8)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }
        Pass
        {
            Blend One OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _CoreColor;
                half4 _RimColor;
                half _Glow;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half3 normalWS : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
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
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half3 n = normalize(i.normalWS);
                half3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half ndv = abs(dot(n, v));
                half fres = pow(1.0 - ndv, 2.5);

                // Fixed "key light" purely so neighbouring facets read as different tones.
                half3 l = normalize(half3(0.3, 0.8, -0.5));
                half facet = abs(dot(n, l));
                half sparkle = pow(saturate(dot(reflect(-v, n), l)), 24.0);

                half3 rgb = _CoreColor.rgb * (0.3 + 0.7 * facet) * (0.4 + 0.6 * _Glow)
                          + _RimColor.rgb * fres * (0.8 + _Glow)
                          + sparkle * _RimColor.rgb;
                half a = saturate(0.5 + fres * 0.5);
                return half4(rgb * a, a);
            }
            ENDHLSL
        }
    }
}
