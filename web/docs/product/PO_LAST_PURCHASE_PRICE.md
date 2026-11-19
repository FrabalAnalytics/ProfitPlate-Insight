# PO last purchase unit price - release 044

Raising or editing a draft PO now displays a read-only last purchase unit price on each material line. Selection of material, unit or order date refreshes that line independently. The editable supplier quote, PO total and saved order data remain separate.

The source is the latest recorded purchase invoice on or before the order date (capped at the current business date), across suppliers in this restaurant. Approved corrections and voids replace original evidence; pending proposals do not change it. Same-day ties use invoice creation time, invoice ID and line position. This is the source quoted unit price before line discount, preserving the source tax basis, which is shown with supplier and purchase date. It is not the monthly weighted recipe cost.

The historical conversion recorded with the source invoice first normalises its quote to the material base unit. The selected PO unit then uses a dimensional conversion or that material's package conversion effective at the order date. Missing conversion never produces a fabricated number. Initial material reference prices are used only when no usable invoice exists, clearly labelled Initial price (no invoice). Missing prices do not block entering a supplier quote.

Price fields have no form name and never enter the saved order payload. Server authorisation requires purchase-entry access; the database verifies restaurant/material/unit membership. Loading/error states hide the previous selection's result, cancellation prevents stale responses, and a failed lookup has a retry button.

Apply `supabase/migrations/202611190044_po_last_purchase_price.sql` before the matching app deployment. Regression coverage includes date cutoffs, package conversion revisions, corrected/voided invoices, initial-price fallback, access boundaries and independent read-only fields on desktop/mobile.
