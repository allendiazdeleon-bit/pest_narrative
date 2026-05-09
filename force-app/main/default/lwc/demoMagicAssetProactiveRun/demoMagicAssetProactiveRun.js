import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import Alert from 'lightning/alert';
import runForAsset from '@salesforce/apex/ProactiveWoGenerator.runForAsset';

export default class DemoMagicAssetProactiveRun extends NavigationMixin(LightningElement) {
  @api recordId; // Property Asset Id

  isRunning = false;
  result;

  async handleRun() {
    this.isRunning = true;
    try {
      // Brief intentional pause so the progress steps in the modal feel
      // like a real callout rather than an instant local insert.
      const apiCall = runForAsset({ assetId: this.recordId });
      const minDelay = new Promise((resolve) => setTimeout(resolve, 2200));
      [this.result] = await Promise.all([apiCall, minDelay]);

      let label, message;
      if (this.result.breachesScanned === 0) {
        label = 'Pest pressure analysis complete - no anomaly';
        message = 'Bait station activity, soil temp, and conducive conditions are all within normal range. No proactive Booster Inspection generated.';
      } else if (this.result.proactiveWosCreated > 0) {
        label = 'Booster Inspection Generated';
        message = 'Customer accepted the proactive outreach. A Booster Inspection Work Order has been queued for dispatch.\n\nOpening the new Work Order.';
      } else if (this.result.declinedCasesCreated > 0) {
        label = 'Customer Declined Visit';
        message = 'Customer was contacted but declined a Booster Inspection. A Case has been logged for follow-up.';
      } else {
        label = 'Already Handled';
        message = 'A Booster Inspection or Case for this property already exists from a prior outreach.';
      }
      await Alert.open({ label, message });
      // If a WO was created, navigate to it.
      if (this.result.proactiveWosCreated > 0 && this.result.createdRecordIds?.length > 0) {
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: {
            recordId: this.result.createdRecordIds[0],
            objectApiName: 'WorkOrder',
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
