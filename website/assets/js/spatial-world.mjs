// A local Three.js scene. Product controls and copy remain ordinary HTML.
const root = typeof document === 'undefined' ? null : document.querySelector('[data-spatial-stage]');
if (root) {
  const start = () => initSpatialWorld(root).catch(() => { root.dataset.renderer = 'poster'; });
  if (document.readyState === 'complete') schedule(start);
  else window.addEventListener('load', () => schedule(start), { once: true });
}
function schedule(callback) {
  if ('requestIdleCallback' in window) window.requestIdleCallback(callback, { timeout: 1000 });
  else window.setTimeout(callback, 100);
}

export async function initSpatialWorld(stage) {
  if (navigator.connection?.saveData) return;
  const viewport = stage.querySelector('[data-spatial-viewport]') || stage;
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  canvas.className = 'spatial-canvas';
  const attributes = { antialias: true, alpha: true, powerPreference: 'low-power' };
  const context = canvas.getContext('webgl2', attributes);
  if (!context) { stage.dataset.renderer = 'poster'; return; }
  const THREE = await import('../vendor/three/three.module.js');
  const { RoomEnvironment } = await import('../vendor/three/RoomEnvironment.js');
  let renderer;
  try { renderer = new THREE.WebGLRenderer({ canvas, context, ...attributes }); }
  catch { stage.dataset.renderer = 'poster'; return; }
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(29, 1, .1, 70);
  const fogColor = new THREE.Color('#dce1e3');
  scene.background = fogColor;
  scene.fog = new THREE.Fog(fogColor, 17, 34);
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, matchMedia('(pointer: coarse)').matches ? 1 : 1.5));
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  let environment = pmrem.fromScene(room, .05);
  scene.environment = environment.texture;
  room.dispose();
  const key = new THREE.DirectionalLight('#fff4dc', 3.2);
  key.position.set(-4, 8, 7);
  scene.add(key, new THREE.HemisphereLight('#f8faf8', '#72808b', 2));
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(70, 70), new THREE.MeshStandardMaterial({ color: '#dce1e3', roughness: .95 }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.y = -2.55;
  scene.add(floor);
  const grid = new THREE.GridHelper(38, 48, '#a4b3bc', '#c5ced2');
  grid.position.y = -2.53;
  grid.material.transparent = true;
  grid.material.opacity = .5;
  scene.add(grid);
  const loader = new THREE.TextureLoader();
  const textures = [];
  const world = new THREE.Group();
  scene.add(world);
  const cream = new THREE.MeshPhysicalMaterial({ color: '#e9ecea', metalness: .52, roughness: .28, clearcoat: .5 });
  const navy = new THREE.MeshPhysicalMaterial({ color: '#183249', metalness: .64, roughness: .26, clearcoat: .5 });
  const amber = new THREE.MeshBasicMaterial({ color: '#d89435' });
  const edgeMaterial = new THREE.LineBasicMaterial({ color: '#a9bac5', transparent: true, opacity: .62 });
  function releaseGraphics() {
    const geometries = new Set(), materials = new Set([cream, navy, amber, edgeMaterial]);
    scene.traverse(object => { if (object.geometry) geometries.add(object.geometry); if (object.material) materials.add(object.material); });
    geometries.forEach(geometry => geometry.dispose()); materials.forEach(material => material.dispose());
    textures.forEach(texture => texture.dispose());
    environment.dispose(); pmrem.dispose(); renderer.dispose(); canvas.remove();
  }
  const makeWorkspace = async (image, material) => {
    const texture = await loader.loadAsync(new URL(`../screens/${image}.webp`, import.meta.url).href);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
    textures.push(texture);
    const group = new THREE.Group();
    const body = new THREE.Mesh(new THREE.BoxGeometry(5.3, 3.42, .14), material);
    group.add(body);
    const rim = new THREE.LineSegments(new THREE.EdgesGeometry(body.geometry), edgeMaterial);
    group.add(rim);
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(5.02, 2.824), new THREE.MeshBasicMaterial({ map: texture, toneMapped: false }));
    screen.position.set(0, -.06, .076);
    group.add(screen);
    for (let i = 0; i < 3; i++) {
      const dot = new THREE.Mesh(new THREE.CircleGeometry(.028, 12), i === 0 ? amber : new THREE.MeshBasicMaterial({ color: '#7c8b93' }));
      dot.position.set(-2.38 + i * .13, 1.54, .08);
      group.add(dot);
    }
    return group;
  };
  let human, agent;
  const loaded = await Promise.allSettled([makeWorkspace('home-desktop', cream), makeWorkspace('home-dark', navy)]);
  loaded.forEach(result => { if (result.status === 'fulfilled') world.add(result.value); });
  if (loaded.some(result => result.status === 'rejected') || !stage.isConnected) {
    releaseGraphics(); stage.dataset.renderer = 'poster'; return;
  }
  [human, agent] = loaded.map(result => result.value);
  human.rotation.set(-.16, .24, -.08);
  agent.rotation.set(-.16, -.24, .04);
  world.add(human, agent);
  const paths = new THREE.Group();
  const particles = new THREE.Group();
  world.add(paths, particles);
  const curves = [];
  for (let i = 0; i < 5; i++) {
    const offset = (i - 2) * .13;
    const curve = new THREE.CubicBezierCurve3(new THREE.Vector3(-1.8, -.5 + offset, .6), new THREE.Vector3(-.7, -2 + offset, 2.6), new THREE.Vector3(.6, -1.8 + offset, 1.8), new THREE.Vector3(2.1, -.1 + offset, -1.1));
    curves.push(curve);
    const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(curve.getPoints(70)), new THREE.LineBasicMaterial({ color: i === 2 ? '#d89435' : '#899ca8', transparent: true, opacity: i === 2 ? .9 : .33 }));
    paths.add(line);
    const particle = new THREE.Mesh(new THREE.SphereGeometry(.037, 8, 6), amber);
    particles.add(particle);
  }
  // Large registration outlines give the two spaces a shared physical plane.
  for (let i = 0; i < 2; i++) {
    const plane = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(6.4, .018, 4.5)), new THREE.LineBasicMaterial({ color: '#8297a6', transparent: true, opacity: .45 }));
    plane.position.set(i ? 2.7 : -2.7, -1.9, i ? -1.5 : 1);
    world.add(plane);
  }
  let view = 'together', paused = false, inView = true, lost = false, disposed = false;
  let pointerX = 0, pointerY = 0, elapsed = 0, frame = 0, previous = 0, frames = 0;
  const media = matchMedia('(prefers-reduced-motion: reduce)');
  const controls = stage.querySelector('[data-spatial-controls]');
  const pause = stage.querySelector('[data-spatial-pause]');
  const feedback = stage.querySelector('[data-spatial-feedback]');
  const canMove = () => !media.matches && !paused && !document.hidden && inView && !lost && !disposed;
  const poses = {
    together: { human: [-2.05, .2, 1.1], agent: [2.05, .85, -1.5], camera: [7.6, 5, 14.3] },
    human: { human: [-.5, .4, 1.8], agent: [4, .9, -3.8], camera: [4.1, 3.6, 12.2] },
    agent: { human: [-4.7, -.1, 1.4], agent: [.3, .65, -.1], camera: [5.1, 3.5, 12.1] },
  };
  let immediate = true;
  function paint(now = 0) {
    frame = 0;
    if (disposed || lost) return;
    const delta = previous ? Math.min((now - previous) / 1000, .05) : 0;
    previous = now;
    if (canMove()) elapsed += delta;
    const target = poses[view];
    const move = canMove() && !immediate ? .065 : 1;
    const aspect = viewport.clientWidth / Math.max(1, viewport.clientHeight);
    const portrait = aspect < .9;
    [human, agent].forEach((group, index) => {
      const pos = target[index ? 'agent' : 'human'];
      const base = new THREE.Vector3(...pos);
      if (portrait && view === 'together') { base.x *= .64; base.y += index ? .4 : -.25; }
      if (canMove()) base.y += Math.sin(elapsed * .55 + index * 2) * .065;
      group.position.lerp(base, move);
    });
    const position = new THREE.Vector3(...target.camera);
    if (portrait) position.multiplyScalar(1.5);
    if (canMove()) { position.x += pointerX * .9; position.y += pointerY * .45; }
    camera.position.lerp(position, move);
    camera.lookAt(0, .05, 0);
    particles.children.forEach((particle, i) => { particle.position.copy(curves[i].getPoint((elapsed * .16 + i * .19) % 1)); });
    const stopped = document.querySelector('[data-workspace-demo]')?.dataset.state;
    particles.visible = stopped !== 'human' && stopped !== 'stopped';
    renderer.render(scene, camera);
    frames++;
    stage.dataset.frames = String(frames);
    stage.dataset.motion = media.matches ? 'reduced' : paused ? 'paused' : canMove() ? 'running' : 'idle';
    immediate = false;
    if (canMove()) frame = requestAnimationFrame(paint);
  }
  function stop() { cancelAnimationFrame(frame); frame = 0; previous = 0; }
  function refresh() { stop(); if (!disposed) paint(performance.now()); }
  function resize() {
    const width = Math.max(1, viewport.clientWidth), height = Math.max(1, viewport.clientHeight);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    immediate = true;
    refresh();
  }
  function onPointer(event) {
    if (!canMove() || event.pointerType === 'touch') return;
    const rect = viewport.getBoundingClientRect();
    pointerX = (event.clientX - rect.left) / rect.width - .5;
    pointerY = .5 - (event.clientY - rect.top) / rect.height;
  }
  function onSelect(event) {
    const button = event.target.closest('[data-space-view]');
    if (!button || !Object.hasOwn(poses, button.dataset.spaceView)) return;
    view = button.dataset.spaceView;
    stage.dataset.view = view;
    controls.querySelectorAll('[data-space-view]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    refresh();
  }
  function onPause() {
    paused = !paused;
    pause.setAttribute('aria-pressed', String(paused));
    pause.textContent = paused ? '恢復動態' : '暫停動態';
    refresh();
  }
  function onMedia() { immediate = true; refresh(); }
  function onWorkspace(event) {
    const state = event.detail?.state;
    if (!['ready', 'human', 'agent', 'stopped'].includes(state)) return;
    stage.dataset.control = state;
    view = state === 'human' ? 'human' : state === 'agent' ? 'agent' : 'together';
    stage.dataset.view = view;
    controls.querySelectorAll('[data-space-view]').forEach(item => item.setAttribute('aria-pressed', String(item.dataset.spaceView === view)));
    refresh();
  }
  function onLost(event) {
    event.preventDefault(); lost = true; stop(); stage.dataset.renderer = 'poster';
    if (controls.contains(document.activeElement)) stage.focus({ preventScroll: true });
    controls.hidden = true;
    if (feedback) feedback.textContent = '立體場景暫時無法顯示，已改用靜態畫面。交接示意與下載仍可使用。';
  }
  function onRestored() {
    try {
      environment.dispose();
      const restoredRoom = new RoomEnvironment();
      environment = pmrem.fromScene(restoredRoom, .05);
      scene.environment = environment.texture;
      restoredRoom.dispose();
      lost = false; stage.dataset.renderer = 'webgl'; controls.hidden = false;
      if (feedback) feedback.textContent = '立體場景已恢復。';
      refresh();
    } catch { lost = true; stage.dataset.renderer = 'poster'; stop(); }
  }
  function onPageHide(event) { if (!event.persisted) cleanup(); else stop(); }
  function onPageShow(event) { if (event.persisted) refresh(); }
  const observer = new IntersectionObserver(entries => { inView = entries[0].isIntersecting; refresh(); }, { rootMargin: '80px' });
  const resizeObserver = new ResizeObserver(resize);
  const cleanup = () => {
    disposed = true;
    stop();
    observer.disconnect(); resizeObserver.disconnect();
    viewport.removeEventListener('pointermove', onPointer);
    controls.removeEventListener('click', onSelect); pause.removeEventListener('click', onPause);
    media.removeEventListener('change', onMedia); document.removeEventListener('visibilitychange', refresh);
    document.removeEventListener('workspace-state', onWorkspace);
    window.removeEventListener('pagehide', onPageHide); window.removeEventListener('pageshow', onPageShow);
    canvas.removeEventListener('webglcontextlost', onLost); canvas.removeEventListener('webglcontextrestored', onRestored);
    releaseGraphics();
  };
  viewport.addEventListener('pointermove', onPointer);
  controls.addEventListener('click', onSelect); pause.addEventListener('click', onPause);
  media.addEventListener('change', onMedia); document.addEventListener('visibilitychange', refresh);
  document.addEventListener('workspace-state', onWorkspace);
  canvas.addEventListener('webglcontextlost', onLost); canvas.addEventListener('webglcontextrestored', onRestored);
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('pageshow', onPageShow);
  viewport.append(canvas);
  observer.observe(viewport); resizeObserver.observe(viewport);
  controls.hidden = false;
  onWorkspace({ detail: { state: document.querySelector('[data-workspace-demo]')?.dataset.state || 'ready' } });
  resize();
  stage.dataset.renderer = 'webgl';
  stage.dataset.view = view;
  return { dispose: cleanup };
}
