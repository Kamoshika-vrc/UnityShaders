// Original Shader by Kamoshika:
// https://neort.io/art/bta9n2c3p9f8mi6u8u50
Shader "Kamoshika/DiscoBalls"
{
    Properties
    {
        _scale ("Scale", float) = 1.0 // スケール
        _iteration ("Ray Marching Iteration", Range (1, 100)) = 100 // Ray Marchingのループ回数
        _radius ("Radius", Range (0.0, 0.5)) = 0.3 // 球の半径
        _numDiv ("Number of Divisions", int) = 10 // 分割数
        _s ("Saturation(Color)", Range (0.0, 1.0)) = 0.8 // 彩度(HSVのS)
        _vCoef ("Value Coef.(Color)", Range (0.0, 1.0)) = 0.1 // 明度(HSVのV)の係数
        _colSpeed ("Color Change Speed", float) = 10.0 // 色が変わる速さ
        _rotSpeed ("Rotation Speed", float) = 1.0 // 回転の速さ
        _fogDensity ("Fog Density", float) = 0.1 // 霧の密度
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

            #define PI  3.141592653589793
            #define PI2 6.283185307179586

            #define hash(x) frac(sin(x) * 43758.5453) // 乱数

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
            float _iteration;
            float _radius;
            int _numDiv;
            float _s;
            float _vCoef;
            float _colSpeed;
            float _rotSpeed;
            float _fogDensity;

            float3 rotate3D(float3 v, float a, float theta, float phi) { // 3次元の座標を回転 (座標軸は3次元極座標のtheta, phiによって受け取る)
                float3 axis = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)); // 回転軸ベクトルの長さは 1
                return lerp(dot(axis, v) * axis, v, cos(a)) - sin(a) * cross(axis, v);
            }

             // HSV色をRGB色に変換
            float3 hsv2rgb(float h, float s, float v) {
                float4 a = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(h + a.xyz) * 6.0 - a.w);
                return v * lerp(a.x, saturate(p - a.x), s);
            }

            float distFunc(float3 p) // 距離関数
            {
                p /= _scale;
                p = frac(p) - 0.5; // 間隔1で無限複製

                return (length(p) - _radius) * _scale;
            }

            float3 getColor(float3 p) // オブジェクトの表面に到達したレイの座標から色を算出
            {
                float time = fmod(_Time.y, 200); // 長時間経過時の精度低下対策
                float3 col = float3(1, 1, 1);

                p /= _scale;

                float h1 = hash(dot(floor(p), float3(13.5276, 23.1682, 51.7282))); // 一つ一つの球ごとに異なる乱数を取得
                p = frac(p) - 0.5;
                p = rotate3D(p, h1 * PI2, hash(h1 * 1.5186) * PI, hash(h1 * 1.9218) * PI2); // 座標をランダムな回転軸でランダムな角度回転
                p = rotate3D(p, time * hash(h1 * 1.2628) * _rotSpeed, hash(h1 * 1.3182) * PI, hash(h1 * 1.1265) * PI2); // 座標をランダムな回転軸、ランダムなスピードで回転
                float theta = acos(p.y / _radius); // 3次元極座標の角度theta: 0 ～ π
                float phi = sign(p.z) * acos(p.x / length(p.xz)); // 3次元極座標の角度phi: -π ～ π

                float2 uv = float2(phi / PI2 + 0.5, theta / PI); // 0 ～ 1に変換
                uv.y = clamp(uv.y, 0.01, 0.99); // 真上付近と真下付近の色がうまく描画されない問題の対策

                float2 cellSize = float2(0.5 / float(_numDiv), 1.0 / float(_numDiv)); // セルのサイズ
                float h2 = hash(dot(floor(uv / cellSize), float2(17.1872, 28.1492)) + h1 + floor(time * _colSpeed + h1) * 1.1826); // セルごとに異なり、一定時間で変わる乱数を取得
                uv = frac(uv / cellSize) - 0.5; // 座標がセル内で -0.5 ～ 0.5 になるように変換
                uv = abs(uv); // 0 ～ 0.5に折りたたむ

                float h = h2;
                _vCoef *= (0.5 - max(uv.x, uv.y)) * 50; // セル内でいい感じに明暗をつける
                
                col = hsv2rgb(h, _s, _vCoef);
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
                float3 normal = sign_normal * normalize(frac(rp / _scale) - 0.5); // 球体の法線ベクトルを求める
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
