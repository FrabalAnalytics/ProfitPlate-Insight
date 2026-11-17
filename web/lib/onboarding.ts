export const concepts = [
  ["QSR", "Quick service restaurant"], ["CASUAL_DINING", "Casual dining"],
  ["FINE_DINING", "Fine dining"], ["BAKERY", "Bakery"], ["CAFE", "Café"],
  ["BAR", "Bar / lounge"], ["CLOUD_KITCHEN", "Cloud kitchen"],
  ["BUFFET", "Buffet"], ["CATERING", "Catering"], ["OTHER", "Other"],
] as const;

export type SetupValues = {
  business_name: string; concept: string; country_code: string; currency_code: string;
  brand_name: string; location_name: string; timezone: string; address: string; step: number;
};

export const emptySetup: SetupValues = {
  business_name: "", concept: "", country_code: "NG", currency_code: "NGN",
  brand_name: "", location_name: "", timezone: "Africa/Lagos", address: "", step: 1,
};

// Database rows include nullable completion metadata. Keep only editable fields
// in form state so metadata never becomes an uncontrolled/nullable hidden input.
export function normaliseSetup(raw: unknown): SetupValues {
  const row = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown> : {};
  const text = (key: Exclude<keyof SetupValues, "step">) =>
    typeof row[key] === "string" ? row[key] as string : emptySetup[key];
  const step = typeof row.step === "number" && Number.isInteger(row.step)
    && row.step >= 1 && row.step <= 3 ? row.step : 1;
  return {
    business_name: text("business_name"), concept: text("concept"),
    country_code: text("country_code"), currency_code: text("currency_code"),
    brand_name: text("brand_name"), location_name: text("location_name"),
    timezone: text("timezone"), address: text("address"), step,
  };
}

export function setupValues(form: FormData): SetupValues {
  const text = (key: string) => String(form.get(key) ?? "").trim();
  return {
    business_name: text("business_name"), concept: text("concept"), country_code: text("country_code"),
    currency_code: text("currency_code"), brand_name: text("brand_name"), location_name: text("location_name"),
    timezone: text("timezone"), address: text("address"), step: Number(form.get("step")),
  };
}

export function validateSetup(values: SetupValues, full = false, draft = false): Record<string, string> {
  const errors: Record<string, string> = {};
  for (const key of ["business_name", "brand_name", "location_name"] as const) {
    if (values[key].length > 120) errors[key] = "Use 120 characters or fewer.";
  }
  if (!draft && !values.business_name) errors.business_name = "Enter your business name.";
  if ((!draft || values.concept) && !concepts.some(([code]) => code === values.concept)) errors.concept = "Choose your business concept.";
  if (!/^[A-Z]{2}$/.test(values.country_code)) errors.country_code = "Choose a country.";
  if (!/^[A-Z]{3}$/.test(values.currency_code)) errors.currency_code = "Choose a currency.";
  if (values.address.length > 500) errors.address = "Use 500 characters or fewer.";
  if (!Number.isInteger(values.step) || values.step < 1 || values.step > 3) errors.step = "Choose a valid setup step.";
  try { new Intl.DateTimeFormat("en", { timeZone: values.timezone }); }
  catch { errors.timezone = "Choose a valid timezone."; }
  if (!draft && (full || values.step > 1)) {
    if (!values.brand_name) errors.brand_name = "Enter your brand name.";
    if (!values.location_name) errors.location_name = "Enter your first location’s name.";
  }
  return errors;
}
