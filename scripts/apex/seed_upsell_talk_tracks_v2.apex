// Updates the 12 Upsell_Talk_Track__mdt records with rewritten copy.
// Tighter (1-2 sentences), anchored to specific signals, drops the
// "while I'm here..." trope, ends with a low-stakes ask.
//
// Run via: sf apex run --file scripts/apex/seed_upsell_talk_tracks_v2.apex --target-org <alias>
// Updates existing records via the Apex Metadata API (workaround for SFDX
// CLI source-tracking failing on CMT records once the type is established).

class TT {
    String devName;
    String label;
    String serviceLine;
    String reasonCode;
    String talkTrack;
    Decimal estAnnualValue;
}

List<TT> tracks = new List<TT>();

TT t = new TT();
t.devName = 'Mosquito_Neighbor_Signed_Up'; t.label = 'Mosquito - Neighbor Signed Up';
t.serviceLine = 'Mosquito'; t.reasonCode = 'NEIGHBOR_BOUGHT_MOSQUITO';
t.talkTrack = 'Three of your neighbors on this street already have our Mosquito Hunter system. Want me to text you what it would cost? Takes 30 seconds, no commitment.';
t.estAnnualValue = 1001;
tracks.add(t);

t = new TT();
t.devName = 'Termite_FL_Season_Peak'; t.label = 'Termite - FL Season Peak';
t.serviceLine = 'Termite'; t.reasonCode = 'FL_TERMITE_SEASON_PEAK';
t.talkTrack = 'Florida termite swarm season starts in three weeks. We\'re booked solid by April — if you want a quote, this week\'s the time. Should I text it over tonight?';
t.estAnnualValue = 1500;
tracks.add(t);

t = new TT();
t.devName = 'Termite_Conducive_Mulch'; t.label = 'Termite - Conducive Mulch';
t.serviceLine = 'Termite'; t.reasonCode = 'CONDUCIVE_CONDITIONS_FLAGGED';
t.talkTrack = 'I noticed mulch piled against the foundation on the south side — that\'s the #1 conducive condition for subterranean termites. Want me to send a Sentricon quote? Lifetime warranty on damage if it ever happens.';
t.estAnnualValue = 1500;
tracks.add(t);

t = new TT();
t.devName = 'Lawn_Disease_Seen'; t.label = 'Lawn - Disease Seen';
t.serviceLine = 'Lawn'; t.reasonCode = 'LAWN_DISEASE_SEEN';
t.talkTrack = 'I\'m seeing some brown patch starting in the back lawn — that\'s a fungal issue, not insect. Our lawn service treats both. Want a quote? It runs about $80/month.';
t.estAnnualValue = 948;
tracks.add(t);

t = new TT();
t.devName = 'Mosquito_HighCatch'; t.label = 'Mosquito - High Catch Count';
t.serviceLine = 'Mosquito'; t.reasonCode = 'MOSQUITO_TRAP_HIGH_CATCH';
t.talkTrack = 'The mosquito trap by the back fence is showing 3x normal catch this month. With your kids out back, you\'d feel a real difference with our perimeter system. Want a quote? About $48/month.';
t.estAnnualValue = 1001;
tracks.add(t);

t = new TT();
t.devName = 'Pest_Quarterly_Bundle_Termite'; t.label = 'Pest+Termite Bundle';
t.serviceLine = 'Termite'; t.reasonCode = 'EXISTING_PEST_CUSTOMER';
t.talkTrack = 'You\'ve been on quarterly pest with us for years — we offer 10% off termite protection for existing customers. The full Sentricon system runs about $125/month bundled. Worth a quote?';
t.estAnnualValue = 1500;
tracks.add(t);

t = new TT();
t.devName = 'Pest_Quarterly_Bundle_Mosquito'; t.label = 'Pest+Mosquito Bundle';
t.serviceLine = 'Mosquito'; t.reasonCode = 'EXISTING_PEST_CUSTOMER';
t.talkTrack = 'Since you\'re already on quarterly pest with us, mosquito protection bundles in at 10% off — about $43/month. Big quality-of-life difference for your evenings on the deck. Want me to grab the numbers?';
t.estAnnualValue = 1001;
tracks.add(t);

t = new TT();
t.devName = 'Termite_To_Pest_Bundle'; t.label = 'Termite - Add Pest';
t.serviceLine = 'Pest'; t.reasonCode = 'TERMITE_ONLY_NO_PEST';
t.talkTrack = 'You have termite protection with us but not the quarterly pest service — that\'s the most common combo. Bundles in at 10% off, about $39/month. Want me to text you what that looks like?';
t.estAnnualValue = 516;
tracks.add(t);

t = new TT();
t.devName = 'Mosquito_To_Lawn'; t.label = 'Mosquito - Add Lawn';
t.serviceLine = 'Lawn'; t.reasonCode = 'OUTDOOR_FOCUSED_PROFILE';
t.talkTrack = 'You\'re already investing in the outdoor space with the mosquito system — most of our Mosquito Hunter customers add lawn service so the yard actually looks good. About $79/month. Worth a quote?';
t.estAnnualValue = 948;
tracks.add(t);

t = new TT();
t.devName = 'Lawn_To_Mosquito'; t.label = 'Lawn - Add Mosquito';
t.serviceLine = 'Mosquito'; t.reasonCode = 'OUTDOOR_FOCUSED_PROFILE';
t.talkTrack = 'You\'re putting work into the lawn — adding our Mosquito Hunter system makes the yard actually usable at dusk. Bundles with lawn at 10% off. Want me to send a quote?';
t.estAnnualValue = 1001;
tracks.add(t);

t = new TT();
t.devName = 'Termite_Sentricon_Upgrade'; t.label = 'Termite Sentricon Upgrade';
t.serviceLine = 'Termite'; t.reasonCode = 'SENTRICON_UPGRADE_FROM_TERMIDOR';
t.talkTrack = 'Your liquid Termidor renewal comes due in three months. A lot of customers switch to Sentricon — same protection, lifetime transferable warranty, and the bait stations work even when you sell the house. Worth comparing?';
t.estAnnualValue = 1500;
tracks.add(t);

t = new TT();
t.devName = 'Pest_Large_Lot_Bifen'; t.label = 'Pest - Large Lot Bifen Add-On';
t.serviceLine = 'Pest'; t.reasonCode = 'LARGE_LOT_BIFEN_OPPORTUNITY';
t.talkTrack = 'Your lot is larger than our standard perimeter — the extended treatment with Bifen runs about $15 more per visit and covers the back acreage. Most customers with land your size add it. Want me to spec it?';
t.estAnnualValue = 180;
tracks.add(t);

// Update via Metadata API
Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();

for (TT track : tracks) {
    Metadata.CustomMetadata md = new Metadata.CustomMetadata();
    md.fullName = 'Upsell_Talk_Track.' + track.devName;
    md.label = track.label;

    Metadata.CustomMetadataValue v;
    v = new Metadata.CustomMetadataValue(); v.field = 'Service_Line__c'; v.value = track.serviceLine; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Reason_Code__c'; v.value = track.reasonCode; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Talk_Track__c'; v.value = track.talkTrack; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Estimated_Annual_Value__c'; v.value = track.estAnnualValue; md.values.add(v);
    v = new Metadata.CustomMetadataValue(); v.field = 'Active__c'; v.value = true; md.values.add(v);

    mdContainer.addMetadata(md);
}

Id deployJobId = Metadata.Operations.enqueueDeployment(mdContainer, null);
System.debug('Enqueued talk-track update job: ' + deployJobId);
System.debug('Records updated: ' + tracks.size());
