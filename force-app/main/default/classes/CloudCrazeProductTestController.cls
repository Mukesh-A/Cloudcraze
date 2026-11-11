public with sharing class CloudCrazeProductTestController {

    public class ProductRow {
        public ccrz__E_Product__c product { get; set; }
        public Decimal price { get; set; }

        public ProductRow(
            ccrz__E_Product__c product,
            Decimal price
        ) {
            this.product = product;
            this.price = price;
        }
    }

    public List<ProductRow> productRows { get; private set; }

    public String message { get; private set; }

    public CloudCrazeProductTestController() {
        loadProducts();
    }

    private void loadProducts() {
        productRows = new List<ProductRow>();

        List<ccrz__E_Product__c> products = [
            SELECT Id, Name, ccrz__SKU__c,
                   ccrz__ProductStatus__c,
                   ccrz__ShortDesc__c
            FROM ccrz__E_Product__c
            WHERE ccrz__ProductStatus__c = 'Released'
            AND ccrz__Storefront__c INCLUDES ('DefaultStore')
            ORDER BY Name
        ];

        if (products.isEmpty()) {
            message = 'No released products found.';
            return;
        }

        Set<Id> productIds = new Set<Id>();

        for (ccrz__E_Product__c product : products) {
            productIds.add(product.Id);
        }

        Map<Id, Decimal> priceByProduct = new Map<Id, Decimal>();

        for (ccrz__E_PriceListItem__c item : [
            SELECT ccrz__Product__c, ccrz__Price__c
            FROM ccrz__E_PriceListItem__c
            WHERE ccrz__Product__c IN :productIds
            AND ccrz__Pricelist__r.Name = 'Demo Price List'
            AND ccrz__Pricelist__r.ccrz__Enabled__c = true
            ORDER BY CreatedDate ASC
        ]) {
            if (!priceByProduct.containsKey(item.ccrz__Product__c)) {
                priceByProduct.put(
                    item.ccrz__Product__c,
                    item.ccrz__Price__c
                );
            }
        }

        for (ccrz__E_Product__c product : products) {
            productRows.add(
                new ProductRow(
                    product,
                    priceByProduct.get(product.Id)
                )
            );
        }

        message = 'Products loaded: ' + productRows.size();
    }

    
    // Data format that JavaScript will receive
    public class ProductData {
        public String id { get; set; }
        public String name { get; set; }
        public Decimal price { get; set; }
         public String imageUrl { get; set; }
    }

    // Allows JavaScript to call Apex asynchronously
    @RemoteAction
    public static List<ProductData> getProducts() {

        List<ProductData> result = new List<ProductData>();

        // Get released products from the DefaultStore
        List<ccrz__E_Product__c> products = [
            SELECT Id, Name, ccrz__SKU__c
            FROM ccrz__E_Product__c
            WHERE ccrz__ProductStatus__c = 'Released'
            AND ccrz__Storefront__c INCLUDES ('DefaultStore')
            ORDER BY Name
        ];

        if (products.isEmpty()) {
            return result;
        }

        // Collect product record IDs
        Set<Id> productIds = new Set<Id>();

        for (ccrz__E_Product__c product : products) {
            productIds.add(product.Id);
        }

        // Get files linked to products
Map<Id, Id> documentByProduct = new Map<Id, Id>();

for (ContentDocumentLink link : [
    SELECT LinkedEntityId, ContentDocumentId
    FROM ContentDocumentLink
    WHERE LinkedEntityId IN :productIds
]) {
    documentByProduct.put(
        link.LinkedEntityId,
        link.ContentDocumentId
    );
}

// Get latest image versions
Set<Id> documentIds = new Set<Id>();
documentIds.addAll(documentByProduct.values());

Map<Id, String> imageByProduct = new Map<Id, String>();

for (ContentVersion version : [
    SELECT Id, ContentDocumentId
    FROM ContentVersion
    WHERE ContentDocumentId IN :documentIds
    AND IsLatest = true
]) {
    for (Id productId : documentByProduct.keySet()) {
        if (documentByProduct.get(productId) == version.ContentDocumentId) {
            imageByProduct.put(
                productId,
                '/sfc/servlet.shepherd/version/download/' + version.Id
            );
        }
    }
}

        // Find prices for those products
        Map<Id, Decimal> priceByProduct = new Map<Id, Decimal>();

        for (ccrz__E_PriceListItem__c item : [
            SELECT ccrz__Product__c, ccrz__Price__c
            FROM ccrz__E_PriceListItem__c
            WHERE ccrz__Product__c IN :productIds
            AND ccrz__Pricelist__r.Name = 'Demo Price List'
            AND ccrz__Pricelist__r.ccrz__Enabled__c = true
            ORDER BY CreatedDate ASC
        ]) {
            if (!priceByProduct.containsKey(item.ccrz__Product__c)) {
                priceByProduct.put(
                    item.ccrz__Product__c,
                    item.ccrz__Price__c
                );
            }
        }

        // Convert Salesforce records into JavaScript-friendly data
        for (ccrz__E_Product__c product : products) {

            ProductData data = new ProductData();

            data.id = String.valueOf(product.Id);
            data.name = product.Name;
            data.price = priceByProduct.get(product.Id);
            data.imageUrl = imageByProduct.get(product.Id);

            result.add(data);
        }

        return result;
    }

}