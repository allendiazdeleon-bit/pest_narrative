/**
 * ServiceAreaValidator — Agentforce-invocable address validation.
 *
 * Returns whether an address is in Massey's serviceable footprint (Orange
 * + Seminole County, FL — the Orlando branch demo area), using
 * Service_Boundary__mdt as the reference table. Also returns a
 * canonicalized address and (if the customer is on file) a matched AssetId.
 *
 * Used in Scene 4 (David Kim's self-service signup at massey-portal):
 * confirms his Lake Nona address is inside the Orlando branch service area
 * before the plan picker renders.
 */
public with sharing class ServiceAreaValidator {

    public class Request {
        @InvocableVariable(required=true) public String addressString;
    }

    public class Response {
        @InvocableVariable public Boolean inServiceArea;
        @InvocableVariable public String canonicalAddress;
        @InvocableVariable public Decimal latitude;
        @InvocableVariable public Decimal longitude;
        @InvocableVariable public Id matchedAssetId;
        @InvocableVariable public String message;
    }

    @InvocableMethod(label='Validate Service Area' description='Check whether an address is inside Massey\'s Orlando branch serviceable footprint (Orange + Seminole County, FL).')
    public static List<Response> validate(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response resp = new Response();
            ExternalGeocoder.GeocodeResult geo = ExternalGeocoder.getCoordinates(r.addressString);
            if (geo == null) {
                resp.inServiceArea = false;
                resp.message = 'Address could not be matched to any Service_Boundary__mdt row.';
            } else {
                resp.inServiceArea = geo.inServiceArea;
                resp.canonicalAddress = geo.canonicalAddress;
                resp.latitude = geo.latitude;
                resp.longitude = geo.longitude;
                resp.message = geo.inServiceArea
                    ? 'Address is inside the Orlando branch service area: ' + geo.canonicalAddress
                    : 'Address is outside the Orlando branch service area: ' + geo.canonicalAddress;

                // Best-effort match to an existing property Asset by name fragment
                String pattern = '%' + r.addressString.substringBefore(' ') + '%';
                List<Asset> assets = [SELECT Id FROM Asset WHERE Name LIKE :pattern LIMIT 1];
                if (!assets.isEmpty()) {
                    resp.matchedAssetId = assets[0].Id;
                }
            }
            out.add(resp);
        }
        return out;
    }
}
