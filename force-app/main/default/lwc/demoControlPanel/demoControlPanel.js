import { LightningElement, track } from 'lwc';

import ensureFoundation from '@salesforce/apex/OrgBootstrap.ensureFoundation';

import loadVariant from '@salesforce/apex/DemoDataLoader.loadVariant';
import demoReset from '@salesforce/apex/DemoDataLoader.reset';
import setDemoTime from '@salesforce/apex/DemoDataLoader.setDemoTime';
import activateMockIncident from '@salesforce/apex/DemoDataLoader.activateMockIncident';

import dispatcherLoad from '@salesforce/apex/DispatcherScenarioLoader.load';
import dispatcherReset from '@salesforce/apex/DispatcherScenarioLoader.reset';

import proactiveRunAll from '@salesforce/apex/ProactiveWoGenerator.runAll';

export default class DemoControlPanel extends LightningElement {
  @track statusBootstrap = '';
  @track statusBaseline = '';
  @track statusDispatcher = '';
  @track statusProactive = '';
  @track statusCluster = '';
  @track statusTime = '';

  busyKey = '';
  daysAgo = 0;

  // Section 0: One-time foundation setup for a new org.
  async runBootstrap() { await this.run('bootstrap', ensureFoundation, (m) => this.statusBootstrap = m); }

  // Section 1: Baseline pest demo data.
  async loadGoGreen() { await this.run('baseline-gogreen', () => loadVariant({ serviceLine: 'Pest' }), (m) => this.statusBaseline = m); }
  async loadTermite() { await this.run('baseline-termite', () => loadVariant({ serviceLine: 'Termite' }), (m) => this.statusBaseline = m); }
  async loadMosquito() { await this.run('baseline-mosquito', () => loadVariant({ serviceLine: 'Mosquito' }), (m) => this.statusBaseline = m); }
  async resetAll() {
    if (!confirm('This deletes all masseyFlow demo Accounts/Assets/WOs/SAs/Incidents/PSCs and dispatcher schedule. Continue?')) return;
    await this.run('baseline-reset', async () => {
      const a = await dispatcherReset();
      const b = await demoReset();
      return a + ' / ' + b;
    }, (m) => this.statusBaseline = m);
  }
  async reloadFresh(serviceLine) {
    if (!confirm('Reset everything and reload as ' + serviceLine + '?')) return;
    await this.run('baseline-reload-' + serviceLine, async () => {
      await dispatcherReset();
      await demoReset();
      return await loadVariant({ serviceLine });
    }, (m) => this.statusBaseline = m);
  }
  reloadFreshGoGreen() { return this.reloadFresh('Pest'); }
  reloadFreshTermite() { return this.reloadFresh('Termite'); }
  reloadFreshMosquito() { return this.reloadFresh('Mosquito'); }

  // Section 2: Dispatcher Gantt scenario (Orlando branch route board).
  async loadDispatcher() { await this.run('dispatcher-load', dispatcherLoad, (m) => this.statusDispatcher = m); }
  async resetDispatcher() { await this.run('dispatcher-reset', dispatcherReset, (m) => this.statusDispatcher = m); }

  // Section 3: Proactive pest pressure run.
  async runProactive() {
    await this.run('proactive', proactiveRunAll, (r) => {
      this.statusProactive = r && r.message ? r.message
        : (r ? JSON.stringify(r) : 'No result returned.');
    });
  }

  // Section 4: Mosquito surge cluster activation (legacy / fallback).
  async activateCluster() { await this.run('cluster-activate', activateMockIncident, (m) => this.statusCluster = m); }

  // Section 5: Time-shift bait-station + pressure readings.
  handleDaysAgoChange(e) { this.daysAgo = Number(e.target.value || 0); }
  async applyTimeShift() {
    const d = this.daysAgo;
    await this.run('time-shift', () => setDemoTime({ daysAgo: d }), (m) => this.statusTime = m);
  }

  // infrastructure
  async run(key, fn, setStatus) {
    if (this.busyKey) return;
    this.busyKey = key;
    setStatus('Running...');
    try {
      const result = await fn();
      setStatus('OK ' + (typeof result === 'string' ? result : JSON.stringify(result)));
    } catch (e) {
      setStatus('Error ' + (e?.body?.message || e?.message || JSON.stringify(e)));
    } finally {
      this.busyKey = '';
    }
  }

  isBusy(key) { return this.busyKey === key; }
  get isAnyBusy() { return !!this.busyKey; }

  get isBootstrapBusy() { return this.busyKey === 'bootstrap'; }
  get isBaselineGoGreenBusy() { return this.busyKey === 'baseline-gogreen'; }
  get isBaselineTermiteBusy() { return this.busyKey === 'baseline-termite'; }
  get isBaselineMosquitoBusy() { return this.busyKey === 'baseline-mosquito'; }
  get isBaselineResetBusy() { return this.busyKey === 'baseline-reset'; }
  get isReloadGoGreenBusy() { return this.busyKey === 'baseline-reload-Pest'; }
  get isReloadTermiteBusy() { return this.busyKey === 'baseline-reload-Termite'; }
  get isReloadMosquitoBusy() { return this.busyKey === 'baseline-reload-Mosquito'; }
  get isDispatcherLoadBusy() { return this.busyKey === 'dispatcher-load'; }
  get isDispatcherResetBusy() { return this.busyKey === 'dispatcher-reset'; }
  get isProactiveBusy() { return this.busyKey === 'proactive'; }
  get isClusterBusy() { return this.busyKey === 'cluster-activate'; }
  get isTimeBusy() { return this.busyKey === 'time-shift'; }
}
