export type CatalogueKind = "material" | "supplier" | "conversion";
export type Unit = { id: string; code: string; name: string; dimension: string };
export type Material = { id: string; code: string; name: string; item_type: string; category_id: string | null; base_uom_id: string; stock_tracked: boolean; is_active: boolean };
export type Supplier = { id: string; code: string; name: string; email: string | null; phone: string | null; address: string | null; is_active: boolean };
export const itemTypes = [
  ["RAW", "Raw ingredient"], ["PACKAGING", "Packaging"], ["RESALE", "Resale item"],
  ["CONSUMABLE", "Consumable"], ["SEMI_FINISHED", "Semi-finished item"], ["FINISHED", "Finished item"],
] as const;
export const isUuid = (value: string) => /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value);

export function validateCatalogue(kind: string, values: Record<string, string>) {
  const errors: Record<string, string> = {};
  if (!isUuid(values.organisation_id ?? "")) errors.organisation_id = "Choose a business you have access to.";
  if (values.id && !isUuid(values.id)) errors.id = "This record is not available.";
  if (!["material", "supplier", "conversion"].includes(kind)) errors.kind = "Choose a valid catalogue action.";
  if (kind === "material" || kind === "supplier") {
    if (!/^[A-Z0-9][A-Z0-9_-]{0,39}$/.test(values.code ?? "")) errors.code = "Use up to 40 letters, numbers, hyphens or underscores.";
    if (!values.name || values.name.length > 120) errors.name = "Enter a name of up to 120 characters.";
  }
  if (kind === "material") {
    if (!itemTypes.some(([code]) => code === values.item_type)) errors.item_type = "Choose a material type.";
    if (!isUuid(values.base_uom_id ?? "")) errors.base_uom_id = "Choose a base unit.";
    if ((values.category ?? "").length > 60) errors.category = "Use 60 characters or fewer.";
  }
  if (kind === "supplier") {
    if (values.email && (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(values.email) || values.email.length > 254)) errors.email = "Enter a valid email address.";
    if ((values.phone ?? "").length > 40) errors.phone = "Use 40 characters or fewer.";
    if ((values.address ?? "").length > 500) errors.address = "Use 500 characters or fewer.";
  }
  if (kind === "conversion") {
    if (!isUuid(values.item_id ?? "")) errors.item_id = "Choose an active material.";
    if (!isUuid(values.from_uom_id ?? "")) errors.from_uom_id = "Choose a source unit.";
    if (!/^(?:0|[1-9]\d{0,13})(?:\.\d{1,6})?$/.test(values.factor ?? "") || !/[1-9]/.test(values.factor ?? "")) {
      errors.factor = "Enter a positive number with up to six decimal places. Do not use commas.";
    }
    try {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(values.effective_from ?? "") || new Date(`${values.effective_from}T00:00:00Z`).toISOString().slice(0, 10) !== values.effective_from) throw new Error();
    } catch { errors.effective_from = "Choose a valid effective date."; }
  }
  return errors;
}
