// Original Shader by Kamoshika:
// https://neort.io/art/c415n5c3p9ffolj045v0
Shader "Kamoshika/TripleGyroid"
{
    Properties
    {
        _scale ("Scale", float) = 1.0 // スケール
        _iteration ("Ray Marching Iteration", Range (1, 100)) = 70 // Ray Marchingのループ回数
        _h ("Hue(Color)", Range (0.0, 1.0)) = 0.0 // 色相(HSVのH)
        _s ("Saturation(Color)", Range (0.0, 1.0)) = 0.8 // 彩度(HSVのS)
        _v ("Value(Color)", Range (0.0, 1.0)) = 1.0 // 明度(HSVのV)
        _fogDensity ("Fog Density", float) = 0.02 // 霧の密度
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "LightMode"="ForwardBase"
        }

        LOD 200
        Cull Front

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 pos : TEXCOORD1;
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.pos = mul(unity_ObjectToWorld, v.vertex).xyz; // ワールド座標
                o.uv = v.uv;
                return o;
            }

            float _scale;
            int _iteration;
            float _h;
            float _s;
            float _v;
            float _fogDensity;

            // HSV色をRGB色に変換
            float3 hsv2rgb(float h, float s, float v) {
                float4 a = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(h + a.xyz) * 6.0 - a.w);
                return v * lerp(a.x, saturate(p - a.x), s);
            }

            float sdGyroid1(float3 p) // ジャイロイドの距離関数1
            {
                return sin(p.x)*cos(p.y) + sin(p.y)*cos(p.z) + sin(p.z)*cos(p.x) + 1.35;
            }

            float sdGyroid2(float3 p) // ジャイロイドの距離関数2
            {
                return -sin(p.x)*cos(p.y) + sin(p.y)*cos(p.z) - sin(p.z)*cos(p.x) + 1.35;
            }

            float sdGyroid3(float3 p) // ジャイロイドの距離関数3
            {
                return sin(p.x)*cos(p.y) - sin(p.y)*cos(p.z) - sin(p.z)*cos(p.x) + 1.35;
            }

            float distFunc(float3 p) // 距離関数
            {
                p /= _scale;
                return min(sdGyroid1(p),
                       min(sdGyroid2(p),
                           sdGyroid3(p)
                           )) * _scale;
            }

            float3 calcNormal(float3 p) // 距離関数から法線ベクトルを計算
            {
                float eps = 0.005 * _scale;
                return normalize(float3(
                    distFunc(p + float3(eps, 0, 0)) - distFunc(p + float3(-eps, 0, 0)),
                    distFunc(p + float3(0, eps, 0)) - distFunc(p + float3(0, -eps, 0)),
                    distFunc(p + float3(0, 0, eps)) - distFunc(p + float3(0, 0, -eps))
                ));
            }

            float3 getColor(float3 p) // オブジェクトの表面に到達したレイの座標から色を算出
            {
                float3 col = float3(1, 1, 1);
                float th = 0.5; // threshold

                p /= _scale;
                if(sdGyroid1(p) < th) {
                    _h += 0.0 / 3.0;
                } else if(sdGyroid2(p) < th) {
                    _h += 1.0 / 3.0;
                } else if(sdGyroid3(p) < th) {
                    _h += 2.0 / 3.0;
                }

                col = hsv2rgb(_h, _s, _v);
                return col;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 col = float3(1, 1, 1);
                float3 ro = _WorldSpaceCameraPos; // カメラのワールド座標(レイの出発点)
                float3 rd = normalize(i.pos - ro); // レイの方向

                float d = 0;
                float t = 0;
                float3 rp = ro; // レイの座標を初期化
                
                float sign_normal = 1;
                d = distFunc(rp);
                if(d < 0.0001 * _scale) { // カメラがオブジェクトの内側にある場合、内側を描画するようにする
                    sign_normal = -1;
                }

                //[unroll]
                for(int i = 0; i < _iteration; i++) {
                    d = sign_normal * distFunc(rp);
                    if(abs(d) < 0.00001 * _scale || t > 100 * _scale) {
                        break;
                    }
                    t += d;
                    rp = ro + rd * t;
                }

                // 色の計算
                float3 normal = sign_normal * calcNormal(rp); // オブジェクトの法線ベクトルを求める
                float3 lightDir = _WorldSpaceLightPos0.xyz; // ディレクショナルライトの方向
                float3 albedo = getColor(rp); // オブジェクトの表面に到達したレイの座標から色を算出
                float diffuse = max(0.2, dot(normal, lightDir)); // ランバート反射
                float specular = pow(max(0, dot(reflect(lightDir, normal), rd)), 20); // 鏡面反射
                col = albedo * diffuse + specular; // 色の合成

                // フォグ(霧)
                float fog = exp(-t * t * _fogDensity * _fogDensity / (_scale * _scale));
                col = lerp(float3(1, 1, 1), col, fog);

                return fixed4(col, 1);
            }
            ENDCG
        }
    }
}
