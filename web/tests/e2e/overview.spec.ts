import {clickNavigation} from './navigation';
import {test,expect,type Page} from '@playwright/test';
const headers='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\n';
async function login(page:Page,email='catalogue@example.test') {
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
}
async function openNavigation(page:Page) {if((page.viewportSize()?.width??1440)<=900){await page.getByRole('button',{name:'Open navigation',exact:true}).click();}}
async function period(page:Page,from:string,to=from) {
 const filter=page.locator('.overview-filter:visible');if(!await filter.evaluate(e=>e.hasAttribute('open')))await filter.locator('summary').click();await page.getByLabel('Overview from',{exact:true}).fill(from);await page.getByLabel('Overview through',{exact:true}).fill(to);await page.getByRole('button',{name:'Update overview',exact:true}).click();await expect(page).toHaveURL(url=>url.pathname==='/workspace/overview'&&url.searchParams.get('from')===from&&url.searchParams.get('to')===to);await expect(page.getByRole('heading',{name:'Executive overview',exact:true})).toBeVisible();await expect(page.locator('.overview-context:visible')).toContainText(`${from} to ${to}`);
}
async function record(page:Page,rows:string[],totals:Record<string,string>,name:string) {
 await clickNavigation(page,'Sales & summary');await page.getByRole('link',{name:'Import sales',exact:true}).click();
 await page.getByLabel('Sales CSV',{exact:true}).setInputFiles({name,mimeType:'text/csv',buffer:Buffer.from(headers+rows.join('\n'))});await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001');await page.getByLabel('Sales source tax format',{exact:true}).selectOption('EXCLUSIVE');await page.getByRole('button',{name:'Validate sales file',exact:true}).click();
 for(const [ref,amount] of Object.entries(totals))await page.getByLabel(`Customer total for ${ref} (Main outlet)`,{exact:true}).fill(amount);
 await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Sales import recorded'})).toBeVisible();
 await openNavigation(page);await page.getByRole('link',{name:'Executive overview',exact:true}).click();await expect(page.getByRole('heading',{name:'Executive overview',exact:true})).toBeVisible();
}
const card=(page:Page,name:string)=>page.locator('.overview-kpis:visible article').filter({has:page.getByText(name,{exact:true})});

test('overview reconciles imported data, distinguishes missing days and preserves context through source drill-down',async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));await page.setViewportSize({width:1440,height:1000});await login(page);
 await record(page,[
 'ORG001,OV_POS,PRIMARY,2020-04-09,OV-PRIOR,1,SALES-MENU,1,2000,0,0,2000,DINE_IN,NORMAL,,PAID',
 'ORG001,OV_POS,PRIMARY,2020-04-10,OV-A,1,SALES-MENU,2,3000,0,0,3000,DINE_IN,NORMAL,,PAID',
 'ORG001,OV_POS,PRIMARY,2020-04-11,OV-B,1,SALES-MENU,1,1500,150,0,1350,TAKEAWAY,NORMAL,,PAID'],{'OV-PRIOR':'2000','OV-A':'3000','OV-B':'1350'},'overview-sales.csv');
 await period(page,'2020-04-10','2020-04-12');await expect(card(page,'Recorded net sales')).toBeVisible();await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00');await expect(card(page,'Estimated food cost')).toContainText('NGN 2,700.00');await expect(card(page,'Estimated food cost')).toContainText('62.07%');await expect(card(page,'Estimated food margin')).toContainText('NGN 1,650.00');await expect(card(page,'Recorded net sales')).toContainText('117.5%');
 await page.getByLabel('Inspect sales date',{exact:true}).selectOption('2');await expect(page.locator('.overview-chart-control')).toContainText('No records');
 await page.getByText('View daily figures',{exact:true}).click();await expect(page.getByRole('table',{name:'Daily recorded sales',exact:true}).getByRole('row').filter({hasText:'2020-04-12'})).toContainText('No records');
 await expect(page.getByText('Preparing your workspace\u2026',{exact:true})).toHaveCount(0);await page.evaluate(()=>scrollTo(0,0));await page.evaluate(()=>document.fonts.ready);await page.screenshot({path:testInfo.outputPath('overview-desktop.png'),fullPage:true});
 const outletLink=page.getByRole('table',{name:'Outlet comparison'}).getByRole('link').first();const selected=new URL((await outletLink.getAttribute('href'))!,page.url()).searchParams.get('location');await outletLink.click();await expect(page).toHaveURL(url=>url.pathname==='/workspace/overview'&&url.searchParams.get('location')===selected);await expect(page.locator('.overview-context:visible > div > span')).toContainText('Main outlet');
 await page.getByRole('link',{name:'View sales',exact:true}).click();await expect(page).toHaveURL(url=>url.pathname==='/workspace/sales'&&url.searchParams.get('from')==='2020-04-10');await expect(page.getByRole('heading',{name:'Sales & margin',exact:true})).toBeVisible();expect(new URL(page.url()).searchParams.get('location')).toBe(selected);
 await page.getByRole('link',{name:'Executive overview',exact:true}).click();await expect(card(page,'Recorded net sales')).toBeVisible();await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00');
 const refreshed=await page.locator('.overview-basis:visible time').getAttribute('datetime');await page.getByRole('button',{name:'Refresh overview',exact:true}).click();await expect(page.locator('.overview-basis:visible time')).not.toHaveAttribute('datetime',refreshed!);
 await page.getByRole('table',{name:'Recent recorded receipts'}).getByRole('link',{name:'OV-B',exact:true}).click();await expect(page.getByRole('heading',{name:'overview-sales.csv',exact:true,level:2})).toBeVisible();await expect(page).toHaveURL(/from=2020-04-10/);expect(errors).toEqual([]);
});

test('finance has a readable mobile overview without team-management navigation',async({page},testInfo)=>{
 await page.setViewportSize({width:375,height:812});await login(page,'reader@example.test');await openNavigation(page);await expect(page.getByRole('link',{name:'Users & roles',exact:true})).toHaveCount(0);await page.getByRole('link',{name:'Executive overview',exact:true}).click();await period(page,'2020-04-10','2020-04-12');await expect(card(page,'Recorded net sales')).toBeVisible();await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await expect(page.getByText('Preparing your workspace\u2026',{exact:true})).toHaveCount(0);await page.evaluate(()=>scrollTo(0,0));await page.evaluate(()=>document.fonts.ready);await page.screenshot({path:testInfo.outputPath('overview-mobile.png'),fullPage:true});
 await period(page,'2020-03-01');await expect(page.getByRole('heading',{name:'No recorded sales for this selection.',exact:true})).toBeVisible();await expect(page.locator('.overview-kpis')).toHaveCount(0);
});

test('missing costs retain revenue while the overview blocks full margin and links the saved version',async({page})=>{
 await login(page);await record(page,['ORG001,OV_POS,PRIMARY,2020-04-13,OV-MISSING,1,SALES-NOCOST,1,1000,0,0,1000,DINE_IN,NORMAL,,PAID'],{'OV-MISSING':'1000'},'overview-missing.csv');await period(page,'2020-04-10','2020-04-13');
 await expect(card(page,'Recorded net sales')).toContainText('NGN 5,350.00');await expect(card(page,'Estimated food cost')).toContainText('Incomplete');await expect(card(page,'Estimated food margin')).toContainText('Unavailable');
 const link=page.getByRole('link',{name:/Review Sales uncosted dish/});await expect(link).toBeVisible();const href=await link.getAttribute('href');expect(href).toContain('version=');expect(href).toContain('date=2020-04-13');
});

test('fully discounted sales expose a negative food margin and no percentage at zero revenue',async({page})=>{
 await login(page);await record(page,['ORG001,OV_POS,PRIMARY,2020-04-14,OV-FREE,1,SALES-MENU,1,1500,1500,0,0,DINE_IN,NORMAL,,PAID'],{'OV-FREE':'0'},'overview-free.csv');await period(page,'2020-04-14');await expect(card(page,'Recorded net sales')).toContainText('NGN 0.00');await expect(card(page,'Estimated food margin')).toContainText('Percentage undefined for zero net sales');await expect(page.locator('.overview-loss')).toContainText('Recorded revenue is below');
});
