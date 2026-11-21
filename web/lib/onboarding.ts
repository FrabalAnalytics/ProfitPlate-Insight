import {parseExpenseCategories} from "./expense-categories";
import {standardChannels,parseMenuCategories} from "./menu-categories";
export const concepts = [
  ["QSR", "Quick service restaurant"], ["CASUAL_DINING", "Casual dining"],
  ["FINE_DINING", "Fine dining"], ["BAKERY", "Bakery"], ["CAFE", "Café"],
  ["BAR", "Bar / lounge"], ["CLOUD_KITCHEN", "Cloud kitchen"],
  ["BUFFET", "Buffet"], ["CATERING", "Catering"], ["OTHER", "Other"],
] as const;

export type SetupValues = {
  business_name: string; concept: string; country_code: string; currency_code: string;
  brand_name: string; location_name: string; timezone: string; address: string; reporting_week_start: string; count_day: string; count_cutoff: string; sales_channels:string; menu_categories:string; expense_categories:string; step: number;
};

export const emptySetup: SetupValues = {
  business_name: "", concept: "", country_code: "NG", currency_code: "NGN",
  brand_name: "", location_name: "", timezone: "Africa/Lagos", address: "", reporting_week_start: "", count_day: "", count_cutoff: "", sales_channels:standardChannels, menu_categories:"[]", expense_categories:"[]", step: 1,
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
    timezone: text("timezone"), address: text("address"), reporting_week_start: text("reporting_week_start"), count_day: text("count_day"), count_cutoff: text("count_cutoff").slice(0,5), sales_channels:text("sales_channels"), menu_categories:text("menu_categories"), expense_categories:text("expense_categories"), step,
  };
}

export function setupValues(form: FormData): SetupValues {
  const text = (key: string) => String(form.get(key) ?? "").trim();
  return {
    business_name: text("business_name"), concept: text("concept"), country_code: text("country_code"),
    currency_code: text("currency_code"), brand_name: text("brand_name"), location_name: text("location_name"),
    timezone: text("timezone"), address: text("address"), reporting_week_start: text("reporting_week_start"), count_day: text("count_day"), count_cutoff: text("count_cutoff"), sales_channels:text("sales_channels")||standardChannels, menu_categories:text("menu_categories")||"[]", expense_categories:text("expense_categories")||"[]", step: Number(form.get("step")),
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
  for (const key of ["reporting_week_start", "count_day"] as const) {
    if ((values[key] || (!draft && (full || values.step > 1))) && !/^[0-6]$/.test(values[key])) errors[key] = "Choose a day.";
  }
  if ((values.count_cutoff || (!draft && (full || values.step > 1))) && !/^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(values.count_cutoff)) errors.count_cutoff = "Choose a physical count cutoff time.";
  try{const rows=JSON.parse(values.sales_channels);if(!Array.isArray(rows)||rows.length>30)throw new Error();if(!draft&&(full||values.step>1)&&!rows.some((r:{is_active?:boolean})=>r.is_active!==false))errors.sales_channels="Choose at least one sales channel.";}catch{errors.sales_channels="Check your sales channels.";}
  try{parseMenuCategories(values.menu_categories,draft||(!full&&values.step===1));}catch(e){errors.menu_categories=e instanceof Error?e.message:"Check menu categories.";}
  try{parseExpenseCategories(values.expense_categories);}catch(e){errors.expense_categories=e instanceof Error?e.message:"Check expense categories.";}
  return errors;
}
