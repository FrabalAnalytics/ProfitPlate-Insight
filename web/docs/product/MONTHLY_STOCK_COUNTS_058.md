# Monthly stock counts — release 058

Monthly stocktaking is mandatory for every active stock centre. It runs alongside weekly counts and uses the same independent review and stock-adjustment safeguards.

## Set up the schedule

1. Open **Data & Setup → Reporting calendar & targets**.
2. Find **Monthly stock count**.
3. Choose the count day: month-end, or a numbered day. Days 29–31 fall on the last day in shorter months.
4. Choose the local cutoff time and submission window (1–168 hours).
5. Save. The restaurant's reporting timezone applies. Schedule changes take effect next month; existing sheets and deadlines stay intact.

The initial default is month-end at 23:59, with 24 hours to submit. Existing centres begin prospectively when migration 058 is applied, not with invented overdue tasks for earlier months. New centres join from their next eligible cutoff. Deactivating a centre stops future obligations while retaining earlier records.

## Record the count

1. The responsible colleague opens **Monthly stock counts** from the workspace alert or Reports navigation.
2. Select the centre and reporting dates. Upcoming counts open at their saved cutoff.
3. Select **Start count**. The system captures book quantities and reference costs at that cutoff.
4. Count the full applicable stock list, including materials that are not flagged for weekly counting, processed SKUs and stocked prepared products.
5. Enter a physical quantity for every line. **Blank is incomplete; 0 is an explicit count.** Explain differences on the affected lines or in the overall note, including when they remain under investigation.
6. If the centre has no applicable material lines, tick **I checked this centre holds no stock**. An empty sheet without that declaration cannot be submitted.
7. Enter the submitter name and save a draft or submit for independent review. Submission does not change inventory balances.

Centre visibility and entry permissions follow existing stock access. A role name alone does not grant another centre's data. Administrators assign centre tasks through Centres & team access.

## Review and post

- An authorised colleague other than the submitter reviews the count. Operations Managers can review counts at their permitted centres.
- Approval does not move stock. Inventory authority is required to post the approved variance.
- Posting adjusts only the saved difference, preserving movements after the cutoff. Repeated submissions and posting retries do not create duplicate adjustments.
- Unresolved handovers, stale/backdated movements or another overlapping count adjustment can block automatic posting. Reconcile the evidence, refresh and recount where required, or complete an explained review without an adjustment.
- Empty-centre declarations can complete review without creating an empty stock document or ledger entry.
- Earlier revisions, quantities, submitters and decisions remain in history. Download the count and variance CSV from the selected sheet.

## When weekly and monthly cutoffs match

One full sheet fulfils both obligations at the same centre and exact cutoff. It includes the monthly material list, uses the earlier submission deadline and produces at most one adjustment. Weekly and monthly counts on the same date with different cutoff times remain separate; overlapping adjustment safeguards still apply.

## Workspace and executive reporting

- Centre colleagues see monthly count tasks, deadlines and submission states within their permitted centres.
- Owners and Operations Managers see overdue monthly counts and submissions awaiting review, with links to the source records.
- The monthly compliance report supports centre and date filters, historical counts and pagination.
- The stock review shows known book and physical values using the **latest submitted count per centre**, rather than adding stock snapshots across different months.
- Monthly history and material variance patterns show shortages, surpluses, exception frequency and affected months. Reference values are available only to authorised financial/oversight roles; unpriced observations stay visible.
- Variance observations may repeat across counts when adjustments remain unresolved. They are investigation signals, not automatically recorded waste, confirmed losses or accounting inventory valuations.

## Deployment

Run `supabase/migrations/202611220058_monthly_stock_accountability.sql` after migration 057 before deploying the matching app. The migration preserves existing weekly sheets, histories, stock documents and ledger quantities. It does not post any stock adjustments.
