"use client";
import { useEffect, useState } from "react";
import type { MenuRecipe } from "@/lib/menus";
import { findMenuRecipes } from "./actions";

export function MenuRecipePicker({ organisationId, selected, onSelect, disabled }: { organisationId: string; selected: MenuRecipe | null; onSelect: (recipe: MenuRecipe | null) => void; disabled: boolean }) {
 const [query, setQuery] = useState(""), [page, setPage] = useState(0), [loading, setLoading] = useState(true);
 const [result, setResult] = useState<{ options: MenuRecipe[]; more: boolean; error?: string }>({ options: [], more: false });
 useEffect(() => {
  let active = true;
  const timer = setTimeout(async () => {
   setLoading(true);
   try { const data = await findMenuRecipes(organisationId, query, page); if (active) setResult(data); }
   catch { if (active) setResult({ options: [], more: false, error: "We could not load saved recipes. Change your search to retry." }); }
   finally { if (active) setLoading(false); }
  }, 250);
  return () => { active = false; clearTimeout(timer); };
 }, [organisationId, query, page]);
 const options = selected && !result.options.some(option => option.id === selected.id) ? [selected, ...result.options] : result.options;
 return <div className="menu-recipe-picker"><div className="setup-field"><label htmlFor="menu-recipe-search">Search saved final recipes</label><input id="menu-recipe-search" type="search" value={query} onChange={event => { setQuery(event.target.value); setPage(0); }} maxLength={80} disabled={disabled} placeholder="Recipe name or code"/></div><div className="setup-field"><label htmlFor="menu-recipe-version">Saved recipe version</label><select id="menu-recipe-version" value={selected?.id ?? ""} onChange={event => onSelect(options.find(option => option.id === event.target.value) ?? null)} disabled={disabled} aria-busy={loading}><option value="">{loading ? "Searching recipes…" : "Choose a final recipe version"}</option>{options.map(option => <option key={option.id} value={option.id}>{option.label} ({option.code})</option>)}</select></div>{result.error && <p className="field-error" role="alert">{result.error}</p>}<div className="menu-picker-pages"><span>{loading ? "Searching…" : `${result.options.length} recipes on this page`}</span><div>{page > 0 && <button type="button" disabled={disabled} onClick={() => setPage(page - 1)}>Previous</button>}{result.more && <button type="button" disabled={disabled} onClick={() => setPage(page + 1)}>More recipes</button>}</div></div></div>;
}
