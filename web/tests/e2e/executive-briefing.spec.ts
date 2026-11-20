import {clickNavigation} from './navigation';
import {test,expect} from '@playwright/test';

test('CEO sees profitability changes and accountable exceptions with source links, without operational task cards',async({page},testInfo)=>{
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill('catalogue@example.test');await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
 await expect(page.getByRole('heading',{name:'Executive workspace',exact:true})).toBeVisible();await expect(page.getByRole('heading',{name:'Your daily work',exact:true})).toHaveCount(0);await expect(page.getByRole('heading',{name:'Recorded invoice price changes',exact:true})).toBeVisible();
 await clickNavigation(page,'Sales & summary');await page.getByRole('link',{name:'Import sales',exact:true}).click();
 const csv='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\nORG001,CEO_POS,PRIMARY,2020-08-10,CEO-PRIOR,1,SALES-MENU,1,2000,0,0,2000,DINE_IN,NORMAL,,PAID\nORG001,CEO_POS,PRIMARY,2020-08-11,CEO-CURRENT,1,SALES-MENU,2,3000,0,0,3000,DINE_IN,NORMAL,,PAID';
 await page.getByLabel('Sales CSV',{exact:true}).setInputFiles({name:'ceo-sales.csv',mimeType:'text/csv',buffer:Buffer.from(csv)});await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001');await page.getByLabel('Sales source tax format',{exact:true}).selectOption('EXCLUSIVE');await page.getByRole('button',{name:'Validate sales file',exact:true}).click();
 for(const[ref,total]of[['CEO-PRIOR','2000'],['CEO-CURRENT','3000']])await page.getByLabel(`Customer total for ${ref} (Main outlet)`,{exact:true}).fill(total);
 await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Sales import recorded'})).toBeVisible();
 const org=new URL(page.url()).searchParams.get('organisation')!;
 await page.goto(`/workspace?organisation=${org}&from=2020-08-11&to=2020-08-11`);
 const metrics=page.getByRole('region',{name:'CEO performance metrics'});
 await expect(metrics).toContainText('NGN 3,000.00');await expect(metrics).toContainText('60%');await expect(metrics).toContainText('+15 pp');await expect(metrics).toContainText('-15 pp');await expect(metrics).toContainText('NGN 1,200.00');
 await expect(page.getByRole('table',{name:'Menu margin watch'})).toContainText('Sales test dish');await expect(page.getByRole('table',{name:'Menu margin watch'})).toContainText('Main outlet');
 await expect(page.getByRole('link',{name:'Record supplier invoice',exact:true})).toHaveCount(0);await expect(page.getByRole('link',{name:'Record expense',exact:true})).toHaveCount(0);
 await page.getByRole('button',{name:'Refresh briefing',exact:true}).click();await expect(metrics).toContainText('NGN 3,000.00');
 await expect(page.getByRole('button',{name:'Refresh briefing',exact:true})).toBeEnabled();await page.screenshot({path:testInfo.outputPath('ceo-briefing-desktop.png'),fullPage:true});
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:testInfo.outputPath('ceo-briefing-mobile.png'),fullPage:true});
 await page.getByText('Change period or outlet',{exact:true}).click();await page.getByLabel('From',{exact:true}).fill('2020-08-20');await page.getByLabel('Through',{exact:true}).fill('2020-08-20');await page.getByRole('button',{name:'Update briefing',exact:true}).click();await expect(page.getByText('No sales recorded for this period.',{exact:false})).toBeVisible();await expect(page.getByRole('heading',{name:'Material movement accountability',exact:true})).toBeVisible();
 await page.goto(`/workspace?organisation=${org}&from=bad&to=2020-08-11`);await expect(page.getByRole('alert').filter({hasText:'Executive briefing unavailable'})).toContainText('Choose valid dates');
});
