# Stock statements and mandatory weekly counts

Apply migrations **052 then 053** before deploying this release. Existing stock, approvals and histories are preserved. Do not rerun applied migrations.

## Stock movement statement

Reports → Stock movement statement reconciles each material at one centre over a selected business-date period:

`opening + additions − removals + count adjustments = closing`

The full ledger contributes, including history beyond the old latest-100 view. Filters support material/category and up to 367 days. Material detail gives source records, movement breakdown and running balances. CSV exports are scope-checked and capped at 5,000 materials/entries; narrow the period/material if necessary. Quantities in different units are not added together.

Financial users see dated **reference-value estimates**, with unpriced balances disclosed. Unit estimates use existing monthly purchase averages, initial-price fallback and derived processing/recipe costs. These live estimates can change when source data changes. This release does **not** create a historical costed valuation ledger, carrying valuation or actual COGS.

## Weekly count setup

1. Configure the restaurant timezone, physical count day and local cutoff in Reporting calendar.
2. Flag required materials with Include in weekly stock counts.
3. Select a centre in Reports → Weekly stock counts, then inspect Weekly-count scope. Flagged materials with ledger/zero-opening history are included automatically. Managers may include additional expected zero-stock SKUs. Held flagged stock cannot be silently excluded.
4. Default submission deadline is cutoff + 24 hours. A stock manager can set a business-wide window of 1–168 hours.

Rollout begins at the next eligible cutoff; no past arrears are invented. Calendar, ownership, scope and deadline changes are effective prospectively from tomorrow. Existing dated obligations and open-sheet snapshots remain intact. Centres without a configured calendar show a setup warning rather than false compliance.

## Count and review

At cutoff, open the due sheet. It freezes the expected material list, book quantities, price estimates and source watermark. Save partial drafts; blank remains missing and explicit zero is valid. Submit requires every physical quantity, submitter name and an explanation for variances on a line or in the overall note. The actual signed-in user is also retained. Requests use revision checks and retry tokens.

Submission does not change stock. A different authorised colleague approves a submitted variance, or completes review without adjustment with a reason. Approval itself does not change stock. Inventory posting applies **physical minus frozen book** once to current stock, preserving later movements; existing negative-stock/reservation checks still apply. This is deliberately separate from waste logging, which remains approval-free.

Late backdated entries require refreshing the cutoff snapshot and recounting. A transfer spanning the cutoff blocks automatic adjustment to prevent correcting the same handover twice; reconcile it and record the review decision. Another posted stock count after cutoff also blocks duplicate correction. Prior quantities and decisions remain in private, permission-checked revision history. Closed reviews are immutable.

The workspace shows due/submitted counts, older overdue tasks, reviews waiting and calendar gaps. Executives see their permitted centres; operational users remain scoped. Reports distinguish late submission from missing submission. Count CSV includes cutoff, deadline, named submitter, book, physical and variance; money is present only with financial access. Variance percentage is unavailable for a zero book balance; positive physical stock then appears as unexpected stock.

Mandatory means a dated obligation and visible noncompliance, not a blanket shutdown of purchasing or service. Reminders are in-app on workspace/report refresh; this release does not send scheduled email/push reminders. Sales-driven theoretical usage remains future work.

## Validation

Database coverage checks retry safety, explicit zero, scoped access, unpriced estimates, older overdue obligations, full-history running balances, independent review, backdated changes and transfers crossing cutoff. Browser coverage exercises draft persistence, submission feedback, review, one-time adjustment, exports and narrow-screen layout. The refreshed test pack adds six manual acceptance cases and the beginner guide explains the new workflows.
