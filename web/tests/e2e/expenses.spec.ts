import {clickNavigation} from './navigation';
import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
const headers='Organisation_Code,Source_System,Expense_Ref,Line_Ref,Category_Code,Scope,Location_Code,Expense_From,Expense_To,Recognition_Method,Payment_Date,Amount,Currency,Description\r\n';
const source=headers+'ORG001,EXP_TEST,WAGES-TEST,1,WAGES,LOCATION,PRIMARY,2020-05-15,2020-05-15,ON_DATE,2020-05-14,600,NGN,Fictional wages\r\nORG001,EXP_TEST,RENT-TEST,1,RENT,CENTRAL,,2020-05-01,2020-05-30,DAILY,2020-05-01,3000,NGN,Fictional rent';
const hydrationErrors=new WeakMap<Page,string[]>();
test.beforeEach(async({page})=>{
 const errors:string[]=[];hydrationErrors.set(page,errors);
 page.on('console',message=>{if(message.type()==='error'&&/hydrat|server rendered HTML|Minified React error #(418|425)/i.test(message.text()))errors.push(message.text());});
 page.on('pageerror',error=>errors.push(error.message));
});
test.afterEach(async({page})=>{expect(hydrationErrors.get(page)??[],'Expense pages must hydrate without console or runtime errors').toEqual([]);});
async function login(page:Page,email='catalogue@example.test') {
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
}
async function openNav(page:Page) {if((page.viewportSize()?.width??1440)<=900)await page.getByRole('button',{name:'Open navigation',exact:true}).click();}
async function expenses(page:Page) {await clickNavigation(page,'Labour & expenses');await expect(page.getByRole('heading',{name:'Labour & operating expenses',exact:true})).toBeVisible();}
async function period(page:Page,from='2020-05-15',location='') {
 const filter=page.locator('.expense-report-context:visible details');if(!await filter.evaluate(e=>e.hasAttribute('open')))await filter.locator('summary').click();await page.getByLabel('Report from',{exact:true}).fill(from);await page.getByLabel('Report through',{exact:true}).fill(from);await page.getByLabel('Report location',{exact:true}).selectOption(location);await page.getByRole('button',{name:'Update expense report',exact:true}).click();await expect(page).toHaveURL(url=>url.pathname==='/workspace/expenses'&&url.searchParams.get('from')===from&&url.searchParams.get('location')===location);await expect(page.locator('.expense-report-context:visible > div > strong')).toContainText(from);
}
const card=(page:Page,name:string)=>page.locator('.expense-kpis:visible article').filter({has:page.getByText(name,{exact:true})});
async function checkOverviewCosts(page:Page,labour:string,prime:string) {
 await clickNavigation(page,'Sales & margin detail');
 const panel=page.getByRole('region',{name:'Labour & operating costs',exact:true});await expect(panel).toBeVisible();
 const costCard=(name:string)=>panel.locator('article').filter({has:page.getByText(name,{exact:true})});
 await expect(costCard('Recorded labour')).toContainText(labour);await expect(costCard('Estimated prime cost')).toContainText(prime);
 const expenseLink=panel.getByRole('link',{name:'Review costs',exact:true});const current=new URL(page.url()),target=new URL((await expenseLink.getAttribute('href'))!,page.url());
 for(const key of ['organisation','from','to','location'])expect(target.searchParams.get(key)).toBe(current.searchParams.get(key));
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:test.info().outputPath('overview-costs.png'),fullPage:true});
 await expenseLink.click();await expect(page.getByRole('heading',{name:'Labour & operating expenses',exact:true})).toBeVisible();
}
async function upload(page:Page,name:string,text=source) {
 await page.getByRole('link',{name:'Add expenses',exact:true}).click();await page.getByRole('button',{name:'CSV import',exact:true}).click();await page.getByLabel('Expense CSV',{exact:true}).setInputFiles({name,mimeType:'text/csv',buffer:Buffer.from(text)});await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001');await page.getByRole('button',{name:'Review expenses',exact:true}).click();await expect(page.getByRole('heading',{name,exact:true,level:2})).toBeVisible();
}
async function post(page:Page,total:string) {
 const form=page.locator('.expense-approval:visible');await form.getByLabel('Source total for all uploaded lines',{exact:true}).fill(total);await form.getByRole('checkbox').check();await form.getByRole('button',{name:'Record reviewed expenses',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Expenses recorded.'})).toBeVisible();
}
async function review(page:Page,kind='labour') {
 const form=page.locator('.expense-coverage-form:visible').filter({has:page.locator(`input[name=kind][value=${kind==='labour'?'LABOUR':'OPERATING'}]`)});await form.getByRole('checkbox').check();await form.getByRole('button',{name:`Confirm ${kind} coverage`,exact:true}).click();await expect(page.locator('.expense-review-panel:visible .expense-coverage-grid > div').filter({has:page.locator('h3').filter({hasText:kind==='labour'?'Labour coverage':'Operating expense coverage'})}).locator('.expense-coverage-state')).toHaveText('Reviewed');
}
test('expense source review, daily allocation, coverage and duplicate protection feed the estimated prime cost',async({page},testInfo)=>{
 await page.setViewportSize({width:1440,height:1000});await login(page);
 // A distinct period keeps these recorded-sales fixtures independent of other modules.
 await clickNavigation(page,'Sales & summary');await page.getByRole('link',{name:'Import sales',exact:true}).click();
 const sales='Organisation_Code,Source_System,Location_Code,Sale_Date,Transaction_Ref,Line_Ref,Menu_Code,Quantity,Gross_Sales,Discount,Tax,Net_Sales,Channel_Code,Line_Type,Parent_Line_Ref,Status\nORG001,EXP_POS,PRIMARY,2020-05-15,EXP-SALE,1,SALES-MENU,3,4500,150,0,4350,DINE_IN,NORMAL,,PAID';
 await page.getByLabel('Sales CSV',{exact:true}).setInputFiles({name:'expense-sales.csv',mimeType:'text/csv',buffer:Buffer.from(sales)});await page.getByLabel('Source organisation code',{exact:true}).fill('ORG001');await page.getByLabel('Sales source tax format',{exact:true}).selectOption('EXCLUSIVE');await page.getByRole('button',{name:'Validate sales file',exact:true}).click();await page.getByLabel('Customer total for EXP-SALE (Main outlet)',{exact:true}).fill('4350');await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Save reviewed sales',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Sales import recorded'})).toBeVisible();
 await expenses(page);await upload(page,'test-expenses.csv');const approval=page.locator('.expense-approval:visible');await approval.getByLabel('Source total for all uploaded lines',{exact:true}).fill('1');await approval.getByRole('checkbox').check();await approval.getByRole('button',{name:'Record reviewed expenses',exact:true}).click();await expect(approval.getByRole('alert')).toContainText('source total does not reconcile');await expect(approval.getByLabel('Source total for all uploaded lines',{exact:true})).toHaveValue('1');await post(page,'3600');
 const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Download original expense CSV',exact:true}).click();const download=await downloadPromise;const path=testInfo.outputPath('original-expenses.csv');await download.saveAs(path);expect(await readFile(path,'utf8')).toBe(source);
 await period(page);
 // A hard navigation exercises server HTML and hydration, unlike client navigation alone.
 const response=await page.reload();expect(response?.ok()).toBe(true);
 const html=await response!.text();const serverHeading=html.match(/<table[^>]*aria-label="Recorded expense entries"[^>]*>[\s\S]*?<thead>([\s\S]*?)<\/thead>/)?.[1];
 expect(serverHeading,'Server-rendered expenses use the same Basis heading as the client').toContain('Basis');expect(serverHeading).not.toContain('Quantity');
 const table=page.getByRole('table',{name:'Recorded expense entries',exact:true});await expect(table.getByRole('columnheader',{name:'Basis',exact:true})).toBeVisible();
 const disclosure=table.getByRole('button',{name:'Show details for WAGES-TEST / 1',exact:true});await disclosure.click();await expect(table.getByRole('button',{name:'Hide details for WAGES-TEST / 1',exact:true})).toHaveAttribute('aria-expanded','true');await table.getByRole('button',{name:'Hide details for WAGES-TEST / 1',exact:true}).click();
 await expect(card(page,'Recorded labour')).toContainText('NGN 600.00');await expect(card(page,'Recorded operating expenses')).toContainText('NGN 100.00');await expect(card(page,'Estimated prime cost')).toContainText('Unavailable');await review(page);await expect(card(page,'Estimated prime cost')).toContainText('NGN 3,300.00');await expect(card(page,'Estimated prime cost')).toContainText('75.86%');await review(page,'operating');await checkOverviewCosts(page,'NGN 600.00','NGN 3,300.00');
 await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:testInfo.outputPath('expenses-desktop.png'),fullPage:true});
 await upload(page,'repeat-expenses.csv');await expect(page.getByRole('table',{name:'Expense import lines',exact:true}).getByText('Already recorded',{exact:true})).toHaveCount(2);await post(page,'3600');await expect(card(page,'Recorded labour')).toContainText('NGN 600.00');await expect(card(page,'Estimated prime cost')).toContainText('NGN 3,300.00');
});

test('manual expenses preserve reporting context; voids retain history and invalidate coverage',async({page})=>{
 await login(page);await expenses(page);await period(page);await page.getByRole('link',{name:'Add expenses',exact:true}).click();
 await page.getByLabel('Expense reference',{exact:true}).fill('MAN-EXTRA');await page.getByLabel('Expense category',{exact:true}).selectOption('WAGES');await page.getByLabel('Expense scope',{exact:true}).selectOption({label:'Main outlet'});await page.getByLabel('Recognition method',{exact:true}).selectOption('ON_DATE');await page.getByLabel('Expense coverage from',{exact:true}).fill('2020-05-15');await page.getByLabel('Expense coverage through',{exact:true}).fill('2020-05-15');await page.getByLabel('Recorded expense amount (NGN)',{exact:true}).fill('50');await page.getByLabel('Description / source note',{exact:true}).fill('Extra payroll, "test"');await page.getByRole('button',{name:'Review expenses',exact:true}).click();await expect(page.getByRole('heading',{name:'manual-expense.csv',exact:true,level:2})).toBeVisible();await post(page,'50');await expect(page).toHaveURL(/from=2020-05-15/);await expect(card(page,'Recorded labour')).toContainText('NGN 650.00');await expect(card(page,'Estimated prime cost')).toContainText('Unavailable');
 await checkOverviewCosts(page,'NGN 650.00','Unavailable');await period(page);const table=page.getByRole('table',{name:'Recorded expense entries',exact:true});await table.getByRole('button',{name:'Show details for MAN-EXTRA / 1',exact:true}).click();const detail=table.locator('.transaction-detail:not([hidden])');await detail.getByText('Void this expense',{exact:true}).click();await detail.getByLabel('Reason for voiding',{exact:true}).fill('Entered twice in error');await detail.getByRole('checkbox').check();await detail.getByRole('button',{name:'Void expense',exact:true}).click();await expect(table.locator('.transaction-main').filter({hasText:'MAN-EXTRA'})).toContainText('Voided');await expect(card(page,'Recorded labour')).toContainText('NGN 600.00');await expect(card(page,'Estimated prime cost')).toContainText('Unavailable');await review(page);await expect(card(page,'Estimated prime cost')).toContainText('NGN 3,300.00');
});

test('finance can enter expenses and review coverage without changing master categories',async({page})=>{
 await login(page,'reader@example.test');await expenses(page);await period(page);await expect(card(page,'Recorded labour')).toContainText('NGN 600.00');await expect(page.getByRole('link',{name:'Add expenses',exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'Confirm labour coverage',exact:true})).toHaveCount(0);await expect(page.getByRole('button',{name:'Create category',exact:true})).toHaveCount(0);
});

test('mobile scope filters keep central costs separate and known-zero labour requires a review',async({page},testInfo)=>{
 await page.setViewportSize({width:375,height:812});await login(page);await expenses(page);await period(page);await expect(card(page,'Estimated prime cost')).toContainText('NGN 3,300.00');await expect(page.getByText('Preparing your workspace…',{exact:true})).toHaveCount(0);await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:testInfo.outputPath('expenses-mobile.png'),fullPage:true});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 const filter=page.locator('.expense-report-context:visible details');await filter.locator('summary').click();const scope=await page.getByLabel('Report location',{exact:true}).locator('option').nth(1).getAttribute('value');await period(page,'2020-05-15',scope!);await expect(page.locator('.expense-warning')).toContainText('central / unallocated entries are excluded');await expect(card(page,'Recorded operating expenses')).toContainText('Not confirmed');await clickNavigation(page,'Sales & margin detail');await expect(page.locator('.overview-costs')).toContainText('central / unallocated entries are excluded');await expect(page.locator('.overview-costs')).toContainText('Cost coverage needs review');await page.getByRole('link',{name:'Review costs',exact:true}).click();
 await period(page,'2020-06-20');await expect(card(page,'Recorded labour')).toContainText('Not confirmed');await review(page);await expect(card(page,'Recorded labour')).toContainText('NGN 0.00');await expect(card(page,'Estimated prime cost')).toContainText('Unavailable');await checkOverviewCosts(page,'NGN 0.00','Unavailable');
});
