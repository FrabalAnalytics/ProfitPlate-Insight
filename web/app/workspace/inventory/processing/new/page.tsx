import {OperationalEntry} from '../../operational-entry';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Promise<{organisation?:string}>}){return <OperationalEntry searchParams={searchParams} kind="PRODUCTION"/>;}
