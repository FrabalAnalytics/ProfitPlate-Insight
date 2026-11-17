"use client";

import { useEffect, useId, useState } from "react";
import { findRecipeComponents } from "./actions";
import type { RecipeOption } from "@/lib/recipes";

export function ComponentPicker({ organisationId, kind, selected, onSelect, lineNumber }: {
 organisationId: string; kind: "ITEM" | "RECIPE"; selected: RecipeOption | null; onSelect: (option: RecipeOption | null) => void; lineNumber: number;
}) {
 const id = useId();
 const [query, setQuery] = useState("");
 const [page, setPage] = useState(0);
 const [result, setResult] = useState<{ options: RecipeOption[]; more: boolean; error?: string }>({ options: [], more: false });
 const [loading, setLoading] = useState(true);
 useEffect(() => {
  let active = true;
  const timer = setTimeout(async () => {
   setLoading(true);
   try {
    const found = await findRecipeComponents(organisationId, kind, query, page);
    if (active) { setResult(found); setLoading(false); }
   } catch {
    if (active) { setResult({ options: [], more: false, error: "We couldn’t connect. Change your search to try again." }); setLoading(false); }
   }
  }, 250);
  return () => { active = false; clearTimeout(timer); };
 }, [organisationId, kind, query, page]);
 const options = selected && !result.options.some(option => option.id === selected.id) ? [selected, ...result.options] : result.options;
 return <div className="recipe-picker"><label className="sr-only" htmlFor={`${id}-search`}>Search component {lineNumber}</label><input id={`${id}-search`} type="search" placeholder={kind === "ITEM" ? "Search materials by name or code…" : "Search saved sub-recipe versions…"} maxLength={80} value={query} onChange={event => { setQuery(event.target.value); setPage(0); }} /><label className="sr-only" htmlFor={`${id}-select`}>Choose component {lineNumber}</label><select id={`${id}-select`} value={selected?.id ?? ""} onChange={event => onSelect(options.find(option => option.id === event.target.value) ?? null)} required aria-busy={loading}><option value="">{loading ? "Loading components…" : "Select a component"}</option>{options.map(option => <option key={option.id} value={option.id}>{option.label} ({option.code})</option>)}</select>{result.error && <p className="field-error" role="alert">{result.error}</p>}<div className="picker-page"><span role="status">{loading ? "Searching…" : `${result.options.length} results on this page`}</span><div>{page > 0 && <button type="button" onClick={() => setPage(page - 1)}>Previous</button>}{result.more && <button type="button" onClick={() => setPage(page + 1)}>More results</button>}</div></div></div>;
}
