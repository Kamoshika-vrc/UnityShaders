Shader "Kamoshika/SphericalShellWithSlits"
{
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

            #define PI2 6.28318530717958
            #define PI  3.14159265358979

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

            float _scale; // 球殻の大きさ
            int N; // 球殻の層の数

            // HSV色をRGB色に変換
            //float3 hsv2rgb(float h, float s, float v) {
            float3 hsv2rgb(float3 hsv) {
                float4 a = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(hsv.x + a.xyz) * 6.0 - a.www);
                return hsv.z * lerp(a.xxx, saturate(p - a.xxx), hsv.y);
            }

            pout frag(v2f i)
            {
                _scale = 1;
                N = 5;

                fixed3 col = fixed3(0, 0, 0); // 色
                float3 ro = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1)).xyz; // カメラのローカル座標(レイの出発点)
                float3 rd = normalize(i.pos - ro); // レイの方向

                float t = 0; // カメラからオブジェクトの表面まで伸ばしたレイの長さ
                bool hit = false; // レイがオブジェクトにヒットしたかどうか

                float3 ce = float3(0, 0, 0); // 球殻の中心座標
                float ra = 0; // 球殻の半径
                float3 oc = ro - ce; // 2次方程式の計算用
                float b = dot(oc, rd); // 2次方程式の計算用
                float D = 0; // 2次方程式の判別式
                float D_tmp = b * b - dot(oc, oc); // 判別式用の変数

                float3 rp = ro; // レイの座標
                
                float s; // 1のときは球殻の表面、-1の時は裏面
                float delta_ra = 0.5 / float(N); // 球殻の半径の刻み幅
                float theta; // 3次元極座標の角度theta
                float phi; // 3次元極座標の角度phi
                for(int i = 0; i < N*2; i++) { // 手前から順番に、
                    if(i < N){ // 球殻の表面
                        ra = 0.5 - float(i) * delta_ra;
                        s = 1;
                    } else { // 球殻の裏面
                        ra = delta_ra + float(i - N) * delta_ra;
                        s = -1;
                    }

                    ra *= _scale; // 半径にスケールを反映
                    D = D_tmp + ra * ra; // 2次方程式の判別式を算出
                    if(D >= 0) { // レイが球体と交点をもつ
                        t = -b - s * sqrt(D); // 2次方程式の解
                        rp = ro + rd * t; // レイを球体表面まで伸ばす
                        theta = acos(rp.y / ra);
                        phi = sign(rp.z) * acos(rp.x / length(rp.xz));
                        
                        float time = fmod(_Time.y, PI2); // 長時間経過時の精度低下対策
                        if(t > 0 && sin((theta + phi - _Time.y) * 10) > 0) { // カメラの後方は描画しない & スリット(切れ目)のための条件
                            hit = true;
                            break;
                        }
                    }
                }
                
                if(hit) {
                    float3 normal = s * normalize(rp); // 法線ベクトル
                    float3 lightDir = normalize(mul(unity_WorldToObject, _WorldSpaceLightPos0).xyz); // ディレクショナルライトの方向をローカル座標にする
                    
                    // 色の計算
                    float3 albedo;
                    float3 hsv; // HSV色
                    if(s > 0) { // 球殻の表面
                        hsv = float3(ra * 2 / _scale - 0.2, 0.7, 1.0);
                    } else { // 球殻の裏面
                        hsv = float3(phi / PI2, 1.0, 1.0);
                    }
                    albedo = hsv2rgb(hsv);

                    float diffuse = max(0.2, dot(normal, lightDir)); // ランバート反射
                    float specular = pow(max(0, dot(reflect(lightDir, normal), rd)), 20); // 鏡面反射
                    
                    col = albedo * diffuse + specular; // 色の合成
                } else {
                    discard;
                }

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