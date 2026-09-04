import{W as e,_ as t,j as n,o as r,u as i}from"./Geometry-apQnTMm4.js";import{a,i as o,n as s,o as c,t as l}from"./BufferResource-BbyfIet8.js";var u={f32:4,i32:4,"vec2<f32>":8,"vec3<f32>":12,"vec4<f32>":16,"vec2<i32>":8,"vec3<i32>":12,"vec4<i32>":16,"mat2x2<f32>":32,"mat3x3<f32>":48,"mat4x4<f32>":64};function d(e){let t=e.map(e=>({data:e,offset:0,size:0})),n=0,r=0;for(let e=0;e<t.length;e++){let i=t[e];if(n=u[i.data.type],!n)throw Error(`Unknown type ${i.data.type}`);i.data.size>1&&(n=Math.max(n,16)*i.data.size);let a=n===12?16:n;i.size=n;let o=r%16;o>0&&16-o<a?r+=(16-o)%16:r+=(n-o%n)%n,i.offset=r,r+=n}return r=Math.ceil(r/16)*16,{uboElements:t,size:r}}function f(e,t){let n=Math.max(u[e.data.type]/16,1),r=e.data.value.length/e.data.size,i=(4-r%4)%4,a=e.data.type.indexOf(`i32`)>=0?`dataInt32`:`data`;return`
        v = uv.${e.data.name};
        offset += ${t};

        arrayOffset = offset;

        t = 0;

        for(var i=0; i < ${e.data.size*n}; i++)
        {
            for(var j = 0; j < ${r}; j++)
            {
                ${a}[arrayOffset++] = v[t++];
            }
            ${i===0?``:`arrayOffset += ${i};`}
        }
    `}function p(e){return o(e,`uboStd40`,f,s)}var m=class extends c{constructor(){super({createUboElements:d,generateUboSync:p})}};m.extension={type:[e.WebGLSystem],name:`ubo`};function h(e,n){let i=[],a=[`
        var g = s.groups;
        var sS = r.shader;
        var p = s.glProgram;
        var ugS = r.uniformGroup;
        var resources;
    `],o=!1,s=0,c=n._getProgramData(e.glProgram);for(let u in e.groups){let d=e.groups[u];i.push(`
            resources = g[${u}].resources;
        `);for(let f in d.resources){let p=d.resources[f];if(p instanceof r)if(p.ubo){let t=e._uniformBindMap[u][Number(f)];i.push(`
                        sS.bindUniformBlock(
                            resources[${f}],
                            '${t}',
                            ${e.glProgram._uniformBlockData[t].index}
                        );
                    `)}else i.push(`
                        ugS.updateUniformGroup(resources[${f}], p, sD);
                    `);else if(p instanceof l){let t=e._uniformBindMap[u][Number(f)];i.push(`
                    sS.bindUniformBlock(
                        resources[${f}],
                        '${t}',
                        ${e.glProgram._uniformBlockData[t].index}
                    );
                `)}else if(p instanceof t){let t=e._uniformBindMap[u][f],r=c.uniformData[t];r&&(o||(o=!0,a.push(`
                        var tS = r.texture;
                        `)),n._gl.uniform1i(r.location,s),i.push(`
                        tS.bind(resources[${f}], ${s});
                    `),s++)}}}let u=[...a,...i].join(`
`);return Function(`r`,`s`,`sD`,u)}var g=class{},_=class{constructor(e,t){this.program=e,this.uniformData=t,this.uniformGroups={},this.uniformDirtyGroups={},this.uniformBlockBindings={}}destroy(){this.uniformData=null,this.uniformGroups=null,this.uniformDirtyGroups=null,this.uniformBlockBindings=null,this.program=null}};function v(e,t,n){let r=e.createShader(t);return e.shaderSource(r,n),e.compileShader(r),r}function y(e){let t=Array(e);for(let e=0;e<t.length;e++)t[e]=!1;return t}function b(e,t){switch(e){case`float`:return 0;case`vec2`:return new Float32Array(2*t);case`vec3`:return new Float32Array(3*t);case`vec4`:return new Float32Array(4*t);case`int`:case`uint`:case`sampler2D`:case`sampler2DArray`:return 0;case`ivec2`:return new Int32Array(2*t);case`ivec3`:return new Int32Array(3*t);case`ivec4`:return new Int32Array(4*t);case`uvec2`:return new Uint32Array(2*t);case`uvec3`:return new Uint32Array(3*t);case`uvec4`:return new Uint32Array(4*t);case`bool`:return!1;case`bvec2`:return y(2*t);case`bvec3`:return y(3*t);case`bvec4`:return y(4*t);case`mat2`:return new Float32Array([1,0,0,1]);case`mat3`:return new Float32Array([1,0,0,0,1,0,0,0,1]);case`mat4`:return new Float32Array([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])}return null}var x=null,S={FLOAT:`float`,FLOAT_VEC2:`vec2`,FLOAT_VEC3:`vec3`,FLOAT_VEC4:`vec4`,INT:`int`,INT_VEC2:`ivec2`,INT_VEC3:`ivec3`,INT_VEC4:`ivec4`,UNSIGNED_INT:`uint`,UNSIGNED_INT_VEC2:`uvec2`,UNSIGNED_INT_VEC3:`uvec3`,UNSIGNED_INT_VEC4:`uvec4`,BOOL:`bool`,BOOL_VEC2:`bvec2`,BOOL_VEC3:`bvec3`,BOOL_VEC4:`bvec4`,FLOAT_MAT2:`mat2`,FLOAT_MAT3:`mat3`,FLOAT_MAT4:`mat4`,SAMPLER_2D:`sampler2D`,INT_SAMPLER_2D:`sampler2D`,UNSIGNED_INT_SAMPLER_2D:`sampler2D`,SAMPLER_CUBE:`samplerCube`,INT_SAMPLER_CUBE:`samplerCube`,UNSIGNED_INT_SAMPLER_CUBE:`samplerCube`,SAMPLER_2D_ARRAY:`sampler2DArray`,INT_SAMPLER_2D_ARRAY:`sampler2DArray`,UNSIGNED_INT_SAMPLER_2D_ARRAY:`sampler2DArray`},C={float:`float32`,vec2:`float32x2`,vec3:`float32x3`,vec4:`float32x4`,int:`sint32`,ivec2:`sint32x2`,ivec3:`sint32x3`,ivec4:`sint32x4`,uint:`uint32`,uvec2:`uint32x2`,uvec3:`uint32x3`,uvec4:`uint32x4`,bool:`uint32`,bvec2:`uint32x2`,bvec3:`uint32x3`,bvec4:`uint32x4`};function w(e,t){if(!x){let t=Object.keys(S);x={};for(let n=0;n<t.length;++n){let r=t[n];x[e[r]]=S[r]}}return x[t]}function T(e,t){return C[w(e,t)]||`float32`}function E(e,t,n=!1){let r={},a=t.getProgramParameter(e,t.ACTIVE_ATTRIBUTES);for(let n=0;n<a;n++){let a=t.getActiveAttrib(e,n);if(a.name.startsWith(`gl_`))continue;let o=T(t,a.type);r[a.name]={location:0,format:o,stride:i(o).stride,offset:0,instance:!1,start:0}}let o=Object.keys(r);if(n){o.sort((e,t)=>e>t?1:-1);for(let n=0;n<o.length;n++)r[o[n]].location=n,t.bindAttribLocation(e,n,o[n]);t.linkProgram(e)}else for(let n=0;n<o.length;n++)r[o[n]].location=t.getAttribLocation(e,o[n]);return r}function D(e,t){if(!t.ACTIVE_UNIFORM_BLOCKS)return{};let n={},r=t.getProgramParameter(e,t.ACTIVE_UNIFORM_BLOCKS);for(let i=0;i<r;i++){let r=t.getActiveUniformBlockName(e,i);n[r]={name:r,index:t.getUniformBlockIndex(e,r),size:t.getActiveUniformBlockParameter(e,i,t.UNIFORM_BLOCK_DATA_SIZE)}}return n}function O(e,t){let n={},r=t.getProgramParameter(e,t.ACTIVE_UNIFORMS);for(let i=0;i<r;i++){let r=t.getActiveUniform(e,i),a=r.name.replace(/\[.*?\]$/,``),o=!!r.name.match(/\[.*?\]$/),s=w(t,r.type);n[a]={name:a,index:i,type:s,size:r.size,isArray:o,value:b(s,r.size)}}return n}function k(e,t){let n=e.getShaderSource(t);if(n===null){console.error(`PixiJS Error: Could not retrieve shader source (WebGL context may be lost).`);return}let r=n.split(`
`).map((e,t)=>`${t}: ${e}`),i=e.getShaderInfoLog(t)??``,a=i.split(`
`),o={},s=a.map(e=>parseFloat(e.replace(/^ERROR\: 0\:([\d]+)\:.*$/,`$1`))).filter(e=>e&&!o[e]?(o[e]=!0,!0):!1),c=[``];s.forEach(e=>{r[e-1]=`%c${r[e-1]}%c`,c.push(`background: #FF0000; color:#FFFFFF; font-size: 10px`,`font-size: 10px`)}),c[0]=r.join(`
`),console.error(i),console.groupCollapsed(`click to view full shader code`),console.warn(...c),console.groupEnd()}function A(e,t,n,r){e.getProgramParameter(t,e.LINK_STATUS)||(e.getShaderParameter(n,e.COMPILE_STATUS)||k(e,n),e.getShaderParameter(r,e.COMPILE_STATUS)||k(e,r),console.error(`PixiJS Error: Could not initialize shader.`),e.getProgramInfoLog(t)!==``&&console.warn(`PixiJS Warning: gl.getProgramInfoLog()`,e.getProgramInfoLog(t)))}function j(e,t){let r=v(e,e.VERTEX_SHADER,t.vertex),i=v(e,e.FRAGMENT_SHADER,t.fragment),a=e.createProgram();e.attachShader(a,r),e.attachShader(a,i);let o=t.transformFeedbackVaryings;o&&(typeof e.transformFeedbackVaryings==`function`?e.transformFeedbackVaryings(a,o.names,o.bufferMode===`separate`?e.SEPARATE_ATTRIBS:e.INTERLEAVED_ATTRIBS):n(`TransformFeedback is not supported but TransformFeedbackVaryings are given.`)),e.linkProgram(a),e.getProgramParameter(a,e.LINK_STATUS)||A(e,a,r,i),t._attributeData=E(a,e,!/^[ \t]*#[ \t]*version[ \t]+300[ \t]+es[ \t]*$/m.test(t.vertex)),t._uniformData=O(a,e),t._uniformBlockData=D(a,e),e.deleteShader(r),e.deleteShader(i);let s={};for(let n in t._uniformData){let r=t._uniformData[n];s[n]={location:e.getUniformLocation(a,n),value:b(r.type,r.size)}}return new _(a,s)}var M={textureCount:0,blockIndex:0},N=class{constructor(e){this._activeProgram=null,this._programDataHash=Object.create(null),this._shaderSyncFunctions=Object.create(null),this._renderer=e}contextChange(e){this._gl=e,this._programDataHash=Object.create(null),this._shaderSyncFunctions=Object.create(null),this._activeProgram=null}bind(e,t){if(this._setProgram(e.glProgram),t)return;M.textureCount=0,M.blockIndex=0;let n=this._shaderSyncFunctions[e.glProgram._key];n||=this._shaderSyncFunctions[e.glProgram._key]=this._generateShaderSync(e,this),this._renderer.buffer.nextBindBase(!!e.glProgram.transformFeedbackVaryings),n(this._renderer,e,M)}updateUniformGroup(e){this._renderer.uniformGroup.updateUniformGroup(e,this._activeProgram,M)}bindUniformBlock(e,t,n=0){let r=this._renderer.buffer,i=this._getProgramData(this._activeProgram),a=e._bufferResource;a||this._renderer.ubo.updateUniformGroup(e);let o=e.buffer,s=r.updateBuffer(o),c=r.freeLocationForBufferBase(s);if(a){let{offset:t,size:n}=e;t===0&&n===o.data.byteLength?r.bindBufferBase(s,c):r.bindBufferRange(s,c,t)}else r.getLastBindBaseLocation(s)!==c&&r.bindBufferBase(s,c);let l=this._activeProgram._uniformBlockData[t].index;i.uniformBlockBindings[n]!==c&&(i.uniformBlockBindings[n]=c,this._renderer.gl.uniformBlockBinding(i.program,l,c))}_setProgram(e){if(this._activeProgram===e)return;this._activeProgram=e;let t=this._getProgramData(e);this._gl.useProgram(t.program)}_getProgramData(e){return this._programDataHash[e._key]||this._createProgramData(e)}_createProgramData(e){let t=e._key;return this._programDataHash[t]=j(this._gl,e),this._programDataHash[t]}destroy(){for(let e of Object.keys(this._programDataHash))this._programDataHash[e].destroy();this._programDataHash=null,this._shaderSyncFunctions=null,this._activeProgram=null,this._renderer=null,this._gl=null}_generateShaderSync(e,t){return h(e,t)}resetState(){this._activeProgram=null}};N.extension={type:[e.WebGLSystem],name:`shader`};var P={f32:`if (cv !== v) {
            cu.value = v;
            gl.uniform1f(location, v);
        }`,"vec2<f32>":`if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2f(location, v[0], v[1]);
        }`,"vec3<f32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3f(location, v[0], v[1], v[2]);
        }`,"vec4<f32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4f(location, v[0], v[1], v[2], v[3]);
        }`,i32:`if (cv !== v) {
            cu.value = v;
            gl.uniform1i(location, v);
        }`,"vec2<i32>":`if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2i(location, v[0], v[1]);
        }`,"vec3<i32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3i(location, v[0], v[1], v[2]);
        }`,"vec4<i32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4i(location, v[0], v[1], v[2], v[3]);
        }`,u32:`if (cv !== v) {
            cu.value = v;
            gl.uniform1ui(location, v);
        }`,"vec2<u32>":`if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2ui(location, v[0], v[1]);
        }`,"vec3<u32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3ui(location, v[0], v[1], v[2]);
        }`,"vec4<u32>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4ui(location, v[0], v[1], v[2], v[3]);
        }`,bool:`if (cv !== v) {
            cu.value = v;
            gl.uniform1i(location, v);
        }`,"vec2<bool>":`if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2i(location, v[0], v[1]);
        }`,"vec3<bool>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3i(location, v[0], v[1], v[2]);
        }`,"vec4<bool>":`if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4i(location, v[0], v[1], v[2], v[3]);
        }`,"mat2x2<f32>":`gl.uniformMatrix2fv(location, false, v);`,"mat3x3<f32>":`gl.uniformMatrix3fv(location, false, v);`,"mat4x4<f32>":`gl.uniformMatrix4fv(location, false, v);`},F={f32:`gl.uniform1fv(location, v);`,"vec2<f32>":`gl.uniform2fv(location, v);`,"vec3<f32>":`gl.uniform3fv(location, v);`,"vec4<f32>":`gl.uniform4fv(location, v);`,"mat2x2<f32>":`gl.uniformMatrix2fv(location, false, v);`,"mat3x3<f32>":`gl.uniformMatrix3fv(location, false, v);`,"mat4x4<f32>":`gl.uniformMatrix4fv(location, false, v);`,i32:`gl.uniform1iv(location, v);`,"vec2<i32>":`gl.uniform2iv(location, v);`,"vec3<i32>":`gl.uniform3iv(location, v);`,"vec4<i32>":`gl.uniform4iv(location, v);`,u32:`gl.uniform1iv(location, v);`,"vec2<u32>":`gl.uniform2iv(location, v);`,"vec3<u32>":`gl.uniform3iv(location, v);`,"vec4<u32>":`gl.uniform4iv(location, v);`,bool:`gl.uniform1iv(location, v);`,"vec2<bool>":`gl.uniform2iv(location, v);`,"vec3<bool>":`gl.uniform3iv(location, v);`,"vec4<bool>":`gl.uniform4iv(location, v);`};function I(e,t){let n=[`
        var v = null;
        var cv = null;
        var cu = null;
        var t = 0;
        var gl = renderer.gl;
        var name = null;
    `];for(let i in e.uniforms){if(!t[i]){e.uniforms[i]instanceof r?e.uniforms[i].ubo?n.push(`
                        renderer.shader.bindUniformBlock(uv.${i}, "${i}");
                    `):n.push(`
                        renderer.shader.updateUniformGroup(uv.${i});
                    `):e.uniforms[i]instanceof l&&n.push(`
                        renderer.shader.bindBufferResource(uv.${i}, "${i}");
                    `);continue}let o=e.uniformStructures[i],s=!1;for(let e=0;e<a.length;e++){let t=a[e];if(o.type===t.type&&t.test(o)){n.push(`name = "${i}";`,a[e].uniform),s=!0;break}}if(!s){let e=(o.size===1?P:F)[o.type].replace(`location`,`ud["${i}"].location`);n.push(`
            cu = ud["${i}"];
            cv = cu.value;
            v = uv["${i}"];
            ${e};`)}}return Function(`ud`,`uv`,`renderer`,`syncData`,n.join(`
`))}var L=class{constructor(e){this._cache={},this._uniformGroupSyncHash={},this._renderer=e,this.gl=null,this._cache={}}contextChange(e){this.gl=e}updateUniformGroup(e,t,n){let r=this._renderer.shader._getProgramData(t);(!e.isStatic||e._dirtyId!==r.uniformDirtyGroups[e.uid])&&(r.uniformDirtyGroups[e.uid]=e._dirtyId,this._getUniformSyncFunction(e,t)(r.uniformData,e.uniforms,this._renderer,n))}_getUniformSyncFunction(e,t){return this._uniformGroupSyncHash[e._signature]?.[t._key]||this._createUniformSyncFunction(e,t)}_createUniformSyncFunction(e,t){let n=this._uniformGroupSyncHash[e._signature]||(this._uniformGroupSyncHash[e._signature]={}),r=this._getSignature(e,t._uniformData,`u`);return this._cache[r]||(this._cache[r]=this._generateUniformsSync(e,t._uniformData)),n[t._key]=this._cache[r],n[t._key]}_generateUniformsSync(e,t){return I(e,t)}_getSignature(e,t,n){let r=e.uniforms,i=[`${n}-`];for(let e in r)i.push(e),t[e]&&i.push(t[e].type);return i.join(`-`)}destroy(){this._renderer=null,this._cache=null}};L.extension={type:[e.WebGLSystem],name:`uniformGroup`};export{d as S,h as _,N as a,f as b,O as c,T as d,w as f,g,_ as h,P as i,D as l,v as m,I as n,j as o,b as p,F as r,A as s,L as t,E as u,m as v,u as x,p as y};