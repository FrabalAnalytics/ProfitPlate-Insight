# Menu price preview scope ? 19 November 2026

Reproduced: an item with a saved Takeaway price could show a missing Dine-in price; changing the visible dropdown to Takeaway without submitting left the previous Dine-in result on screen. The price was present, but the visible input no longer described the applied calculation.

Preview outlet/channel/date changes now apply through navigation automatically. Pending or invalid changed inputs hide the old result, while the result identifies its applied outlet/channel/date. Initial previews prefer an available effective saved price without replacing explicit filter choices. The initial choice never resumes an older price after a newer price expires; SQL remains authoritative for prices, tax, currency, effective dates, recipe costs and authorisation. Price/menu mutations also refresh the profitability register.

No migration or stored-price change required. Browser regression covers the exact saved-Takeaway/missing-Dine-in case, automatic update, unchanged price-history count, initial scope and date changes. Existing database tests retain tax, expiry, correction, negative-margin and access checks.
