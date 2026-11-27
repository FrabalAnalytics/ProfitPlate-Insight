"use client";
export function ProfitabilitySort({value}:{value:string}){
 return <div className="profitability-sort"><label htmlFor="profit-sort">Sort by</label><select id="profit-sort" name="sort" defaultValue={value} key={value} onChange={e=>e.currentTarget.form?.requestSubmit()}><option value="PRIORITY">Needs attention first</option><option value="GROSS_DESC">Gross margin %: highest to lowest</option><option value="GROSS_ASC">Gross margin %: lowest to highest</option></select></div>;
}
