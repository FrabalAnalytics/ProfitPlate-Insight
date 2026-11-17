"use client";

import { Fragment, useId, useState, type ReactNode } from "react";
import { ChevronDown } from "lucide-react";
import {TableScroll,StatusBadge} from "./data-table";
import "./transaction-table.css";

export type TransactionRow = {
  id: string; date: string; reference: string; item: string; context: string;
  quantity: string; amount: string; status: string; attention?: boolean;
  notices: ReactNode; details: ReactNode;
};

/** Shared record-table styling, horizontal scrolling and accessible row details. */
export function TransactionTable({ rows, label, amountLabel, quantityLabel="Quantity" }: {
  rows: TransactionRow[]; label: string; amountLabel: string; quantityLabel?:string;
}) {
  const prefix = useId();
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  if (!rows.length) return null;
  return <TableScroll label={label}><table className="transaction-table data-table" aria-label={label}>
    <thead><tr><th scope="col">Date / reference</th><th scope="col">Item / location</th><th scope="col" className="transaction-number numeric">{quantityLabel}</th><th scope="col" className="transaction-number numeric">{amountLabel}</th><th scope="col">Status</th><th scope="col"><span className="sr-only">Details</span></th></tr></thead>
    <tbody>{rows.map((row, index) => {
      const open = expanded.has(row.id), detailId = `${prefix}-${index}`;
      return <Fragment key={row.id}>
        <tr className={`transaction-main ${row.attention ? "transaction-attention" : ""}`}>
          <td className="transaction-reference"><time dateTime={row.date}>{row.date || "Date missing"}</time><small>{row.reference}</small></td>
          <th scope="row" className="transaction-item"><strong>{row.item || "Unresolved item"}</strong><small>{row.context}</small></th>
          <td className="transaction-quantity transaction-number numeric">{row.quantity}</td>
          <td className="transaction-amount transaction-number numeric"><span className="sr-only">{amountLabel}: </span>{row.amount}</td>
          <td className="transaction-state"><StatusBadge tone={row.attention?"warning":row.status==="Voided"?"danger":/recorded|ready/i.test(row.status)?"success":"neutral"}>{row.status}</StatusBadge></td>
          <td className="transaction-toggle"><button type="button" aria-label={`${open ? "Hide" : "Show"} details for ${row.reference}`} aria-expanded={open} aria-controls={detailId} onClick={() => setExpanded(previous => { const next = new Set(previous); if (next.has(row.id)) next.delete(row.id); else next.add(row.id); return next; })}><ChevronDown size={16} aria-hidden="true"/><span className="transaction-mobile-meta">Details</span></button></td>
        </tr>
        {row.notices && <tr className="transaction-notices"><td colSpan={6}>{row.notices}</td></tr>}
        <tr id={detailId} hidden={!open} className="transaction-detail"><td colSpan={6}><div className="transaction-detail-content">{row.details}</div></td></tr>
      </Fragment>;
    })}</tbody>
  </table></TableScroll>;
}
