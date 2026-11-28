"use client";

import { useId, useState } from 'react';
import { materialChoices, materialGroup, materialMatches, type MaterialChoice } from '@/lib/material-selection';

export function MaterialPicker({ id, name, value, onChange, options, placeholder = 'Choose material', required = false, disabled = false, search = true, ...aria }: {
 id?: string; name?: string; value: string; onChange: (value: string) => void;
 options: MaterialChoice[]; placeholder?: string; required?: boolean; disabled?: boolean; search?: boolean;
 'aria-label'?: string;
}) {
 const generated = useId(), selectId = id ?? generated;
 const [query, setQuery] = useState('');
 const selected = options.find(item => item.id === value);
 const shown = materialChoices(options, query, value);
 const groups = [...new Set(shown.map(materialGroup))];
 const duplicate = selected && options.some(item => item.id !== selected.id && item.name.trim().toLocaleLowerCase() === selected.name.trim().toLocaleLowerCase());
 return <div className="material-picker">
  {search && options.length >= 12 && <input className="material-picker-search" type="search" aria-label={`Search ${aria['aria-label'] ?? 'materials'}`} placeholder={options.some(item => item.code) ? 'Find by name or code' : 'Find by name'} maxLength={120} disabled={disabled} value={query} onChange={event => setQuery(event.target.value)} onKeyDown={event => { if (event.key === "Enter") event.preventDefault(); if (event.key === "Escape") setQuery(''); }} />}
  <select {...aria} id={selectId} name={name} value={value} required={required} disabled={disabled} aria-describedby={`${selectId}-detail`} onChange={event => { onChange(event.target.value); setQuery(''); }}>
   <option value="">{query && !shown.length ? 'No matching materials' : placeholder}</option>
   {groups.map(group => <optgroup label={group} key={group}>{shown.filter(item => materialGroup(item) === group).map(item => <option key={item.id} value={item.id} disabled={item.disabled}>{item.name}</option>)}</optgroup>)}
  </select>
  <div id={`${selectId}-detail`} className="material-picker-detail">
   {selected && <><span>{selected.unit ? `Unit: ${selected.unit}` : 'Unit not supplied'}{selected.item_type ? ` · ${materialGroup(selected)}` : ''}</span>{selected.detail && <small>{selected.detail}</small>}{selected.code && <details><summary>Material code</summary><span>{selected.code}</span></details>}{duplicate && <small role="status">Another material has this name. Check its unit and material code.</small>}</>}
   {query && <small role="status">{options.filter(item => materialMatches(item, query)).length} matches{selected && !materialMatches(selected, query) ? ' · current selection retained' : ''}</small>}
  </div>
 </div>;
}
