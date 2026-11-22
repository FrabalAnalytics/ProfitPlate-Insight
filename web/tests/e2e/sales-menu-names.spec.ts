import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import {clickNavigation} from './navigation';

const headers='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Name,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status';
const csv=(name:string,receipt:string)=>`${headers}\r\nORG001,NAME_BROWSER,PRIMARY,2020-08-20,${receipt},L1,${name},1,6000,0,0,6000,DINE_IN,NORMAL,,PAID`;
async function open(page:Page){
 await page.goto('/login');await page.getByLabel('Email address').fill('catalogue@example.test');await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await clickNavigation(page,'Sales & summary');
}
async function upload(page:Page,text:string,filename:string){
 await page.getByRole('link',{name:'Import sales',exact:true}).click();
 await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001');await page.getByLabel('Sales source tax format',{exact:true}).selectOption('EXCLUSIVE');
 await page.getByLabel('Sales CSV',{exact:true}).setInputFiles({name:filename,mimeType:'text/csv',buffer:Buffer.from(text)});await expect(page.getByText(`${filename} is selected.`,{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Validate sales file',exact:true}).click();await expect(page.getByRole('heading',{name:filename,exact:true})).toBeVisible();
}
test('POS names match automatically, unmatched names are selected by menu and remembered after saving',async({page},testInfo)=>{
 await open(page);await upload(page,csv('Sales test dish','NAME-AUTO'),'name-auto.csv');
 const review=page.getByRole('table',{name:'Matched menus and stock centres',exact:true});await expect(review).toContainText('Sales test dish');await expect(review).toContainText('Menu cost recipe');await expect(review).toContainText('Name matched');
 await clickNavigation(page,'Sales & summary');
 await upload(page,csv('POS Kitchen Special','NAME-SELECT'),'name-select.csv');await expect(page.getByText(/No matching menu name at this outlet/)).toBeVisible();
 await page.getByRole('link',{name:'Correct file or match menus',exact:true}).click();await page.getByText('Match selling menus (1)',{exact:true}).click();await page.locator('.sales-menu-match summary').click();
 const picker=page.getByLabel('Selling menu for POS Kitchen Special',{exact:true});await expect(picker).toBeEnabled();await expect(picker.locator('option[value="SALES-MENU"]')).toContainText('Sales test dish');await picker.selectOption('SALES-MENU');
 await page.getByRole('button',{name:'Validate sales file',exact:true}).click();await expect(review).toContainText('Selected during review');await expect(review).toContainText('No stock centre assigned on the sales date');
 await page.getByLabel('Customer total for NAME-SELECT (Main outlet)',{exact:true}).fill('6000');await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Sales import recorded'})).toBeVisible();
 await upload(page,csv('POS Kitchen Special','NAME-REMEMBER'),'name-remember.csv');await expect(review).toContainText('Saved POS match');await expect(review).toContainText('Sales test dish');await expect(page.getByRole('heading',{name:'Reconcile and save sales',exact:true})).toBeVisible();
 await page.screenshot({path:testInfo.outputPath('name-first-review.png'),fullPage:true});
});
test('training download uses the current restaurant menu and keeps the legacy code template available',async({page},testInfo)=>{
 await open(page);await page.getByRole('link',{name:'Import sales',exact:true}).click();
 const promise=page.waitForEvent('download');await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();const download=await promise,path=testInfo.outputPath('training-sales.csv');await download.saveAs(path);const text=(await readFile(path,'utf8')).replace(/^\uFEFF/,'').replaceAll('"','');
 expect(text.split('\r\n')[0]).toBe(headers);expect(text).toContain('TRAINING,PROFITPLATE_TRAINING,PRIMARY,');expect(text).toContain('Sales test dish');expect(text).toContain(',12000,0,0,12000,');expect(text).toContain(',6000,150,0,5850,');
 await expect(page.getByLabel('Source organisation code',{exact:true})).toHaveValue('TRAINING');await page.getByText('Using an earlier code-based export?',{exact:true}).click();await expect(page.getByRole('link',{name:'Download code-based CSV template',exact:true})).toHaveAttribute('href','/templates/sales-import-codes.csv');
});
test('sample setup errors appear on the page without creating a broken download and retry succeeds',async({page})=>{
 await open(page);await page.getByRole('link',{name:'Import sales',exact:true}).click();
 const downloads:string[]=[];page.on('download',download=>downloads.push(download.suggestedFilename()));
 await page.getByLabel('Source organisation code',{exact:true}).fill('MY_POS');
 const endpoint='**/workspace/sales/sample?*';
 await page.route(endpoint,route=>route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({error:'Publish a final-recipe-linked selling menu at an active outlet before downloading its training sample.'})}));
 await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();await expect(page.getByRole('alert').filter({hasText:'Publish a final-recipe-linked selling menu'})).toBeVisible();
 await expect(page.getByLabel('Source organisation code',{exact:true})).toHaveValue('MY_POS');expect(downloads).toEqual([]);
 await page.unroute(endpoint);const next=page.waitForEvent('download');await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();const downloaded=await next;expect(downloaded.suggestedFilename()).toMatch(/^ProfitPlate_training_sales_\d{4}-\d{2}-\d{2}\.csv$/);await expect(page.getByRole('alert').filter({hasText:'Publish a final-recipe-linked selling menu'})).toHaveCount(0);
});
test('sample connection errors and sign-in responses never download as CSV',async({page})=>{
 await open(page);await page.getByRole('link',{name:'Import sales',exact:true}).click();const downloads:string[]=[];page.on('download',d=>downloads.push(d.suggestedFilename()));const endpoint='**/workspace/sales/sample?*';
 await page.route(endpoint,route=>route.abort('failed'));await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();await expect(page.getByRole('alert').filter({hasText:'Check your connection'})).toBeVisible();await page.unroute(endpoint);
 await page.route(endpoint,route=>route.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:'Your session has expired. Sign in again, then retry the download.'})}));await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();await expect(page.getByRole('alert').filter({hasText:'Your session has expired'})).toBeVisible();await page.unroute(endpoint);
 await page.route(endpoint,route=>route.fulfill({status:200,contentType:'text/html',body:'<html>Sign in</html>'}));await page.getByRole('button',{name:'Download restaurant training sample',exact:true}).click();await expect(page.getByRole('alert').filter({hasText:'Refresh the page'})).toBeVisible();expect(downloads).toEqual([]);
});
test('sample endpoint returns structured private errors for invalid or inaccessible restaurants',async({page})=>{
 await open(page);const invalid=await page.request.get('/workspace/sales/sample?organisation=invalid');expect(invalid.status()).toBe(400);expect(await invalid.json()).toEqual({error:'Choose your training restaurant.'});expect(invalid.headers()['cache-control']).toContain('no-store');
 const foreign=await page.request.get('/workspace/sales/sample?organisation=00000000-0000-0000-0000-000000000001');expect(foreign.status()).toBe(403);expect((await foreign.json()).error).toContain('does not have sales-import access');expect(foreign.headers()['content-disposition']).toBeUndefined();
});
