/**
 * PropertyTreatmentHistoryService — synthesizes a property service
 * history view for the masseyFlow demo's property-history LWC.
 *
 * Returns the bait-station / mosquito-system / treatment-perimeter
 * topology around an Asset on a property. For Termite (Sentricon):
 * Property → perimeter ring of Sentricon stations + interior stations.
 * For Mosquito: Property → mosquito-system controller + nozzle layout.
 * For Pest / Lawn: Property → interior trap zones + treatment perimeter.
 * Asset.Service_Line__c on the seed Asset selects which traversal to
 * render; Equipment_Type__c identifies what each node along the path is.
 *
 * No real GIS. Coordinates are derived deterministically from the seed
 * Account's BillingStreet so the same address always produces the same
 * map. Surrounding nodes are pulled from nearby route Accounts (the
 * next 6-8 after the seed in alphabetical/Id order) so the demo data
 * graph drives what shows up.
 *
 * Returns:
 *  - PropertyTopology (nodes + edges + center) for an Asset or Incident
 *  - ImpactArea showing which downstream properties on the route lose
 *    a station / nozzle when a given perimeter leg is taken offline
 *    (e.g., a tree comes down on a Sentricon ring).
 *
 * Demo-only. Side-effect-free synthesis, no DML, no callouts.
 *
 * Public method signatures preserved from the inherited topology
 * service so existing LWC bindings continue to resolve.
 */
public with sharing class PropertyTreatmentHistoryService {

    // Orlando rough center — all synthesized coordinates float around here
    private static final Decimal BASE_LAT = 28.5384;
    private static final Decimal BASE_LON = -81.3789;

    // Approx degrees per ~100ft at this latitude (rough, demo-only)
    private static final Decimal LAT_STEP = 0.00027;
    private static final Decimal LON_STEP = 0.00031;

    // Keywords that flag a property as high priority on the impact area
    private static final Map<String, String> PRIORITY_KEYWORDS = new Map<String, String>{
        'school'    => 'School in route area',
        'daycare'   => 'Daycare in route area',
        'clinic'    => 'Medical clinic in route area',
        'hospital'  => 'Hospital in route area',
        'nursing'   => 'Nursing home in route area',
        'apiary'    => 'Apiary in route area (avoid drift)'
    };

    // ---------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------

    public class PropertyNode {
        @AuraEnabled public String id;
        // For Termite: 'Property','Sentricon_Station','Treatment_Perimeter'
        // For Mosquito: 'Property','Mosquito_System','Mosquito_Nozzle'
        // For Pest/Lawn: 'Property','Trap','Treatment_Perimeter'
        @AuraEnabled public String nodeType;
        @AuraEnabled public String label;
        // Stations: Untouched/Activity/Heavy_Activity/Replaced
        // Properties / nozzles: Active/Inactive
        @AuraEnabled public String state;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String accountName;
    }

    public class PropertyEdge {
        @AuraEnabled public String id;
        @AuraEnabled public String fromNodeId;
        @AuraEnabled public String toNodeId;
        // 'Perimeter' (between property center and station / nozzle on perimeter)
        // 'Interior' (between property center and interior trap)
        @AuraEnabled public String edgeType;
        // Spec: '5ft station spacing','10ft nozzle spacing','interior'
        @AuraEnabled public String spec;
        @AuraEnabled public Boolean flowing;
    }

    public class PropertyTopology {
        @AuraEnabled public Decimal centerLatitude;
        @AuraEnabled public Decimal centerLongitude;
        @AuraEnabled public List<PropertyNode> nodes;
        @AuraEnabled public List<PropertyEdge> edges;
        @AuraEnabled public String summary;

        public PropertyTopology() {
            this.nodes = new List<PropertyNode>();
            this.edges = new List<PropertyEdge>();
        }
    }

    public class ImpactArea {
        // Identifier of the perimeter leg / interior zone whose offline
        // status is being previewed. Field name preserved for binary
        // compat with existing LWC callers.
        @AuraEnabled public String closedValveId;
        @AuraEnabled public List<String> affectedNodeIds;
        @AuraEnabled public List<Id> affectedAccountIds;
        @AuraEnabled public List<String> affectedAccountNames;
        @AuraEnabled public Integer affectedCount;
        @AuraEnabled public List<String> highPriorityFlags;

        public ImpactArea() {
            this.affectedNodeIds = new List<String>();
            this.affectedAccountIds = new List<Id>();
            this.affectedAccountNames = new List<String>();
            this.highPriorityFlags = new List<String>();
            this.affectedCount = 0;
        }
    }

    // ---------------------------------------------------------------------
    // Public entry points (signatures preserved so callers don't break)
    // ---------------------------------------------------------------------

    /**
     * Returns a synthesized property topology centered on the asset's
     * account location with ~6-8 nearby route properties (Sentricon
     * stations for Termite, mosquito systems for Mosquito, traps for
     * Pest/Lawn), 2-3 perimeter legs, 1-2 interior zones, and the
     * connecting paths.
     */
    @AuraEnabled(cacheable=true)
    public static PropertyTopology getTopologyAroundAsset(Id assetId) {
        if (assetId == null) {
            throw new AuraHandledException('assetId is required.');
        }

        Asset seed;
        try {
            seed = [SELECT Id, Name, SerialNumber, AccountId, Account.Name, Account.BillingStreet,
                           Account.BillingCity, Account.BillingPostalCode,
                           Service_Line__c, Equipment_Type__c,
                           Service_Group__c, Bait_Station_State__c,
                           Property_Type__c
                    FROM Asset WHERE Id = :assetId LIMIT 1];
        } catch (QueryException qe) {
            throw new AuraHandledException('Asset not found: ' + assetId);
        }

        List<Account> nearby = fetchNearbyAccounts(seed.AccountId, 8);
        return buildTopology(seed, nearby);
    }

    /**
     * Returns a topology covering all assets linked to Cases on this
     * Incident (via Case.Linked_Incident__c). Centers on the first
     * asset's account; surrounding properties are the other case-linked
     * assets plus a few neighbors to flesh out the route map.
     */
    @AuraEnabled(cacheable=true)
    public static PropertyTopology getTopologyForIncident(Id incidentId) {
        if (incidentId == null) {
            throw new AuraHandledException('incidentId is required.');
        }

        List<Case> linked = [
            SELECT Id, AccountId, AssetId, Account.Name, Account.BillingStreet,
                   Account.BillingCity, Account.BillingPostalCode,
                   Asset.Id, Asset.Name, Asset.SerialNumber, Asset.AccountId
            FROM Case
            WHERE Linked_Incident__c = :incidentId
              AND AssetId != null
            ORDER BY CreatedDate ASC
        ];

        if (linked.isEmpty()) {
            PropertyTopology empty = new PropertyTopology();
            empty.centerLatitude = BASE_LAT;
            empty.centerLongitude = BASE_LON;
            empty.summary = 'No assets linked to this Incident yet.';
            return empty;
        }

        // Re-query the seed Asset with pest fields hydrated for centering
        Asset seed = [
            SELECT Id, Name, SerialNumber, AccountId, Account.Name,
                   Account.BillingStreet, Account.BillingCity, Account.BillingPostalCode,
                   Service_Line__c, Equipment_Type__c,
                   Service_Group__c, Bait_Station_State__c,
                   Property_Type__c
            FROM Asset WHERE Id = :linked[0].Asset.Id LIMIT 1
        ];

        // Collect the other affected accounts from the remaining cases
        List<Account> affectedAccounts = new List<Account>();
        Set<Id> seen = new Set<Id>{linked[0].AccountId};
        for (Integer i = 1; i < linked.size(); i++) {
            Case c = linked[i];
            if (c.AccountId == null || seen.contains(c.AccountId)) continue;
            seen.add(c.AccountId);
            affectedAccounts.add(new Account(
                Id = c.AccountId,
                Name = c.Account.Name,
                BillingStreet = c.Account.BillingStreet,
                BillingCity = c.Account.BillingCity,
                BillingPostalCode = c.Account.BillingPostalCode
            ));
        }

        // Top up to ~7 surrounding properties by pulling additional nearby accounts
        Integer needed = 7 - affectedAccounts.size();
        if (needed > 0) {
            for (Account a : fetchNearbyAccounts(linked[0].AccountId, needed + seen.size())) {
                if (seen.contains(a.Id)) continue;
                affectedAccounts.add(a);
                seen.add(a.Id);
                if (affectedAccounts.size() >= 7) break;
            }
        }

        PropertyTopology topo = buildTopology(seed, affectedAccounts);
        topo.summary = 'Affected route area for cluster Incident — '
            + linked.size() + ' linked Case(s), '
            + topo.nodes.size() + ' property nodes mapped.';
        return topo;
    }

    /**
     * Returns the impact area for taking a given perimeter leg offline
     * (e.g., a Sentricon ring section blocked by a fallen tree, or a
     * mosquito-system zone that needs valve isolation for service).
     * Picks ~3-5 of the nearby properties as "downstream" of the leg
     * (deterministic by leg id) and reports them.
     *
     * Method name preserved (`previewValveClose`) for caller binary
     * compat; the parameter `valveNodeId` likewise still names the leg
     * node id chosen on the map.
     */
    @AuraEnabled(cacheable=false)
    public static ImpactArea previewValveClose(Id assetId, String valveNodeId) {
        if (assetId == null || String.isBlank(valveNodeId)) {
            throw new AuraHandledException('assetId and valveNodeId are required.');
        }

        PropertyTopology topo = getTopologyAroundAsset(assetId);

        // Confirm the leg actually exists on this topology — perimeter
        // legs and interior zones are both isolation points.
        PropertyNode leg;
        for (PropertyNode n : topo.nodes) {
            if (n.id == valveNodeId && (n.nodeType == 'Treatment_Perimeter' || n.nodeType == 'Mosquito_Nozzle')) {
                leg = n;
                break;
            }
        }
        if (leg == null) {
            throw new AuraHandledException('Perimeter leg ' + valveNodeId + ' not found on topology.');
        }

        // Collect all property endpoints on the topology
        List<PropertyNode> endpoints = new List<PropertyNode>();
        for (PropertyNode n : topo.nodes) {
            if (n.nodeType == 'Sentricon_Station' || n.nodeType == 'Trap' || n.nodeType == 'Property') endpoints.add(n);
        }

        // Deterministic downstream selection: hash the leg id to pick a
        // contiguous slice of endpoints. Slice size 3-5 depending on leg.
        Integer h = Math.abs(valveNodeId.hashCode());
        Integer sliceSize = 3 + Math.mod(h, 3);  // 3, 4, or 5
        if (sliceSize > endpoints.size()) sliceSize = endpoints.size();
        Integer start = endpoints.isEmpty() ? 0 : Math.mod(h / 7, endpoints.size());

        ImpactArea area = new ImpactArea();
        area.closedValveId = valveNodeId;

        for (Integer i = 0; i < sliceSize; i++) {
            PropertyNode m = endpoints[Math.mod(start + i, endpoints.size())];
            area.affectedNodeIds.add(m.id);
            if (m.accountName != null) area.affectedAccountNames.add(m.accountName);
        }

        // Pull AccountIds for the affected property assets in one query
        Set<Id> endpointAssetIds = new Set<Id>();
        for (Integer i = 0; i < sliceSize; i++) {
            PropertyNode m = endpoints[Math.mod(start + i, endpoints.size())];
            if (m.assetId != null) endpointAssetIds.add(m.assetId);
        }
        if (!endpointAssetIds.isEmpty()) {
            for (Asset a : [SELECT Id, AccountId FROM Asset WHERE Id IN :endpointAssetIds]) {
                if (a.AccountId != null) area.affectedAccountIds.add(a.AccountId);
            }
        }

        area.affectedCount = area.affectedNodeIds.size();
        area.highPriorityFlags = scanForPriority(area.affectedAccountNames);
        return area;
    }

    // ---------------------------------------------------------------------
    // Synthesis helpers
    // ---------------------------------------------------------------------

    /**
     * Pull up to `max` nearby Accounts from the same route. "Nearby" is
     * faked as the next Person Accounts after the seed in deterministic
     * order, excluding the seed itself. Filters to Accounts that own a
     * property Asset (Sentricon station, mosquito system, or property
     * trap) — these are the route's serviceable properties in the demo.
     */
    private static List<Account> fetchNearbyAccounts(Id seedAccountId, Integer max) {
        List<Account> out = new List<Account>();
        if (seedAccountId == null) return out;

        for (Account a : [
            SELECT Id, Name, BillingStreet, BillingCity, BillingPostalCode
            FROM Account
            WHERE Id != :seedAccountId
              AND IsPersonAccount = true
              AND BillingStreet != null
              AND Id IN (
                  SELECT AccountId FROM Asset
                  WHERE Equipment_Type__c IN ('Sentricon_Station','Mosquito_System','Property','Trap','Treatment_Perimeter')
              )
            ORDER BY Name ASC
            LIMIT :max
        ]) {
            out.add(a);
        }
        return out;
    }

    /**
     * Build the full property-treatment topology. Pest-shaped:
     *   Termite:   Property → perimeter ring → Sentricon stations
     *   Mosquito:  Property → controller → nozzle layout
     *   Pest/Lawn: Property → interior trap zones + treatment perimeter
     * The seed Asset's Service_Line__c selects the variant.
     */
    private static PropertyTopology buildTopology(Asset seed, List<Account> nearby) {
        PropertyTopology topo = new PropertyTopology();

        Decimal[] center = seedCoordinates(seed.Account != null ? seed.Account.BillingStreet : null);
        topo.centerLatitude = center[0];
        topo.centerLongitude = center[1];

        Boolean isMosquito = (seed.Service_Line__c == 'Mosquito');
        Boolean isTermite = (seed.Service_Line__c == 'Termite');

        // Vocabulary that flips by service line
        String rootType     = 'Property';
        String legType      = isMosquito ? 'Mosquito_Nozzle' : 'Treatment_Perimeter';
        String endpointType = isTermite ? 'Sentricon_Station' : (isMosquito ? 'Mosquito_System' : 'Trap');
        String interiorZoneType   = isTermite ? 'Treatment_Perimeter' : 'Treatment_Perimeter';
        String perimeterSpec = isTermite ? '10ft station spacing' : (isMosquito ? '15ft nozzle spacing' : '5ft trap spacing');
        String interiorSpec  = 'interior';

        // 1. Property root — labeled by Service_Group__c when present
        PropertyNode root = new PropertyNode();
        root.id = 'PROP-' + safeShortId(seed.Id);
        root.nodeType = rootType;
        root.label = String.isNotBlank(seed.Service_Group__c)
            ? 'Property — route ' + seed.Service_Group__c
            : 'Property — route';
        root.latitude = center[0];
        root.longitude = center[1];
        topo.nodes.add(root);

        // 2. The seed property's service endpoint itself (Sentricon for
        //    Termite, mosquito system for Mosquito, trap for Pest/Lawn)
        PropertyNode seedEndpoint = buildEndpointNode(
            endpointType,
            seed.Id,
            seed.Account != null ? seed.Account.Name : 'Seed Account',
            center[0] + LAT_STEP * 0.4,
            center[1] + LON_STEP * 0.4,
            seed.Bait_Station_State__c
        );
        topo.nodes.add(seedEndpoint);
        topo.edges.add(buildEdge('Interior', root.id, seedEndpoint.id, interiorSpec, true));

        // 3. Surrounding properties from nearby route accounts. We need
        //    each one's Asset Id, so query their property Assets.
        Map<Id, Asset> endpointByAccount = endpointAssetsByAccount(nearby);

        Integer placed = 0;
        Integer count = nearby.size();
        for (Integer i = 0; i < count && placed < 8; i++) {
            Account a = nearby[i];
            // Ring positions around center — angle by index, radius 1-2 steps out
            Decimal angle = (Math.PI * 2 * i) / Math.max(count, 1);
            Decimal radius = 1.2 + Math.mod(i, 3) * 0.6;
            Decimal lat = center[0] + LAT_STEP * radius * Decimal.valueOf(Math.cos(angle.doubleValue()));
            Decimal lon = center[1] + LON_STEP * radius * Decimal.valueOf(Math.sin(angle.doubleValue()));

            Asset endpointAsset = endpointByAccount.get(a.Id);
            Id endpointAssetId = endpointAsset != null ? endpointAsset.Id : null;
            String state = endpointAsset != null ? endpointAsset.Bait_Station_State__c : null;
            PropertyNode ep = buildEndpointNode(endpointType, endpointAssetId, a.Name, lat, lon, state);
            topo.nodes.add(ep);
            topo.edges.add(buildEdge('Interior', root.id, ep.id, interiorSpec, true));
            placed++;
        }

        // 4. Perimeter legs (Termite/Pest/Lawn) or nozzle zones (Mosquito).
        //    These are the isolation points reported by previewValveClose.
        Integer legCount = (placed >= 6) ? 3 : 2;
        for (Integer v = 0; v < legCount; v++) {
            Decimal angle = (Math.PI * 2 * v) / legCount + Math.PI / 4;
            PropertyNode legNode = new PropertyNode();
            legNode.id = (isMosquito ? 'NOZ-' : 'PER-') + String.valueOf(v + 1).leftPad(2, '0');
            legNode.nodeType = legType;
            legNode.label = (isMosquito ? 'Nozzle zone ' : 'Perimeter leg ') + (v + 1);
            legNode.state = 'Active';
            legNode.latitude = center[0] + LAT_STEP * 2.4 * Decimal.valueOf(Math.cos(angle.doubleValue()));
            legNode.longitude = center[1] + LON_STEP * 2.4 * Decimal.valueOf(Math.sin(angle.doubleValue()));
            topo.nodes.add(legNode);
            topo.edges.add(buildEdge('Perimeter', root.id, legNode.id, perimeterSpec, true));
        }

        // 5. Interior treatment zones — passive features at corners
        Integer interiorZoneCount = (placed >= 5) ? 2 : 1;
        for (Integer hIdx = 0; hIdx < interiorZoneCount; hIdx++) {
            Decimal angle = Math.PI * (0.75 + hIdx * 0.5);
            PropertyNode zoneNode = new PropertyNode();
            zoneNode.id = 'INT-' + String.valueOf(hIdx + 1).leftPad(2, '0');
            zoneNode.nodeType = interiorZoneType;
            zoneNode.label = 'Interior treatment zone ' + (hIdx + 1);
            zoneNode.state = 'Available';
            zoneNode.latitude = center[0] + LAT_STEP * 1.8 * Decimal.valueOf(Math.cos(angle.doubleValue()));
            zoneNode.longitude = center[1] + LON_STEP * 1.8 * Decimal.valueOf(Math.sin(angle.doubleValue()));
            topo.nodes.add(zoneNode);
            topo.edges.add(buildEdge('Perimeter', root.id, zoneNode.id, perimeterSpec, true));
        }

        topo.summary = 'Property treatment area — '
            + (isTermite ? 'Termite (Sentricon)' : (isMosquito ? 'Mosquito system' : 'Pest / Lawn'))
            + ' — ' + topo.nodes.size() + ' nodes, '
            + topo.edges.size() + ' segments centered on '
            + (seed.Account != null && seed.Account.BillingStreet != null
                ? seed.Account.BillingStreet
                : 'service location') + '.';
        return topo;
    }

    /**
     * Return last treatment summary for an Account: most recent service
     * visit date, last EPA reg # used, and the property's pest pressure
     * trend over the last quarterly cycle. Used by the agent-side
     * Property History panel and by KnowledgeArticleSuggester to anchor
     * "what was tried last time" recommendations.
     */
    @AuraEnabled(cacheable=true)
    public static List<Asset> getPriorTreatments(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('accountId is required.');
        }
        return [
            SELECT Id, Name, Service_Line__c, Equipment_Type__c,
                   Bait_Station_State__c, Bait_Station_Hits_30d__c,
                   Last_Bait_Station_Hit_Date__c, Last_Treatment_DateTime__c,
                   Days_Since_Last_Service__c, EPA_Reg_Number_Last_Used__c,
                   Pest_Pressure_Score__c, Conducive_Conditions__c
            FROM Asset
            WHERE AccountId = :accountId
            ORDER BY Last_Treatment_DateTime__c DESC NULLS LAST
        ];
    }

    /**
     * Map AccountId -> Asset for the property service endpoint on each
     * supplied account.
     */
    private static Map<Id, Asset> endpointAssetsByAccount(List<Account> accounts) {
        Map<Id, Asset> out = new Map<Id, Asset>();
        if (accounts == null || accounts.isEmpty()) return out;

        Set<Id> acctIds = new Set<Id>();
        for (Account a : accounts) acctIds.add(a.Id);

        for (Asset a : [
            SELECT Id, AccountId, SerialNumber, Name, Equipment_Type__c, Bait_Station_State__c
            FROM Asset
            WHERE AccountId IN :acctIds
              AND Equipment_Type__c IN ('Sentricon_Station','Mosquito_System','Property','Trap')
        ]) {
            // First endpoint wins per account (1:1 in the demo data)
            if (!out.containsKey(a.AccountId)) out.put(a.AccountId, a);
        }
        return out;
    }

    private static PropertyNode buildEndpointNode(String endpointType, Id assetId, String accountName, Decimal lat, Decimal lon, String stationState) {
        PropertyNode n = new PropertyNode();
        String prefix;
        if (endpointType == 'Sentricon_Station') prefix = 'STN-';
        else if (endpointType == 'Mosquito_System') prefix = 'MSQ-';
        else if (endpointType == 'Trap') prefix = 'TRP-';
        else prefix = 'EP-';
        n.id = prefix + (assetId != null ? safeShortId(assetId) : String.valueOf(Math.abs((accountName + lat).hashCode())));
        n.nodeType = endpointType;
        n.label = accountName != null ? accountName : endpointType;
        n.state = String.isNotBlank(stationState) ? stationState : 'Active';
        n.latitude = lat;
        n.longitude = lon;
        n.assetId = assetId;
        n.accountName = accountName;
        return n;
    }

    private static PropertyEdge buildEdge(String type, String fromId, String toId, String spec, Boolean flowing) {
        PropertyEdge e = new PropertyEdge();
        e.id = 'EDG-' + fromId + '-' + toId;
        e.fromNodeId = fromId;
        e.toNodeId = toId;
        e.edgeType = type;
        e.spec = spec;
        e.flowing = flowing;
        return e;
    }

    /**
     * Derive a deterministic lat/lon from a street string. Same address
     * always yields the same point. If we have no street, fall back to
     * the base point.
     */
    private static Decimal[] seedCoordinates(String street) {
        if (String.isBlank(street)) {
            return new Decimal[]{ BASE_LAT, BASE_LON };
        }
        Integer h = Math.abs(street.hashCode());
        // Spread across roughly a 2-mile box around base
        Decimal latOffset = LAT_STEP * (Math.mod(h, 200) - 100);
        Decimal lonOffset = LON_STEP * (Math.mod(h / 7, 200) - 100);
        return new Decimal[]{ BASE_LAT + latOffset, BASE_LON + lonOffset };
    }

    /**
     * Short form of an Id for use in synthetic node ids — just the
     * trailing 6 chars of the 18-char Id, safe across null.
     */
    private static String safeShortId(Id recId) {
        if (recId == null) return 'X';
        String s = String.valueOf(recId);
        return s.length() > 6 ? s.substring(s.length() - 6) : s;
    }

    /**
     * Scan affected account names for high-priority keywords. Returns
     * a deduplicated list of human-readable flags.
     */
    private static List<String> scanForPriority(List<String> names) {
        List<String> flags = new List<String>();
        Set<String> seen = new Set<String>();
        if (names == null) return flags;
        for (String name : names) {
            if (name == null) continue;
            String lower = name.toLowerCase();
            for (String key : PRIORITY_KEYWORDS.keySet()) {
                if (lower.contains(key)) {
                    String flag = PRIORITY_KEYWORDS.get(key);
                    if (!seen.contains(flag)) {
                        seen.add(flag);
                        flags.add(flag);
                    }
                }
            }
        }
        return flags;
    }
}
