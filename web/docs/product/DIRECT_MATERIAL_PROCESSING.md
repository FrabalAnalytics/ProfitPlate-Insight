# Direct material processing - release 043

The authorised colleague at the configured processing centre selects the material, enters actual input and output, and submits with a required human name. No colleague approval or separate posting is required. The signed-in account remains separately audited. Notes are optional, including an out-of-tolerance result.

The selected published baseline supplies the output SKU and expected output per actual input. The form displays expected output, absolute gap, percentage variance and baseline achievement. Optional measured waste stays inside production consumption; usable mass yield is shown only when comparable weights exist. Piece shortfall never becomes an inferred KG waste quantity.

Add material supports up to 30 processing rows. Each row retains a distinct batch record and immutable baseline evidence. The entire submission is one database transaction. Current available stock (after receiver reservations) is checked against combined requirements before any output can fund another input. All source deductions, output additions, waste evidence, cost snapshots and audit events commit together or roll back together. Organisation locking serialises competing posting operations. Replay of the same submission token and identical payload returns the original IDs; changed payload/actor is rejected. A fresh token represents a new processing event.

The form prevents submission while a displayed shortage exists. The database rechecks stock at submit time. Backdated entries cannot bypass later stock movements. Centre, active responsibility, role permissions, material scope, baseline, units and quantity validation remain enforced by checked functions.

Migration 043 does not post existing Requested/Approved batches. Their original recorder, still authorised at that processing centre, can complete the original entry from its expanded history using a submitter name. This posts the saved quantities once. Closed/posted entries cannot be posted again. No re-entry is necessary.

Apply `supabase/migrations/202611190043_direct_material_processing.sql` before deploying the matching app. Legacy stock-request functions remain for older integrations and history compatibility; the processing UI uses `submit_material_processing`. Opening counts and transfers retain their existing controls. The updated Word guide, workbook and acceptance pack include this workflow.
