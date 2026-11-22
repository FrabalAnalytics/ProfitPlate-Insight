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
 const promise=page.waitForEvent('download');await page.getByRole('link',{name:'Download restaurant training sample',exact:true}).click();const download=await promise,path=testInfo.outputPath('training-sales.csv');await download.saveAs(path);const text=(await readFile(path,'utf8')).replace(/^\uFEFF/,'').replaceAll('"','');
 expect(text.split('\r\n')[0]).toBe(headers);expect(text).toContain('TRAINING,PROFITPLATE_TRAINING,PRIMARY,');expect(text).toContain('Sales test dish');expect(text).toContain(',12000,0,0,12000,');expect(text).toContain(',6000,150,0,5850,');
 await expect(page.getByLabel('Source organisation code',{exact:true})).toHaveValue('TRAINING');await page.getByText('Using an earlier code-based export?',{exact:true}).click();await expect(page.getByRole('link',{name:'Download code-based CSV template',exact:true})).toHaveAttribute('href','/templates/sales-import-codes.csv');
});
