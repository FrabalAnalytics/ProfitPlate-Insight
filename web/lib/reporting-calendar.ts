export const weekdays=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'] as const;
export type ReportingCalendar={timezone:string;week_start:number|null;count_day:number|null;cutoff:string|null;week_from:string|null;week_to:string|null};
