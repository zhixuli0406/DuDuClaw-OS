/*!
 * ogl 1.0.11 — minimal WebGL library, vendored for DuDuClaw OS website
 * https://github.com/oframe/ogl  ·  (c) Nathan Gordon
 *
 * SPDX-License-Identifier: Unlicense
 * The npm package declares "license": "Unlicense" (the upstream repository
 * ships no LICENSE file of its own; the registry metadata for ogl@1.0.11 is
 * the authoritative statement). Full text of the Unlicense follows.
 *
 *   This is free and unencumbered software released into the public domain.
 *
 *   Anyone is free to copy, modify, publish, use, compile, sell, or
 *   distribute this software, either in source code form or as a compiled
 *   binary, for any purpose, commercial or non-commercial, and by any
 *   means.
 *
 *   In jurisdictions that recognize copyright laws, the author or authors
 *   of this software dedicate any and all copyright interest in the
 *   software to the public domain. We make this dedication for the benefit
 *   of the public at large and to the detriment of our heirs and
 *   successors. We intend this dedication to be an overt act of
 *   relinquishment in perpetuity of all present and future rights to this
 *   software under copyright law.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 *   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 *   IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 *   OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 *   ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 *   For more information, please refer to <https://unlicense.org/>
 *
 * ---------------------------------------------------------------------------
 * How this file was produced (reproducible):
 *   npm pack ogl@1.0.11                     # tarball sha1 369d6b8681035500fbb14d461f4d74f014527b88
 *   tar xzf ogl-1.0.11.tgz
 *   # entry.js re-exports only core + math (no extras / loaders / helpers)
 *   npx esbuild@0.25.9 entry.js --bundle --format=esm --outfile=ogl.mjs
 * Exports: Geometry, Program, Renderer, Camera, Transform, Mesh,
 *          Color, Euler, Mat3, Mat4, Quat, Vec2, Vec3, Vec4.
 * Upstream `extras/` (Orbit, GLTFLoader, Post, Text, …) is intentionally
 * omitted — the cat needs none of it. Do not hand-edit; regenerate instead.
 */
// package/src/math/functions/Vec3Func.js
function length(a) {
  let x = a[0];
  let y = a[1];
  let z = a[2];
  return Math.sqrt(x * x + y * y + z * z);
}
function copy(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  out[2] = a[2];
  return out;
}
function set(out, x, y, z) {
  out[0] = x;
  out[1] = y;
  out[2] = z;
  return out;
}
function add(out, a, b) {
  out[0] = a[0] + b[0];
  out[1] = a[1] + b[1];
  out[2] = a[2] + b[2];
  return out;
}
function subtract(out, a, b) {
  out[0] = a[0] - b[0];
  out[1] = a[1] - b[1];
  out[2] = a[2] - b[2];
  return out;
}
function multiply(out, a, b) {
  out[0] = a[0] * b[0];
  out[1] = a[1] * b[1];
  out[2] = a[2] * b[2];
  return out;
}
function divide(out, a, b) {
  out[0] = a[0] / b[0];
  out[1] = a[1] / b[1];
  out[2] = a[2] / b[2];
  return out;
}
function scale(out, a, b) {
  out[0] = a[0] * b;
  out[1] = a[1] * b;
  out[2] = a[2] * b;
  return out;
}
function distance(a, b) {
  let x = b[0] - a[0];
  let y = b[1] - a[1];
  let z = b[2] - a[2];
  return Math.sqrt(x * x + y * y + z * z);
}
function squaredDistance(a, b) {
  let x = b[0] - a[0];
  let y = b[1] - a[1];
  let z = b[2] - a[2];
  return x * x + y * y + z * z;
}
function squaredLength(a) {
  let x = a[0];
  let y = a[1];
  let z = a[2];
  return x * x + y * y + z * z;
}
function negate(out, a) {
  out[0] = -a[0];
  out[1] = -a[1];
  out[2] = -a[2];
  return out;
}
function inverse(out, a) {
  out[0] = 1 / a[0];
  out[1] = 1 / a[1];
  out[2] = 1 / a[2];
  return out;
}
function normalize(out, a) {
  let x = a[0];
  let y = a[1];
  let z = a[2];
  let len = x * x + y * y + z * z;
  if (len > 0) {
    len = 1 / Math.sqrt(len);
  }
  out[0] = a[0] * len;
  out[1] = a[1] * len;
  out[2] = a[2] * len;
  return out;
}
function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
function cross(out, a, b) {
  let ax = a[0], ay = a[1], az = a[2];
  let bx = b[0], by = b[1], bz = b[2];
  out[0] = ay * bz - az * by;
  out[1] = az * bx - ax * bz;
  out[2] = ax * by - ay * bx;
  return out;
}
function lerp(out, a, b, t) {
  let ax = a[0];
  let ay = a[1];
  let az = a[2];
  out[0] = ax + t * (b[0] - ax);
  out[1] = ay + t * (b[1] - ay);
  out[2] = az + t * (b[2] - az);
  return out;
}
function smoothLerp(out, a, b, decay, dt) {
  const exp = Math.exp(-decay * dt);
  let ax = a[0];
  let ay = a[1];
  let az = a[2];
  out[0] = b[0] + (ax - b[0]) * exp;
  out[1] = b[1] + (ay - b[1]) * exp;
  out[2] = b[2] + (az - b[2]) * exp;
  return out;
}
function transformMat4(out, a, m) {
  let x = a[0], y = a[1], z = a[2];
  let w = m[3] * x + m[7] * y + m[11] * z + m[15];
  w = w || 1;
  out[0] = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w;
  out[1] = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w;
  out[2] = (m[2] * x + m[6] * y + m[10] * z + m[14]) / w;
  return out;
}
function scaleRotateMat4(out, a, m) {
  let x = a[0], y = a[1], z = a[2];
  let w = m[3] * x + m[7] * y + m[11] * z + m[15];
  w = w || 1;
  out[0] = (m[0] * x + m[4] * y + m[8] * z) / w;
  out[1] = (m[1] * x + m[5] * y + m[9] * z) / w;
  out[2] = (m[2] * x + m[6] * y + m[10] * z) / w;
  return out;
}
function transformMat3(out, a, m) {
  let x = a[0], y = a[1], z = a[2];
  out[0] = x * m[0] + y * m[3] + z * m[6];
  out[1] = x * m[1] + y * m[4] + z * m[7];
  out[2] = x * m[2] + y * m[5] + z * m[8];
  return out;
}
function transformQuat(out, a, q) {
  let x = a[0], y = a[1], z = a[2];
  let qx = q[0], qy = q[1], qz = q[2], qw = q[3];
  let uvx = qy * z - qz * y;
  let uvy = qz * x - qx * z;
  let uvz = qx * y - qy * x;
  let uuvx = qy * uvz - qz * uvy;
  let uuvy = qz * uvx - qx * uvz;
  let uuvz = qx * uvy - qy * uvx;
  let w2 = qw * 2;
  uvx *= w2;
  uvy *= w2;
  uvz *= w2;
  uuvx *= 2;
  uuvy *= 2;
  uuvz *= 2;
  out[0] = x + uvx + uuvx;
  out[1] = y + uvy + uuvy;
  out[2] = z + uvz + uuvz;
  return out;
}
var angle = /* @__PURE__ */ (function() {
  const tempA = [0, 0, 0];
  const tempB = [0, 0, 0];
  return function(a, b) {
    copy(tempA, a);
    copy(tempB, b);
    normalize(tempA, tempA);
    normalize(tempB, tempB);
    let cosine = dot(tempA, tempB);
    if (cosine > 1) {
      return 0;
    } else if (cosine < -1) {
      return Math.PI;
    } else {
      return Math.acos(cosine);
    }
  };
})();
function exactEquals(a, b) {
  return a[0] === b[0] && a[1] === b[1] && a[2] === b[2];
}

// package/src/math/Vec3.js
var Vec3 = class _Vec3 extends Array {
  constructor(x = 0, y = x, z = x) {
    super(x, y, z);
    return this;
  }
  get x() {
    return this[0];
  }
  get y() {
    return this[1];
  }
  get z() {
    return this[2];
  }
  set x(v) {
    this[0] = v;
  }
  set y(v) {
    this[1] = v;
  }
  set z(v) {
    this[2] = v;
  }
  set(x, y = x, z = x) {
    if (x.length) return this.copy(x);
    set(this, x, y, z);
    return this;
  }
  copy(v) {
    copy(this, v);
    return this;
  }
  add(va, vb) {
    if (vb) add(this, va, vb);
    else add(this, this, va);
    return this;
  }
  sub(va, vb) {
    if (vb) subtract(this, va, vb);
    else subtract(this, this, va);
    return this;
  }
  multiply(v) {
    if (v.length) multiply(this, this, v);
    else scale(this, this, v);
    return this;
  }
  divide(v) {
    if (v.length) divide(this, this, v);
    else scale(this, this, 1 / v);
    return this;
  }
  inverse(v = this) {
    inverse(this, v);
    return this;
  }
  // Can't use 'length' as Array.prototype uses it
  len() {
    return length(this);
  }
  distance(v) {
    if (v) return distance(this, v);
    else return length(this);
  }
  squaredLen() {
    return squaredLength(this);
  }
  squaredDistance(v) {
    if (v) return squaredDistance(this, v);
    else return squaredLength(this);
  }
  negate(v = this) {
    negate(this, v);
    return this;
  }
  cross(va, vb) {
    if (vb) cross(this, va, vb);
    else cross(this, this, va);
    return this;
  }
  scale(v) {
    scale(this, this, v);
    return this;
  }
  normalize() {
    normalize(this, this);
    return this;
  }
  dot(v) {
    return dot(this, v);
  }
  equals(v) {
    return exactEquals(this, v);
  }
  applyMatrix3(mat3) {
    transformMat3(this, this, mat3);
    return this;
  }
  applyMatrix4(mat4) {
    transformMat4(this, this, mat4);
    return this;
  }
  scaleRotateMatrix4(mat4) {
    scaleRotateMat4(this, this, mat4);
    return this;
  }
  applyQuaternion(q) {
    transformQuat(this, this, q);
    return this;
  }
  angle(v) {
    return angle(this, v);
  }
  lerp(v, t) {
    lerp(this, this, v, t);
    return this;
  }
  smoothLerp(v, decay, dt) {
    smoothLerp(this, this, v, decay, dt);
    return this;
  }
  clone() {
    return new _Vec3(this[0], this[1], this[2]);
  }
  fromArray(a, o = 0) {
    this[0] = a[o];
    this[1] = a[o + 1];
    this[2] = a[o + 2];
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    a[o + 2] = this[2];
    return a;
  }
  transformDirection(mat4) {
    const x = this[0];
    const y = this[1];
    const z = this[2];
    this[0] = mat4[0] * x + mat4[4] * y + mat4[8] * z;
    this[1] = mat4[1] * x + mat4[5] * y + mat4[9] * z;
    this[2] = mat4[2] * x + mat4[6] * y + mat4[10] * z;
    return this.normalize();
  }
};

// package/src/core/Geometry.js
var tempVec3 = /* @__PURE__ */ new Vec3();
var ID = 1;
var ATTR_ID = 1;
var isBoundsWarned = false;
var Geometry = class {
  constructor(gl, attributes = {}) {
    if (!gl.canvas) console.error("gl not passed as first argument to Geometry");
    this.gl = gl;
    this.attributes = attributes;
    this.id = ID++;
    this.VAOs = {};
    this.drawRange = { start: 0, count: 0 };
    this.instancedCount = 0;
    this.gl.renderer.bindVertexArray(null);
    this.gl.renderer.currentGeometry = null;
    this.glState = this.gl.renderer.state;
    for (let key in attributes) {
      this.addAttribute(key, attributes[key]);
    }
  }
  addAttribute(key, attr) {
    this.attributes[key] = attr;
    attr.id = ATTR_ID++;
    attr.size = attr.size || 1;
    attr.type = attr.type || (attr.data.constructor === Float32Array ? this.gl.FLOAT : attr.data.constructor === Uint16Array ? this.gl.UNSIGNED_SHORT : this.gl.UNSIGNED_INT);
    attr.target = key === "index" ? this.gl.ELEMENT_ARRAY_BUFFER : this.gl.ARRAY_BUFFER;
    attr.normalized = attr.normalized || false;
    attr.stride = attr.stride || 0;
    attr.offset = attr.offset || 0;
    attr.count = attr.count || (attr.stride ? attr.data.byteLength / attr.stride : attr.data.length / attr.size);
    attr.divisor = attr.instanced || 0;
    attr.needsUpdate = false;
    attr.usage = attr.usage || this.gl.STATIC_DRAW;
    if (!attr.buffer) {
      this.updateAttribute(attr);
    }
    if (attr.divisor) {
      this.isInstanced = true;
      if (this.instancedCount && this.instancedCount !== attr.count * attr.divisor) {
        console.warn("geometry has multiple instanced buffers of different length");
        return this.instancedCount = Math.min(this.instancedCount, attr.count * attr.divisor);
      }
      this.instancedCount = attr.count * attr.divisor;
    } else if (key === "index") {
      this.drawRange.count = attr.count;
    } else if (!this.attributes.index) {
      this.drawRange.count = Math.max(this.drawRange.count, attr.count);
    }
  }
  updateAttribute(attr) {
    const isNewBuffer = !attr.buffer;
    if (isNewBuffer) attr.buffer = this.gl.createBuffer();
    if (this.glState.boundBuffer !== attr.buffer) {
      this.gl.bindBuffer(attr.target, attr.buffer);
      this.glState.boundBuffer = attr.buffer;
    }
    if (isNewBuffer) {
      this.gl.bufferData(attr.target, attr.data, attr.usage);
    } else {
      this.gl.bufferSubData(attr.target, 0, attr.data);
    }
    attr.needsUpdate = false;
  }
  setIndex(value) {
    this.addAttribute("index", value);
  }
  setDrawRange(start, count) {
    this.drawRange.start = start;
    this.drawRange.count = count;
  }
  setInstancedCount(value) {
    this.instancedCount = value;
  }
  createVAO(program) {
    this.VAOs[program.attributeOrder] = this.gl.renderer.createVertexArray();
    this.gl.renderer.bindVertexArray(this.VAOs[program.attributeOrder]);
    this.bindAttributes(program);
  }
  bindAttributes(program) {
    program.attributeLocations.forEach((location, { name, type }) => {
      if (!this.attributes[name]) {
        console.warn(`active attribute ${name} not being supplied`);
        return;
      }
      const attr = this.attributes[name];
      this.gl.bindBuffer(attr.target, attr.buffer);
      this.glState.boundBuffer = attr.buffer;
      let numLoc = 1;
      if (type === 35674) numLoc = 2;
      if (type === 35675) numLoc = 3;
      if (type === 35676) numLoc = 4;
      const size = attr.size / numLoc;
      const stride = numLoc === 1 ? 0 : numLoc * numLoc * 4;
      const offset = numLoc === 1 ? 0 : numLoc * 4;
      for (let i = 0; i < numLoc; i++) {
        this.gl.vertexAttribPointer(location + i, size, attr.type, attr.normalized, attr.stride + stride, attr.offset + i * offset);
        this.gl.enableVertexAttribArray(location + i);
        this.gl.renderer.vertexAttribDivisor(location + i, attr.divisor);
      }
    });
    if (this.attributes.index) this.gl.bindBuffer(this.gl.ELEMENT_ARRAY_BUFFER, this.attributes.index.buffer);
  }
  draw({ program, mode = this.gl.TRIANGLES }) {
    if (this.gl.renderer.currentGeometry !== `${this.id}_${program.attributeOrder}`) {
      if (!this.VAOs[program.attributeOrder]) this.createVAO(program);
      this.gl.renderer.bindVertexArray(this.VAOs[program.attributeOrder]);
      this.gl.renderer.currentGeometry = `${this.id}_${program.attributeOrder}`;
    }
    program.attributeLocations.forEach((location, { name }) => {
      const attr = this.attributes[name];
      if (attr.needsUpdate) this.updateAttribute(attr);
    });
    let indexBytesPerElement = 2;
    if (this.attributes.index?.type === this.gl.UNSIGNED_INT) indexBytesPerElement = 4;
    if (this.isInstanced) {
      if (this.attributes.index) {
        this.gl.renderer.drawElementsInstanced(
          mode,
          this.drawRange.count,
          this.attributes.index.type,
          this.attributes.index.offset + this.drawRange.start * indexBytesPerElement,
          this.instancedCount
        );
      } else {
        this.gl.renderer.drawArraysInstanced(mode, this.drawRange.start, this.drawRange.count, this.instancedCount);
      }
    } else {
      if (this.attributes.index) {
        this.gl.drawElements(
          mode,
          this.drawRange.count,
          this.attributes.index.type,
          this.attributes.index.offset + this.drawRange.start * indexBytesPerElement
        );
      } else {
        this.gl.drawArrays(mode, this.drawRange.start, this.drawRange.count);
      }
    }
  }
  getPosition() {
    const attr = this.attributes.position;
    if (attr.data) return attr;
    if (isBoundsWarned) return;
    console.warn("No position buffer data found to compute bounds");
    return isBoundsWarned = true;
  }
  computeBoundingBox(attr) {
    if (!attr) attr = this.getPosition();
    const array = attr.data;
    const stride = attr.size;
    if (!this.bounds) {
      this.bounds = {
        min: new Vec3(),
        max: new Vec3(),
        center: new Vec3(),
        scale: new Vec3(),
        radius: Infinity
      };
    }
    const min = this.bounds.min;
    const max = this.bounds.max;
    const center = this.bounds.center;
    const scale6 = this.bounds.scale;
    min.set(Infinity);
    max.set(-Infinity);
    for (let i = 0, l = array.length; i < l; i += stride) {
      const x = array[i];
      const y = array[i + 1];
      const z = array[i + 2];
      min.x = Math.min(x, min.x);
      min.y = Math.min(y, min.y);
      min.z = Math.min(z, min.z);
      max.x = Math.max(x, max.x);
      max.y = Math.max(y, max.y);
      max.z = Math.max(z, max.z);
    }
    scale6.sub(max, min);
    center.add(min, max).divide(2);
  }
  computeBoundingSphere(attr) {
    if (!attr) attr = this.getPosition();
    const array = attr.data;
    const stride = attr.size;
    if (!this.bounds) this.computeBoundingBox(attr);
    let maxRadiusSq = 0;
    for (let i = 0, l = array.length; i < l; i += stride) {
      tempVec3.fromArray(array, i);
      maxRadiusSq = Math.max(maxRadiusSq, this.bounds.center.squaredDistance(tempVec3));
    }
    this.bounds.radius = Math.sqrt(maxRadiusSq);
  }
  remove() {
    for (let key in this.VAOs) {
      this.gl.renderer.deleteVertexArray(this.VAOs[key]);
      delete this.VAOs[key];
    }
    for (let key in this.attributes) {
      this.gl.deleteBuffer(this.attributes[key].buffer);
      delete this.attributes[key];
    }
  }
};

// package/src/core/Program.js
var ID2 = 1;
var arrayCacheF32 = {};
var Program = class {
  constructor(gl, {
    vertex,
    fragment,
    uniforms = {},
    transparent = false,
    cullFace = gl.BACK,
    frontFace = gl.CCW,
    depthTest = true,
    depthWrite = true,
    depthFunc = gl.LEQUAL
  } = {}) {
    if (!gl.canvas) console.error("gl not passed as first argument to Program");
    this.gl = gl;
    this.uniforms = uniforms;
    this.id = ID2++;
    if (!vertex) console.warn("vertex shader not supplied");
    if (!fragment) console.warn("fragment shader not supplied");
    this.transparent = transparent;
    this.cullFace = cullFace;
    this.frontFace = frontFace;
    this.depthTest = depthTest;
    this.depthWrite = depthWrite;
    this.depthFunc = depthFunc;
    this.blendFunc = {};
    this.blendEquation = {};
    this.stencilFunc = {};
    this.stencilOp = {};
    if (this.transparent && !this.blendFunc.src) {
      if (this.gl.renderer.premultipliedAlpha) this.setBlendFunc(this.gl.ONE, this.gl.ONE_MINUS_SRC_ALPHA);
      else this.setBlendFunc(this.gl.SRC_ALPHA, this.gl.ONE_MINUS_SRC_ALPHA);
    }
    this.vertexShader = gl.createShader(gl.VERTEX_SHADER);
    this.fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
    this.program = gl.createProgram();
    gl.attachShader(this.program, this.vertexShader);
    gl.attachShader(this.program, this.fragmentShader);
    this.setShaders({ vertex, fragment });
  }
  setShaders({ vertex, fragment }) {
    if (vertex) {
      this.gl.shaderSource(this.vertexShader, vertex);
      this.gl.compileShader(this.vertexShader);
      if (this.gl.getShaderInfoLog(this.vertexShader) !== "") {
        console.warn(`${this.gl.getShaderInfoLog(this.vertexShader)}
Vertex Shader
${addLineNumbers(vertex)}`);
      }
    }
    if (fragment) {
      this.gl.shaderSource(this.fragmentShader, fragment);
      this.gl.compileShader(this.fragmentShader);
      if (this.gl.getShaderInfoLog(this.fragmentShader) !== "") {
        console.warn(`${this.gl.getShaderInfoLog(this.fragmentShader)}
Fragment Shader
${addLineNumbers(fragment)}`);
      }
    }
    this.gl.linkProgram(this.program);
    if (!this.gl.getProgramParameter(this.program, this.gl.LINK_STATUS)) {
      return console.warn(this.gl.getProgramInfoLog(this.program));
    }
    this.uniformLocations = /* @__PURE__ */ new Map();
    let numUniforms = this.gl.getProgramParameter(this.program, this.gl.ACTIVE_UNIFORMS);
    for (let uIndex = 0; uIndex < numUniforms; uIndex++) {
      let uniform = this.gl.getActiveUniform(this.program, uIndex);
      this.uniformLocations.set(uniform, this.gl.getUniformLocation(this.program, uniform.name));
      const split = uniform.name.match(/(\w+)/g);
      uniform.uniformName = split[0];
      uniform.nameComponents = split.slice(1);
    }
    this.attributeLocations = /* @__PURE__ */ new Map();
    const locations = [];
    const numAttribs = this.gl.getProgramParameter(this.program, this.gl.ACTIVE_ATTRIBUTES);
    for (let aIndex = 0; aIndex < numAttribs; aIndex++) {
      const attribute = this.gl.getActiveAttrib(this.program, aIndex);
      const location = this.gl.getAttribLocation(this.program, attribute.name);
      if (location === -1) continue;
      locations[location] = attribute.name;
      this.attributeLocations.set(attribute, location);
    }
    this.attributeOrder = locations.join("");
  }
  setBlendFunc(src, dst, srcAlpha, dstAlpha) {
    this.blendFunc.src = src;
    this.blendFunc.dst = dst;
    this.blendFunc.srcAlpha = srcAlpha;
    this.blendFunc.dstAlpha = dstAlpha;
    if (src) this.transparent = true;
  }
  setBlendEquation(modeRGB, modeAlpha) {
    this.blendEquation.modeRGB = modeRGB;
    this.blendEquation.modeAlpha = modeAlpha;
  }
  setStencilFunc(func, ref, mask) {
    this.stencilRef = ref;
    this.stencilFunc.func = func;
    this.stencilFunc.ref = ref;
    this.stencilFunc.mask = mask;
  }
  setStencilOp(stencilFail, depthFail, depthPass) {
    this.stencilOp.stencilFail = stencilFail;
    this.stencilOp.depthFail = depthFail;
    this.stencilOp.depthPass = depthPass;
  }
  applyState() {
    if (this.depthTest) this.gl.renderer.enable(this.gl.DEPTH_TEST);
    else this.gl.renderer.disable(this.gl.DEPTH_TEST);
    if (this.cullFace) this.gl.renderer.enable(this.gl.CULL_FACE);
    else this.gl.renderer.disable(this.gl.CULL_FACE);
    if (this.blendFunc.src) this.gl.renderer.enable(this.gl.BLEND);
    else this.gl.renderer.disable(this.gl.BLEND);
    if (this.cullFace) this.gl.renderer.setCullFace(this.cullFace);
    this.gl.renderer.setFrontFace(this.frontFace);
    this.gl.renderer.setDepthMask(this.depthWrite);
    this.gl.renderer.setDepthFunc(this.depthFunc);
    if (this.blendFunc.src) this.gl.renderer.setBlendFunc(this.blendFunc.src, this.blendFunc.dst, this.blendFunc.srcAlpha, this.blendFunc.dstAlpha);
    this.gl.renderer.setBlendEquation(this.blendEquation.modeRGB, this.blendEquation.modeAlpha);
    if (this.stencilFunc.func || this.stencilOp.stencilFail) this.gl.renderer.enable(this.gl.STENCIL_TEST);
    else this.gl.renderer.disable(this.gl.STENCIL_TEST);
    this.gl.renderer.setStencilFunc(this.stencilFunc.func, this.stencilFunc.ref, this.stencilFunc.mask);
    this.gl.renderer.setStencilOp(this.stencilOp.stencilFail, this.stencilOp.depthFail, this.stencilOp.depthPass);
  }
  use({ flipFaces = false } = {}) {
    let textureUnit = -1;
    const programActive = this.gl.renderer.state.currentProgram === this.id;
    if (!programActive) {
      this.gl.useProgram(this.program);
      this.gl.renderer.state.currentProgram = this.id;
    }
    this.uniformLocations.forEach((location, activeUniform) => {
      let uniform = this.uniforms[activeUniform.uniformName];
      for (const component of activeUniform.nameComponents) {
        if (!uniform) break;
        if (component in uniform) {
          uniform = uniform[component];
        } else if (Array.isArray(uniform.value)) {
          break;
        } else {
          uniform = void 0;
          break;
        }
      }
      if (!uniform) {
        return warn(`Active uniform ${activeUniform.name} has not been supplied`);
      }
      if (uniform && uniform.value === void 0) {
        return warn(`${activeUniform.name} uniform is missing a value parameter`);
      }
      if (uniform.value.texture) {
        textureUnit = textureUnit + 1;
        uniform.value.update(textureUnit);
        return setUniform(this.gl, activeUniform.type, location, textureUnit);
      }
      if (uniform.value.length && uniform.value[0].texture) {
        const textureUnits = [];
        uniform.value.forEach((value) => {
          textureUnit = textureUnit + 1;
          value.update(textureUnit);
          textureUnits.push(textureUnit);
        });
        return setUniform(this.gl, activeUniform.type, location, textureUnits);
      }
      setUniform(this.gl, activeUniform.type, location, uniform.value);
    });
    this.applyState();
    if (flipFaces) this.gl.renderer.setFrontFace(this.frontFace === this.gl.CCW ? this.gl.CW : this.gl.CCW);
  }
  remove() {
    this.gl.deleteProgram(this.program);
  }
};
function setUniform(gl, type, location, value) {
  value = value.length ? flatten(value) : value;
  const setValue = gl.renderer.state.uniformLocations.get(location);
  if (value.length) {
    if (setValue === void 0 || setValue.length !== value.length) {
      gl.renderer.state.uniformLocations.set(location, value.slice(0));
    } else {
      if (arraysEqual(setValue, value)) return;
      setValue.set ? setValue.set(value) : setArray(setValue, value);
      gl.renderer.state.uniformLocations.set(location, setValue);
    }
  } else {
    if (setValue === value) return;
    gl.renderer.state.uniformLocations.set(location, value);
  }
  switch (type) {
    case 5126:
      return value.length ? gl.uniform1fv(location, value) : gl.uniform1f(location, value);
    // FLOAT
    case 35664:
      return gl.uniform2fv(location, value);
    // FLOAT_VEC2
    case 35665:
      return gl.uniform3fv(location, value);
    // FLOAT_VEC3
    case 35666:
      return gl.uniform4fv(location, value);
    // FLOAT_VEC4
    case 35670:
    // BOOL
    case 5124:
    // INT
    case 35678:
    // SAMPLER_2D
    case 36306:
    // U_SAMPLER_2D
    case 35680:
    // SAMPLER_CUBE
    case 36289:
      return value.length ? gl.uniform1iv(location, value) : gl.uniform1i(location, value);
    // SAMPLER_CUBE
    case 35671:
    // BOOL_VEC2
    case 35667:
      return gl.uniform2iv(location, value);
    // INT_VEC2
    case 35672:
    // BOOL_VEC3
    case 35668:
      return gl.uniform3iv(location, value);
    // INT_VEC3
    case 35673:
    // BOOL_VEC4
    case 35669:
      return gl.uniform4iv(location, value);
    // INT_VEC4
    case 35674:
      return gl.uniformMatrix2fv(location, false, value);
    // FLOAT_MAT2
    case 35675:
      return gl.uniformMatrix3fv(location, false, value);
    // FLOAT_MAT3
    case 35676:
      return gl.uniformMatrix4fv(location, false, value);
  }
}
function addLineNumbers(string) {
  let lines = string.split("\n");
  for (let i = 0; i < lines.length; i++) {
    lines[i] = i + 1 + ": " + lines[i];
  }
  return lines.join("\n");
}
function flatten(a) {
  const arrayLen = a.length;
  const valueLen = a[0].length;
  if (valueLen === void 0) return a;
  const length4 = arrayLen * valueLen;
  let value = arrayCacheF32[length4];
  if (!value) arrayCacheF32[length4] = value = new Float32Array(length4);
  for (let i = 0; i < arrayLen; i++) value.set(a[i], i * valueLen);
  return value;
}
function arraysEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0, l = a.length; i < l; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}
function setArray(a, b) {
  for (let i = 0, l = a.length; i < l; i++) {
    a[i] = b[i];
  }
}
var warnCount = 0;
function warn(message) {
  if (warnCount > 100) return;
  console.warn(message);
  warnCount++;
  if (warnCount > 100) console.warn("More than 100 program warnings - stopping logs.");
}

// package/src/core/Renderer.js
var tempVec32 = /* @__PURE__ */ new Vec3();
var ID3 = 1;
var Renderer = class {
  constructor({
    canvas = document.createElement("canvas"),
    width = 300,
    height = 150,
    dpr = 1,
    alpha = false,
    depth = true,
    stencil = false,
    antialias = false,
    premultipliedAlpha = false,
    preserveDrawingBuffer = false,
    powerPreference = "default",
    autoClear = true,
    webgl = 2
  } = {}) {
    const attributes = { alpha, depth, stencil, antialias, premultipliedAlpha, preserveDrawingBuffer, powerPreference };
    this.dpr = dpr;
    this.alpha = alpha;
    this.color = true;
    this.depth = depth;
    this.stencil = stencil;
    this.premultipliedAlpha = premultipliedAlpha;
    this.autoClear = autoClear;
    this.id = ID3++;
    if (webgl === 2) this.gl = canvas.getContext("webgl2", attributes);
    this.isWebgl2 = !!this.gl;
    if (!this.gl) this.gl = canvas.getContext("webgl", attributes);
    if (!this.gl) console.error("unable to create webgl context");
    this.gl.renderer = this;
    this.setSize(width, height);
    this.state = {};
    this.state.blendFunc = { src: this.gl.ONE, dst: this.gl.ZERO };
    this.state.blendEquation = { modeRGB: this.gl.FUNC_ADD };
    this.state.cullFace = false;
    this.state.frontFace = this.gl.CCW;
    this.state.depthMask = true;
    this.state.depthFunc = this.gl.LEQUAL;
    this.state.premultiplyAlpha = false;
    this.state.flipY = false;
    this.state.unpackAlignment = 4;
    this.state.framebuffer = null;
    this.state.viewport = { x: 0, y: 0, width: null, height: null };
    this.state.textureUnits = [];
    this.state.activeTextureUnit = 0;
    this.state.boundBuffer = null;
    this.state.uniformLocations = /* @__PURE__ */ new Map();
    this.state.currentProgram = null;
    this.extensions = {};
    if (this.isWebgl2) {
      this.getExtension("EXT_color_buffer_float");
      this.getExtension("OES_texture_float_linear");
    } else {
      this.getExtension("OES_texture_float");
      this.getExtension("OES_texture_float_linear");
      this.getExtension("OES_texture_half_float");
      this.getExtension("OES_texture_half_float_linear");
      this.getExtension("OES_element_index_uint");
      this.getExtension("OES_standard_derivatives");
      this.getExtension("EXT_sRGB");
      this.getExtension("WEBGL_depth_texture");
      this.getExtension("WEBGL_draw_buffers");
    }
    this.getExtension("WEBGL_compressed_texture_astc");
    this.getExtension("EXT_texture_compression_bptc");
    this.getExtension("WEBGL_compressed_texture_s3tc");
    this.getExtension("WEBGL_compressed_texture_etc1");
    this.getExtension("WEBGL_compressed_texture_pvrtc");
    this.getExtension("WEBKIT_WEBGL_compressed_texture_pvrtc");
    this.vertexAttribDivisor = this.getExtension("ANGLE_instanced_arrays", "vertexAttribDivisor", "vertexAttribDivisorANGLE");
    this.drawArraysInstanced = this.getExtension("ANGLE_instanced_arrays", "drawArraysInstanced", "drawArraysInstancedANGLE");
    this.drawElementsInstanced = this.getExtension("ANGLE_instanced_arrays", "drawElementsInstanced", "drawElementsInstancedANGLE");
    this.createVertexArray = this.getExtension("OES_vertex_array_object", "createVertexArray", "createVertexArrayOES");
    this.bindVertexArray = this.getExtension("OES_vertex_array_object", "bindVertexArray", "bindVertexArrayOES");
    this.deleteVertexArray = this.getExtension("OES_vertex_array_object", "deleteVertexArray", "deleteVertexArrayOES");
    this.drawBuffers = this.getExtension("WEBGL_draw_buffers", "drawBuffers", "drawBuffersWEBGL");
    this.parameters = {};
    this.parameters.maxTextureUnits = this.gl.getParameter(this.gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS);
    this.parameters.maxAnisotropy = this.getExtension("EXT_texture_filter_anisotropic") ? this.gl.getParameter(this.getExtension("EXT_texture_filter_anisotropic").MAX_TEXTURE_MAX_ANISOTROPY_EXT) : 0;
  }
  setSize(width, height) {
    this.width = width;
    this.height = height;
    this.gl.canvas.width = width * this.dpr;
    this.gl.canvas.height = height * this.dpr;
    if (!this.gl.canvas.style) return;
    Object.assign(this.gl.canvas.style, {
      width: width + "px",
      height: height + "px"
    });
  }
  setViewport(width, height, x = 0, y = 0) {
    if (this.state.viewport.width === width && this.state.viewport.height === height) return;
    this.state.viewport.width = width;
    this.state.viewport.height = height;
    this.state.viewport.x = x;
    this.state.viewport.y = y;
    this.gl.viewport(x, y, width, height);
  }
  setScissor(width, height, x = 0, y = 0) {
    this.gl.scissor(x, y, width, height);
  }
  enable(id) {
    if (this.state[id] === true) return;
    this.gl.enable(id);
    this.state[id] = true;
  }
  disable(id) {
    if (this.state[id] === false) return;
    this.gl.disable(id);
    this.state[id] = false;
  }
  setBlendFunc(src, dst, srcAlpha, dstAlpha) {
    if (this.state.blendFunc.src === src && this.state.blendFunc.dst === dst && this.state.blendFunc.srcAlpha === srcAlpha && this.state.blendFunc.dstAlpha === dstAlpha)
      return;
    this.state.blendFunc.src = src;
    this.state.blendFunc.dst = dst;
    this.state.blendFunc.srcAlpha = srcAlpha;
    this.state.blendFunc.dstAlpha = dstAlpha;
    if (srcAlpha !== void 0) this.gl.blendFuncSeparate(src, dst, srcAlpha, dstAlpha);
    else this.gl.blendFunc(src, dst);
  }
  setBlendEquation(modeRGB, modeAlpha) {
    modeRGB = modeRGB || this.gl.FUNC_ADD;
    if (this.state.blendEquation.modeRGB === modeRGB && this.state.blendEquation.modeAlpha === modeAlpha) return;
    this.state.blendEquation.modeRGB = modeRGB;
    this.state.blendEquation.modeAlpha = modeAlpha;
    if (modeAlpha !== void 0) this.gl.blendEquationSeparate(modeRGB, modeAlpha);
    else this.gl.blendEquation(modeRGB);
  }
  setCullFace(value) {
    if (this.state.cullFace === value) return;
    this.state.cullFace = value;
    this.gl.cullFace(value);
  }
  setFrontFace(value) {
    if (this.state.frontFace === value) return;
    this.state.frontFace = value;
    this.gl.frontFace(value);
  }
  setDepthMask(value) {
    if (this.state.depthMask === value) return;
    this.state.depthMask = value;
    this.gl.depthMask(value);
  }
  setDepthFunc(value) {
    if (this.state.depthFunc === value) return;
    this.state.depthFunc = value;
    this.gl.depthFunc(value);
  }
  setStencilMask(value) {
    if (this.state.stencilMask === value) return;
    this.state.stencilMask = value;
    this.gl.stencilMask(value);
  }
  setStencilFunc(func, ref, mask) {
    if (this.state.stencilFunc === func && this.state.stencilRef === ref && this.state.stencilFuncMask === mask) return;
    this.state.stencilFunc = func || this.gl.ALWAYS;
    this.state.stencilRef = ref || 0;
    this.state.stencilFuncMask = mask || 0;
    this.gl.stencilFunc(func || this.gl.ALWAYS, ref || 0, mask || 0);
  }
  setStencilOp(stencilFail, depthFail, depthPass) {
    if (this.state.stencilFail === stencilFail && this.state.stencilDepthFail === depthFail && this.state.stencilDepthPass === depthPass) return;
    this.state.stencilFail = stencilFail;
    this.state.stencilDepthFail = depthFail;
    this.state.stencilDepthPass = depthPass;
    this.gl.stencilOp(stencilFail, depthFail, depthPass);
  }
  activeTexture(value) {
    if (this.state.activeTextureUnit === value) return;
    this.state.activeTextureUnit = value;
    this.gl.activeTexture(this.gl.TEXTURE0 + value);
  }
  bindFramebuffer({ target = this.gl.FRAMEBUFFER, buffer = null } = {}) {
    if (this.state.framebuffer === buffer) return;
    this.state.framebuffer = buffer;
    this.gl.bindFramebuffer(target, buffer);
  }
  getExtension(extension, webgl2Func, extFunc) {
    if (webgl2Func && this.gl[webgl2Func]) return this.gl[webgl2Func].bind(this.gl);
    if (!this.extensions[extension]) {
      this.extensions[extension] = this.gl.getExtension(extension);
    }
    if (!webgl2Func) return this.extensions[extension];
    if (!this.extensions[extension]) return null;
    return this.extensions[extension][extFunc].bind(this.extensions[extension]);
  }
  sortOpaque(a, b) {
    if (a.renderOrder !== b.renderOrder) {
      return a.renderOrder - b.renderOrder;
    } else if (a.program.id !== b.program.id) {
      return a.program.id - b.program.id;
    } else if (a.zDepth !== b.zDepth) {
      return a.zDepth - b.zDepth;
    } else {
      return b.id - a.id;
    }
  }
  sortTransparent(a, b) {
    if (a.renderOrder !== b.renderOrder) {
      return a.renderOrder - b.renderOrder;
    }
    if (a.zDepth !== b.zDepth) {
      return b.zDepth - a.zDepth;
    } else {
      return b.id - a.id;
    }
  }
  sortUI(a, b) {
    if (a.renderOrder !== b.renderOrder) {
      return a.renderOrder - b.renderOrder;
    } else if (a.program.id !== b.program.id) {
      return a.program.id - b.program.id;
    } else {
      return b.id - a.id;
    }
  }
  getRenderList({ scene, camera, frustumCull, sort }) {
    let renderList = [];
    if (camera && frustumCull) camera.updateFrustum();
    scene.traverse((node) => {
      if (!node.visible) return true;
      if (!node.draw) return;
      if (frustumCull && node.frustumCulled && camera) {
        if (!camera.frustumIntersectsMesh(node)) return;
      }
      renderList.push(node);
    });
    if (sort) {
      const opaque = [];
      const transparent = [];
      const ui = [];
      renderList.forEach((node) => {
        if (!node.program.transparent) {
          opaque.push(node);
        } else if (node.program.depthTest) {
          transparent.push(node);
        } else {
          ui.push(node);
        }
        node.zDepth = 0;
        if (node.renderOrder !== 0 || !node.program.depthTest || !camera) return;
        node.worldMatrix.getTranslation(tempVec32);
        tempVec32.applyMatrix4(camera.projectionViewMatrix);
        node.zDepth = tempVec32.z;
      });
      opaque.sort(this.sortOpaque);
      transparent.sort(this.sortTransparent);
      ui.sort(this.sortUI);
      renderList = opaque.concat(transparent, ui);
    }
    return renderList;
  }
  render({ scene, camera, target = null, update = true, sort = true, frustumCull = true, clear }) {
    if (target === null) {
      this.bindFramebuffer();
      this.setViewport(this.width * this.dpr, this.height * this.dpr);
    } else {
      this.bindFramebuffer(target);
      this.setViewport(target.width, target.height);
    }
    if (clear || this.autoClear && clear !== false) {
      if (this.depth && (!target || target.depth)) {
        this.enable(this.gl.DEPTH_TEST);
        this.setDepthMask(true);
      }
      if (this.stencil || (!target || target.stencil)) {
        this.enable(this.gl.STENCIL_TEST);
        this.setStencilMask(255);
      }
      this.gl.clear(
        (this.color ? this.gl.COLOR_BUFFER_BIT : 0) | (this.depth ? this.gl.DEPTH_BUFFER_BIT : 0) | (this.stencil ? this.gl.STENCIL_BUFFER_BIT : 0)
      );
    }
    if (update) scene.updateMatrixWorld();
    if (camera) camera.updateMatrixWorld();
    const renderList = this.getRenderList({ scene, camera, frustumCull, sort });
    renderList.forEach((node) => {
      node.draw({ camera });
    });
  }
};

// package/src/math/functions/Vec4Func.js
function copy2(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  out[2] = a[2];
  out[3] = a[3];
  return out;
}
function set2(out, x, y, z, w) {
  out[0] = x;
  out[1] = y;
  out[2] = z;
  out[3] = w;
  return out;
}
function scale2(out, a, b) {
  out[0] = a[0] * b;
  out[1] = a[1] * b;
  out[2] = a[2] * b;
  out[3] = a[3] * b;
  return out;
}
function normalize2(out, a) {
  let x = a[0];
  let y = a[1];
  let z = a[2];
  let w = a[3];
  let len = x * x + y * y + z * z + w * w;
  if (len > 0) {
    len = 1 / Math.sqrt(len);
  }
  out[0] = x * len;
  out[1] = y * len;
  out[2] = z * len;
  out[3] = w * len;
  return out;
}
function dot2(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
}

// package/src/math/functions/QuatFunc.js
function identity(out) {
  out[0] = 0;
  out[1] = 0;
  out[2] = 0;
  out[3] = 1;
  return out;
}
function setAxisAngle(out, axis, rad) {
  rad = rad * 0.5;
  let s = Math.sin(rad);
  out[0] = s * axis[0];
  out[1] = s * axis[1];
  out[2] = s * axis[2];
  out[3] = Math.cos(rad);
  return out;
}
function multiply2(out, a, b) {
  let ax = a[0], ay = a[1], az = a[2], aw = a[3];
  let bx = b[0], by = b[1], bz = b[2], bw = b[3];
  out[0] = ax * bw + aw * bx + ay * bz - az * by;
  out[1] = ay * bw + aw * by + az * bx - ax * bz;
  out[2] = az * bw + aw * bz + ax * by - ay * bx;
  out[3] = aw * bw - ax * bx - ay * by - az * bz;
  return out;
}
function rotateX(out, a, rad) {
  rad *= 0.5;
  let ax = a[0], ay = a[1], az = a[2], aw = a[3];
  let bx = Math.sin(rad), bw = Math.cos(rad);
  out[0] = ax * bw + aw * bx;
  out[1] = ay * bw + az * bx;
  out[2] = az * bw - ay * bx;
  out[3] = aw * bw - ax * bx;
  return out;
}
function rotateY(out, a, rad) {
  rad *= 0.5;
  let ax = a[0], ay = a[1], az = a[2], aw = a[3];
  let by = Math.sin(rad), bw = Math.cos(rad);
  out[0] = ax * bw - az * by;
  out[1] = ay * bw + aw * by;
  out[2] = az * bw + ax * by;
  out[3] = aw * bw - ay * by;
  return out;
}
function rotateZ(out, a, rad) {
  rad *= 0.5;
  let ax = a[0], ay = a[1], az = a[2], aw = a[3];
  let bz = Math.sin(rad), bw = Math.cos(rad);
  out[0] = ax * bw + ay * bz;
  out[1] = ay * bw - ax * bz;
  out[2] = az * bw + aw * bz;
  out[3] = aw * bw - az * bz;
  return out;
}
function slerp(out, a, b, t) {
  let ax = a[0], ay = a[1], az = a[2], aw = a[3];
  let bx = b[0], by = b[1], bz = b[2], bw = b[3];
  let omega, cosom, sinom, scale0, scale1;
  cosom = ax * bx + ay * by + az * bz + aw * bw;
  if (cosom < 0) {
    cosom = -cosom;
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }
  if (1 - cosom > 1e-6) {
    omega = Math.acos(cosom);
    sinom = Math.sin(omega);
    scale0 = Math.sin((1 - t) * omega) / sinom;
    scale1 = Math.sin(t * omega) / sinom;
  } else {
    scale0 = 1 - t;
    scale1 = t;
  }
  out[0] = scale0 * ax + scale1 * bx;
  out[1] = scale0 * ay + scale1 * by;
  out[2] = scale0 * az + scale1 * bz;
  out[3] = scale0 * aw + scale1 * bw;
  return out;
}
function invert(out, a) {
  let a0 = a[0], a1 = a[1], a2 = a[2], a3 = a[3];
  let dot5 = a0 * a0 + a1 * a1 + a2 * a2 + a3 * a3;
  let invDot = dot5 ? 1 / dot5 : 0;
  out[0] = -a0 * invDot;
  out[1] = -a1 * invDot;
  out[2] = -a2 * invDot;
  out[3] = a3 * invDot;
  return out;
}
function conjugate(out, a) {
  out[0] = -a[0];
  out[1] = -a[1];
  out[2] = -a[2];
  out[3] = a[3];
  return out;
}
function fromMat3(out, m) {
  let fTrace = m[0] + m[4] + m[8];
  let fRoot;
  if (fTrace > 0) {
    fRoot = Math.sqrt(fTrace + 1);
    out[3] = 0.5 * fRoot;
    fRoot = 0.5 / fRoot;
    out[0] = (m[5] - m[7]) * fRoot;
    out[1] = (m[6] - m[2]) * fRoot;
    out[2] = (m[1] - m[3]) * fRoot;
  } else {
    let i = 0;
    if (m[4] > m[0]) i = 1;
    if (m[8] > m[i * 3 + i]) i = 2;
    let j = (i + 1) % 3;
    let k = (i + 2) % 3;
    fRoot = Math.sqrt(m[i * 3 + i] - m[j * 3 + j] - m[k * 3 + k] + 1);
    out[i] = 0.5 * fRoot;
    fRoot = 0.5 / fRoot;
    out[3] = (m[j * 3 + k] - m[k * 3 + j]) * fRoot;
    out[j] = (m[j * 3 + i] + m[i * 3 + j]) * fRoot;
    out[k] = (m[k * 3 + i] + m[i * 3 + k]) * fRoot;
  }
  return out;
}
function fromEuler(out, euler, order = "YXZ") {
  let sx = Math.sin(euler[0] * 0.5);
  let cx = Math.cos(euler[0] * 0.5);
  let sy = Math.sin(euler[1] * 0.5);
  let cy = Math.cos(euler[1] * 0.5);
  let sz = Math.sin(euler[2] * 0.5);
  let cz = Math.cos(euler[2] * 0.5);
  if (order === "XYZ") {
    out[0] = sx * cy * cz + cx * sy * sz;
    out[1] = cx * sy * cz - sx * cy * sz;
    out[2] = cx * cy * sz + sx * sy * cz;
    out[3] = cx * cy * cz - sx * sy * sz;
  } else if (order === "YXZ") {
    out[0] = sx * cy * cz + cx * sy * sz;
    out[1] = cx * sy * cz - sx * cy * sz;
    out[2] = cx * cy * sz - sx * sy * cz;
    out[3] = cx * cy * cz + sx * sy * sz;
  } else if (order === "ZXY") {
    out[0] = sx * cy * cz - cx * sy * sz;
    out[1] = cx * sy * cz + sx * cy * sz;
    out[2] = cx * cy * sz + sx * sy * cz;
    out[3] = cx * cy * cz - sx * sy * sz;
  } else if (order === "ZYX") {
    out[0] = sx * cy * cz - cx * sy * sz;
    out[1] = cx * sy * cz + sx * cy * sz;
    out[2] = cx * cy * sz - sx * sy * cz;
    out[3] = cx * cy * cz + sx * sy * sz;
  } else if (order === "YZX") {
    out[0] = sx * cy * cz + cx * sy * sz;
    out[1] = cx * sy * cz + sx * cy * sz;
    out[2] = cx * cy * sz - sx * sy * cz;
    out[3] = cx * cy * cz - sx * sy * sz;
  } else if (order === "XZY") {
    out[0] = sx * cy * cz - cx * sy * sz;
    out[1] = cx * sy * cz - sx * cy * sz;
    out[2] = cx * cy * sz + sx * sy * cz;
    out[3] = cx * cy * cz + sx * sy * sz;
  }
  return out;
}
var copy3 = copy2;
var set3 = set2;
var dot3 = dot2;
var normalize3 = normalize2;

// package/src/math/Quat.js
var Quat = class extends Array {
  constructor(x = 0, y = 0, z = 0, w = 1) {
    super(x, y, z, w);
    this.onChange = () => {
    };
    this._target = this;
    const triggerProps = ["0", "1", "2", "3"];
    return new Proxy(this, {
      set(target, property) {
        const success = Reflect.set(...arguments);
        if (success && triggerProps.includes(property)) target.onChange();
        return success;
      }
    });
  }
  get x() {
    return this[0];
  }
  get y() {
    return this[1];
  }
  get z() {
    return this[2];
  }
  get w() {
    return this[3];
  }
  set x(v) {
    this._target[0] = v;
    this.onChange();
  }
  set y(v) {
    this._target[1] = v;
    this.onChange();
  }
  set z(v) {
    this._target[2] = v;
    this.onChange();
  }
  set w(v) {
    this._target[3] = v;
    this.onChange();
  }
  identity() {
    identity(this._target);
    this.onChange();
    return this;
  }
  set(x, y, z, w) {
    if (x.length) return this.copy(x);
    set3(this._target, x, y, z, w);
    this.onChange();
    return this;
  }
  rotateX(a) {
    rotateX(this._target, this._target, a);
    this.onChange();
    return this;
  }
  rotateY(a) {
    rotateY(this._target, this._target, a);
    this.onChange();
    return this;
  }
  rotateZ(a) {
    rotateZ(this._target, this._target, a);
    this.onChange();
    return this;
  }
  inverse(q = this._target) {
    invert(this._target, q);
    this.onChange();
    return this;
  }
  conjugate(q = this._target) {
    conjugate(this._target, q);
    this.onChange();
    return this;
  }
  copy(q) {
    copy3(this._target, q);
    this.onChange();
    return this;
  }
  normalize(q = this._target) {
    normalize3(this._target, q);
    this.onChange();
    return this;
  }
  multiply(qA, qB) {
    if (qB) {
      multiply2(this._target, qA, qB);
    } else {
      multiply2(this._target, this._target, qA);
    }
    this.onChange();
    return this;
  }
  dot(v) {
    return dot3(this._target, v);
  }
  fromMatrix3(matrix3) {
    fromMat3(this._target, matrix3);
    this.onChange();
    return this;
  }
  fromEuler(euler, isInternal) {
    fromEuler(this._target, euler, euler.order);
    if (!isInternal) this.onChange();
    return this;
  }
  fromAxisAngle(axis, a) {
    setAxisAngle(this._target, axis, a);
    this.onChange();
    return this;
  }
  slerp(q, t) {
    slerp(this._target, this._target, q, t);
    this.onChange();
    return this;
  }
  fromArray(a, o = 0) {
    this._target[0] = a[o];
    this._target[1] = a[o + 1];
    this._target[2] = a[o + 2];
    this._target[3] = a[o + 3];
    this.onChange();
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    a[o + 2] = this[2];
    a[o + 3] = this[3];
    return a;
  }
};

// package/src/math/functions/Mat4Func.js
var EPSILON = 1e-6;
function copy4(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  out[2] = a[2];
  out[3] = a[3];
  out[4] = a[4];
  out[5] = a[5];
  out[6] = a[6];
  out[7] = a[7];
  out[8] = a[8];
  out[9] = a[9];
  out[10] = a[10];
  out[11] = a[11];
  out[12] = a[12];
  out[13] = a[13];
  out[14] = a[14];
  out[15] = a[15];
  return out;
}
function set4(out, m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33) {
  out[0] = m00;
  out[1] = m01;
  out[2] = m02;
  out[3] = m03;
  out[4] = m10;
  out[5] = m11;
  out[6] = m12;
  out[7] = m13;
  out[8] = m20;
  out[9] = m21;
  out[10] = m22;
  out[11] = m23;
  out[12] = m30;
  out[13] = m31;
  out[14] = m32;
  out[15] = m33;
  return out;
}
function identity2(out) {
  out[0] = 1;
  out[1] = 0;
  out[2] = 0;
  out[3] = 0;
  out[4] = 0;
  out[5] = 1;
  out[6] = 0;
  out[7] = 0;
  out[8] = 0;
  out[9] = 0;
  out[10] = 1;
  out[11] = 0;
  out[12] = 0;
  out[13] = 0;
  out[14] = 0;
  out[15] = 1;
  return out;
}
function invert2(out, a) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  let a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  let a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  let a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  let b00 = a00 * a11 - a01 * a10;
  let b01 = a00 * a12 - a02 * a10;
  let b02 = a00 * a13 - a03 * a10;
  let b03 = a01 * a12 - a02 * a11;
  let b04 = a01 * a13 - a03 * a11;
  let b05 = a02 * a13 - a03 * a12;
  let b06 = a20 * a31 - a21 * a30;
  let b07 = a20 * a32 - a22 * a30;
  let b08 = a20 * a33 - a23 * a30;
  let b09 = a21 * a32 - a22 * a31;
  let b10 = a21 * a33 - a23 * a31;
  let b11 = a22 * a33 - a23 * a32;
  let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (!det) {
    return null;
  }
  det = 1 / det;
  out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det;
  out[1] = (a02 * b10 - a01 * b11 - a03 * b09) * det;
  out[2] = (a31 * b05 - a32 * b04 + a33 * b03) * det;
  out[3] = (a22 * b04 - a21 * b05 - a23 * b03) * det;
  out[4] = (a12 * b08 - a10 * b11 - a13 * b07) * det;
  out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * det;
  out[6] = (a32 * b02 - a30 * b05 - a33 * b01) * det;
  out[7] = (a20 * b05 - a22 * b02 + a23 * b01) * det;
  out[8] = (a10 * b10 - a11 * b08 + a13 * b06) * det;
  out[9] = (a01 * b08 - a00 * b10 - a03 * b06) * det;
  out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * det;
  out[11] = (a21 * b02 - a20 * b04 - a23 * b00) * det;
  out[12] = (a11 * b07 - a10 * b09 - a12 * b06) * det;
  out[13] = (a00 * b09 - a01 * b07 + a02 * b06) * det;
  out[14] = (a31 * b01 - a30 * b03 - a32 * b00) * det;
  out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * det;
  return out;
}
function determinant(a) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  let a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  let a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  let a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  let b00 = a00 * a11 - a01 * a10;
  let b01 = a00 * a12 - a02 * a10;
  let b02 = a00 * a13 - a03 * a10;
  let b03 = a01 * a12 - a02 * a11;
  let b04 = a01 * a13 - a03 * a11;
  let b05 = a02 * a13 - a03 * a12;
  let b06 = a20 * a31 - a21 * a30;
  let b07 = a20 * a32 - a22 * a30;
  let b08 = a20 * a33 - a23 * a30;
  let b09 = a21 * a32 - a22 * a31;
  let b10 = a21 * a33 - a23 * a31;
  let b11 = a22 * a33 - a23 * a32;
  return b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
}
function multiply3(out, a, b) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  let a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  let a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  let a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  let b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3];
  out[0] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[1] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[2] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[3] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  b0 = b[4];
  b1 = b[5];
  b2 = b[6];
  b3 = b[7];
  out[4] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[5] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[6] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[7] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  b0 = b[8];
  b1 = b[9];
  b2 = b[10];
  b3 = b[11];
  out[8] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[9] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[10] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[11] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  b0 = b[12];
  b1 = b[13];
  b2 = b[14];
  b3 = b[15];
  out[12] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
  out[13] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
  out[14] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
  out[15] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;
  return out;
}
function translate(out, a, v) {
  let x = v[0], y = v[1], z = v[2];
  let a00, a01, a02, a03;
  let a10, a11, a12, a13;
  let a20, a21, a22, a23;
  if (a === out) {
    out[12] = a[0] * x + a[4] * y + a[8] * z + a[12];
    out[13] = a[1] * x + a[5] * y + a[9] * z + a[13];
    out[14] = a[2] * x + a[6] * y + a[10] * z + a[14];
    out[15] = a[3] * x + a[7] * y + a[11] * z + a[15];
  } else {
    a00 = a[0];
    a01 = a[1];
    a02 = a[2];
    a03 = a[3];
    a10 = a[4];
    a11 = a[5];
    a12 = a[6];
    a13 = a[7];
    a20 = a[8];
    a21 = a[9];
    a22 = a[10];
    a23 = a[11];
    out[0] = a00;
    out[1] = a01;
    out[2] = a02;
    out[3] = a03;
    out[4] = a10;
    out[5] = a11;
    out[6] = a12;
    out[7] = a13;
    out[8] = a20;
    out[9] = a21;
    out[10] = a22;
    out[11] = a23;
    out[12] = a00 * x + a10 * y + a20 * z + a[12];
    out[13] = a01 * x + a11 * y + a21 * z + a[13];
    out[14] = a02 * x + a12 * y + a22 * z + a[14];
    out[15] = a03 * x + a13 * y + a23 * z + a[15];
  }
  return out;
}
function scale3(out, a, v) {
  let x = v[0], y = v[1], z = v[2];
  out[0] = a[0] * x;
  out[1] = a[1] * x;
  out[2] = a[2] * x;
  out[3] = a[3] * x;
  out[4] = a[4] * y;
  out[5] = a[5] * y;
  out[6] = a[6] * y;
  out[7] = a[7] * y;
  out[8] = a[8] * z;
  out[9] = a[9] * z;
  out[10] = a[10] * z;
  out[11] = a[11] * z;
  out[12] = a[12];
  out[13] = a[13];
  out[14] = a[14];
  out[15] = a[15];
  return out;
}
function rotate(out, a, rad, axis) {
  let x = axis[0], y = axis[1], z = axis[2];
  let len = Math.hypot(x, y, z);
  let s, c, t;
  let a00, a01, a02, a03;
  let a10, a11, a12, a13;
  let a20, a21, a22, a23;
  let b00, b01, b02;
  let b10, b11, b12;
  let b20, b21, b22;
  if (Math.abs(len) < EPSILON) {
    return null;
  }
  len = 1 / len;
  x *= len;
  y *= len;
  z *= len;
  s = Math.sin(rad);
  c = Math.cos(rad);
  t = 1 - c;
  a00 = a[0];
  a01 = a[1];
  a02 = a[2];
  a03 = a[3];
  a10 = a[4];
  a11 = a[5];
  a12 = a[6];
  a13 = a[7];
  a20 = a[8];
  a21 = a[9];
  a22 = a[10];
  a23 = a[11];
  b00 = x * x * t + c;
  b01 = y * x * t + z * s;
  b02 = z * x * t - y * s;
  b10 = x * y * t - z * s;
  b11 = y * y * t + c;
  b12 = z * y * t + x * s;
  b20 = x * z * t + y * s;
  b21 = y * z * t - x * s;
  b22 = z * z * t + c;
  out[0] = a00 * b00 + a10 * b01 + a20 * b02;
  out[1] = a01 * b00 + a11 * b01 + a21 * b02;
  out[2] = a02 * b00 + a12 * b01 + a22 * b02;
  out[3] = a03 * b00 + a13 * b01 + a23 * b02;
  out[4] = a00 * b10 + a10 * b11 + a20 * b12;
  out[5] = a01 * b10 + a11 * b11 + a21 * b12;
  out[6] = a02 * b10 + a12 * b11 + a22 * b12;
  out[7] = a03 * b10 + a13 * b11 + a23 * b12;
  out[8] = a00 * b20 + a10 * b21 + a20 * b22;
  out[9] = a01 * b20 + a11 * b21 + a21 * b22;
  out[10] = a02 * b20 + a12 * b21 + a22 * b22;
  out[11] = a03 * b20 + a13 * b21 + a23 * b22;
  if (a !== out) {
    out[12] = a[12];
    out[13] = a[13];
    out[14] = a[14];
    out[15] = a[15];
  }
  return out;
}
function getTranslation(out, mat) {
  out[0] = mat[12];
  out[1] = mat[13];
  out[2] = mat[14];
  return out;
}
function getScaling(out, mat) {
  let m11 = mat[0];
  let m12 = mat[1];
  let m13 = mat[2];
  let m21 = mat[4];
  let m22 = mat[5];
  let m23 = mat[6];
  let m31 = mat[8];
  let m32 = mat[9];
  let m33 = mat[10];
  out[0] = Math.hypot(m11, m12, m13);
  out[1] = Math.hypot(m21, m22, m23);
  out[2] = Math.hypot(m31, m32, m33);
  return out;
}
function getMaxScaleOnAxis(mat) {
  let m11 = mat[0];
  let m12 = mat[1];
  let m13 = mat[2];
  let m21 = mat[4];
  let m22 = mat[5];
  let m23 = mat[6];
  let m31 = mat[8];
  let m32 = mat[9];
  let m33 = mat[10];
  const x = m11 * m11 + m12 * m12 + m13 * m13;
  const y = m21 * m21 + m22 * m22 + m23 * m23;
  const z = m31 * m31 + m32 * m32 + m33 * m33;
  return Math.sqrt(Math.max(x, y, z));
}
var getRotation = /* @__PURE__ */ (function() {
  const temp = [1, 1, 1];
  return function(out, mat) {
    let scaling = temp;
    getScaling(scaling, mat);
    let is1 = 1 / scaling[0];
    let is2 = 1 / scaling[1];
    let is3 = 1 / scaling[2];
    let sm11 = mat[0] * is1;
    let sm12 = mat[1] * is2;
    let sm13 = mat[2] * is3;
    let sm21 = mat[4] * is1;
    let sm22 = mat[5] * is2;
    let sm23 = mat[6] * is3;
    let sm31 = mat[8] * is1;
    let sm32 = mat[9] * is2;
    let sm33 = mat[10] * is3;
    let trace = sm11 + sm22 + sm33;
    let S = 0;
    if (trace > 0) {
      S = Math.sqrt(trace + 1) * 2;
      out[3] = 0.25 * S;
      out[0] = (sm23 - sm32) / S;
      out[1] = (sm31 - sm13) / S;
      out[2] = (sm12 - sm21) / S;
    } else if (sm11 > sm22 && sm11 > sm33) {
      S = Math.sqrt(1 + sm11 - sm22 - sm33) * 2;
      out[3] = (sm23 - sm32) / S;
      out[0] = 0.25 * S;
      out[1] = (sm12 + sm21) / S;
      out[2] = (sm31 + sm13) / S;
    } else if (sm22 > sm33) {
      S = Math.sqrt(1 + sm22 - sm11 - sm33) * 2;
      out[3] = (sm31 - sm13) / S;
      out[0] = (sm12 + sm21) / S;
      out[1] = 0.25 * S;
      out[2] = (sm23 + sm32) / S;
    } else {
      S = Math.sqrt(1 + sm33 - sm11 - sm22) * 2;
      out[3] = (sm12 - sm21) / S;
      out[0] = (sm31 + sm13) / S;
      out[1] = (sm23 + sm32) / S;
      out[2] = 0.25 * S;
    }
    return out;
  };
})();
function decompose(srcMat, dstRotation, dstTranslation, dstScale) {
  let sx = length([srcMat[0], srcMat[1], srcMat[2]]);
  const sy = length([srcMat[4], srcMat[5], srcMat[6]]);
  const sz = length([srcMat[8], srcMat[9], srcMat[10]]);
  const det = determinant(srcMat);
  if (det < 0) sx = -sx;
  dstTranslation[0] = srcMat[12];
  dstTranslation[1] = srcMat[13];
  dstTranslation[2] = srcMat[14];
  const _m1 = srcMat.slice();
  const invSX = 1 / sx;
  const invSY = 1 / sy;
  const invSZ = 1 / sz;
  _m1[0] *= invSX;
  _m1[1] *= invSX;
  _m1[2] *= invSX;
  _m1[4] *= invSY;
  _m1[5] *= invSY;
  _m1[6] *= invSY;
  _m1[8] *= invSZ;
  _m1[9] *= invSZ;
  _m1[10] *= invSZ;
  getRotation(dstRotation, _m1);
  dstScale[0] = sx;
  dstScale[1] = sy;
  dstScale[2] = sz;
}
function compose(dstMat, srcRotation, srcTranslation, srcScale) {
  const te = dstMat;
  const x = srcRotation[0], y = srcRotation[1], z = srcRotation[2], w = srcRotation[3];
  const x2 = x + x, y2 = y + y, z2 = z + z;
  const xx = x * x2, xy = x * y2, xz = x * z2;
  const yy = y * y2, yz = y * z2, zz = z * z2;
  const wx = w * x2, wy = w * y2, wz = w * z2;
  const sx = srcScale[0], sy = srcScale[1], sz = srcScale[2];
  te[0] = (1 - (yy + zz)) * sx;
  te[1] = (xy + wz) * sx;
  te[2] = (xz - wy) * sx;
  te[3] = 0;
  te[4] = (xy - wz) * sy;
  te[5] = (1 - (xx + zz)) * sy;
  te[6] = (yz + wx) * sy;
  te[7] = 0;
  te[8] = (xz + wy) * sz;
  te[9] = (yz - wx) * sz;
  te[10] = (1 - (xx + yy)) * sz;
  te[11] = 0;
  te[12] = srcTranslation[0];
  te[13] = srcTranslation[1];
  te[14] = srcTranslation[2];
  te[15] = 1;
  return te;
}
function fromQuat(out, q) {
  let x = q[0], y = q[1], z = q[2], w = q[3];
  let x2 = x + x;
  let y2 = y + y;
  let z2 = z + z;
  let xx = x * x2;
  let yx = y * x2;
  let yy = y * y2;
  let zx = z * x2;
  let zy = z * y2;
  let zz = z * z2;
  let wx = w * x2;
  let wy = w * y2;
  let wz = w * z2;
  out[0] = 1 - yy - zz;
  out[1] = yx + wz;
  out[2] = zx - wy;
  out[3] = 0;
  out[4] = yx - wz;
  out[5] = 1 - xx - zz;
  out[6] = zy + wx;
  out[7] = 0;
  out[8] = zx + wy;
  out[9] = zy - wx;
  out[10] = 1 - xx - yy;
  out[11] = 0;
  out[12] = 0;
  out[13] = 0;
  out[14] = 0;
  out[15] = 1;
  return out;
}
function perspective(out, fovy, aspect, near, far) {
  let f = 1 / Math.tan(fovy / 2);
  let nf = 1 / (near - far);
  out[0] = f / aspect;
  out[1] = 0;
  out[2] = 0;
  out[3] = 0;
  out[4] = 0;
  out[5] = f;
  out[6] = 0;
  out[7] = 0;
  out[8] = 0;
  out[9] = 0;
  out[10] = (far + near) * nf;
  out[11] = -1;
  out[12] = 0;
  out[13] = 0;
  out[14] = 2 * far * near * nf;
  out[15] = 0;
  return out;
}
function ortho(out, left, right, bottom, top, near, far) {
  let lr = 1 / (left - right);
  let bt = 1 / (bottom - top);
  let nf = 1 / (near - far);
  out[0] = -2 * lr;
  out[1] = 0;
  out[2] = 0;
  out[3] = 0;
  out[4] = 0;
  out[5] = -2 * bt;
  out[6] = 0;
  out[7] = 0;
  out[8] = 0;
  out[9] = 0;
  out[10] = 2 * nf;
  out[11] = 0;
  out[12] = (left + right) * lr;
  out[13] = (top + bottom) * bt;
  out[14] = (far + near) * nf;
  out[15] = 1;
  return out;
}
function targetTo(out, eye, target, up) {
  let eyex = eye[0], eyey = eye[1], eyez = eye[2], upx = up[0], upy = up[1], upz = up[2];
  let z0 = eyex - target[0], z1 = eyey - target[1], z2 = eyez - target[2];
  let len = z0 * z0 + z1 * z1 + z2 * z2;
  if (len === 0) {
    z2 = 1;
  } else {
    len = 1 / Math.sqrt(len);
    z0 *= len;
    z1 *= len;
    z2 *= len;
  }
  let x0 = upy * z2 - upz * z1, x1 = upz * z0 - upx * z2, x2 = upx * z1 - upy * z0;
  len = x0 * x0 + x1 * x1 + x2 * x2;
  if (len === 0) {
    if (upz) {
      upx += 1e-6;
    } else if (upy) {
      upz += 1e-6;
    } else {
      upy += 1e-6;
    }
    x0 = upy * z2 - upz * z1, x1 = upz * z0 - upx * z2, x2 = upx * z1 - upy * z0;
    len = x0 * x0 + x1 * x1 + x2 * x2;
  }
  len = 1 / Math.sqrt(len);
  x0 *= len;
  x1 *= len;
  x2 *= len;
  out[0] = x0;
  out[1] = x1;
  out[2] = x2;
  out[3] = 0;
  out[4] = z1 * x2 - z2 * x1;
  out[5] = z2 * x0 - z0 * x2;
  out[6] = z0 * x1 - z1 * x0;
  out[7] = 0;
  out[8] = z0;
  out[9] = z1;
  out[10] = z2;
  out[11] = 0;
  out[12] = eyex;
  out[13] = eyey;
  out[14] = eyez;
  out[15] = 1;
  return out;
}
function add3(out, a, b) {
  out[0] = a[0] + b[0];
  out[1] = a[1] + b[1];
  out[2] = a[2] + b[2];
  out[3] = a[3] + b[3];
  out[4] = a[4] + b[4];
  out[5] = a[5] + b[5];
  out[6] = a[6] + b[6];
  out[7] = a[7] + b[7];
  out[8] = a[8] + b[8];
  out[9] = a[9] + b[9];
  out[10] = a[10] + b[10];
  out[11] = a[11] + b[11];
  out[12] = a[12] + b[12];
  out[13] = a[13] + b[13];
  out[14] = a[14] + b[14];
  out[15] = a[15] + b[15];
  return out;
}
function subtract2(out, a, b) {
  out[0] = a[0] - b[0];
  out[1] = a[1] - b[1];
  out[2] = a[2] - b[2];
  out[3] = a[3] - b[3];
  out[4] = a[4] - b[4];
  out[5] = a[5] - b[5];
  out[6] = a[6] - b[6];
  out[7] = a[7] - b[7];
  out[8] = a[8] - b[8];
  out[9] = a[9] - b[9];
  out[10] = a[10] - b[10];
  out[11] = a[11] - b[11];
  out[12] = a[12] - b[12];
  out[13] = a[13] - b[13];
  out[14] = a[14] - b[14];
  out[15] = a[15] - b[15];
  return out;
}
function multiplyScalar(out, a, b) {
  out[0] = a[0] * b;
  out[1] = a[1] * b;
  out[2] = a[2] * b;
  out[3] = a[3] * b;
  out[4] = a[4] * b;
  out[5] = a[5] * b;
  out[6] = a[6] * b;
  out[7] = a[7] * b;
  out[8] = a[8] * b;
  out[9] = a[9] * b;
  out[10] = a[10] * b;
  out[11] = a[11] * b;
  out[12] = a[12] * b;
  out[13] = a[13] * b;
  out[14] = a[14] * b;
  out[15] = a[15] * b;
  return out;
}

// package/src/math/Mat4.js
var Mat4 = class extends Array {
  constructor(m00 = 1, m01 = 0, m02 = 0, m03 = 0, m10 = 0, m11 = 1, m12 = 0, m13 = 0, m20 = 0, m21 = 0, m22 = 1, m23 = 0, m30 = 0, m31 = 0, m32 = 0, m33 = 1) {
    super(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33);
    return this;
  }
  get x() {
    return this[12];
  }
  get y() {
    return this[13];
  }
  get z() {
    return this[14];
  }
  get w() {
    return this[15];
  }
  set x(v) {
    this[12] = v;
  }
  set y(v) {
    this[13] = v;
  }
  set z(v) {
    this[14] = v;
  }
  set w(v) {
    this[15] = v;
  }
  set(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33) {
    if (m00.length) return this.copy(m00);
    set4(this, m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33);
    return this;
  }
  translate(v, m = this) {
    translate(this, m, v);
    return this;
  }
  rotate(v, axis, m = this) {
    rotate(this, m, v, axis);
    return this;
  }
  scale(v, m = this) {
    scale3(this, m, typeof v === "number" ? [v, v, v] : v);
    return this;
  }
  add(ma, mb) {
    if (mb) add3(this, ma, mb);
    else add3(this, this, ma);
    return this;
  }
  sub(ma, mb) {
    if (mb) subtract2(this, ma, mb);
    else subtract2(this, this, ma);
    return this;
  }
  multiply(ma, mb) {
    if (!ma.length) {
      multiplyScalar(this, this, ma);
    } else if (mb) {
      multiply3(this, ma, mb);
    } else {
      multiply3(this, this, ma);
    }
    return this;
  }
  identity() {
    identity2(this);
    return this;
  }
  copy(m) {
    copy4(this, m);
    return this;
  }
  fromPerspective({ fov, aspect, near, far } = {}) {
    perspective(this, fov, aspect, near, far);
    return this;
  }
  fromOrthogonal({ left, right, bottom, top, near, far }) {
    ortho(this, left, right, bottom, top, near, far);
    return this;
  }
  fromQuaternion(q) {
    fromQuat(this, q);
    return this;
  }
  setPosition(v) {
    this.x = v[0];
    this.y = v[1];
    this.z = v[2];
    return this;
  }
  inverse(m = this) {
    invert2(this, m);
    return this;
  }
  compose(q, pos, scale6) {
    compose(this, q, pos, scale6);
    return this;
  }
  decompose(q, pos, scale6) {
    decompose(this, q, pos, scale6);
    return this;
  }
  getRotation(q) {
    getRotation(q, this);
    return this;
  }
  getTranslation(pos) {
    getTranslation(pos, this);
    return this;
  }
  getScaling(scale6) {
    getScaling(scale6, this);
    return this;
  }
  getMaxScaleOnAxis() {
    return getMaxScaleOnAxis(this);
  }
  lookAt(eye, target, up) {
    targetTo(this, eye, target, up);
    return this;
  }
  determinant() {
    return determinant(this);
  }
  fromArray(a, o = 0) {
    this[0] = a[o];
    this[1] = a[o + 1];
    this[2] = a[o + 2];
    this[3] = a[o + 3];
    this[4] = a[o + 4];
    this[5] = a[o + 5];
    this[6] = a[o + 6];
    this[7] = a[o + 7];
    this[8] = a[o + 8];
    this[9] = a[o + 9];
    this[10] = a[o + 10];
    this[11] = a[o + 11];
    this[12] = a[o + 12];
    this[13] = a[o + 13];
    this[14] = a[o + 14];
    this[15] = a[o + 15];
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    a[o + 2] = this[2];
    a[o + 3] = this[3];
    a[o + 4] = this[4];
    a[o + 5] = this[5];
    a[o + 6] = this[6];
    a[o + 7] = this[7];
    a[o + 8] = this[8];
    a[o + 9] = this[9];
    a[o + 10] = this[10];
    a[o + 11] = this[11];
    a[o + 12] = this[12];
    a[o + 13] = this[13];
    a[o + 14] = this[14];
    a[o + 15] = this[15];
    return a;
  }
};

// package/src/math/functions/EulerFunc.js
function fromRotationMatrix(out, m, order = "YXZ") {
  if (order === "XYZ") {
    out[1] = Math.asin(Math.min(Math.max(m[8], -1), 1));
    if (Math.abs(m[8]) < 0.99999) {
      out[0] = Math.atan2(-m[9], m[10]);
      out[2] = Math.atan2(-m[4], m[0]);
    } else {
      out[0] = Math.atan2(m[6], m[5]);
      out[2] = 0;
    }
  } else if (order === "YXZ") {
    out[0] = Math.asin(-Math.min(Math.max(m[9], -1), 1));
    if (Math.abs(m[9]) < 0.99999) {
      out[1] = Math.atan2(m[8], m[10]);
      out[2] = Math.atan2(m[1], m[5]);
    } else {
      out[1] = Math.atan2(-m[2], m[0]);
      out[2] = 0;
    }
  } else if (order === "ZXY") {
    out[0] = Math.asin(Math.min(Math.max(m[6], -1), 1));
    if (Math.abs(m[6]) < 0.99999) {
      out[1] = Math.atan2(-m[2], m[10]);
      out[2] = Math.atan2(-m[4], m[5]);
    } else {
      out[1] = 0;
      out[2] = Math.atan2(m[1], m[0]);
    }
  } else if (order === "ZYX") {
    out[1] = Math.asin(-Math.min(Math.max(m[2], -1), 1));
    if (Math.abs(m[2]) < 0.99999) {
      out[0] = Math.atan2(m[6], m[10]);
      out[2] = Math.atan2(m[1], m[0]);
    } else {
      out[0] = 0;
      out[2] = Math.atan2(-m[4], m[5]);
    }
  } else if (order === "YZX") {
    out[2] = Math.asin(Math.min(Math.max(m[1], -1), 1));
    if (Math.abs(m[1]) < 0.99999) {
      out[0] = Math.atan2(-m[9], m[5]);
      out[1] = Math.atan2(-m[2], m[0]);
    } else {
      out[0] = 0;
      out[1] = Math.atan2(m[8], m[10]);
    }
  } else if (order === "XZY") {
    out[2] = Math.asin(-Math.min(Math.max(m[4], -1), 1));
    if (Math.abs(m[4]) < 0.99999) {
      out[0] = Math.atan2(m[6], m[5]);
      out[1] = Math.atan2(m[8], m[0]);
    } else {
      out[0] = Math.atan2(-m[9], m[10]);
      out[1] = 0;
    }
  }
  return out;
}

// package/src/math/Euler.js
var tmpMat4 = /* @__PURE__ */ new Mat4();
var Euler = class extends Array {
  constructor(x = 0, y = x, z = x, order = "YXZ") {
    super(x, y, z);
    this.order = order;
    this.onChange = () => {
    };
    this._target = this;
    const triggerProps = ["0", "1", "2"];
    return new Proxy(this, {
      set(target, property) {
        const success = Reflect.set(...arguments);
        if (success && triggerProps.includes(property)) target.onChange();
        return success;
      }
    });
  }
  get x() {
    return this[0];
  }
  get y() {
    return this[1];
  }
  get z() {
    return this[2];
  }
  set x(v) {
    this._target[0] = v;
    this.onChange();
  }
  set y(v) {
    this._target[1] = v;
    this.onChange();
  }
  set z(v) {
    this._target[2] = v;
    this.onChange();
  }
  set(x, y = x, z = x) {
    if (x.length) return this.copy(x);
    this._target[0] = x;
    this._target[1] = y;
    this._target[2] = z;
    this.onChange();
    return this;
  }
  copy(v) {
    this._target[0] = v[0];
    this._target[1] = v[1];
    this._target[2] = v[2];
    this.onChange();
    return this;
  }
  reorder(order) {
    this._target.order = order;
    this.onChange();
    return this;
  }
  fromRotationMatrix(m, order = this.order) {
    fromRotationMatrix(this._target, m, order);
    this.onChange();
    return this;
  }
  fromQuaternion(q, order = this.order, isInternal) {
    tmpMat4.fromQuaternion(q);
    this._target.fromRotationMatrix(tmpMat4, order);
    if (!isInternal) this.onChange();
    return this;
  }
  fromArray(a, o = 0) {
    this._target[0] = a[o];
    this._target[1] = a[o + 1];
    this._target[2] = a[o + 2];
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    a[o + 2] = this[2];
    return a;
  }
};

// package/src/core/Transform.js
var Transform = class {
  constructor() {
    this.parent = null;
    this.children = [];
    this.visible = true;
    this.matrix = new Mat4();
    this.worldMatrix = new Mat4();
    this.matrixAutoUpdate = true;
    this.worldMatrixNeedsUpdate = false;
    this.position = new Vec3();
    this.quaternion = new Quat();
    this.scale = new Vec3(1);
    this.rotation = new Euler();
    this.up = new Vec3(0, 1, 0);
    this.rotation._target.onChange = () => this.quaternion.fromEuler(this.rotation, true);
    this.quaternion._target.onChange = () => this.rotation.fromQuaternion(this.quaternion, void 0, true);
  }
  setParent(parent, notifyParent = true) {
    if (this.parent && parent !== this.parent) this.parent.removeChild(this, false);
    this.parent = parent;
    if (notifyParent && parent) parent.addChild(this, false);
  }
  addChild(child, notifyChild = true) {
    if (!~this.children.indexOf(child)) this.children.push(child);
    if (notifyChild) child.setParent(this, false);
  }
  removeChild(child, notifyChild = true) {
    if (!!~this.children.indexOf(child)) this.children.splice(this.children.indexOf(child), 1);
    if (notifyChild) child.setParent(null, false);
  }
  updateMatrixWorld(force) {
    if (this.matrixAutoUpdate) this.updateMatrix();
    if (this.worldMatrixNeedsUpdate || force) {
      if (this.parent === null) this.worldMatrix.copy(this.matrix);
      else this.worldMatrix.multiply(this.parent.worldMatrix, this.matrix);
      this.worldMatrixNeedsUpdate = false;
      force = true;
    }
    for (let i = 0, l = this.children.length; i < l; i++) {
      this.children[i].updateMatrixWorld(force);
    }
  }
  updateMatrix() {
    this.matrix.compose(this.quaternion, this.position, this.scale);
    this.worldMatrixNeedsUpdate = true;
  }
  traverse(callback) {
    if (callback(this)) return;
    for (let i = 0, l = this.children.length; i < l; i++) {
      this.children[i].traverse(callback);
    }
  }
  decompose() {
    this.matrix.decompose(this.quaternion._target, this.position, this.scale);
    this.rotation.fromQuaternion(this.quaternion);
  }
  lookAt(target, invert4 = false) {
    if (invert4) this.matrix.lookAt(this.position, target, this.up);
    else this.matrix.lookAt(target, this.position, this.up);
    this.matrix.getRotation(this.quaternion._target);
    this.rotation.fromQuaternion(this.quaternion);
  }
};

// package/src/core/Camera.js
var tempMat4 = /* @__PURE__ */ new Mat4();
var tempVec3a = /* @__PURE__ */ new Vec3();
var tempVec3b = /* @__PURE__ */ new Vec3();
var Camera = class extends Transform {
  constructor(gl, { near = 0.1, far = 100, fov = 45, aspect = 1, left, right, bottom, top, zoom = 1 } = {}) {
    super();
    Object.assign(this, { near, far, fov, aspect, left, right, bottom, top, zoom });
    this.projectionMatrix = new Mat4();
    this.viewMatrix = new Mat4();
    this.projectionViewMatrix = new Mat4();
    this.worldPosition = new Vec3();
    this.type = left || right ? "orthographic" : "perspective";
    if (this.type === "orthographic") this.orthographic();
    else this.perspective();
  }
  perspective({ near = this.near, far = this.far, fov = this.fov, aspect = this.aspect } = {}) {
    Object.assign(this, { near, far, fov, aspect });
    this.projectionMatrix.fromPerspective({ fov: fov * (Math.PI / 180), aspect, near, far });
    this.type = "perspective";
    return this;
  }
  orthographic({
    near = this.near,
    far = this.far,
    left = this.left || -1,
    right = this.right || 1,
    bottom = this.bottom || -1,
    top = this.top || 1,
    zoom = this.zoom
  } = {}) {
    Object.assign(this, { near, far, left, right, bottom, top, zoom });
    left /= zoom;
    right /= zoom;
    bottom /= zoom;
    top /= zoom;
    this.projectionMatrix.fromOrthogonal({ left, right, bottom, top, near, far });
    this.type = "orthographic";
    return this;
  }
  updateMatrixWorld() {
    super.updateMatrixWorld();
    this.viewMatrix.inverse(this.worldMatrix);
    this.worldMatrix.getTranslation(this.worldPosition);
    this.projectionViewMatrix.multiply(this.projectionMatrix, this.viewMatrix);
    return this;
  }
  updateProjectionMatrix() {
    if (this.type === "perspective") {
      return this.perspective();
    } else {
      return this.orthographic();
    }
  }
  lookAt(target) {
    super.lookAt(target, true);
    return this;
  }
  // Project 3D coordinate to 2D point
  project(v) {
    v.applyMatrix4(this.viewMatrix);
    v.applyMatrix4(this.projectionMatrix);
    return this;
  }
  // Unproject 2D point to 3D coordinate
  unproject(v) {
    v.applyMatrix4(tempMat4.inverse(this.projectionMatrix));
    v.applyMatrix4(this.worldMatrix);
    return this;
  }
  updateFrustum() {
    if (!this.frustum) {
      this.frustum = [new Vec3(), new Vec3(), new Vec3(), new Vec3(), new Vec3(), new Vec3()];
    }
    const m = this.projectionViewMatrix;
    this.frustum[0].set(m[3] - m[0], m[7] - m[4], m[11] - m[8]).constant = m[15] - m[12];
    this.frustum[1].set(m[3] + m[0], m[7] + m[4], m[11] + m[8]).constant = m[15] + m[12];
    this.frustum[2].set(m[3] + m[1], m[7] + m[5], m[11] + m[9]).constant = m[15] + m[13];
    this.frustum[3].set(m[3] - m[1], m[7] - m[5], m[11] - m[9]).constant = m[15] - m[13];
    this.frustum[4].set(m[3] - m[2], m[7] - m[6], m[11] - m[10]).constant = m[15] - m[14];
    this.frustum[5].set(m[3] + m[2], m[7] + m[6], m[11] + m[10]).constant = m[15] + m[14];
    for (let i = 0; i < 6; i++) {
      const invLen = 1 / this.frustum[i].distance();
      this.frustum[i].multiply(invLen);
      this.frustum[i].constant *= invLen;
    }
  }
  frustumIntersectsMesh(node, worldMatrix = node.worldMatrix) {
    if (!node.geometry.attributes.position) return true;
    if (!node.geometry.bounds || node.geometry.bounds.radius === Infinity) node.geometry.computeBoundingSphere();
    if (!node.geometry.bounds) return true;
    const center = tempVec3a;
    center.copy(node.geometry.bounds.center);
    center.applyMatrix4(worldMatrix);
    const radius = node.geometry.bounds.radius * worldMatrix.getMaxScaleOnAxis();
    return this.frustumIntersectsSphere(center, radius);
  }
  frustumIntersectsSphere(center, radius) {
    const normal = tempVec3b;
    for (let i = 0; i < 6; i++) {
      const plane = this.frustum[i];
      const distance3 = normal.copy(plane).dot(center) + plane.constant;
      if (distance3 < -radius) return false;
    }
    return true;
  }
};

// package/src/math/functions/Mat3Func.js
function fromMat4(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  out[2] = a[2];
  out[3] = a[4];
  out[4] = a[5];
  out[5] = a[6];
  out[6] = a[8];
  out[7] = a[9];
  out[8] = a[10];
  return out;
}
function fromQuat2(out, q) {
  let x = q[0], y = q[1], z = q[2], w = q[3];
  let x2 = x + x;
  let y2 = y + y;
  let z2 = z + z;
  let xx = x * x2;
  let yx = y * x2;
  let yy = y * y2;
  let zx = z * x2;
  let zy = z * y2;
  let zz = z * z2;
  let wx = w * x2;
  let wy = w * y2;
  let wz = w * z2;
  out[0] = 1 - yy - zz;
  out[3] = yx - wz;
  out[6] = zx + wy;
  out[1] = yx + wz;
  out[4] = 1 - xx - zz;
  out[7] = zy - wx;
  out[2] = zx - wy;
  out[5] = zy + wx;
  out[8] = 1 - xx - yy;
  return out;
}
function copy5(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  out[2] = a[2];
  out[3] = a[3];
  out[4] = a[4];
  out[5] = a[5];
  out[6] = a[6];
  out[7] = a[7];
  out[8] = a[8];
  return out;
}
function set5(out, m00, m01, m02, m10, m11, m12, m20, m21, m22) {
  out[0] = m00;
  out[1] = m01;
  out[2] = m02;
  out[3] = m10;
  out[4] = m11;
  out[5] = m12;
  out[6] = m20;
  out[7] = m21;
  out[8] = m22;
  return out;
}
function identity3(out) {
  out[0] = 1;
  out[1] = 0;
  out[2] = 0;
  out[3] = 0;
  out[4] = 1;
  out[5] = 0;
  out[6] = 0;
  out[7] = 0;
  out[8] = 1;
  return out;
}
function invert3(out, a) {
  let a00 = a[0], a01 = a[1], a02 = a[2];
  let a10 = a[3], a11 = a[4], a12 = a[5];
  let a20 = a[6], a21 = a[7], a22 = a[8];
  let b01 = a22 * a11 - a12 * a21;
  let b11 = -a22 * a10 + a12 * a20;
  let b21 = a21 * a10 - a11 * a20;
  let det = a00 * b01 + a01 * b11 + a02 * b21;
  if (!det) {
    return null;
  }
  det = 1 / det;
  out[0] = b01 * det;
  out[1] = (-a22 * a01 + a02 * a21) * det;
  out[2] = (a12 * a01 - a02 * a11) * det;
  out[3] = b11 * det;
  out[4] = (a22 * a00 - a02 * a20) * det;
  out[5] = (-a12 * a00 + a02 * a10) * det;
  out[6] = b21 * det;
  out[7] = (-a21 * a00 + a01 * a20) * det;
  out[8] = (a11 * a00 - a01 * a10) * det;
  return out;
}
function multiply4(out, a, b) {
  let a00 = a[0], a01 = a[1], a02 = a[2];
  let a10 = a[3], a11 = a[4], a12 = a[5];
  let a20 = a[6], a21 = a[7], a22 = a[8];
  let b00 = b[0], b01 = b[1], b02 = b[2];
  let b10 = b[3], b11 = b[4], b12 = b[5];
  let b20 = b[6], b21 = b[7], b22 = b[8];
  out[0] = b00 * a00 + b01 * a10 + b02 * a20;
  out[1] = b00 * a01 + b01 * a11 + b02 * a21;
  out[2] = b00 * a02 + b01 * a12 + b02 * a22;
  out[3] = b10 * a00 + b11 * a10 + b12 * a20;
  out[4] = b10 * a01 + b11 * a11 + b12 * a21;
  out[5] = b10 * a02 + b11 * a12 + b12 * a22;
  out[6] = b20 * a00 + b21 * a10 + b22 * a20;
  out[7] = b20 * a01 + b21 * a11 + b22 * a21;
  out[8] = b20 * a02 + b21 * a12 + b22 * a22;
  return out;
}
function translate2(out, a, v) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a10 = a[3], a11 = a[4], a12 = a[5], a20 = a[6], a21 = a[7], a22 = a[8], x = v[0], y = v[1];
  out[0] = a00;
  out[1] = a01;
  out[2] = a02;
  out[3] = a10;
  out[4] = a11;
  out[5] = a12;
  out[6] = x * a00 + y * a10 + a20;
  out[7] = x * a01 + y * a11 + a21;
  out[8] = x * a02 + y * a12 + a22;
  return out;
}
function rotate2(out, a, rad) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a10 = a[3], a11 = a[4], a12 = a[5], a20 = a[6], a21 = a[7], a22 = a[8], s = Math.sin(rad), c = Math.cos(rad);
  out[0] = c * a00 + s * a10;
  out[1] = c * a01 + s * a11;
  out[2] = c * a02 + s * a12;
  out[3] = c * a10 - s * a00;
  out[4] = c * a11 - s * a01;
  out[5] = c * a12 - s * a02;
  out[6] = a20;
  out[7] = a21;
  out[8] = a22;
  return out;
}
function scale4(out, a, v) {
  let x = v[0], y = v[1];
  out[0] = x * a[0];
  out[1] = x * a[1];
  out[2] = x * a[2];
  out[3] = y * a[3];
  out[4] = y * a[4];
  out[5] = y * a[5];
  out[6] = a[6];
  out[7] = a[7];
  out[8] = a[8];
  return out;
}
function normalFromMat4(out, a) {
  let a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  let a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  let a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  let a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
  let b00 = a00 * a11 - a01 * a10;
  let b01 = a00 * a12 - a02 * a10;
  let b02 = a00 * a13 - a03 * a10;
  let b03 = a01 * a12 - a02 * a11;
  let b04 = a01 * a13 - a03 * a11;
  let b05 = a02 * a13 - a03 * a12;
  let b06 = a20 * a31 - a21 * a30;
  let b07 = a20 * a32 - a22 * a30;
  let b08 = a20 * a33 - a23 * a30;
  let b09 = a21 * a32 - a22 * a31;
  let b10 = a21 * a33 - a23 * a31;
  let b11 = a22 * a33 - a23 * a32;
  let det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (!det) {
    return null;
  }
  det = 1 / det;
  out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det;
  out[1] = (a12 * b08 - a10 * b11 - a13 * b07) * det;
  out[2] = (a10 * b10 - a11 * b08 + a13 * b06) * det;
  out[3] = (a02 * b10 - a01 * b11 - a03 * b09) * det;
  out[4] = (a00 * b11 - a02 * b08 + a03 * b07) * det;
  out[5] = (a01 * b08 - a00 * b10 - a03 * b06) * det;
  out[6] = (a31 * b05 - a32 * b04 + a33 * b03) * det;
  out[7] = (a32 * b02 - a30 * b05 - a33 * b01) * det;
  out[8] = (a30 * b04 - a31 * b02 + a33 * b00) * det;
  return out;
}

// package/src/math/Mat3.js
var Mat3 = class extends Array {
  constructor(m00 = 1, m01 = 0, m02 = 0, m10 = 0, m11 = 1, m12 = 0, m20 = 0, m21 = 0, m22 = 1) {
    super(m00, m01, m02, m10, m11, m12, m20, m21, m22);
    return this;
  }
  set(m00, m01, m02, m10, m11, m12, m20, m21, m22) {
    if (m00.length) return this.copy(m00);
    set5(this, m00, m01, m02, m10, m11, m12, m20, m21, m22);
    return this;
  }
  translate(v, m = this) {
    translate2(this, m, v);
    return this;
  }
  rotate(v, m = this) {
    rotate2(this, m, v);
    return this;
  }
  scale(v, m = this) {
    scale4(this, m, v);
    return this;
  }
  multiply(ma, mb) {
    if (mb) {
      multiply4(this, ma, mb);
    } else {
      multiply4(this, this, ma);
    }
    return this;
  }
  identity() {
    identity3(this);
    return this;
  }
  copy(m) {
    copy5(this, m);
    return this;
  }
  fromMatrix4(m) {
    fromMat4(this, m);
    return this;
  }
  fromQuaternion(q) {
    fromQuat2(this, q);
    return this;
  }
  fromBasis(vec3a, vec3b, vec3c) {
    this.set(vec3a[0], vec3a[1], vec3a[2], vec3b[0], vec3b[1], vec3b[2], vec3c[0], vec3c[1], vec3c[2]);
    return this;
  }
  inverse(m = this) {
    invert3(this, m);
    return this;
  }
  getNormalMatrix(m) {
    normalFromMat4(this, m);
    return this;
  }
};

// package/src/core/Mesh.js
var ID4 = 0;
var Mesh = class extends Transform {
  constructor(gl, { geometry, program, mode = gl.TRIANGLES, frustumCulled = true, renderOrder = 0 } = {}) {
    super();
    if (!gl.canvas) console.error("gl not passed as first argument to Mesh");
    this.gl = gl;
    this.id = ID4++;
    this.geometry = geometry;
    this.program = program;
    this.mode = mode;
    this.frustumCulled = frustumCulled;
    this.renderOrder = renderOrder;
    this.modelViewMatrix = new Mat4();
    this.normalMatrix = new Mat3();
    this.beforeRenderCallbacks = [];
    this.afterRenderCallbacks = [];
  }
  onBeforeRender(f) {
    this.beforeRenderCallbacks.push(f);
    return this;
  }
  onAfterRender(f) {
    this.afterRenderCallbacks.push(f);
    return this;
  }
  draw({ camera } = {}) {
    if (camera) {
      if (!this.program.uniforms.modelMatrix) {
        Object.assign(this.program.uniforms, {
          modelMatrix: { value: null },
          viewMatrix: { value: null },
          modelViewMatrix: { value: null },
          normalMatrix: { value: null },
          projectionMatrix: { value: null },
          cameraPosition: { value: null }
        });
      }
      this.program.uniforms.projectionMatrix.value = camera.projectionMatrix;
      this.program.uniforms.cameraPosition.value = camera.worldPosition;
      this.program.uniforms.viewMatrix.value = camera.viewMatrix;
      this.modelViewMatrix.multiply(camera.viewMatrix, this.worldMatrix);
      this.normalMatrix.getNormalMatrix(this.modelViewMatrix);
      this.program.uniforms.modelMatrix.value = this.worldMatrix;
      this.program.uniforms.modelViewMatrix.value = this.modelViewMatrix;
      this.program.uniforms.normalMatrix.value = this.normalMatrix;
    }
    this.beforeRenderCallbacks.forEach((f) => f && f({ mesh: this, camera }));
    let flipFaces = this.program.cullFace && this.worldMatrix.determinant() < 0;
    this.program.use({ flipFaces });
    this.geometry.draw({ mode: this.mode, program: this.program });
    this.afterRenderCallbacks.forEach((f) => f && f({ mesh: this, camera }));
  }
};

// package/src/math/functions/ColorFunc.js
var NAMES = {
  black: "#000000",
  white: "#ffffff",
  red: "#ff0000",
  green: "#00ff00",
  blue: "#0000ff",
  fuchsia: "#ff00ff",
  cyan: "#00ffff",
  yellow: "#ffff00",
  orange: "#ff8000"
};
function hexToRGB(hex) {
  if (hex.length === 4) hex = hex[0] + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3];
  const rgb = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!rgb) console.warn(`Unable to convert hex string ${hex} to rgb values`);
  return [parseInt(rgb[1], 16) / 255, parseInt(rgb[2], 16) / 255, parseInt(rgb[3], 16) / 255];
}
function numberToRGB(num) {
  num = parseInt(num);
  return [(num >> 16 & 255) / 255, (num >> 8 & 255) / 255, (num & 255) / 255];
}
function parseColor(color) {
  if (color === void 0) return [0, 0, 0];
  if (arguments.length === 3) return arguments;
  if (!isNaN(color)) return numberToRGB(color);
  if (color[0] === "#") return hexToRGB(color);
  if (NAMES[color.toLowerCase()]) return hexToRGB(NAMES[color.toLowerCase()]);
  console.warn("Color format not recognised");
  return [0, 0, 0];
}

// package/src/math/Color.js
var Color = class extends Array {
  constructor(color) {
    if (Array.isArray(color)) return super(...color);
    return super(...parseColor(...arguments));
  }
  get r() {
    return this[0];
  }
  get g() {
    return this[1];
  }
  get b() {
    return this[2];
  }
  set r(v) {
    this[0] = v;
  }
  set g(v) {
    this[1] = v;
  }
  set b(v) {
    this[2] = v;
  }
  set(color) {
    if (Array.isArray(color)) return this.copy(color);
    return this.copy(parseColor(...arguments));
  }
  copy(v) {
    this[0] = v[0];
    this[1] = v[1];
    this[2] = v[2];
    return this;
  }
};

// package/src/math/functions/Vec2Func.js
function copy6(out, a) {
  out[0] = a[0];
  out[1] = a[1];
  return out;
}
function set6(out, x, y) {
  out[0] = x;
  out[1] = y;
  return out;
}
function add4(out, a, b) {
  out[0] = a[0] + b[0];
  out[1] = a[1] + b[1];
  return out;
}
function subtract3(out, a, b) {
  out[0] = a[0] - b[0];
  out[1] = a[1] - b[1];
  return out;
}
function multiply5(out, a, b) {
  out[0] = a[0] * b[0];
  out[1] = a[1] * b[1];
  return out;
}
function divide2(out, a, b) {
  out[0] = a[0] / b[0];
  out[1] = a[1] / b[1];
  return out;
}
function scale5(out, a, b) {
  out[0] = a[0] * b;
  out[1] = a[1] * b;
  return out;
}
function distance2(a, b) {
  var x = b[0] - a[0], y = b[1] - a[1];
  return Math.sqrt(x * x + y * y);
}
function squaredDistance2(a, b) {
  var x = b[0] - a[0], y = b[1] - a[1];
  return x * x + y * y;
}
function length3(a) {
  var x = a[0], y = a[1];
  return Math.sqrt(x * x + y * y);
}
function squaredLength2(a) {
  var x = a[0], y = a[1];
  return x * x + y * y;
}
function negate2(out, a) {
  out[0] = -a[0];
  out[1] = -a[1];
  return out;
}
function inverse2(out, a) {
  out[0] = 1 / a[0];
  out[1] = 1 / a[1];
  return out;
}
function normalize4(out, a) {
  var x = a[0], y = a[1];
  var len = x * x + y * y;
  if (len > 0) {
    len = 1 / Math.sqrt(len);
  }
  out[0] = a[0] * len;
  out[1] = a[1] * len;
  return out;
}
function dot4(a, b) {
  return a[0] * b[0] + a[1] * b[1];
}
function cross2(a, b) {
  return a[0] * b[1] - a[1] * b[0];
}
function lerp3(out, a, b, t) {
  var ax = a[0], ay = a[1];
  out[0] = ax + t * (b[0] - ax);
  out[1] = ay + t * (b[1] - ay);
  return out;
}
function smoothLerp2(out, a, b, decay, dt) {
  const exp = Math.exp(-decay * dt);
  let ax = a[0];
  let ay = a[1];
  out[0] = b[0] + (ax - b[0]) * exp;
  out[1] = b[1] + (ay - b[1]) * exp;
  return out;
}
function transformMat32(out, a, m) {
  var x = a[0], y = a[1];
  out[0] = m[0] * x + m[3] * y + m[6];
  out[1] = m[1] * x + m[4] * y + m[7];
  return out;
}
function transformMat42(out, a, m) {
  let x = a[0];
  let y = a[1];
  out[0] = m[0] * x + m[4] * y + m[12];
  out[1] = m[1] * x + m[5] * y + m[13];
  return out;
}
function exactEquals2(a, b) {
  return a[0] === b[0] && a[1] === b[1];
}

// package/src/math/Vec2.js
var Vec2 = class _Vec2 extends Array {
  constructor(x = 0, y = x) {
    super(x, y);
    return this;
  }
  get x() {
    return this[0];
  }
  get y() {
    return this[1];
  }
  set x(v) {
    this[0] = v;
  }
  set y(v) {
    this[1] = v;
  }
  set(x, y = x) {
    if (x.length) return this.copy(x);
    set6(this, x, y);
    return this;
  }
  copy(v) {
    copy6(this, v);
    return this;
  }
  add(va, vb) {
    if (vb) add4(this, va, vb);
    else add4(this, this, va);
    return this;
  }
  sub(va, vb) {
    if (vb) subtract3(this, va, vb);
    else subtract3(this, this, va);
    return this;
  }
  multiply(v) {
    if (v.length) multiply5(this, this, v);
    else scale5(this, this, v);
    return this;
  }
  divide(v) {
    if (v.length) divide2(this, this, v);
    else scale5(this, this, 1 / v);
    return this;
  }
  inverse(v = this) {
    inverse2(this, v);
    return this;
  }
  // Can't use 'length' as Array.prototype uses it
  len() {
    return length3(this);
  }
  distance(v) {
    if (v) return distance2(this, v);
    else return length3(this);
  }
  squaredLen() {
    return this.squaredDistance();
  }
  squaredDistance(v) {
    if (v) return squaredDistance2(this, v);
    else return squaredLength2(this);
  }
  negate(v = this) {
    negate2(this, v);
    return this;
  }
  cross(va, vb) {
    if (vb) return cross2(va, vb);
    return cross2(this, va);
  }
  scale(v) {
    scale5(this, this, v);
    return this;
  }
  normalize() {
    normalize4(this, this);
    return this;
  }
  dot(v) {
    return dot4(this, v);
  }
  equals(v) {
    return exactEquals2(this, v);
  }
  applyMatrix3(mat3) {
    transformMat32(this, this, mat3);
    return this;
  }
  applyMatrix4(mat4) {
    transformMat42(this, this, mat4);
    return this;
  }
  lerp(v, a) {
    lerp3(this, this, v, a);
    return this;
  }
  smoothLerp(v, decay, dt) {
    smoothLerp2(this, this, v, decay, dt);
    return this;
  }
  clone() {
    return new _Vec2(this[0], this[1]);
  }
  fromArray(a, o = 0) {
    this[0] = a[o];
    this[1] = a[o + 1];
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    return a;
  }
};

// package/src/math/Vec4.js
var Vec4 = class extends Array {
  constructor(x = 0, y = x, z = x, w = x) {
    super(x, y, z, w);
    return this;
  }
  get x() {
    return this[0];
  }
  get y() {
    return this[1];
  }
  get z() {
    return this[2];
  }
  get w() {
    return this[3];
  }
  set x(v) {
    this[0] = v;
  }
  set y(v) {
    this[1] = v;
  }
  set z(v) {
    this[2] = v;
  }
  set w(v) {
    this[3] = v;
  }
  set(x, y = x, z = x, w = x) {
    if (x.length) return this.copy(x);
    set2(this, x, y, z, w);
    return this;
  }
  copy(v) {
    copy2(this, v);
    return this;
  }
  normalize() {
    normalize2(this, this);
    return this;
  }
  multiply(v) {
    scale2(this, this, v);
    return this;
  }
  dot(v) {
    return dot2(this, v);
  }
  fromArray(a, o = 0) {
    this[0] = a[o];
    this[1] = a[o + 1];
    this[2] = a[o + 2];
    this[3] = a[o + 3];
    return this;
  }
  toArray(a = [], o = 0) {
    a[o] = this[0];
    a[o + 1] = this[1];
    a[o + 2] = this[2];
    a[o + 3] = this[3];
    return a;
  }
};
export {
  Camera,
  Color,
  Euler,
  Geometry,
  Mat3,
  Mat4,
  Mesh,
  Program,
  Quat,
  Renderer,
  Transform,
  Vec2,
  Vec3,
  Vec4
};
