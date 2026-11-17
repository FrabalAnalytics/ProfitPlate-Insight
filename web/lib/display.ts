/** Presentation rounding only; source amounts and financial calculations stay unchanged. */
export const displayPercent = (value: string) => new Intl.NumberFormat("en-NG", {
  maximumFractionDigits: 2,
}).format(Number(value));
