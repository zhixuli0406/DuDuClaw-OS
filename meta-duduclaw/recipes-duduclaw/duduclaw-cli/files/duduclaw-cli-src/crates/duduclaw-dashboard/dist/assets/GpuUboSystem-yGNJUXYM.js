import{W as e}from"./Geometry-apQnTMm4.js";import{i as t,o as n,r}from"./BufferResource-BbyfIet8.js";var i={i32:{align:4,size:4},u32:{align:4,size:4},f32:{align:4,size:4},f16:{align:2,size:2},"vec2<i32>":{align:8,size:8},"vec2<u32>":{align:8,size:8},"vec2<f32>":{align:8,size:8},"vec2<f16>":{align:4,size:4},"vec3<i32>":{align:16,size:12},"vec3<u32>":{align:16,size:12},"vec3<f32>":{align:16,size:12},"vec3<f16>":{align:8,size:6},"vec4<i32>":{align:16,size:16},"vec4<u32>":{align:16,size:16},"vec4<f32>":{align:16,size:16},"vec4<f16>":{align:8,size:8},"mat2x2<f32>":{align:8,size:16},"mat2x2<f16>":{align:4,size:8},"mat3x2<f32>":{align:8,size:24},"mat3x2<f16>":{align:4,size:12},"mat4x2<f32>":{align:8,size:32},"mat4x2<f16>":{align:4,size:16},"mat2x3<f32>":{align:16,size:32},"mat2x3<f16>":{align:8,size:16},"mat3x3<f32>":{align:16,size:48},"mat3x3<f16>":{align:8,size:24},"mat4x3<f32>":{align:16,size:64},"mat4x3<f16>":{align:8,size:32},"mat2x4<f32>":{align:16,size:32},"mat2x4<f16>":{align:8,size:16},"mat3x4<f32>":{align:16,size:48},"mat3x4<f16>":{align:8,size:24},"mat4x4<f32>":{align:16,size:64},"mat4x4<f16>":{align:8,size:32}};function a(e){let t=e.map(e=>({data:e,offset:0,size:0})),n=0;for(let e=0;e<t.length;e++){let r=t[e],a=i[r.data.type].size,o=i[r.data.type].align;if(!i[r.data.type])throw Error(`[Pixi.js] WebGPU UniformBuffer: Unknown type ${r.data.type}`);r.data.size>1&&(a=Math.max(a,o)*r.data.size),n=Math.ceil(n/o)*o,r.size=a,r.offset=n,n+=a}return n=Math.ceil(n/16)*16,{uboElements:t,size:n}}function o(e,t){let{size:n,align:r}=i[e.data.type],a=(r-n)/4,o=e.data.type.indexOf(`i32`)>=0?`dataInt32`:`data`;return`
         v = uv.${e.data.name};
         ${t===0?``:`offset += ${t};`}

         arrayOffset = offset;

         t = 0;

         for(var i=0; i < ${e.data.size*(n/4)}; i++)
         {
             for(var j = 0; j < ${n/4}; j++)
             {
                 ${o}[arrayOffset++] = v[t++];
             }
             ${a===0?``:`arrayOffset += ${a};`}
         }
     `}function s(e){return t(e,`uboWgsl`,o,r)}var c=class extends n{constructor(){super({createUboElements:a,generateUboSync:s})}};c.extension={type:[e.WebGPUSystem],name:`ubo`};export{a,i,s as n,o as r,c as t};