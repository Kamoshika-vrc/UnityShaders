// Original Shader by Kamoshika:
// https://neort.io/art/c5ct1gc3p9fe3sqpll9g
Shader "Kamoshika/SphericalShellsWithNoise"
{
    Properties
    {
        _scale ("Scale", float) = 1.0 // 球殻の大きさ
        _N ("Number of Shells    *** large value will slow down the process ***", int) = 5 // 球殻の層の数
        _h("Hue(Color) of Outermost Shell", Range (0.0, 1.0)) = 0.5 // 一番外側の球殻の色相(HSVのH)
        _s("Saturation(Color)", Range (0.0, 1.0)) = 0.8 // 彩度(HSVのS)
        _v("Value(Color)", Range (0.0, 1.0)) = 1.0 // 明度(HSVのV)
        _speed("Speed of Noise", float) = 1.0 // ノイズが変化する速さ
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

            //#define PI  3.141592653589793
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

            struct pout // fragmentシェーダーの出力用構造体
            {
                fixed4 color : SV_Target;
                float depth : SV_Depth;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.pos = v.vertex.xyz; // ローカル座標
                o.uv = v.uv;
                return o;
            }

            float _scale;
            int _N;
            float _h;
            float _s;
            float _v;
            float _speed;

            float3 hsv2rgb(float h, float s, float v) { // HSV色をRGB色に変換
                float4 a = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(h + a.xyz) * 6.0 - a.w);
                return v * lerp(a.x, saturate(p - a.x), s);
            }

            // 3次元のバリューノイズ
            /*float valueNoise3D(float3 p) {
                float3 i = floor(p);
                float3 f = frac(p);
                float3 b = float3(17, 61, 7);
                float4 h = float4(0, b.yz, b.y + b.z) + dot(i, b);
                f = f * f * (3 - 2 * f);
                h = lerp(hash(h), hash(h + b.x), f.x);
                h.xy = lerp(h.xz, h.yw, f.y);
                return lerp(h.x, h.y, f.z); // 0 ～ 1
            }*/

            // 4次元のバリューノイズ
            float valueNoise4D(float4 p) {
                float4 i = floor(p);
                float4 f = frac(p);
                float4 b = float4(17, 61, 31, 7);
                float h = dot(i, b);
                f = f * f * (3 - 2 * f);

                 // 0 ～ 1
                return lerp(lerp(lerp(lerp(hash(h), hash(h + b.x), f.x),
                                      lerp(hash(h + b.y), hash(h + b.x + b.y), f.x),
                                      f.y),
                                 lerp(lerp(hash(h + b.z), hash(h + b.x + b.z), f.x),
                                      lerp(hash(h + b.y + b.z), hash(h + b.x + b.y + b.z), f.x),
                                      f.y),
                                 f.z),
                            lerp(lerp(lerp(hash(h + b.w), hash(h + b.x + b.w), f.x),
                                      lerp(hash(h + b.y + b.w), hash(h + b.x + b.y + b.w), f.x),
                                      f.y),
                                 lerp(lerp(hash(h + b.z + b.w), hash(h + b.x + b.z + b.w), f.x),
                                      lerp(hash(h + b.y + b.z + b.w), hash(h + b.x + b.y + b.z + b.w), f.x),
                                      f.y),
                                 f.z),
                            f.w);
            }

            pout frag(v2f i)
            {
                float3 col = float3(0, 0, 0); // 色
                float3 ro = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz; // カメラのローカル座標(レイの出発点)
                float3 rd = normalize(i.pos - ro); // レイの方向

                float t = 0; // カメラからオブジェクトの表面まで伸ばしたレイの長さ
                bool hit = false; // レイがオブジェクトにヒットしたかどうか

                // 以下、2次方程式を解くことによって、球体と視線(直線)の交点座標(ro + rd * t)を求める

                float3 ce = float3(0, 0, 0); // 球殻の中心座標
                float ra = 0; // 球殻の半径
                float3 oc = ro - ce; // 2次方程式の計算用
                float b = dot(oc, rd); // 2次方程式の計算用
                float D = 0; // 2次方程式の判別式
                float D_tmp = b * b - dot(oc, oc); // 判別式用の変数

                float3 rp = ro; // レイの座標
                
                float sign_normal; // 1のときは球殻の表面、-1の時は裏面
                float delta_ra = 0.5 / float(_N) * _scale; // 球殻の半径の刻み幅
                int n; // 中心から数えて何番目の球殻か

                for(int i = 0; i < _N * 2; i++) { // N枚の球殻について、表面と裏面に分けて手前から順番に t を求める
                    if(i < _N){ // 球殻の表面
                        n = _N - i;
                        sign_normal = 1;
                    } else { // 球殻の裏面
                        n = i - _N + 1;
                        sign_normal = -1;
                    }
                    ra = float(n) * delta_ra;

                    D = D_tmp + ra * ra; // 2次方程式の判別式を算出
                    if(D < 0){ // レイが球殻と交点をもたない
                        continue; // 次の球殻
                    }

                    t = -b - sign_normal * sqrt(D); // 2次方程式の解
                    if(t <= 0){ // カメラの後方
                        continue; // 次の球殻
                    }

                    rp = ro + rd * t; // レイを球体まで伸ばす
                    
                    float time = fmod(_Time.y + float(n) / float(_N) * PI2, 500); // 長時間経過時の精度低下対策 & 層によって時間をずらす
                    if(frac(valueNoise4D(float4(rp * 5 / _scale + float(n) * 100.5172, time * _speed)) * 20 / PI2) > 0.7) { // ノイズの部分だけ描画するための条件
                        hit = true; // ヒットしたらforループを抜ける
                        break;
                    }
                }
                
                if(!hit) { // ヒットしなかったら描画しない
                    discard;
                }

                float3 normal = sign_normal * normalize(rp - ce); // 法線ベクトル
                float3 lightDir = normalize(mul(unity_WorldToObject, _WorldSpaceLightPos0).xyz); // ディレクショナルライトの方向をローカル座標にする
                    
                // 色の計算
                float3 albedo;
                _h += float(n) / float(_N); // 層によって色を変える
                albedo = hsv2rgb(_h, _s, _v);

                float diffuse = max(0.2, dot(normal, lightDir)); // ランバート反射
                float specular = pow(max(0, dot(reflect(lightDir, normal), rd)), 20); // 鏡面反射
                
                col = albedo * diffuse + specular; // 色の合成

                // デプス(depth)書き込み
                pout o;
                o.color = fixed4(col, 1);
                float4 projectionPos = UnityObjectToClipPos(float4(rp, 1));
                o.depth = projectionPos.z / projectionPos.w;

                return o;
            }
            ENDCG
        }
    }
}