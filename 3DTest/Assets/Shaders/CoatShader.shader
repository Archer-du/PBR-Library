Shader "Porsche/Coat Shader"
{
    // Properties语义并不是必需的
    Properties
    {
        _Diffuse("Color", Color) = (1.0, 1.0, 1.0, 1.0)
        // 高光反射叠加的颜色，默认为白色
        _Specular ("Specular", Color) = (1, 1, 1, 1)
        // 光泽度，控制高光区域的大小
        _Gloss ("Gloss", Range(8.0, 256)) = 20
        
        _ReflectColor ("Reflect Color", Color) = (1, 1, 1, 1)
        // 反射程度
        _ReflectIntensity ("Refect Intensity", Range(0, 1)) = 1
        // 反射的环境映射纹理
        _Cubemap ("Refect Cubemap", Cube) = "_Skybox" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            
            Cull Off

            CGPROGRAM

            #pragma multi_compile_fwdbase
            
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "Lighting.cginc"

            fixed4 _Diffuse;
            fixed4 _Specular;
            float _Gloss;

            fixed4 _ReflectColor;
            fixed _ReflectIntensity;
            samplerCUBE _Cubemap;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 worldViewDir : TEXCOORD2;
                float3 worldRef1 : TEXCOORD3;
            };

            v2f vert (a2v v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.worldViewDir = UnityWorldSpaceViewDir(o.worldPos);
                o.worldRef1 = reflect(-o.worldViewDir, o.worldNormal);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed3 worldNormal = normalize(i.worldNormal);
                fixed3 worldLightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));
                fixed3 worldViewDir = normalize(i.worldViewDir);

                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * _Diffuse.rgb;
                // 根据兰伯特漫反射公式计算漫反射
                fixed3 diffuse = _LightColor0.rgb * _Diffuse.rgb * saturate(dot(worldNormal, worldLightDir));
                
                fixed3 halfDir = normalize(worldLightDir + worldViewDir);
                // 根据高光反射公式计算高光反射
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(saturate(dot(halfDir, worldNormal)), _Gloss);

                
                // 调用texCUBE函数对立方体纹理进行采样，参数2：反射方向
                fixed3 reflection = texCUBE(_Cubemap, i.worldRef1).rgb;
                fixed3 color = ambient + lerp(diffuse, reflection, _ReflectIntensity);
                
                // 环境光+漫反射+高光反射
                return fixed4(color + specular, 1.0);
            }

            ENDCG
        }
        // Additional pass
        Pass
        {
            // 设置为ForwardAdd
            Tags { "LightMode" = "ForwardAdd" }

            // 开启混合模式，将帧缓冲中的颜色值和不同光照结果进行叠加
            // （Blend One One并不是唯一，也可以使用其他Blend指令，比如：Blend SrcAlpha One）
            Blend One One

            // Additional pass中的顶点、片元着色器代码是根据Base Pass中的代码复制修改得到的
            // 这些修改一般包括：去掉Base Pass中的环境光、自发光、逐顶点光照、SH光照的部分
            CGPROGRAM

            // 执行该指令，保证Additional Pass中访问到正确的光照变量
            #define POINT
            #pragma multi_compile_fwdadd_fullshadows

            #pragma vertex vert
            #pragma fragment frag

            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            #include "UnityLightingCommon.cginc"
            
            fixed4 _Diffuse;
            fixed4 _Specular;
            float _Gloss;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            v2f vert(a2v v)
            {
                v2f o;

                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed3 worldNormal = normalize(i.worldNormal);

                // 计算不同光源的方向
                #ifdef USING_DIRECTIONAL_LIGHT
                    // 平行光方向可以直接通过_WorldSpaceLightPos0.xyz得到
                    fixed3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
                #else
                    // 点光源或聚光灯，_WorldSpaceLightPos0表示世界空间下的光源位置
                    // 需要减去世界空间下的顶点位置才能得到光源方向
                    fixed3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos.xyz);
                #endif

                fixed3 diffuse = _LightColor0.rgb * _Diffuse.rgb * max(0, dot(worldNormal, worldLightDir));

                fixed3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
                fixed3 halfDir = normalize(worldLightDir + viewDir);
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(worldNormal, halfDir)), _Gloss);

                // 计算不同光源的衰减
                #ifdef USING_DIRECTIONAL_LIGHT
                    // 平行光不衰减
                    fixed atten = 1.0;
                #else
                    // 将片元的坐标由世界空间转到光源空间
                    float3 lightCoord = mul(unity_WorldToLight, float4(i.worldPos, 1)).xyz;
                    // Unity选择使用一张纹理作为查找表（Lookup Table, LUT）
                    // 对衰减纹理进行采样得到衰减值
                    fixed atten = tex2D(_LightTexture0, dot(lightCoord, lightCoord).rr).UNITY_ATTEN_CHANNEL;
                #endif

                return fixed4((diffuse + specular) * atten, 1.0);
            }

            ENDCG
        }
    }

    Fallback "Specular"
}