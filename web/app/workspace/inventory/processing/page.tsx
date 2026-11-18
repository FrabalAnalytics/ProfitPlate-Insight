import ProcessingHistory from './history';
export const instant=false;
export default async function Page({searchParams}:{searchParams:Parameters<typeof ProcessingHistory>[0]['searchParams']}){return <ProcessingHistory searchParams={searchParams}/>;}
