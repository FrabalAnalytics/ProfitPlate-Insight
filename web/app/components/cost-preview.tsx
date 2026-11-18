"use client";

import { useState } from "react";
import { ChefHat, SlidersHorizontal, Utensils } from "lucide-react";

const money = (value: number) => `₦${value.toLocaleString("en-NG", { maximumFractionDigits: 0 })}`;

export function CostPreview() {
  const [ingredientCost, setIngredientCost] = useState(3500);
  const price = 6500, packaging = 250, foodProfit = price - ingredientCost - packaging;
  const margin = foodProfit / price * 100;
  return <section className="cost-preview" aria-labelledby="cost-preview-heading">
    <div className="preview-window-bar"><div><span /><span /><span /></div><span>ProfitPlate / Menu profitability</span><span className="sample-label">ILLUSTRATIVE PREVIEW</span></div>
    <div className="preview-content"><div className="preview-title-row"><div><span className="preview-eyebrow">A CLOSER LOOK AT ONE PLATE</span><h2 id="cost-preview-heading">The margin behind the menu.</h2></div><span className="preview-dish-icon"><Utensils size={20} /></span></div>
      <div className="preview-dish"><span className="preview-dish-initial"><ChefHat size={23} /></span><div><strong>Chicken rice bowl</strong><span>Example dish · price excludes tax</span></div><span className="preview-selling-price">{money(price)}<small>Selling price</small></span></div>
      <div className="preview-metrics"><div><span>Food gross profit</span><strong aria-live="polite" aria-atomic="true" data-testid="preview-profit">{money(foodProfit)}</strong><small>Per portion, before other costs</small></div><div><span>Food gross margin</span><strong data-testid="preview-margin">{margin.toFixed(1)}<small>%</small></strong><small>Based on the example inputs</small></div></div>
      <div className="preview-cost-bar" aria-hidden="true"><span style={{ width: `${ingredientCost / price * 100}%` }} /><span style={{ width: `${packaging / price * 100}%` }} /><span style={{ width: `${margin}%` }} /></div>
      <div className="preview-legend"><span><i />Ingredients</span><span><i />Packaging</span><span><i />Food gross profit</span></div>
      <div className="preview-slider-panel"><div><label htmlFor="ingredient-cost"><SlidersHorizontal size={15} /> Ingredient cost per portion</label><output htmlFor="ingredient-cost">{money(ingredientCost)}</output></div><input id="ingredient-cost" type="range" min="2500" max="5000" step="100" value={ingredientCost} onChange={event => setIngredientCost(Number(event.target.value))} aria-valuetext={`${money(ingredientCost)} per portion`} /><div className="preview-range-labels"><span>{money(2500)}</span><span>Drag to explore the difference</span><span>{money(5000)}</span></div></div>
      <p className="preview-disclaimer">Fictional example. Packaging: {money(packaging)} per portion. Excludes labour, commissions and other operating costs.</p>
    </div>
  </section>;
}
