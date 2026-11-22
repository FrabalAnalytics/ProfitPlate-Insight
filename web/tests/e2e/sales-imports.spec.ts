import {clickNavigation} from './navigation';
import { test, expect, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
const headers = 'Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\r\n';
const source = headers + 'ORG001,POS_TEST,PRIMARY,2020-06-01,S001,L1,SALES-MENU,2,3000,0,0,3000,DINE_IN,NORMAL,,PAID\r\nORG001,POS_TEST,PRIMARY,2020-06-01,S002,L1,SALES-MENU,1,1500,150,0,1350,TAKEAWAY,NORMAL,,PAID';
async function openSales(page: Page, email = 'catalogue@example.test') {
 await page.goto('/login'); await page.getByLabel('Email address').fill(email); await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');
 await page.getByRole('button',{name:'Sign in',exact:true}).click(); await clickNavigation(page,'Sales & summary');
 await expect(page).toHaveURL(/\/workspace\/sales\?/);
}
async function upload(page: Page, text: string, filename: string) {
 await page.getByRole('link',{name:'Import sales',exact:true}).click();
 await page.getByLabel('Sales CSV',{exact:true}).setInputFiles({name:filename,mimeType:'text/csv',buffer:Buffer.from(text)});
 await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001'); await page.getByLabel('Sales source tax format',{exact:true}).selectOption('EXCLUSIVE');
 await page.getByRole('button',{name:'Validate sales file',exact:true}).click();
 await expect(page.getByRole('heading',{name:filename,exact:true,level:2})).toBeVisible();
}
async function setPeriod(page: Page, from: string, to=from) {
 const filters = page.locator('.sales-filter-panel');
 if (!await filters.evaluate(element=>element.hasAttribute('open'))) await filters.locator('summary').click();
 await page.getByLabel('Sales from',{exact:true}).fill(from); await page.getByLabel('Sales through',{exact:true}).fill(to);
 await page.getByRole('button',{name:'Update sales summary',exact:true}).click(); await expect(page).toHaveURL(new RegExp('from='+from));
}
const card = (page: Page, label: string) => page.locator('.sales-summary-cards article').filter({has:page.getByText(label,{exact:true})});
async function save(page: Page) {
 await page.getByRole('checkbox').check(); await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Sales import recorded'})).toBeVisible();
}

test('sales receipts reconcile and produce discounted period revenue without duplicate imports',async({page},testInfo)=>{
 await page.setViewportSize({width:1440,height:1000}); const errors:string[]=[]; page.on('pageerror',error=>errors.push(error.message));
 await openSales(page); await upload(page,source,'pilot-sales.csv');
 const navigation = page.getByRole('navigation',{name:'Main navigation',exact:true});
 await expect(navigation.getByRole('link',{name:'Sales & summary',exact:true})).toHaveAttribute('aria-current','page');
 const navBoxes = await navigation.getByRole('link').filter({visible:true}).evaluateAll(nodes => nodes.map(node => ({left:node.getBoundingClientRect().left,height:node.getBoundingClientRect().height})));
 expect(new Set(navBoxes.map(box=>box.left)).size).toBe(1); expect(navBoxes.every(box=>box.height>=44 && box.height<=48)).toBe(true);
 const firstLine = page.getByRole('table',{name:'Sales import lines',exact:true}).locator('.transaction-main').first();
 expect((await firstLine.boundingBox())!.height).toBeLessThan(100);
 await page.getByRole('button',{name:'Show details for S001 / L1',exact:true}).click();
 await expect(page.locator('.transaction-detail:not([hidden])').getByText('Customer total',{exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Hide details for S001 / L1',exact:true}).click();
 await page.screenshot({path:testInfo.outputPath('sales-transactions-desktop.png'),fullPage:true});
 await page.getByLabel('Customer total for S001 (Main outlet)',{exact:true}).fill('1'); await page.getByLabel('Customer total for S002 (Main outlet)',{exact:true}).fill('1350');
 await page.getByRole('checkbox').check(); await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();
 await expect(page.getByRole('alert').filter({hasText:'Receipt total does not reconcile'})).toBeVisible();
 await page.getByLabel('Customer total for S001 (Main outlet)',{exact:true}).fill('3000'); await save(page);
 const downloadPromise=page.waitForEvent('download'); await page.getByRole('button',{name:'Download original sales CSV',exact:true}).click();
 const download=await downloadPromise, path=testInfo.outputPath('original-sales.csv'); await download.saveAs(path); expect(await readFile(path,'utf8')).toBe(source);
 await setPeriod(page,'2020-06-01'); await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00'); await expect(card(page,'Estimated food cost')).toContainText('NGN 2,700.00');
 await expect(card(page,'Estimated food margin')).toContainText('NGN 1,650.00'); await expect(card(page,'Estimated food margin')).toContainText('37.93%'); await expect(page.locator('.sales-period-facts')).toContainText('2 receipts');
 await expect(page.locator('.sales-period-facts')).toContainText('3 menu units sold');
 await expect(page.getByText('Preparing your workspace…',{exact:true})).toHaveCount(0); await expect(page.locator('.sales-summary-cards')).toBeVisible();
 await page.screenshot({path:testInfo.outputPath('sales-summary-desktop.png'),fullPage:true});
 await upload(page,source,'repeat-sales.csv'); await expect(page.getByText('Already recorded — will skip',{exact:true})).toHaveCount(2); await save(page);
 await setPeriod(page,'2020-06-01'); await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00'); expect(errors).toEqual([]);
});

test('external menu, location and channel codes can be reviewed and mapped on mobile',async({page},testInfo)=>{
 await page.setViewportSize({width:375,height:812}); await openSales(page);
 await upload(page,headers+'ORG001,POS_TEST,EXT-LOC,2020-06-02,MAPPED,L1,EXT-MENU,1,1500,0,0,1500,EAT-IN,NORMAL,,PAID','mapped-sales.csv');
 await expect(page.getByText(/Unknown or retired sales channel/)).toBeVisible(); await expect(page.getByRole('button',{name:'Save reviewed sales',exact:true})).toHaveCount(0);
 await page.getByRole('link',{name:'Correct file or match menus',exact:true}).click();
 await page.getByText('Map source location codes (1)',{exact:true}).click(); await page.getByLabel('Map location EXT-LOC',{exact:true}).fill('PRIMARY');
 await page.getByText('Map source channel codes (1)',{exact:true}).click(); await page.getByLabel('Map channel EAT-IN',{exact:true}).selectOption('DINE_IN');
 await page.getByText('Match selling menus (1)',{exact:true}).click();await page.locator('.sales-menu-match').locator('summary').click();await page.getByLabel('Selling menu for EXT-MENU',{exact:true}).selectOption('SALES-MENU');
 await page.getByRole('button',{name:'Validate sales file',exact:true}).click(); await expect(page.getByRole('heading',{name:'Reconcile and save sales',exact:true})).toBeVisible();
 const mobileLine = page.locator('.transaction-main').first();
 expect((await mobileLine.boundingBox())!.height).toBeLessThan(190);
 await page.getByRole('button',{name:'Show details for MAPPED / L1',exact:true}).click();
 await expect(page.locator('.transaction-detail:not([hidden])').getByText('Customer total',{exact:true})).toBeVisible();
 await page.screenshot({path:testInfo.outputPath('sales-transactions-mobile.png'),fullPage:true});
 await page.getByRole('button',{name:'Hide details for MAPPED / L1',exact:true}).click();
 await page.getByLabel('Customer total for MAPPED (Main outlet)',{exact:true}).fill('1500'); await save(page);
 await setPeriod(page,'2020-06-02'); await expect(card(page,'Estimated food margin')).toContainText('NGN 600.00');
 await expect(page.getByText('Preparing your workspace…',{exact:true})).toHaveCount(0); await expect(page.locator('.sales-summary-cards')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true); await page.screenshot({path:testInfo.outputPath('sales-summary-mobile.png'),fullPage:true});
});

test('missing ingredient costs keep recorded revenue visible and block full period margins',async({page})=>{
 await openSales(page); await upload(page,headers+'ORG001,POS_TEST,PRIMARY,2020-06-03,UNCOSTED,L1,SALES-NOCOST,1,1000,0,0,1000,DINE_IN,NORMAL,,PAID','uncosted-sales.csv');
 await page.getByLabel('Customer total for UNCOSTED (Main outlet)',{exact:true}).fill('1000'); await save(page);
 await setPeriod(page,'2020-06-01','2020-06-03'); await expect(card(page,'Recorded net sales')).toContainText('NGN 6,850.00');
 await expect(card(page,'Estimated food cost')).toContainText('Incomplete'); await expect(card(page,'Estimated food margin')).toContainText('Unavailable');
 await expect(page.locator('.sales-missing')).toContainText('1 sales line needs usable costs');
 await expect(page.getByRole('link',{name:/Sales uncosted dish.*2020-06-03/})).toBeVisible();
});

test('combo rows block the whole file and an unposted attempt can be cancelled',async({page})=>{
 await openSales(page);
 await upload(page,headers+'ORG001,POS_TEST,PRIMARY,2020-06-01,COMBO,L1,SALES-MENU,1,1500,0,0,1500,DINE_IN,NORMAL,,PAID\r\nORG001,POS_TEST,PRIMARY,2020-06-01,COMBO,L2,SALES-MENU,1,0,0,0,0,DINE_IN,COMBO_CHILD,L1,PAID','unsupported-sales.csv');
 await expect(page.getByText(/Only NORMAL lines with a blank Parent_Line_Ref/)).toBeVisible(); await expect(page.getByRole('button',{name:'Save reviewed sales',exact:true})).toHaveCount(0);
 await page.getByRole('button',{name:'Cancel unposted sales import',exact:true}).click(); await expect(page.locator('.purchase-batch-heading')).toContainText('Cancelled');
 await expect(page.getByRole('button',{name:'Download original sales CSV',exact:true})).toBeVisible();
});

test('finance can review sales and period estimates without upload or posting controls',async({page})=>{
 await openSales(page,'reader@example.test'); await expect(page.getByText(/You have read-only sales access/)).toBeVisible();
 await expect(page.getByRole('link',{name:'Import sales',exact:true})).toHaveCount(0); await setPeriod(page,'2020-06-01');
 await expect(card(page,'Recorded net sales')).toContainText('NGN 4,350.00');
 await page.getByRole('link',{name:'Review sales import pilot-sales.csv',exact:true}).click();
 await expect(page.getByRole('button',{name:'Download original sales CSV',exact:true})).toBeVisible();
 await page.goto(page.url()+'&new=1'); await expect(page.getByLabel('Sales CSV',{exact:true})).toHaveCount(0);
});
