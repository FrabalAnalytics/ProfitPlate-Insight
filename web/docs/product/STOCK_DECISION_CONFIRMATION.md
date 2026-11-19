# Stock decision confirmation ? 19 November 2026

The decision form was keyed by document state. Revalidation changed that key after approval, resetting the action-state success message. The replacement form could also default to cancellation because it selected the first permitted action.

The selected document now displays a persistent status/next-step panel based on its current database state. Approval explicitly says stock has not changed and identifies posting or dispatch/acceptance as the next step. Completed posting confirms the ledger and balances are updated. Historical on-dispatch transfers and older named-waste completion retain their distinct explanations.

Successful decisions redirect to the same document after revalidation, so refresh reads the record instead of repeating a form submission. Primary actions use an explicit priority; cancellation-only controls are collapsed under Other actions and require an explicit selection. Pending controls remain disabled, and database state/permission checks are unchanged.

Verified: repeated approval and posting are rejected with no duplicate ledger quantity; browser checks cover approval confirmation after refresh, cancellation not preselected, posting completion, receiver acceptance and guided stock setup. No migration required.
