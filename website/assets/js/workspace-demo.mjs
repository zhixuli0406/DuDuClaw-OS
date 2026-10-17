export const DEMO_STATES = Object.freeze({
  ready: { label: '等待你交辦', detail: '按下「示範交辦」，看看工作區如何切換。' },
  agent: { label: 'AI 在影子工作區工作', detail: '示意任務已交給 AI。你仍可使用自己的桌面，也可隨時接手。' },
  human: { label: '你已接手，AI 輸入凍結', detail: '示意 AI 不再輸入。需要時按「交還 AI」，才讓它繼續。' },
  stopped: { label: '已急停', detail: '示意工作已停止，不會自動恢復。重新交辦可再體驗一次。' },
});
export const TRANSITIONS = Object.freeze({ ready: { dispatch: 'agent' }, agent: { takeover: 'human', stop: 'stopped' }, human: { resume: 'agent', stop: 'stopped' }, stopped: { dispatch: 'agent' } });
export function transition(state, action) {
  if (!Object.hasOwn(DEMO_STATES, state)) throw new Error('Unknown demo state');
  return action === 'reset' ? 'ready' : TRANSITIONS[state][action] || state;
}
export function canAct(state, action) { return action === 'reset' || Object.hasOwn(TRANSITIONS[state] || {}, action); }
export function initDemo(doc) {
  const demo = doc.querySelector('[data-workspace-demo]');
  if (demo) {
    let state = 'ready';
    const buttons = [...demo.querySelectorAll('[data-demo-action]')];
    const render = () => {
      demo.dataset.state = state;
      demo.querySelector('[data-demo-status]').textContent = DEMO_STATES[state].label;
      demo.querySelector('[data-demo-detail]').textContent = DEMO_STATES[state].detail;
      buttons.forEach(button => { button.disabled = !canAct(state, button.dataset.demoAction); });
      doc.dispatchEvent(new CustomEvent('workspace-state', { detail: { state } }));
    };
    buttons.forEach(button => button.addEventListener('click', () => {
      const focused = doc.activeElement === button;
      state = transition(state, button.dataset.demoAction);
      render();
      // A disabled trigger must not strand keyboard focus after a transition.
      if (focused && button.disabled) {
        const next = { ready: 'dispatch', agent: 'takeover', human: 'resume', stopped: 'dispatch' }[state];
        buttons.find(item => item.dataset.demoAction === next)?.focus({ preventScroll: true });
      }
    }));
    demo.querySelector('[data-demo-controls]').hidden = false;
    render();
  }
}
if (typeof document !== 'undefined') initDemo(document);
