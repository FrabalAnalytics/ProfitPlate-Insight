# Inspect PO and GRN materials

On **Purchase Orders & GRNs**, choose **View materials & GRNs** next to an order. Its materials open inside the register, preserving the selected status and page.

The compact material table shows each material's unit, ordered quantity, accepted quantity, outstanding quantity, quoted unit price and line total. Quoted line totals include line discounts/tax. **Open full Purchase Order** retains the separate discount/tax breakdown, printing and the existing role-permitted actions.

The expanded order also lists its supplier GRNs. Under a GRN, expand **View received materials** to see each delivered material, accepted and rejected quantities, units and rejection reasons. **Open GRN** opens the complete supplier receipt and correction history. Voided/pending-void GRNs retain their status; PO outstanding quantities continue to use active receipts only.

The same material disclosures are available from Inventory, Procurement and Finance wherever the user already has PO/GRN read access. Details are fetched only for the selected order, with its existing database permissions rechecked. They are not preloaded for all orders. Historical PO/GRN reports also provide a visible **View materials** source link.

## Procurement workspace

Procurement-only accounts no longer have Inventory & movements or material requisitions in their workspace/navigation. Migration **029**, applied once after **028**, also removes Procurement as a stock-read role, so a copied inventory URL or stock RPC cannot bypass that separation. Procurement retains supplier POs/GRNs, supplier invoices and Materials & suppliers. Independently assigned Finance, Inventory Manager, receiving or department roles retain their own stock permissions.

Apply `202611170029_procurement_stock_separation.sql` after 028, skip already applied migrations, then deploy the application. Existing material lines are already stored; no material-data backfill is required.
