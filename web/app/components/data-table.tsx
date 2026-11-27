import type { ReactNode } from "react";
import {displayQuantity} from "@/lib/recipes";
const numberCell=(cell:ReactNode,numeric?:boolean)=>numeric&&(typeof cell==='number'||typeof cell==='string'&&/^-?\d+\.\d{4,}$/.test(cell))?displayQuantity(cell as string|number):cell;

export function TableScroll({children,label}:{children:ReactNode;label:string}) {
 return <div className="data-table-shell"><div className="data-table-scroll procurement-table-scroll" role="region" aria-label={label} tabIndex={0}>{children}</div><p className="data-table-scroll-hint">Scroll across to see all columns</p></div>;
}

export function StatusBadge({children,tone="neutral"}:{children:ReactNode;tone?:"neutral"|"success"|"warning"|"danger"}) {
 return <span className={`record-status record-status-${tone}`}>{children}</span>;
}

export function DataTable({label,columns,rows,empty="No records to display."}:{label:string;columns:{label:string;numeric?:boolean}[];rows:{id:string;cells:ReactNode[]}[];empty?:string}) {
 return <TableScroll label={label}><table className="data-table" aria-label={label}><thead><tr>{columns.map((column,index)=><th key={index} scope="col" className={column.numeric?"numeric":undefined}>{column.label}</th>)}</tr></thead><tbody>{rows.map(row=><tr key={row.id}>{row.cells.map((cell,index)=>index===0?<th key={index} scope="row">{numberCell(cell,columns[index]?.numeric)}</th>:<td key={index} className={columns[index]?.numeric?"numeric":undefined}>{numberCell(cell,columns[index]?.numeric)}</td>)}</tr>)}{!rows.length&&<tr><td colSpan={columns.length} className="data-table-empty">{empty}</td></tr>}</tbody></table></TableScroll>;
}
