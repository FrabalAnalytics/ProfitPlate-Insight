export type PlanRecipe={id:string;recipe_id:string;name:string;code:string;version:number;recipe_type:string;effective_from:string;batch_yield:string;unit:string;baseline_id:string|null};
export type PlanOptions={centres:{id:string;name:string}[];recipes:PlanRecipe[];date:string};
export type PlanRow={recipe_version_id:string;quantity:string};
export type MaterialPlan={organisation:string;restaurant:string;centre_id:string;centre:string;plan_date:string;generated_at:string;generated_by:string;basis:'STOCK'|'RECIPE';recipes:(PlanRecipe&{target_quantity:string;requirements:{item_id:string;quantity:string}[]})[];materials:{item_id:string;name:string;code:string;unit:string;required:string;available:string|null;shortage:string|null;stock_tracked:boolean}[]};
