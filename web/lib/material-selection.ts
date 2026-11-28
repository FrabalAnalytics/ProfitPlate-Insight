export type MaterialChoice = {
 id: string;
 name: string;
 code?: string | null;
 unit?: string | null;
 item_type?: string;
 detail?: string;
 disabled?: boolean;
};

const normalise = (text: string) => text.normalize('NFKD').replace(/\p{M}/gu, '').toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
export function materialMatches(item: MaterialChoice, query: string) {
 const words = normalise(query).split(/\s+/).filter(Boolean);
 const text = normalise(`${item.name} ${item.code ?? ''} ${item.unit ?? ''} ${item.detail ?? ''}`);
 return words.every(word => text.includes(word));
}

/** Search affects presentation only. Never add options from outside the caller's permitted list. */
export function materialChoices(items: MaterialChoice[], query: string, selected: string) {
 return items.filter(item => item.id === selected || materialMatches(item, query))
  .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }) || (a.code ?? '').localeCompare(b.code ?? '') || a.id.localeCompare(b.id));
}

export function materialGroup(item: MaterialChoice) {
 return ({ RAW: 'Raw ingredients', SEMI_FINISHED: 'Prepared ingredients', FINISHED: 'Finished items', PACKAGING: 'Packaging', RESALE: 'Resale items', CONSUMABLE: 'Consumables', GENERAL: 'General materials' } as Record<string, string>)[item.item_type ?? ''] ?? 'Materials';
}
