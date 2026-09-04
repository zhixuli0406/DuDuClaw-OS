import{I as e,U as t,a as n,i as r}from"./Geometry-apQnTMm4.js";import{i}from"./AbstractRenderer-DBIXZFxr.js";var a=class{constructor(e){this._syncFunctionHash=Object.create(null),this._adaptor=e,this._systemCheck()}_systemCheck(){if(!i())throw Error(`Current environment does not allow unsafe-eval, please use pixi.js/unsafe-eval module to enable support.`)}ensureUniformGroup(e){let t=this.getUniformGroupData(e);e.buffer||=new r({data:new Float32Array(t.layout.size/4),usage:n.UNIFORM|n.COPY_DST})}getUniformGroupData(e){return this._syncFunctionHash[e._signature]||this._initUniformGroup(e)}_initUniformGroup(e){let t=e._signature,n=this._syncFunctionHash[t];if(!n){let r=Object.keys(e.uniformStructures).map(t=>e.uniformStructures[t]),i=this._adaptor.createUboElements(r),a=this._generateUboSync(i.uboElements);n=this._syncFunctionHash[t]={layout:i,syncFunction:a}}return this._syncFunctionHash[t]}_generateUboSync(e){return this._adaptor.generateUboSync(e)}syncUniformGroup(e,t,i){let a=this.getUniformGroupData(e);e.buffer||=new r({data:new Float32Array(a.layout.size/4),usage:n.UNIFORM|n.COPY_DST});let o=null;return t||(t=e.buffer.data,o=e.buffer.dataInt32),i||=0,a.syncFunction(e.uniforms,t,o,i),!0}updateUniformGroup(e){if(e.isStatic&&!e._dirtyId)return!1;e._dirtyId=0;let t=this.syncUniformGroup(e);return e.buffer.update(),t}destroy(){this._syncFunctionHash=null}},o=[{type:`mat3x3<f32>`,test:e=>e.value.a!==void 0,ubo:`
            var matrix = uv[name].toArray(true);
            data[offset] = matrix[0];
            data[offset + 1] = matrix[1];
            data[offset + 2] = matrix[2];
            data[offset + 4] = matrix[3];
            data[offset + 5] = matrix[4];
            data[offset + 6] = matrix[5];
            data[offset + 8] = matrix[6];
            data[offset + 9] = matrix[7];
            data[offset + 10] = matrix[8];
        `,uniform:`
            gl.uniformMatrix3fv(ud[name].location, false, uv[name].toArray(true));
        `},{type:`vec4<f32>`,test:e=>e.type===`vec4<f32>`&&e.size===1&&e.value.width!==void 0,ubo:`
            v = uv[name];
            data[offset] = v.x;
            data[offset + 1] = v.y;
            data[offset + 2] = v.width;
            data[offset + 3] = v.height;
        `,uniform:`
            cv = ud[name].value;
            v = uv[name];
            if (cv[0] !== v.x || cv[1] !== v.y || cv[2] !== v.width || cv[3] !== v.height) {
                cv[0] = v.x;
                cv[1] = v.y;
                cv[2] = v.width;
                cv[3] = v.height;
                gl.uniform4f(ud[name].location, v.x, v.y, v.width, v.height);
            }
        `},{type:`vec2<f32>`,test:e=>e.type===`vec2<f32>`&&e.size===1&&e.value.x!==void 0,ubo:`
            v = uv[name];
            data[offset] = v.x;
            data[offset + 1] = v.y;
        `,uniform:`
            cv = ud[name].value;
            v = uv[name];
            if (cv[0] !== v.x || cv[1] !== v.y) {
                cv[0] = v.x;
                cv[1] = v.y;
                gl.uniform2f(ud[name].location, v.x, v.y);
            }
        `},{type:`vec4<f32>`,test:e=>e.type===`vec4<f32>`&&e.size===1&&e.value.red!==void 0,ubo:`
            v = uv[name];
            data[offset] = v.red;
            data[offset + 1] = v.green;
            data[offset + 2] = v.blue;
            data[offset + 3] = v.alpha;
        `,uniform:`
            cv = ud[name].value;
            v = uv[name];
            if (cv[0] !== v.red || cv[1] !== v.green || cv[2] !== v.blue || cv[3] !== v.alpha) {
                cv[0] = v.red;
                cv[1] = v.green;
                cv[2] = v.blue;
                cv[3] = v.alpha;
                gl.uniform4f(ud[name].location, v.red, v.green, v.blue, v.alpha);
            }
        `},{type:`vec3<f32>`,test:e=>e.type===`vec3<f32>`&&e.size===1&&e.value.red!==void 0,ubo:`
            v = uv[name];
            data[offset] = v.red;
            data[offset + 1] = v.green;
            data[offset + 2] = v.blue;
        `,uniform:`
            cv = ud[name].value;
            v = uv[name];
            if (cv[0] !== v.red || cv[1] !== v.green || cv[2] !== v.blue) {
                cv[0] = v.red;
                cv[1] = v.green;
                cv[2] = v.blue;
                gl.uniform3f(ud[name].location, v.red, v.green, v.blue);
            }
        `}];function s(e,t,n,r){let i=[`
        var v = null;
        var v2 = null;
        var t = 0;
        var index = 0;
        var name = null;
        var arrayOffset = null;
    `],a=0;for(let s=0;s<e.length;s++){let c=e[s],l=c.data.name,u=!1,d=0;for(let e=0;e<o.length;e++)if(o[e].test(c.data)){d=c.offset/4,i.push(`name = "${l}";`,`offset += ${d-a};`,o[e][t]||o[e].ubo),u=!0;break}if(!u)if(c.data.size>1)d=c.offset/4,i.push(n(c,d-a));else{let e=r[c.data.type];d=c.offset/4,i.push(`
                    v = uv.${l};
                    offset += ${d-a};
                    ${e};
                `)}a=d}let s=i.join(`
`);return Function(`uv`,`data`,`dataInt32`,`offset`,s)}function c(e,t){return`
        for (let i = 0; i < ${e*t}; i++) {
            data[offset + (((i / ${e})|0) * 4) + (i % ${e})] = v[i];
        }
    `}var l={f32:`
        data[offset] = v;`,i32:`
        dataInt32[offset] = v;`,"vec2<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];`,"vec3<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];
        data[offset + 2] = v[2];`,"vec4<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];
        data[offset + 2] = v[2];
        data[offset + 3] = v[3];`,"vec2<i32>":`
        dataInt32[offset] = v[0];
        dataInt32[offset + 1] = v[1];`,"vec3<i32>":`
        dataInt32[offset] = v[0];
        dataInt32[offset + 1] = v[1];
        dataInt32[offset + 2] = v[2];`,"vec4<i32>":`
        dataInt32[offset] = v[0];
        dataInt32[offset + 1] = v[1];
        dataInt32[offset + 2] = v[2];
        dataInt32[offset + 3] = v[3];`,"mat2x2<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];
        data[offset + 4] = v[2];
        data[offset + 5] = v[3];`,"mat3x3<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];
        data[offset + 2] = v[2];
        data[offset + 4] = v[3];
        data[offset + 5] = v[4];
        data[offset + 6] = v[5];
        data[offset + 8] = v[6];
        data[offset + 9] = v[7];
        data[offset + 10] = v[8];`,"mat4x4<f32>":`
        for (let i = 0; i < 16; i++) {
            data[offset + i] = v[i];
        }`,"mat3x2<f32>":c(3,2),"mat4x2<f32>":c(4,2),"mat2x3<f32>":c(2,3),"mat4x3<f32>":c(4,3),"mat2x4<f32>":c(2,4),"mat3x4<f32>":c(3,4)},u={...l,"mat2x2<f32>":`
        data[offset] = v[0];
        data[offset + 1] = v[1];
        data[offset + 2] = v[2];
        data[offset + 3] = v[3];
    `},d=class extends t{constructor({buffer:t,offset:n,size:r}){super(),this.uid=e(`buffer`),this._resourceType=`bufferResource`,this._touched=0,this._resourceId=e(`resource`),this._bufferResource=!0,this.destroyed=!1,this.buffer=t,this.offset=n|0,this.size=r,this.buffer.on(`change`,this.onBufferChange,this)}onBufferChange(){this._resourceId=e(`resource`),this.emit(`change`,this)}destroy(e=!1){this.destroyed=!0,e&&this.buffer.destroy(),this.emit(`change`,this),this.buffer=null,this.removeAllListeners()}};export{o as a,s as i,l as n,a as o,u as r,d as t};