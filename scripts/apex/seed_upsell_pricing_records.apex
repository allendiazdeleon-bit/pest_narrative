// Loads the 5 Upsell_Pricing__mdt records via the Apex Metadata API.
// Used as a workaround when the SFDX CLI's source-tracking refuses to
// deploy CustomMetadata records (known caching issue with first-deploy
// of a new CMT type).
//
// Run with: sf apex run --file scripts/apex/seed_upsell_pricing_records.apex --target-org <alias>

class PriceSpec {
    String devName;
    String label;
    String sku;
    String serviceLine;
    String displayName;
    Decimal installFee;
    Decimal monthly;
    Decimal annualY1;
    Decimal bundlePct;
    String warranty;
    String inclusions;
}

List<PriceSpec> specs = new List<PriceSpec>();

PriceSpec p = new PriceSpec();
p.devName = 'GOGREEN_PEST';
p.label = 'GoGreen Quarterly Pest';
p.sku = 'GOGREEN_PEST'; p.serviceLine = 'Pest';
p.displayName = 'GoGreen Quarterly Pest Service';
p.installFee = 0; p.monthly = 43; p.annualY1 = 516; p.bundlePct = 0;
p.warranty = 'Re-service guarantee between visits';
p.inclusions = '• 4 quarterly service visits per year\n• Full perimeter spray + foundation\n• Interior treatment as needed\n• Targeted ant baiting (sugar / carpenter / fire)\n• Roach, silverfish, earwig, spider control\n• Free re-service if pests return';
specs.add(p);

p = new PriceSpec();
p.devName = 'TERMITE_SENTRICON';
p.label = 'Termite Sentricon AlwaysActive';
p.sku = 'TERMITE_SENTRICON'; p.serviceLine = 'Termite';
p.displayName = 'Termite Sentricon AlwaysActive Protection';
p.installFee = 1200; p.monthly = 25; p.annualY1 = 1500; p.bundlePct = 10;
p.warranty = 'Lifetime renewable warranty, transferable';
p.inclusions = '• Sentricon AlwaysActive bait stations every 10 ft\n• Quarterly station inspections + monitoring\n• Bait replenishment included\n• Full-structure damage warranty (up to $500K)\n• Annual graphic inspection report\n• Transferable to next homeowner';
specs.add(p);

p = new PriceSpec();
p.devName = 'TERMITE_LIQUID';
p.label = 'Termite Liquid (Termidor)';
p.sku = 'TERMITE_LIQUID'; p.serviceLine = 'Termite';
p.displayName = 'Termite Liquid Soil Treatment (Termidor SC)';
p.installFee = 1800; p.monthly = 0; p.annualY1 = 1800; p.bundlePct = 10;
p.warranty = '5-year renewable warranty';
p.inclusions = '• Termidor SC continuous soil barrier\n• Trench-and-treat method (4-inch trench + drill)\n• Foam injection into wall voids where prior activity\n• Full-structure damage warranty (up to $250K)\n• Annual re-inspection for warranty renewal';
specs.add(p);

p = new PriceSpec();
p.devName = 'MOSQUITO_HUNTER';
p.label = 'Mosquito Hunter Perimeter System';
p.sku = 'MOSQUITO_HUNTER'; p.serviceLine = 'Mosquito';
p.displayName = 'Mosquito Hunter Perimeter Misting System';
p.installFee = 425; p.monthly = 48; p.annualY1 = 1001; p.bundlePct = 10;
p.warranty = '1-year hardware + lifetime workmanship';
p.inclusions = '• Perimeter misting system: ~30 nozzles\n• Wi-Fi controller with smartphone app\n• Monthly larvicide / adulticide refill\n• Quarterly nozzle inspection + cleaning\n• 1-year hardware warranty\n• System winterization (Nov-Mar) included';
specs.add(p);

p = new PriceSpec();
p.devName = 'LAWN_CARE';
p.label = 'Lawn Care Quarterly';
p.sku = 'LAWN_CARE'; p.serviceLine = 'Lawn';
p.displayName = 'Lawn Care Quarterly Service';
p.installFee = 0; p.monthly = 79; p.annualY1 = 948; p.bundlePct = 10;
p.warranty = 'Re-treatment guarantee between visits';
p.inclusions = '• 4 quarterly fertilizer applications\n• Pre-emergent + post-emergent weed control\n• Targeted insecticide for fire ants, chinch bugs, grubs\n• Soil pH testing + amendment\n• Fungus + lawn-disease treatment\n• Re-treatment guarantee between visits';
specs.add(p);

Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();

for (PriceSpec spec : specs) {
    Metadata.CustomMetadata md = new Metadata.CustomMetadata();
    md.fullName = 'Upsell_Pricing.' + spec.devName;
    md.label = spec.label;

    Metadata.CustomMetadataValue v;

    v = new Metadata.CustomMetadataValue(); v.field = 'Sku__c'; v.value = spec.sku; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Service_Line__c'; v.value = spec.serviceLine; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Display_Name__c'; v.value = spec.displayName; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Install_Fee__c'; v.value = spec.installFee; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Monthly_Service__c'; v.value = spec.monthly; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Annual_Y1_Estimate__c'; v.value = spec.annualY1; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Bundle_Discount_Pct__c'; v.value = spec.bundlePct; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Warranty_Description__c'; v.value = spec.warranty; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Inclusions__c'; v.value = spec.inclusions; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Active__c'; v.value = true; md.values.add(v);

    mdContainer.addMetadata(md);
}

Id deployJobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
System.debug('Enqueued CMT deploy job: ' + deployJobId);
System.debug('Records queued: ' + specs.size());
System.debug('Check status: SELECT Id, Status FROM AsyncApexJob WHERE Id = \'' + deployJobId + '\'');
