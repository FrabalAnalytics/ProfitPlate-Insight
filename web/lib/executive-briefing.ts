import type { Overview } from "./overview";
import type { SalesSummary } from "./sales-imports";

export type ExecutiveBriefing = {
 po_exposure?:{unavailable:string|null;total:number;open:number;potential_exposure:string;unmatched:number;rows:{order_id:string;reference:string;line_id:string;item_id:string;name:string;location_id:string;outlet_name:string;supplier:string;unit:string;baseline:{source:string;date?:string;backfilled?:boolean};quote_unit_cost:string;baseline_unit_cost:string;change_percent:string|null;ordered_quantity:string;received_quantity:string;billed_quantity:string;unbilled_quantity:string;potential_exposure:string;stage:string;affected_menus:{id:string;name:string}[]}[]};
 processing?:{batches:number;exceptions:number;rows:{id:string;reference:string;source_id:string;centre:string;recipe:string;output_unit:string;variance_percent:string;unexplained_weight_kg:string|null;responsible_name:string;actual_unit_cost:string|null;standard_unit_cost:string|null}[]};
 from:string;to:string;prior_from:string;prior_to:string;currency:string;refreshed_at:string;recorded_days:number;
 summary:SalesSummary;previous:SalesSummary|null;comparison:Overview["comparison"];outlets:Overview["outlets"];food_cost_percent:string|null;food_cost_change_pp:string|null;food_margin_change_pp:string|null;
 prices:{unavailable:string|null;total?:number;impact?:string;unmatched?:number;excluded_currency_invoices?:number;rows:{item_id:string;name:string;outlet:string;outlet_name:string;suppliers:string;unit:string;current_price:string;prior_price:string;change_percent:string;impact:string}[]};
 waste:{lines:number;unpriced:number;known_value:string;waste_value:string;shortage_value:string;prior_lines:number;prior_unpriced:number;prior_value:string;change_value:string;rows:{id:number;document_id:string;reference:string;kind:string;location_id:string;location_name:string;outlet_name:string;item_name:string;unit:string;quantity:string;value:string|null}[]};
 movements:{open:number;handover:number;overdue:number;exceptions:number;rows:{id:string;reference:string;state:string;source_name:string;destination_name:string;source_outlet:string;destination_outlet:string;next_action:string;waiting_since:string;overdue:boolean}[]};
 menus:{target_missing?:number;total:number;rows:(SalesSummary["menus"][number]&{food_cost_percent:string|null;margin_percent:string|null;locations:string;location_id?:string;target?:string|null;primary_category?:string|null})[]};
};
