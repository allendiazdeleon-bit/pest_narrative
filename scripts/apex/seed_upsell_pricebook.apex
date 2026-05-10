// Seeds Pricebook2 + Product2 + PricebookEntry rows used by the upsell-quote
// flow. Reads pricing from Upsell_Pricing__mdt and creates:
//   - 1 custom Pricebook2 ("Massey Pest Pricebook")
//   - 2 Product2 per SKU (Install + Monthly Service) + 1 "Bundle Discount" product
//   - PricebookEntry on standard + Massey pricebooks for each Product2
//
// Idempotent: SOQL guards on ProductCode + Pricebook+Product combo. Reruns
// are no-ops or fill in missing rows.
//
// Run AFTER deploying Upsell_Pricing__mdt records.
//   sf apex run --file scripts/apex/seed_upsell_pricebook.apex --target-org <alias>

final String MASSEY_PRICEBOOK = 'Massey Pest Pricebook';
final String DISCOUNT_PRODUCT_CODE = 'BUNDLE_DISCOUNT';

// 1. Pricebook2 — find or create the Massey pricebook
Pricebook2 standardPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];

Pricebook2 masseyPb;
List<Pricebook2> existingMasseyPb = [SELECT Id, Name, IsActive FROM Pricebook2
                                      WHERE Name = :MASSEY_PRICEBOOK LIMIT 1];
if (existingMasseyPb.isEmpty()) {
    masseyPb = new Pricebook2(Name = MASSEY_PRICEBOOK, IsActive = true,
                               Description = 'Massey Services rate card for upsell quoting (auto-seeded).');
    insert masseyPb;
} else {
    masseyPb = existingMasseyPb[0];
    if (!masseyPb.IsActive) { masseyPb.IsActive = true; update masseyPb; }
}

// 2. Product2 — one Install + one Monthly per pricing tier, plus a Bundle Discount product
Map<String, Upsell_Pricing__mdt> pricingBySku = new Map<String, Upsell_Pricing__mdt>();
for (Upsell_Pricing__mdt p : [SELECT Sku__c, Display_Name__c, Install_Fee__c,
                                     Monthly_Service__c, Service_Line__c, Active__c
                              FROM Upsell_Pricing__mdt WHERE Active__c = true]) {
    pricingBySku.put(p.Sku__c, p);
}

if (pricingBySku.isEmpty()) {
    System.debug(LoggingLevel.WARN,
        'No active Upsell_Pricing__mdt records found. Deploy the CMT records first.');
    return;
}

Set<String> wantedCodes = new Set<String>{ DISCOUNT_PRODUCT_CODE };
for (String sku : pricingBySku.keySet()) {
    wantedCodes.add(sku + '_INSTALL');
    wantedCodes.add(sku + '_MONTHLY');
}

Map<String, Product2> existingProducts = new Map<String, Product2>();
for (Product2 p : [SELECT Id, Name, ProductCode, IsActive FROM Product2 WHERE ProductCode IN :wantedCodes]) {
    existingProducts.put(p.ProductCode, p);
}

List<Product2> productsToInsert = new List<Product2>();
for (String sku : pricingBySku.keySet()) {
    Upsell_Pricing__mdt p = pricingBySku.get(sku);
    String installCode = sku + '_INSTALL';
    String monthlyCode = sku + '_MONTHLY';
    if (!existingProducts.containsKey(installCode)) {
        productsToInsert.add(new Product2(
            Name = p.Display_Name__c + ' — Install',
            ProductCode = installCode,
            Family = p.Service_Line__c,
            IsActive = true,
            Description = 'One-time install/setup fee for ' + p.Display_Name__c + '.'
        ));
    }
    if (!existingProducts.containsKey(monthlyCode)) {
        productsToInsert.add(new Product2(
            Name = p.Display_Name__c + ' — Monthly Service',
            ProductCode = monthlyCode,
            Family = p.Service_Line__c,
            IsActive = true,
            Description = 'Recurring monthly service fee for ' + p.Display_Name__c + '. Quote line uses Quantity = 12 for Y1.'
        ));
    }
}
if (!existingProducts.containsKey(DISCOUNT_PRODUCT_CODE)) {
    productsToInsert.add(new Product2(
        Name = 'Bundle Discount',
        ProductCode = DISCOUNT_PRODUCT_CODE,
        Family = 'Discount',
        IsActive = true,
        Description = 'Negative-amount line item used to apply existing-customer bundle discounts on upsell quotes.'
    ));
}
if (!productsToInsert.isEmpty()) insert productsToInsert;

// Re-query so we have all Product2 ids
existingProducts = new Map<String, Product2>();
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE ProductCode IN :wantedCodes]) {
    existingProducts.put(p.ProductCode, p);
}

// 3. PricebookEntry — standard + Massey, one per Product2
Set<Id> productIds = new Set<Id>();
for (Product2 p : existingProducts.values()) productIds.add(p.Id);

Set<String> existingPbeKey = new Set<String>();   // key: pricebook2Id|product2Id
for (PricebookEntry pbe : [SELECT Pricebook2Id, Product2Id FROM PricebookEntry WHERE Product2Id IN :productIds]) {
    existingPbeKey.add(pbe.Pricebook2Id + '|' + pbe.Product2Id);
}

List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
for (String sku : pricingBySku.keySet()) {
    Upsell_Pricing__mdt p = pricingBySku.get(sku);
    Decimal installPrice = p.Install_Fee__c != null ? p.Install_Fee__c : 0;
    Decimal monthlyPrice = p.Monthly_Service__c != null ? p.Monthly_Service__c : 0;
    Product2 installProd = existingProducts.get(sku + '_INSTALL');
    Product2 monthlyProd = existingProducts.get(sku + '_MONTHLY');
    for (Pricebook2 pb : new List<Pricebook2>{ standardPb, masseyPb }) {
        if (installProd != null) {
            String key = pb.Id + '|' + installProd.Id;
            if (!existingPbeKey.contains(key)) {
                pbesToInsert.add(new PricebookEntry(
                    Pricebook2Id = pb.Id, Product2Id = installProd.Id,
                    UnitPrice = installPrice, IsActive = true, UseStandardPrice = false
                ));
                existingPbeKey.add(key);
            }
        }
        if (monthlyProd != null) {
            String key = pb.Id + '|' + monthlyProd.Id;
            if (!existingPbeKey.contains(key)) {
                pbesToInsert.add(new PricebookEntry(
                    Pricebook2Id = pb.Id, Product2Id = monthlyProd.Id,
                    UnitPrice = monthlyPrice, IsActive = true, UseStandardPrice = false
                ));
                existingPbeKey.add(key);
            }
        }
    }
}

// Bundle Discount PBE — UnitPrice 0; the QLI sets a per-quote negative price
Product2 discountProd = existingProducts.get(DISCOUNT_PRODUCT_CODE);
if (discountProd != null) {
    for (Pricebook2 pb : new List<Pricebook2>{ standardPb, masseyPb }) {
        String key = pb.Id + '|' + discountProd.Id;
        if (!existingPbeKey.contains(key)) {
            pbesToInsert.add(new PricebookEntry(
                Pricebook2Id = pb.Id, Product2Id = discountProd.Id,
                UnitPrice = 0, IsActive = true, UseStandardPrice = false
            ));
        }
    }
}

if (!pbesToInsert.isEmpty()) insert pbesToInsert;

System.debug('Pricebook2 (Massey):     ' + masseyPb.Id);
System.debug('Standard Pricebook2:     ' + standardPb.Id);
System.debug('Product2 records total:  ' + existingProducts.size());
System.debug('PricebookEntry inserted: ' + pbesToInsert.size());
System.debug('Pricing tiers:           ' + String.join(new List<String>(pricingBySku.keySet()), ', '));
