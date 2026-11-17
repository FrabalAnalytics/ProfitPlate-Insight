# Workspace navigation and transaction density

This presentation update preserves the existing routes, server actions, access
checks, import controls and financial calculations. No migration is required.

- Shared navigation uses uniform 44px minimum links, aligned icons, clear current
  states and Transactions / Profitability / Business setup groups. The compact
  sticky header retains business context. The mobile drawer preserves focus
  trapping, Escape dismissal and focus return.
- Sales and purchase import lines share one semantic transaction table. Desktop
  columns align dates/references, items/locations, quantities, amounts and status.
  On narrow screens the same records become compact rows with visible item,
  context, date/reference, quantity, amount and status.
- Each row has a keyboard-operable disclosure with expanded state. Supporting
  source, tax and conversion details stay available. Findings and review warnings
  remain visible even when details are collapsed. Saved menu versions remain in
  the primary sales row.
- Sales includes business-date shortcuts, a compact selected-period/location
  disclosure and paired mobile cost/margin cards. Long estimate guidance is
  available under About these estimates. Missing-cost warnings remain prominent.
- Money retains existing currency formatting. Percentages round to at most two
  decimals for display only. Recorded precision and calculations are unchanged.
- Catalogue, recipe/menu libraries and import histories use tighter list spacing;
  interactive controls retain adequate touch targets. Menu/recipe mobile totals
  use the same compact card rhythm.

Validation includes production compilation and the existing end-to-end workflows,
with added checks for navigation alignment, transaction density, desktop/mobile
disclosures, percentage formatting and absence of mobile horizontal overflow.
