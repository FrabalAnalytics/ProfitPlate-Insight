'use client';
import Link from 'next/link';
import {useSearchParams} from 'next/navigation';
import {contextQuery,type NavigationAccess,type ReportingContext} from '@/lib/overview';
import {reviewRoles} from '@/lib/management-reviews';
import './report-navigation.css';

export function ReportNavigation({organisation,pathname,roles,access,context}:{organisation:string;pathname:string;roles:string[];access:NavigationAccess;context?:ReportingContext}){
 const params=useSearchParams();
 const performance=pathname==='/workspace/performance'||pathname==='/workspace/overview';
 const reviews=pathname.startsWith('/workspace/reviews')||pathname.startsWith('/workspace/reports');
 if(!performance&&!reviews)return null;
 const selectedContext=context??{from:params.get('from')??undefined,to:params.get('to')??undefined,location:params.get('location')??undefined};
 const financial=access.overview;
 const operational=roles.includes('operations')&&!roles.includes('ceo');
 const links=performance?[
  {label:operational?'Operational overview':'Summary',path:'/workspace/performance',allowed:financial||operational,active:pathname==='/workspace/performance'},
  {label:'Sales & margin detail',path:'/workspace/overview',allowed:financial,active:pathname==='/workspace/overview'},
 ]:[
  {label:'Period reviews',path:'/workspace/reviews',allowed:roles.some(r=>reviewRoles.includes(r)),active:pathname==='/workspace/reviews'||pathname.startsWith('/workspace/reviews/history')},
  {label:'Financial report',path:'/workspace/reports',allowed:financial,active:pathname.startsWith('/workspace/reports')},
  {label:'Monthly close',path:'/workspace/reviews/close',allowed:roles.some(r=>['ceo','finance','restaurant_admin','operations'].includes(r)),active:pathname.startsWith('/workspace/reviews/close')},
 ];
 const href=(path:string)=>{const extra:Record<string,string>={};if(path==='/workspace/reviews/close'){const month=params.get('month')??selectedContext.from?.slice(0,7);if(month&&/^\d{4}-(0[1-9]|1[0-2])$/.test(month))extra.month=month;if(params.get('site'))extra.site=params.get('site')!;}return `${path}?${contextQuery(organisation,selectedContext,extra)}`;};
 return <nav className="report-subnavigation" aria-label={performance?'Business performance views':'Management review sections'}>{links.filter(l=>l.allowed).map(l=><Link key={l.path} href={href(l.path)} aria-current={l.active?'page':undefined}>{l.label}</Link>)}</nav>;
}
