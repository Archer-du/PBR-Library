Shader "Porsche/Logo Shader"
{
    // Properties语义并不是必需的
    Properties
    {
        _MainTex("Main Tex", 2D) = "white" {}
        // 高光反射叠加的颜色，默认为白色
        _Specular ("Specular", Color) = (1, 1, 1, 1)
        // 光泽度，控制高光区域的大小
        _Gloss ("Gloss", Range(8.0, 256)) = 20
    }
    SubShader
    {
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Lighting.cginc"

            sampler2D _MainTex;
            // 与_MainTex配套的纹理缩放（scale）和平移（translation），在材质面板的纹理属性中可以调节
            // 命名规范为：纹理变量名 + "_ST"
            // _MainTex_ST.xy 存储缩放值
            // _MainTex_ST.zw 存储偏移值
            float4 _MainTex_ST;
            fixed4 _Specular;
            float _Gloss;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                //裁剪坐标
                float4 pos : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float2 uv : TEXCOORD2;
            };

            v2f vert (a2v v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed3 worldNormal = normalize(i.worldNormal);
                fixed3 worldLightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));

                fixed3 albedo = tex2D(_MainTex, i.uv).rgb;

                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * albedo;
                if(all(albedo == fixed3(1, 1, 1))) discard;
                // 根据兰伯特漫反射公式计算漫反射
                fixed3 diffuse = _LightColor0.rgb * albedo * saturate(dot(worldNormal, worldLightDir));

                fixed3 viewDir = normalize(UnityWorldSpaceViewDir(i.worldPos));
                
                fixed3 halfDir = normalize(worldLightDir + viewDir);
                // 根据高光反射公式计算高光反射
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(saturate(dot(halfDir, worldNormal)), _Gloss);
                
                // 环境光+漫反射+高光反射
                return fixed4(ambient + diffuse + specular, 1.0);
            }

            ENDCG
        }
    }
}