import test from 'node:test';
import assert from 'node:assert/strict';
import { transition, canAct } from '../assets/js/workspace-demo.mjs';
test('human takeover freezes until explicit handback', () => {
  assert.equal(transition('ready','dispatch'),'agent');
  assert.equal(transition('agent','takeover'),'human');
  assert.equal(transition('human','dispatch'),'human');
  assert.equal(transition('human','resume'),'agent');
});
test('stop never resumes without a new dispatch', () => {
  for (const from of ['agent','human']) assert.equal(transition(from,'stop'),'stopped');
  assert.equal(transition('stopped','resume'),'stopped');
  assert.equal(canAct('stopped','resume'),false);
  assert.equal(transition('stopped','dispatch'),'agent');
});
test('invalid and reset actions stay bounded', () => {
  assert.equal(transition('ready','resume'),'ready');
  assert.equal(transition('human','reset'),'ready');
  assert.throws(()=>transition('invalid','dispatch'));
});

// Exercise the DOM controller's keyboard handoff, not only its state table.
import { initDemo } from '../assets/js/workspace-demo.mjs';
function demoDocument() {
  const status = { textContent: '' }, detail = { textContent: '' }, controls = { hidden: true };
  const events = [];
  const doc = { activeElement: null, querySelector: () => demo, dispatchEvent: event => events.push(event.detail.state) };
  const buttons = ['dispatch','takeover','resume','stop','reset'].map(action => ({
    dataset: { demoAction: action }, disabled: false,
    addEventListener(type, handler) { this.handler = handler; },
    focus() { doc.activeElement = this; },
    activate() { if (!this.disabled) { this.focus(); this.handler(); } },
  }));
  const demo = { dataset: {}, querySelectorAll: () => buttons, querySelector: selector => ({ '[data-demo-status]': status, '[data-demo-detail]': detail, '[data-demo-controls]': controls })[selector] };
  initDemo(doc);
  return { doc, demo, status, controls, buttons: Object.fromEntries(buttons.map(b => [b.dataset.demoAction,b])), events };
}
test('keyboard activation advances focus to the next enabled control', () => {
  const { doc, demo, buttons, status, events } = demoDocument();
  const liveNode = status;
  for (const [action,state,next] of [['dispatch','agent','takeover'],['takeover','human','resume'],['resume','agent','takeover'],['stop','stopped','dispatch']]) {
    buttons[action].activate();
    assert.equal(demo.dataset.state,state);
    assert.equal(doc.activeElement,buttons[next]);
    assert.equal(doc.activeElement.disabled,false);
    assert.equal(status,liveNode);
  }
  assert.deepEqual(events,['ready','agent','human','agent','stopped']);
});
test('stopped DOM exposes a new dispatch and reset while handback stays disabled', () => {
  const { demo, buttons, status, controls } = demoDocument();
  assert.equal(controls.hidden,false);
  buttons.dispatch.activate(); buttons.stop.activate();
  buttons.resume.activate();
  assert.equal(demo.dataset.state,'stopped');
  assert.equal(buttons.resume.disabled,true);
  assert.match(status.textContent,/急停/);
  buttons.reset.activate();
  assert.equal(demo.dataset.state,'ready');
  assert.equal(buttons.dispatch.disabled,false);
});
