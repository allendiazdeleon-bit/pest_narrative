import { LightningElement, api, track } from 'lwc';

/**
 * Massey Flow NFC Scanner.
 *
 * Used to scan NFC tags on:
 *   • Sentricon termite bait stations (each station carries a unique tag —
 *     scanning confirms the tech actually opened it on this visit and
 *     stamps the inspection record with the station ID).
 *   • Mosquito Hunter system controllers (the in-yard misting unit; tag
 *     verifies the tech reached the controller before declaring a refill).
 *
 * Requires the FSL Mobile Nimbus bridge — degrades gracefully on desktop.
 */
export default class MasseyFlowNfcScanner extends LightningElement {
    @api isOpen = false;
    @api expectedTagId = null;

    @track isScanning = true;
    @track scanResult = null;
    @track scanError = null;
    @track nfcAvailable = true;

    connectedCallback() {
        if (this.isOpen) {
            this.initializeNfcScanner();
        }
    }

    renderedCallback() {
        if (this.isOpen && !this.scanResult && !this.scanError) {
            this.initializeNfcScanner();
        }
    }

    async initializeNfcScanner() {
        // NFC scanning requires the FSL Mobile app's Nimbus bridge. The
        // NFCService plugin is only available on device at runtime — on
        // desktop / browser, gracefully show "not available".
        try {
            // eslint-disable-next-line no-undef
            if (typeof nimbus !== 'undefined' && nimbus.plugins && nimbus.plugins.NFCService) {
                // eslint-disable-next-line no-undef
                const readResult = await nimbus.plugins.NFCService.read();
                if (readResult && readResult.nfcData) {
                    const tagId = this.extractTagId(readResult.nfcData);
                    this.handleNfcScanResult(tagId);
                }
            } else {
                this.handleNfcNotAvailable();
            }
        } catch (error) {
            if (error.message && error.message.includes('not available')) {
                this.handleNfcNotAvailable();
            } else {
                console.error('[NfcScanner] NFC scan error:', error.message, error);
                this.scanError = error.message || 'Failed to read NFC tag';
                this.isScanning = false;
            }
        }
    }

    extractTagId(nfcData) {
        if (typeof nfcData === 'string') return nfcData;
        if (nfcData.id) return nfcData.id;
        if (nfcData.serialNumber) return nfcData.serialNumber;
        return nfcData.toString();
    }

    handleNfcScanResult(tagId) {
        this.isScanning = false;

        const matched = this.expectedTagId
            ? tagId.toLowerCase() === this.expectedTagId.toLowerCase()
            : true;

        this.scanResult = { tagId, matched };

        const event = new CustomEvent('nfcscancomplete', {
            detail: { tagId, matched }
        });
        this.dispatchEvent(event);
    }

    handleNfcNotAvailable() {
        this.isScanning = false;
        this.nfcAvailable = false;
        this.scanError = 'NFC scanner not available on this device. Please ensure NFC is enabled and try again.';
    }

    handleClose() {
        this.isScanning = false;
        this.scanResult = null;
        this.scanError = null;

        this.dispatchEvent(new CustomEvent('close'));
    }

    get scanningMessage() {
        return 'Scanning for Sentricon / system controller tag…';
    }

    get scanSuccessMessage() {
        return this.scanResult && this.scanResult.matched
            ? 'NFC Tag Matched Successfully'
            : 'Unknown NFC Tag';
    }

    get scanDetailMessage() {
        return this.scanResult ? `Tag ID: ${this.scanResult.tagId}` : '';
    }

    get showSuccessState() { return this.scanResult && this.scanResult.matched; }
    get showWarningState() { return this.scanResult && !this.scanResult.matched; }
    get showErrorState() { return !!this.scanError; }
    get showScanningState() { return this.isScanning; }
}
