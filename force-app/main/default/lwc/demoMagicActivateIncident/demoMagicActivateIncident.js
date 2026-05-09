import { LightningElement, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import Alert from 'lightning/alert';
import activate from '@salesforce/apex/DemoDataLoader.activateMockIncident';
import getClusterCalls from '@salesforce/apex/DemoDataLoader.getClusterCalls';

export default class DemoMagicActivateIncident extends LightningElement {
  isRunning = false;
  result;
  allCalls = [];   // pre-fetched mosquito surge cluster Cases (8 of them)
  visibleCalls = []; // calls revealed during the simulated stream
  phase = 'idle';  // idle | streaming | correlating | linking | notifying | done

  @wire(getClusterCalls)
  wiredCalls({ data }) {
    if (data) this.allCalls = data;
  }

  get isStreaming() { return this.phase === 'streaming'; }
  get isCorrelating() { return this.phase === 'correlating'; }
  get isLinking() { return this.phase === 'linking'; }
  get isNotifying() { return this.phase === 'notifying'; }
  get hasVisibleCalls() { return this.visibleCalls.length > 0; }

  sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  async handleActivate() {
    this.isRunning = true;
    this.visibleCalls = [];

    try {
      // Kick off the real Apex activation in parallel with the animation.
      const apiCall = activate();

      // Phase 1: stream the 8 inbound mosquito-surge calls into view.
      this.phase = 'streaming';
      for (let i = 0; i < this.allCalls.length; i++) {
        await this.sleep(220);
        this.visibleCalls = [...this.visibleCalls, this.allCalls[i]];
      }

      // Phase 2: geographic correlation against ZIP 32828 / Avalon Park.
      this.phase = 'correlating';
      await this.sleep(900);

      // Phase 3: link to parent Mosquito Surge Incident.
      this.phase = 'linking';
      await this.sleep(700);

      // Phase 4: mass notification to affected customers.
      this.phase = 'notifying';
      await this.sleep(700);

      // Wait for the actual Apex call (should be done well before this point).
      this.result = await apiCall;
      this.phase = 'done';

      await Alert.open({
        label: 'Mosquito Surge Cluster Activated',
        message: '8 inbound calls received in 3 minutes. Geographic correlation grouped them into one parent Incident at Avalon Park / Waterford Lakes (ZIP 32828). Mass-notification text sent to all 47 affected Mosquito Hunter customers. Crew dispatch is next.'
      });
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      await Alert.open({ label: 'Integration error', message: e?.body?.message || JSON.stringify(e) });
    } finally {
      this.isRunning = false;
    }
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
