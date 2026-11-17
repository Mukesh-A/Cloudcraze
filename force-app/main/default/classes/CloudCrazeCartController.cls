public with sharing class CloudCrazeCartController {
    public CloudCrazeCartController(CloudCrazeProductTestController controller) {
        
    }
    public class CartItemData {
    public String cartItemId { get; set; }
    public String productId { get; set; }
    public String productName { get; set; }
    public Decimal price { get; set; }
    public Decimal quantity { get; set; }
    public Decimal subtotal { get; set; }
    public String imageUrl { get; set; }
}

    public class CartResponse {
    public Boolean success { get; set; }
    public String message { get; set; }
    public String cartId { get; set; }
    public String cartItemId { get; set; }
    public Integer quantity { get; set; }

    public List<CartItemData> items {get;set;}
      public CartResponse() {
            success = false;
            items = new List<CartItemData>();
        }
}

    @RemoteAction
    public static String checkActiveCart(){
       Id currentUserId = UserInfo.getUserId();

       List<ccrz__E_Cart__c> carts = [select id,ccrz__CartId__c, ccrz__ActiveCart__c,
           ccrz__CartStatus__c, ccrz__Storefront__c from ccrz__E_Cart__c WHERE ccrz__User__c = :currentUserId
            AND ccrz__ActiveCart__c = true
            AND ccrz__Storefront__c = 'DefaultStore'
            ORDER BY CreatedDate DESC
            LIMIT 1];
            if(!carts.isEmpty()){
                return String.valueOf(carts[0].Id);
            }
       ccrz__E_Cart__c newCart = new ccrz__E_Cart__c();

        newCart.ccrz__User__c = currentUserId;
        newCart.ccrz__CartStatus__c = 'Open';
        newCart.ccrz__CartType__c = 'Cart';
        newCart.ccrz__ActiveCart__c = true;
        newCart.ccrz__Storefront__c = 'DefaultStore';

        try {
            insert newCart;
            return String.valueOf(newCart.Id);
            } catch (DmlException e) {
                return 'CART_CREATION_ERROR: ' + e.getDmlMessage(0);
            }
        }

        @RemoteAction
        public static CartResponse addToCart(String productId, Integer quantity) {

        CartResponse response = new CartResponse();
        response.success = false;
        try {
            if (String.isBlank(productId) || quantity == null || quantity < 1) {
                response.message = 'Invalid product or quantity';
                return response;
            }

            // Find the active cart
            List<ccrz__E_Cart__c> carts = [
                SELECT Id
                FROM ccrz__E_Cart__c
                WHERE ccrz__User__c = :UserInfo.getUserId()
                AND ccrz__ActiveCart__c = true
                AND ccrz__Storefront__c = 'DefaultStore'
                LIMIT 1
            ];

            if (carts.isEmpty()) {
                response.message = 'No active cart found';
                return response;
            }

            // Find the selected product
            ccrz__E_Product__c product = [
                SELECT Id
                FROM ccrz__E_Product__c
                WHERE Id = :productId
                AND ccrz__ProductStatus__c = 'Released'
                LIMIT 1
            ];

            // Find an active price for the product
            Date today = Date.today();

            List<ccrz__E_PriceListItem__c> prices = [
                SELECT Id, ccrz__Price__c
                FROM ccrz__E_PriceListItem__c
                WHERE ccrz__Product__c = :product.Id
                AND ccrz__StartDate__c <= :today
                AND ccrz__EndDate__c >= :today
                LIMIT 1
            ];

            if (prices.isEmpty()) {
                response.message = 'No active price found';
                return response;
            }

            // Check whether this product is already in the cart
            List<ccrz__E_CartItem__c> items = [
                SELECT Id, ccrz__Quantity__c
                FROM ccrz__E_CartItem__c
                WHERE ccrz__Cart__c = :carts[0].Id
                AND ccrz__Product__c = :product.Id
                LIMIT 1
            ];
            ccrz__E_CartItem__c cartItem;
            Integer finalQuantity;

            if (!items.isEmpty()) {
                 cartItem = items[0];
                finalQuantity = Integer.valueOf(cartItem.ccrz__Quantity__c) + quantity;

                cartItem.ccrz__Quantity__c = finalQuantity;
                update cartItem;
            } else {
                ccrz__E_CartItem__c newItem = new ccrz__E_CartItem__c();
                newItem.ccrz__Cart__c = carts[0].Id;
                newItem.ccrz__Product__c = product.Id;
                newItem.ccrz__Quantity__c = quantity;
                newItem.ccrz__Price__c = prices[0].ccrz__Price__c;
                newItem.ccrz__ItemStatus__c = 'Available';

                insert newItem;
            }
              response.success = true;
                response.message = 'Product added successfully';
                response.cartId = String.valueOf(carts[0].Id);
                response.cartItemId = String.valueOf(cartItem.Id);
                response.quantity = finalQuantity;


        } catch (Exception e) {
              response.success = false;
        response.message = e.getMessage();
        }
        return response;
    }

    //Get all items from the active cart.
    @RemoteAction
    public static CartResponse getCartItems(){
        CartResponse response = new CartResponse();

        try {

            List<ccrz__E_Cart__c> carts = [
                SELECT Id
                FROM ccrz__E_Cart__c
                WHERE ccrz__User__c = :UserInfo.getUserId()
                AND ccrz__ActiveCart__c = true
                AND ccrz__Storefront__c = 'DefaultStore'
                LIMIT 1
            ];

            if(carts.isEmpty()){
                response.success = true;
                response.message = 'No active Cart Found';
                return response;
            }

            // Fetch cart items
            List<ccrz__E_CartItem__c> cartItems = [
                SELECT Id,
                       ccrz__Product__c,
                       ccrz__Product__r.Name,
                       ccrz__Price__c,
                       ccrz__Quantity__c,
                       ccrz__ItemTotal__c
                FROM ccrz__E_CartItem__c
                WHERE ccrz__Cart__c = :carts[0].Id
                AND ccrz__ItemStatus__c = 'Available'
            ];


            // Collect product IDs from cart items
            Set<Id> productIds = new Set<Id>();

            for (ccrz__E_CartItem__c item : cartItems) {
                if (item.ccrz__Product__c != null) {
                    productIds.add(item.ccrz__Product__c);
                }
            }

            // Find files linked to products
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

            // Collect Content Document IDs
            Set<Id> documentIds = new Set<Id>();
            documentIds.addAll(documentByProduct.values());

            // Map product IDs to image URLs
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


            for(ccrz__E_CartItem__c item : cartItems){
                CartItemData data = new CartItemData();
                data.cartItemId = String.valueOf(item.id);
                data.productId = String.valueOf(item.ccrz__Product__c);
                data.productName = item.ccrz__Product__r.Name;
                data.price = item.ccrz__Price__c;
                data.quantity = item.ccrz__Quantity__c;
                data.subtotal = item.ccrz__ItemTotal__c;
                data.imageUrl = imageByProduct.get(item.ccrz__Product__c);
                response.items.add(data);
            }
            response.success = true;
            response.message = 'Cart items retrieved successfully';
            response.cartId = String.valueOf(carts[0].Id);

            
        } catch (Exception e) {
             response.success = false;
            response.message = e.getMessage();
        }
        return response;
    }

    @RemoteAction
    public static CartResponse updateCartItemQuantity(String cartItemId, Integer quantity){

        CartResponse response = new CartResponse();

        try {

          if(quantity == null || String.isBlank(cartItemId) || quantity < 1){
            response.message = 'Invalid cart Item or quantity';
            return response;
          }
            Id currentUserId = UserInfo.getUserId();

            List<ccrz__E_Cart__c> carts = [
            SELECT Id
            FROM ccrz__E_Cart__c
            WHERE ccrz__User__c = :currentUserId
            AND ccrz__ActiveCart__c = true
            AND ccrz__Storefront__c = 'DefaultStore'
            LIMIT 1];

            if(carts.isEmpty()){
                response.message =  'Active Cart not Available';
                return response;
            }

            List<ccrz__E_CartItem__c> items = [
            SELECT Id, ccrz__Quantity__c
            FROM ccrz__E_CartItem__c
            WHERE Id = :cartItemId
            AND ccrz__Cart__c = :carts[0].Id
            LIMIT 1];

            if(items.isEmpty()){
                response.message = 'Cart item not found';
                return response;
            }
            
            items[0].ccrz__Quantity__c = quantity;
            update items;

            response.success = true;
            response.cartItemId = String.valueOf(items[0].Id);
            response.quantity = quantity;
            response.message = 'Cart quantity updated successfully.';

            return response;
         

        } catch (Exception e) {

            response.success = false;
            response.message = e.getMessage();
       
    }
    return response;
    }

    
}