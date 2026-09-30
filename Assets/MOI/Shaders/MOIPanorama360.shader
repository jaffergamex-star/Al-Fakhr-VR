// 360 video on the sky: Unity's Skybox/Panoramic (latitude-longitude, mono / side-by-side / over-under, same
// colour maths, so films look exactly as before) plus _Zoom for the front of the picture (the film's centre):
// above 1 zoomed in (bigger), below 1 zoomed out (0.8 = everything looks 1.25 times farther away), easing back to 1
// behind the viewer, so the whole sphere stays covered with no seam or pinch. Angle from the front t is shown with
// the picture from t - (1 - 1/zoom) * sin(t) (valid for zoom > 0.5).
Shader "MOI/Panorama360"
{
    Properties
    {
        _Tint ("Tint Color", Color) = (.5, .5, .5, .5)
        [Gamma] _Exposure ("Exposure", Range(0, 8)) = 1.0
        _Rotation ("Rotation", Range(0, 360)) = 0
        [NoScaleOffset] _MainTex ("Spherical (HDR)", 2D) = "grey" {}
        [Enum(None, 0, Side by Side, 1, Over Under, 2)] _Layout ("3D Layout", Float) = 0
        _Zoom ("Zoom (front of the picture)", Range(0.6, 2)) = 1
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            half4 _MainTex_HDR;
            half4 _Tint;
            half _Exposure;
            float _Rotation;
            int _Layout;
            float _Zoom;

            float3 RotateAroundYInDegrees(float3 vertex, float degrees)
            {
                float alpha = degrees * UNITY_PI / 180.0;
                float sina, cosa;
                sincos(alpha, sina, cosa);
                float2x2 m = float2x2(cosa, -sina, sina, cosa);
                return float3(mul(m, vertex.xz), vertex.y).xzy;
            }

            // The picture's centre is at +X in these (unrotated) coordinates, as in Skybox/Panoramic.
            float3 ZoomFront(float3 d)
            {
                if (abs(_Zoom - 1.0) < 0.0001) return d;
                float t = acos(clamp(d.x, -1.0, 1.0));
                float2 side = d.yz;
                float len = length(side);
                if (len < 1e-5) return d;
                float s = t - (1.0 - 1.0 / _Zoom) * sin(t);
                float sins, coss;
                sincos(s, sins, coss);
                return float3(coss, side / len * sins);
            }

            float2 ToRadialCoords(float3 d)
            {
                float latitude = acos(clamp(d.y, -1.0, 1.0));
                float longitude = atan2(d.z, d.x);
                float2 sphereCoords = float2(longitude, latitude) * float2(0.5 / UNITY_PI, 1.0 / UNITY_PI);
                return float2(0.5, 1.0) - sphereCoords;
            }

            struct appdata_t
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 texcoord : TEXCOORD0;
                float4 layout3DScaleAndOffset : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 rotated = RotateAroundYInDegrees(v.vertex.xyz, _Rotation);
                o.vertex = UnityObjectToClipPos(rotated);
                o.texcoord = v.vertex.xyz;
                if (_Layout == 0) o.layout3DScaleAndOffset = float4(0, 0, 1, 1);
                else if (_Layout == 1) o.layout3DScaleAndOffset = float4(unity_StereoEyeIndex, 0, 0.5, 1);
                else o.layout3DScaleAndOffset = float4(0, 1 - unity_StereoEyeIndex, 1, 0.5);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 d = ZoomFront(normalize(i.texcoord));
                float2 tc = ToRadialCoords(d);
                tc.x = frac(tc.x);
                tc = (tc + i.layout3DScaleAndOffset.xy) * i.layout3DScaleAndOffset.zw;
                half4 tex = tex2Dlod(_MainTex, float4(tc, 0, 0));
                half3 c = DecodeHDR(tex, _MainTex_HDR);
                c = c * _Tint.rgb * unity_ColorSpaceDouble.rgb;
                c *= _Exposure;
                return half4(c, 1);
            }
            ENDCG
        }
    }
    Fallback Off
}
