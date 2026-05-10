import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue, updateRecord, createRecord } from 'lightning/uiRecordApi';
import Alert from 'lightning/alert';

import analyzePhoto from '@salesforce/apex/PhotoAnalysisService.analyzePhoto';
import analyzePestPressure from '@salesforce/apex/PestPressureAnalyzer.analyzeForAsset';
import getPropertyHistory from '@salesforce/apex/PropertyTreatmentHistoryService.recentVisits';

// Custom Labels — pest voice
import LBL_READING_PROMPT from '@salesforce/label/c.MasseyFlow_ReadingPrompt';
import LBL_ISOLATION from '@salesforce/label/c.MasseyFlow_IsolationAction';

// WorkOrder schema imports
import WO_ASSET_ID from '@salesforce/schema/WorkOrder.AssetId';
import WO_ACCOUNT_ID from '@salesforce/schema/WorkOrder.AccountId';

// Asset (Property) shared schema imports — pest fields per P1.1
import ASSET_NAME from '@salesforce/schema/Asset.Name';
import ASSET_SERIAL from '@salesforce/schema/Asset.SerialNumber';
import ASSET_LAT from '@salesforce/schema/Asset.Latitude';
import ASSET_LON from '@salesforce/schema/Asset.Longitude';
import ASSET_STATUS from '@salesforce/schema/Asset.Status';
import ASSET_INSTALL_DATE from '@salesforce/schema/Asset.InstallDate';
import ASSET_NFC_TAG from '@salesforce/schema/Asset.NFC_Tag_Id__c';

// Variant driver (P1.1 — required field). Drives all branching below.
import ASSET_SERVICE_LINE from '@salesforce/schema/Asset.Service_Line__c';

// Pest variant: spray equipment + treatment perimeter
import ASSET_LAST_TREATMENT from '@salesforce/schema/Asset.Last_Treatment_DateTime__c';
import ASSET_PEST_PRESSURE from '@salesforce/schema/Asset.Pest_Pressure_Score__c';
import ASSET_CONDUCIVE_CONDITIONS from '@salesforce/schema/Asset.Conducive_Conditions__c';
import ASSET_PERIMETER_LF from '@salesforce/schema/Asset.Treatment_Perimeter_LinearFt__c';

// Termite variant: bait stations + soil treatment
import ASSET_STATION_COUNT from '@salesforce/schema/Asset.Bait_Station_Count__c';
import ASSET_STATION_LAST_INSPECT from '@salesforce/schema/Asset.Last_Station_Inspection__c';
import ASSET_SOIL_PRODUCT from '@salesforce/schema/Asset.Soil_Treatment_Product__c';

// Mosquito variant: nozzles + larvicide
import ASSET_NOZZLE_COUNT from '@salesforce/schema/Asset.Nozzle_Count__c';
import ASSET_LARVICIDE_PRODUCT from '@salesforce/schema/Asset.Larvicide_Product__c';
import ASSET_STANDING_WATER from '@salesforce/schema/Asset.Standing_Water_Sources__c';

// Lawn variant: turf inputs + soil temp
import ASSET_TURF_TYPE from '@salesforce/schema/Asset.Turf_Type__c';
import ASSET_SOIL_TEMP from '@salesforce/schema/Asset.Soil_Temp_F__c';
import ASSET_LAST_FERT from '@salesforce/schema/Asset.Last_Fertilizer_Date__c';

const ASSET_FIELDS = [
    ASSET_NAME, ASSET_SERIAL, ASSET_LAT, ASSET_LON,
    ASSET_STATUS, ASSET_INSTALL_DATE, ASSET_NFC_TAG,
    ASSET_SERVICE_LINE,
    ASSET_LAST_TREATMENT, ASSET_PEST_PRESSURE, ASSET_CONDUCIVE_CONDITIONS, ASSET_PERIMETER_LF,
    ASSET_STATION_COUNT, ASSET_STATION_LAST_INSPECT, ASSET_SOIL_PRODUCT,
    ASSET_NOZZLE_COUNT, ASSET_LARVICIDE_PRODUCT, ASSET_STANDING_WATER,
    ASSET_TURF_TYPE, ASSET_SOIL_TEMP, ASSET_LAST_FERT
];

export default class MasseyFlowSiteStep extends LightningElement {
    @api recordId;
    @api workOrder;
    // Account flowed from orchestrator. Required for the embedded
    // <c-massey-upsell-coach> at the bottom of the walk-around.
    @api accountId;

    label = {
        readingPrompt: LBL_READING_PROMPT,
        perimeter: LBL_ISOLATION
    };

    @track assetId;
    @track assetData = {};

    // Live measurements captured during the walk-around. Each service line
    // populates its own subset; the rest stay null.
    @track measurements = {
        // Pest (residential GoGreen)
        pestPressureScore: null,
        conduciveConditions: '',
        perimeterLinearFeet: null,
        // Termite (Sentricon + Termidor)
        baitStationsActive: null,
        soilTreatmentDepthInches: null,
        // Mosquito Hunter
        standingWaterSources: null,
        nozzlesInspected: null,
        // Lawn Service
        soilTempF: null,
        weedCoveragePct: null
    };

    @track isScannerOpen = false;
    @track photos = [];
    _photoIdCounter = 0;
    _captureAttributeSet = false;
    @track isSaving = false;

    @track propertyHistory;

    renderedCallback() {
        if (!this._captureAttributeSet) {
            const captureInput = this.template.querySelector('input.capture-input');
            if (captureInput) {
                captureInput.setAttribute('capture', 'environment');
                this._captureAttributeSet = true;
            }
        }
    }

    get saveButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Save Walk-Around';
    }

    @wire(getRecord, { recordId: '$recordId', fields: [WO_ASSET_ID, WO_ACCOUNT_ID] })
    wiredWorkOrder({ data, error }) {
        if (data) {
            const assetRef = getFieldValue(data, WO_ASSET_ID);
            if (assetRef) this.assetId = assetRef;
            // Fall through to @api accountId from orchestrator if set; else self-fill.
            if (!this.accountId) {
                this.accountId = getFieldValue(data, WO_ACCOUNT_ID);
            }
        } else if (error) {
            console.error('[SiteStep] Error loading WorkOrder:', JSON.stringify(error));
            this.showAlert('Error', 'Failed to fetch WorkOrder details.');
        }
    }

    @wire(getRecord, { recordId: '$assetId', fields: ASSET_FIELDS })
    wiredAsset({ data, error }) {
        if (data) {
            this.assetData = this.flattenRecord(data);
            if (this.assetId && !this.propertyHistory) {
                this.loadPropertyHistory();
            }
        } else if (error) {
            console.error('[SiteStep] Error loading Asset:', JSON.stringify(error));
            this.showAlert('Error', 'Failed to fetch property details.');
        }
    }

    flattenRecord(record) {
        return {
            Id: record.id,
            Name: getFieldValue(record, ASSET_NAME),
            SerialNumber: getFieldValue(record, ASSET_SERIAL),
            Latitude: getFieldValue(record, ASSET_LAT),
            Longitude: getFieldValue(record, ASSET_LON),
            Status: getFieldValue(record, ASSET_STATUS),
            InstallDate: getFieldValue(record, ASSET_INSTALL_DATE),
            NFC_Tag_Id__c: getFieldValue(record, ASSET_NFC_TAG),
            Service_Line__c: getFieldValue(record, ASSET_SERVICE_LINE),
            Last_Treatment_DateTime__c: getFieldValue(record, ASSET_LAST_TREATMENT),
            Pest_Pressure_Score__c: getFieldValue(record, ASSET_PEST_PRESSURE),
            Conducive_Conditions__c: getFieldValue(record, ASSET_CONDUCIVE_CONDITIONS),
            Treatment_Perimeter_LinearFt__c: getFieldValue(record, ASSET_PERIMETER_LF),
            Bait_Station_Count__c: getFieldValue(record, ASSET_STATION_COUNT),
            Last_Station_Inspection__c: getFieldValue(record, ASSET_STATION_LAST_INSPECT),
            Soil_Treatment_Product__c: getFieldValue(record, ASSET_SOIL_PRODUCT),
            Nozzle_Count__c: getFieldValue(record, ASSET_NOZZLE_COUNT),
            Larvicide_Product__c: getFieldValue(record, ASSET_LARVICIDE_PRODUCT),
            Standing_Water_Sources__c: getFieldValue(record, ASSET_STANDING_WATER),
            Turf_Type__c: getFieldValue(record, ASSET_TURF_TYPE),
            Soil_Temp_F__c: getFieldValue(record, ASSET_SOIL_TEMP),
            Last_Fertilizer_Date__c: getFieldValue(record, ASSET_LAST_FERT)
        };
    }

    // ── Service-line variant getters (P1.1) ────────────────────────────
    // Drives template-level lwc:if branches for the field-measurement panel
    // and the "what to look for" walk-around prompts.
    get serviceLine() {
        return this.assetData.Service_Line__c;
    }

    get isPest() { return this.serviceLine === 'GoGreen Pest'; }
    get isTermite() { return this.serviceLine === 'Termite Protection'; }
    get isMosquito() { return this.serviceLine === 'Mosquito Hunter'; }
    get isLawn() { return this.serviceLine === 'Lawn Service'; }

    get nameLabel() {
        if (this.isPest) return 'Property Address';
        if (this.isTermite) return 'Property Address (Sentricon coverage)';
        if (this.isMosquito) return 'Property Address (Mosquito system)';
        if (this.isLawn) return 'Property Address (Turf coverage)';
        return 'Property';
    }

    // Static info display getters
    get displayName() { return this.assetData.Name || 'Property'; }
    get displaySerialNumber() { return this.assetData.SerialNumber || 'N/A'; }
    get displayLatitude() { return this.assetData.Latitude || 'N/A'; }
    get displayLongitude() { return this.assetData.Longitude || 'N/A'; }
    get displayNfcTagId() { return this.assetData.NFC_Tag_Id__c || 'Not Set'; }
    get displayLastTreatment() { return this.assetData.Last_Treatment_DateTime__c || 'No prior visit on file'; }
    get displayPerimeter() {
        return this.assetData.Treatment_Perimeter_LinearFt__c
            ? `${this.assetData.Treatment_Perimeter_LinearFt__c} linear ft`
            : 'Not measured';
    }
    get displayStationCount() { return this.assetData.Bait_Station_Count__c || 'N/A'; }
    get displayLastStationInspection() { return this.assetData.Last_Station_Inspection__c || 'Never'; }
    get displaySoilProduct() { return this.assetData.Soil_Treatment_Product__c || 'Not selected'; }
    get displayNozzleCount() { return this.assetData.Nozzle_Count__c || 'N/A'; }
    get displayLarvicideProduct() { return this.assetData.Larvicide_Product__c || 'Not selected'; }
    get displayStandingWater() { return this.assetData.Standing_Water_Sources__c || 0; }
    get displayTurfType() { return this.assetData.Turf_Type__c || 'N/A'; }
    get displaySoilTemp() {
        return this.assetData.Soil_Temp_F__c != null
            ? `${this.assetData.Soil_Temp_F__c} °F`
            : 'Not measured';
    }
    get displayLastFert() { return this.assetData.Last_Fertilizer_Date__c || 'Never'; }

    handleOpenScanner() { this.isScannerOpen = true; }
    handleScannerClose() { this.isScannerOpen = false; }

    handleNfcScanComplete(event) {
        const { tagId, matched } = event.detail;
        this.isScannerOpen = false;
        if (matched) {
            this.showAlert('NFC Tag Matched', `Successfully scanned NFC tag: ${tagId}`);
        } else {
            this.showAlert('Warning', `Scanned tag (${tagId}) does not match expected tag.`);
        }
    }

    // ── Measurement input handlers ────────────────────────────────────
    handlePestPressureChange(event) {
        this.measurements.pestPressureScore = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleConduciveChange(event) {
        this.measurements.conduciveConditions = event.target.value || '';
    }
    handlePerimeterChange(event) {
        this.measurements.perimeterLinearFeet = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleBaitStationsChange(event) {
        this.measurements.baitStationsActive = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleSoilDepthChange(event) {
        this.measurements.soilTreatmentDepthInches = event.target.value
            ? parseFloat(event.target.value) : null;
    }
    handleStandingWaterChange(event) {
        this.measurements.standingWaterSources = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleNozzlesChange(event) {
        this.measurements.nozzlesInspected = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }
    handleSoilTempChange(event) {
        this.measurements.soilTempF = event.target.value
            ? parseFloat(event.target.value) : null;
    }
    handleWeedCoverageChange(event) {
        this.measurements.weedCoveragePct = event.target.value
            ? parseInt(event.target.value, 10) : null;
    }

    async handleSaveReadings() {
        if (!this.validateMeasurements()) {
            this.showAlert('Validation', 'Please enter the required walk-around measurements.');
            return;
        }
        this.isSaving = true;
        try {
            const fields = { Id: this.assetId };
            if (this.isPest) {
                if (this.measurements.pestPressureScore != null) {
                    fields[ASSET_PEST_PRESSURE.fieldApiName] = this.measurements.pestPressureScore;
                }
                if (this.measurements.conduciveConditions) {
                    fields[ASSET_CONDUCIVE_CONDITIONS.fieldApiName] = this.measurements.conduciveConditions;
                }
                if (this.measurements.perimeterLinearFeet != null) {
                    fields[ASSET_PERIMETER_LF.fieldApiName] = this.measurements.perimeterLinearFeet;
                }
            } else if (this.isTermite) {
                if (this.measurements.baitStationsActive != null) {
                    fields[ASSET_STATION_COUNT.fieldApiName] = this.measurements.baitStationsActive;
                }
                fields[ASSET_STATION_LAST_INSPECT.fieldApiName] = new Date().toISOString();
            } else if (this.isMosquito) {
                if (this.measurements.standingWaterSources != null) {
                    fields[ASSET_STANDING_WATER.fieldApiName] = this.measurements.standingWaterSources;
                }
                if (this.measurements.nozzlesInspected != null) {
                    fields[ASSET_NOZZLE_COUNT.fieldApiName] = this.measurements.nozzlesInspected;
                }
            } else if (this.isLawn) {
                if (this.measurements.soilTempF != null) {
                    fields[ASSET_SOIL_TEMP.fieldApiName] = this.measurements.soilTempF;
                }
            }
            await updateRecord({ fields });
            this.showAlert('Saved', 'Walk-around readings saved.');
            this.dispatchStepComplete();
        } catch (error) {
            console.error('[SiteStep] Error saving readings:', JSON.stringify(error));
            this.showAlert('Error', `Failed to save readings: ${error?.body?.message || error?.message || ''}`);
        } finally {
            this.isSaving = false;
        }
    }

    validateMeasurements() {
        if (this.isPest) {
            return this.measurements.pestPressureScore !== null;
        }
        if (this.isTermite) {
            return this.measurements.baitStationsActive !== null;
        }
        if (this.isMosquito) {
            return this.measurements.standingWaterSources !== null;
        }
        if (this.isLawn) {
            return this.measurements.soilTempF !== null;
        }
        return true;
    }

    async loadPropertyHistory() {
        if (!this.assetId) return;
        try {
            const visits = await getPropertyHistory({ assetId: this.assetId, limitCount: 5 });
            this.propertyHistory = visits;
        } catch (e) {
            console.error('[SiteStep] Property history load failed:', JSON.stringify(e));
        }
    }

    get hasPropertyHistory() {
        return this.propertyHistory && this.propertyHistory.length > 0;
    }

    // ── Photos ─────────────────────────────────────────────────────────
    get photoCount() { return this.photos.length; }
    get hasPhotos() { return this.photos.length > 0; }
    get noPhotos() { return this.photos.length === 0; }

    handleCapturePhoto() {
        const input = this.template.querySelector('input.capture-input');
        if (input) input.click();
    }

    handleUploadPhoto() {
        const input = this.template.querySelector('input.upload-input');
        if (input) input.click();
    }

    handleFileSelected(event) {
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            const dataUrl = reader.result;
            const base64 = dataUrl.split(',')[1];

            const photo = {
                id: `photo-${++this._photoIdCounter}`,
                name: file.name,
                dataUrl,
                base64,
                timestamp: new Date().toISOString(),
                analysis: null,
                analyzing: false
            };

            this.photos = [...this.photos, photo];
            this.createContentVersion(photo);
        };
        reader.readAsDataURL(file);
        event.target.value = '';
    }

    createContentVersion(photo) {
        const fields = {
            Title: photo.name,
            PathOnClient: photo.name,
            VersionData: photo.base64,
            FirstPublishLocationId: this.recordId
        };

        createRecord({ apiName: 'ContentVersion', fields })
            .then((result) => {
                this.photos = this.photos.map((p) =>
                    p.id === photo.id ? { ...p, contentVersionId: result.id } : p
                );
                this.runPhotoAnalysis(photo.id, result.id);
            })
            .catch((error) => {
                console.error('[SiteStep] Error creating ContentVersion:', JSON.stringify(error));
            });
    }

    async runPhotoAnalysis(photoId, contentVersionId) {
        this.photos = this.photos.map((p) =>
            p.id === photoId ? { ...p, analyzing: true } : p
        );
        try {
            const result = await analyzePhoto({ contentVersionId });
            this.photos = this.photos.map((p) =>
                p.id === photoId
                    ? {
                          ...p,
                          analyzing: false,
                          analysis: {
                              ...result,
                              severityClass: this.severityClass(result.severity),
                              confidencePct: Math.round((result.confidence || 0) * 100)
                          }
                      }
                    : p
            );
        } catch (e) {
            console.error('[SiteStep] Photo analysis failed:', JSON.stringify(e));
            this.photos = this.photos.map((p) =>
                p.id === photoId ? { ...p, analyzing: false } : p
            );
        }
    }

    handleReanalyze(event) {
        const photoId = event.currentTarget.dataset.id;
        const photo = this.photos.find((p) => p.id === photoId);
        if (photo && photo.contentVersionId) {
            this.runPhotoAnalysis(photoId, photo.contentVersionId);
        }
    }

    severityClass(sev) {
        switch (sev) {
            case 'Critical': return 'severity severity-critical';
            case 'High':     return 'severity severity-high';
            case 'Medium':   return 'severity severity-medium';
            case 'Low':      return 'severity severity-low';
            default:         return 'severity severity-medium';
        }
    }

    handleRemovePhoto(event) {
        const photoId = event.currentTarget.dataset.id;
        this.photos = this.photos.filter((p) => p.id !== photoId);
    }

    dispatchStepComplete() {
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            detail: { status: 'completed' },
            bubbles: true,
            composed: true
        }));
    }

    async showAlert(title, message) {
        await Alert.open({ label: title, message });
    }

    // ── AI Pest Pressure forecast ─────────────────────────────────────
    @track pressureForecast;
    @track forecastTimestamp;

    @wire(analyzePestPressure, { assetId: '$assetId' })
    wiredPestPressure({ data, error }) {
        if (data) {
            this.pressureForecast = data;
            this.forecastTimestamp = new Date().toISOString();
        } else if (error) {
            console.error('[SiteStep] PestPressure unavailable:', JSON.stringify(error));
            this.pressureForecast = null;
        }
    }

    get hasPressureForecastCard() {
        return !!this.pressureForecast
            && Number(this.pressureForecast.riskScore) > 50;
    }

    get forecastSeverity() {
        if (!this.pressureForecast) return 'info';
        const score = Number(this.pressureForecast.riskScore);
        if (score > 75) return 'critical';
        if (score > 50) return 'warning';
        return 'info';
    }

    get forecastTitle() { return 'Pest Pressure Forecast'; }
    get forecastSummary() { return this.pressureForecast ? this.pressureForecast.summary : ''; }
    get forecastConfidence() { return this.pressureForecast ? this.pressureForecast.confidence : 70; }
    get forecastSource() { return this.pressureForecast ? this.pressureForecast.source : ''; }

    get forecastDetails() {
        if (!this.pressureForecast) return [];
        return [
            { label: 'Risk Score', value: String(this.pressureForecast.riskScore) + '/100' },
            { label: 'Conducive Conditions', value: this.pressureForecast.conduciveConditions || '—' }
        ];
    }

    // ── Embedded Upsell Coach event handler ───────────────────────────
    // The <c-massey-upsell-coach> dispatches `outcomecaptured` when the tech
    // logs an upsell offer outcome. We simply forward it to the orchestrator
    // so the summary step + manager dashboard can roll it up.
    handleUpsellOutcome(event) {
        // Forward to orchestrator. Detail shape: { accountId, serviceLine, outcome }.
        this.dispatchEvent(new CustomEvent('upsellcaptured', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }
}
