// Original Shader by Kamoshika:
// https://neort.io/art/c5ct1gc3p9fe3sqpll9g
Shader "Kamoshika/SphericalShellsWithNoise"
{
    Properties
    {
        _scale ("Scale", float) = 1.0 // 球体の大きさ
        _N ("Number of Shells ** IF LARGE, SLOW. **", Range (1, 50)) = 5 // 球体の層の数
        _h ("Hue(Color) of Outermost Shell", Range (0.0, 1.0)) = 0.5 // 一番外側の球体の色相(HSVのH)
        _s ("Saturation(Color)", Range (0.0, 1.0)) = 0.8 // 彩度(HSVのS)
        _v ("Value(Color)", Range (0.0, 1.0)) = 1.0 // 明度(HSVのV)
        _noiseScale ("Noise Scale", float) = 1.0 // ノイズのスケール
        _noiseDensity ("Noise Density", Range (0.0, 1.0)) = 0.3 // ノイズの密度
        _noiseSpeed ("Noise Speed", float) = 1.0 // ノイズが変化する速さ
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
            //#define PI2 6.283185307179586
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
            float _noiseScale;
            float _noiseDensity;
            float _noiseSpeed;

            // HSV色をRGB色に変換
            float3 hsv2rgb(float h, float s, float v) {
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

                // 以下、2次方程式の解の公式を使って、球体と視線(直線)の交点座標(ro + rd * t)を求める

                float3 ce = float3(0, 0, 0); // 球体の中心座標
                float ra = 0; // 球体の半径
                float3 oc = ro - ce; // 球体の中心からカメラまでのベクトル
                float rc2 = dot(oc, oc); // 球体の中心からカメラまでの距離の2乗
                float rc = sqrt(rc2); // 球体の中心からカメラまでの距離
                float b = dot(oc, rd); // カメラを通り、視線(rd)を法線とする平面と、球体の中心との距離(球体の中心がカメラの前方にある時はマイナス)
                float D_tmp = b * b - rc2; // 判別式用の変数

                float3 rp = ro; // レイの座標を初期化
                
                float sign_normal; // 1のときは球体の表面、-1の時は裏面
                float delta_ra = 0.5 / float(_N) * _scale; // 球体の半径の刻み幅
                int n; // 中心から数えて何番目の球体か
                float nDivN; // float(n)/float(_N) の値

                for(int i = 0; i < _N * 2; i++) { // N枚の球体について、表面と裏面に分けて手前から順番に t を求める
                    if(i < _N){ // 球体の表面
                        n = _N - i;
                        sign_normal = 1;
                    } else { // 球体の裏面
                        n = i - _N + 1;
                        sign_normal = -1;
                    }
                    ra = float(n) * delta_ra;

                    if(b > ra) { // 球体が完全にカメラの背後にあるときはループを抜ける
                        break;
                    }

                    if(i == 0 && rc < ra) { // ループ1回目 & カメラが球体の中にある
                        int nc = int(rc / delta_ra); // カメラよりも内側にある球殻の枚数 (値は 0 以上 _N 未満 となっている)
                        if(b < 0) { // カメラの前方に球体の表面があるので、そこまでループを飛ばす
                            i = _N - nc - 1;
                        } else { // カメラの前方に球体の表面はないので、一番近くの裏面までループを飛ばす
                            i = _N + nc - 1;
                        }
                        continue; // 次の球体
                    }
                    
                    float D = D_tmp + ra * ra; // 2次方程式の判別式
                    if(D < 0){ // レイが球体と交点をもたない
                        if(i < _N) { // 球体の表面
                            i = _N * 2 - i - 1; // 今の球体と交点をもたないならばそれより内側の球体と交点をもたないことは確定するので
                                                // 交点をもつ可能性のある球体の裏面までループを飛ばす
                        }

                        continue; // 次の球体
                    }

                    t = -b - sign_normal * sqrt(D); // 2次方程式の解

                    // ループを飛ばす処理によって、球体がカメラの前方にある場合のみ t が計算されるのでここは不要
                    /*if(t <= 0){ // 球体がカメラの後方にある
                        continue; // 次の球体
                    }*/

                    rp = ro + rd * t; // レイを球体まで伸ばす
                    
                    nDivN = float(n) / float(_N);
                    float time = fmod(_Time.y + nDivN * 6, 500); // 長時間経過時の精度低下対策 & 層によって時間をずらす
                    float3 noisePos = rp * 5 / _scale + nDivN * 100.8172; // ノイズに使用する座標
                    if(frac(valueNoise4D(float4(noisePos, time * _noiseSpeed) / _noiseScale) * 3) < _noiseDensity) { // ノイズの部分だけ描画するための条件
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
                _h += nDivN; // 層によって色を変える
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
