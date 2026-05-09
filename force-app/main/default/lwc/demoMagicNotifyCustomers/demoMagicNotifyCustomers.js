import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import Alert from 'lightning/alert';
import previewAudience from '@salesforce/apex/CustomerNotificationService.previewAudience';
import sendCampaign from '@salesforce/apex/CustomerNotificationService.sendCampaign';

const TEMPLATES = [
  {
    label: 'Holding statement (cause unknown)',
    value: 'HOLDING',
    body: 'Massey Services alert: We are aware of elevated pest activity affecting your address. A crew has been dispatched to investigate. We will text again with an estimated treatment window within 30 minutes. Reply HELP for help, STOP to opt out.'
  },
  {
    label: 'ETA known - 30 minutes',
    value: 'ETA_30',
    body: 'Massey Services update: Crews are en route to treat the breeding source affecting your area. Estimated arrival: within 30 minutes. We will notify you when treatment is complete. Reply HELP for help, STOP to opt out.'
  },
  {
    label: 'ETA known - 2 hours',
    value: 'ETA_120',
    body: 'Massey Services update: Crews are assessing the source of the mosquito surge affecting your area. Estimated treatment: within 2 hours. We will notify you when treatment is complete. Reply HELP for help, STOP to opt out.'
  },
  {
    label: 'Treatment complete',
    value: 'RESTORED',
    body: 'Massey Services alert: Larvicide and perimeter ULV fog treatment is complete in your area. Re-entry interval has cleared. If you continue to see elevated mosquito activity, please reply HELP. Thank you for your patience.'
  }
];

export default class DemoMagicNotifyCustomers extends NavigationMixin(LightningElement) {
  @api recordId;  // Incident Id

  audience = [];
  channel = 'SMS';
  templateValue = 'HOLDING';
  isSending = false;
  phase = 'idle';   // idle | preparing | targeting | sending | done

  @wire(previewAudience, { incidentId: '$recordId' })
  wiredAudience({ data }) { if (data) this.audience = data; }

  get channelOptions() {
    return [
      { label: 'SMS', value: 'SMS' },
      { label: 'Voice IVR', value: 'IVR' },
      { label: 'Email', value: 'Email' }
    ];
  }

  get templateOptions() {
    return TEMPLATES.map((t) => ({ label: t.label, value: t.value }));
  }

  get messageBody() {
    return (TEMPLATES.find((t) => t.value === this.templateValue) || TEMPLATES[0]).body;
  }

  get audienceCount() { return this.audience.length; }
  get audienceCountText() {
    return this.audience.length + ' customer' + (this.audience.length === 1 ? '' : 's')
      + ' will be contacted via ' + this.channel + '.';
  }

  get isPreparing() { return this.phase === 'preparing'; }
  get isTargeting() { return this.phase === 'targeting'; }
  get isSending2() { return this.phase === 'sending'; }

  handleChannel(e) { this.channel = e.detail.value; }
  handleTemplate(e) { this.templateValue = e.detail.value; }

  sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  async handleSend() {
    this.isSending = true;
    try {
      const apiCall = sendCampaign({
        incidentId: this.recordId,
        channel: this.channel,
        messageBody: this.messageBody
      });
      this.phase = 'preparing';
      await this.sleep(700);
      this.phase = 'targeting';
      await this.sleep(700);
      this.phase = 'sending';
      await this.sleep(700);
      const r = await apiCall;
      this.phase = 'done';

      const verb = r.reused ? 'Refreshed' : 'Created';
      const msg = verb + ' Product Service Campaign "' + r.campaignName + '" with '
        + r.itemsCreated + ' new per-property items. The campaign is now visible in the related list below - next, decide on field dispatch.';
      await Alert.open({ label: 'Cluster Customers Notified', message: msg });

      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (e) {
      await Alert.open({ label: 'Notification error', message: e?.body?.message || JSON.stringify(e) });
    } finally {
      this.isSending = false;
    }
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}
