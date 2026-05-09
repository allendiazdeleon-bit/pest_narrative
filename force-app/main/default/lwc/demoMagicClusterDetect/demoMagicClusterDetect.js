import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import Alert from 'lightning/alert';
import previewSiblings from '@salesforce/apex/ClusterDetector.previewSiblings';
import detectFromCase from '@salesforce/apex/ClusterDetector.detectFromCase';

export default class DemoMagicClusterDetect extends NavigationMixin(LightningElement) {
  @api recordId;  // Case Id

  isRunning = false;
  result;
  siblings = [];
  visibleSiblings = [];
  phase = 'idle';   // idle | scanning | found | correlating | creating | linking | done

  @wire(previewSiblings, { sourceCaseId: '$recordId' })
  wiredPreview({ data }) { if (data) this.siblings = data; }

  get isScanning() { return this.phase === 'scanning'; }
  get isFound() { return this.phase === 'found'; }
  get isCorrelating() { return this.phase === 'correlating'; }
  get isCreating() { return this.phase === 'creating'; }
  get isLinking() { return this.phase === 'linking'; }
  get hasVisibleSiblings() { return this.visibleSiblings.length > 0; }
  get foundCountText() { return 'Found ' + this.siblings.length + ' additional Cases in same ZIP / route'; }

  sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  async handleDetect() {
    this.isRunning = true;
    this.visibleSiblings = [];

    try {
      // Kick off the actual detection in parallel with the animation.
      const apiCall = detectFromCase({ sourceCaseId: this.recordId });

      this.phase = 'scanning';
      await this.sleep(900);

      this.phase = 'found';
      await this.sleep(400);

      // Reveal sibling Cases one at a time.
      for (let i = 0; i < this.siblings.length; i++) {
        await this.sleep(200);
        this.visibleSiblings = [...this.visibleSiblings, this.siblings[i]];
      }

      this.phase = 'correlating';
      await this.sleep(700);

      this.phase = 'creating';
      await this.sleep(700);

      this.phase = 'linking';
      await this.sleep(600);

      this.result = await apiCall;
      this.phase = 'done';

      const msg = this.result.linkedCaseCount + ' Cases auto-correlated into Incident: ' + this.result.incidentSubject + '.\n\nFrom the Incident page you can now (1) Notify Cluster Customers and (2) Dispatch Field Action. Opening the Incident.';
      await Alert.open({ label: 'Incident Created from Cluster', message: msg });

      if (this.result.incidentId) {
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: {
            recordId: this.result.incidentId,
            objectApiName: 'Incident',
            actionName: 'view'
          }
        });
      }
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
