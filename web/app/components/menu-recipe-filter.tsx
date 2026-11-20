"use client";

import { useId, useTransition } from "react";
import { useRouter } from "next/navigation";
import "./menu-recipe-filter.css";

export function MenuRecipeFilter({ organisation, selected }: {
  organisation: string;
  selected: "menu" | "recipes";
}) {
  const id = useId();
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  return <div className="menu-recipe-filter" aria-busy={pending}>
    <label htmlFor={id}>Show</label>
    <select id={id} aria-label="Selling menu or recipes" value={selected} disabled={pending}
      onChange={event => {
        const path = event.target.value === "recipes" ? "recipes" : "menus";
        startTransition(() => router.push(`/workspace/${path}?${new URLSearchParams({ organisation })}`));
      }}>
      <option value="menu">Selling menu</option>
      <option value="recipes">Recipes</option>
    </select>
    {pending && <span role="status">Loading...</span>}
  </div>;
}
