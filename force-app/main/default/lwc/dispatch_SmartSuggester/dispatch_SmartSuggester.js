import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import suggestOrderForToday from '@salesforce/apex/SmartDispatchSuggester.suggestOrderForToday';

const MAX_ROWS = 10;
const LOW_CONFIDENCE_THRESHOLD = 60;

// Badge labels are driven by SmartDispatchSuggester (Apex). Keep generic, dispatch-domain
// vocabulary so the UI works for pest, termite, mosquito, and lawn appointments.
// Pest anchors: "Cluster Linked" surfaces mosquito-surge / breeding-source pull-ins;
// "Cluster" surfaces nearby-route grouping (e.g., Avalon Park / Waterford Lakes).
const BADGE_CLASSES = {
  'SLA Risk': 'badge badge-red',
  'Cluster Linked': 'badge badge-orange',
  'Cluster': 'badge badge-blue',
  'Retention Risk': 'badge badge-purple',
  'Standard': 'badge badge-gray'
};

export default class DispatchSmartSuggester extends NavigationMixin(LightningElement) {
  rawSuggestions;
  error;
  loaded = false;

  @wire(suggestOrderForToday)
  wiredSuggestions({ data, error }) {
    if (data) {
      this.rawSuggestions = data;
      this.error = null;
      this.loaded = true;
    } else if (error) {
      this.error = error?.body?.message || 'Failed to load AI dispatch suggestions.';
      this.rawSuggestions = [];
      this.loaded = true;
    }
  }

  get suggestions() {
    if (!Array.isArray(this.rawSuggestions) || this.rawSuggestions.length === 0) return [];
    return this.rawSuggestions.slice(0, MAX_ROWS).map((s) => {
      const conf = Math.round(s.confidence ?? 0);
      const badge = s.criticalityBadge || 'Standard';
      return {
        id: s.serviceAppointmentId,
        rank: s.recommendedRank,
        subject: s.subject || '(no subject)',
        rationale: s.rationale || '',
        badge,
        badgeClass: BADGE_CLASSES[badge] || BADGE_CLASSES.Standard,
        confidence: `${conf}%`,
        confidenceClass: conf < LOW_CONFIDENCE_THRESHOLD ? 'confidence confidence-low' : 'confidence'
      };
    });
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
  }

  get hasError() {
    return !!this.error;
  }

  get isLoading() {
    return !this.loaded;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && !this.hasSuggestions;
  }

  get showLowConfidenceDisclaimer() {
    if (!this.suggestions.length) return false;
    const total = this.suggestions.reduce(
      (sum, s) => sum + parseInt(s.confidence, 10),
      0
    );
    const avg = total / this.suggestions.length;
    return avg < LOW_CONFIDENCE_THRESHOLD;
  }

  handleRowClick(event) {
    const saId = event.currentTarget.dataset.id;
    if (!saId) return;
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: saId,
        objectApiName: 'ServiceAppointment',
        actionName: 'view'
      }
    });
  }

  handleRowKey(event) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      this.handleRowClick(event);
    }
  }
}
