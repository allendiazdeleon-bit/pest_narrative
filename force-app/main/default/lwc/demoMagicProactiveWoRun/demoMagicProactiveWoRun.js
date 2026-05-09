import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import Alert from 'lightning/alert';
import runForMonitor from '@salesforce/apex/ProactiveWoGenerator.runForMonitor';

export default class DemoMagicProactiveWoRun extends LightningElement {
  @api recordId; // RecordsetFilterCriteria.Id

  isRunning = false;
  result;

  async handleRun() {
    this.isRunning = true;
    try {
      this.result = await runForMonitor({ monitorId: this.recordId });
      await Alert.open({
        label: 'Proactive Pest Pressure Run Complete',
        message: this.result.message
      });
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      await Alert.open({ label: 'Error', message: e?.body?.message || JSON.stringify(e) });
    } finally {
      this.isRunning = false;
    }
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
