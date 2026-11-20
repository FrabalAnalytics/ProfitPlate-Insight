# Multi-centre, single-output production (050)

Apply `supabase/migrations/202611200050_multi_centre_single_output_production.sql` before deploying the matching app. Existing enabled centre flags, output bindings, baseline revisions, quantities, waste schedules and historical batches are preserved. The migration does not enable any additional centre or post/revalue stock automatically.

## Setup and operating model

Restaurant administrators select multiple active, owned centres under Centres & team access > Choose where processing & production happen. Main Store can portion raw goods while Central Kitchen produces stocked preparations. Front Kitchen, Back Kitchen and Bar can remain storage/service centres, or be enabled where they actually record stock production. Enabling a centre grants no new user role or stock assignment.

Each baseline explicitly selects its permitted enabled centres. Guided setup accepts 1-30 distinct tracked material inputs, one of which is the main yield-scaling input marked Requires processing. Inputs may include already-produced stock. It publishes one recipe version and binds exactly one produced SKU, then saves the baseline atomically. Existing linked recipes can still use the advanced baseline form. Cycles, incompatible units, cross-restaurant references and outlet-scope conflicts retain existing validation. Cost estimates include all recipe inputs and preserve existing output-family rules.

Daily entry derives the output and expected yield from that baseline. Secondary quantities begin with scaled suggestions and are editable as measured actual inputs. Optional measured waste can be recorded against each consumed input. The same 30-row submission can contain several independent batches, each with one output. It does not implement several outputs sharing a single input batch. Small and Big Beef Cuts therefore use separate batches and only the raw quantity actually allocated to each.

The existing atomic processing function checks total available input after reservations across every batch before any output posts. Direct processing needs the named submitter and current centre permissions, not another centre's approval. A shortage or invalid final row rolls back the entire submission. Existing retry tokens, audit identity, frozen batch costs and daily waste reopening apply unchanged.

## Configuration safeguards

The new centre-selection API validates administrator access, active ownership and restaurant scope. An optimistic revision rejects stale configuration. Changes are audited. Disabling/deactivating a producing centre with pending legacy batches is blocked; disabling another centre does not affect those batches. Ordinary centre/owner edits omit production settings and preserve the saved flag. Saved production settings redirect to a persistent confirmation and refreshed controls.

The legacy single-unit RPC remains available for integrations/tests expecting an explicit single-unit replacement. The new UI uses the multiple-centre API. The legacy default pointer is compatibility data, not a new restriction on baseline sites. Setup readiness checks enabled, owned baseline sites rather than requiring all processes to use that pointer.

## Requisitions and prepared items

Existing routes already support Front Kitchen requesting raw stock from Central Store and stocked preparations from Central Kitchen. Prepared items need tracked SKUs; a recipe definition alone is not transferable stock. Inventory/source-authorised approval and dispatch remain required, and destination acceptance alone posts accepted transfer quantities. Return routes and rejected-quantity follow-up remain unchanged.

This release does not add an automatic production-order planner or automatically launch production from a requisition. The producing centre records required production before dispatching the prepared stock. Standard final recipes for immediate service remain distinct from preparations deliberately produced into stock.

## Verification

Database coverage includes upgrade preservation, several inputs and derived costs, actual secondary consumption at two centres, per-centre restrictions, combined shortage rollback, repeated-submission safety, pending-batch disable protection and raw/prepared requisitions followed by receiver acceptance. Browser coverage exercises enabling two centres, guided baseline site selection, adding a second input, editing actual consumption and mobile shortage feedback. The complete training sample keeps its original single-centre arithmetic; additional UAT cases use separate references.
