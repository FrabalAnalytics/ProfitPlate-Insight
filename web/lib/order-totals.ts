type OrderLineInput = { quantity: string; unit_price: string; discount: string; tax: string };

const scale = BigInt(1000000);
const amountScale = scale * scale;
function decimal(value: string): bigint | null {
  if (!/^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$/.test(value)) return null;
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole) * scale + BigInt(fraction.padEnd(6, "0"));
}
function format(value: bigint): string {
  const fraction = (value % amountScale).toString().padStart(12, "0").replace(/0+$/, "");
  return `${value / amountScale}${fraction ? `.${fraction}` : ""}`;
}

// Match the database's exact decimal arithmetic without rounding intermediate lines.
export function orderTotals(lines: OrderLineInput[], basis: string): { total: string; lines: string[] } | null {
  if (!lines.length || !["EXCLUSIVE", "INCLUSIVE"].includes(basis)) return null;
  let total = BigInt(0);
  const amounts: string[] = [];
  for (const line of lines) {
    const quantity = decimal(line.quantity), price = decimal(line.unit_price);
    const discount = decimal(line.discount), tax = decimal(line.tax);
    if (quantity === null || quantity <= BigInt(0) || price === null || price <= BigInt(0) || discount === null || tax === null) return null;
    const net = quantity * price - discount * scale;
    if (net <= BigInt(0) || (basis === "INCLUSIVE" && tax * scale >= net)) return null;
    const amount = net + (basis === "EXCLUSIVE" ? tax * scale : BigInt(0));
    if (amount >= BigInt("100000000000000000000000000") * amountScale) return null;
    total += amount;
    amounts.push(format(amount));
  }
  return {total: format(total), lines: amounts};
}
