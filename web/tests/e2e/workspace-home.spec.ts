import {clickNavigation} from './navigation';
import {test,expect,type Page} from '@playwright/test';
async function login(page:Page,email:string){
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace$/);
}
test('Procurement lands on purchasing work on first and later sign-ins',async({page},testInfo)=>{
 await login(page,'procurement@example.test');
 await expect(page.getByText('Procurement workspace /', {exact:false})).toBeVisible();
 await expect(page.getByRole('link',{name:'Inventory & movements',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Open inventory & movements',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Data & Setup',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Record expense',exact:true})).toHaveCount(0);
 const home=page.url();await page.goto(home.replace('/workspace','/workspace/inventory'));await expect(page.getByRole('heading',{name:'Inventory is restricted or unavailable.',exact:true})).toBeVisible();await page.goto(home);await clickNavigation(page,'Purchase Orders');await expect(page.getByRole('heading',{name:'Purchase Orders',exact:true})).toBeVisible();
 await expect(page.getByRole('link',{name:'Purchase Orders',exact:true})).toHaveAttribute('aria-current','page');
 await page.getByRole('link',{name:'My workspace',exact:true}).click();await expect(page.getByText('Procurement workspace /', {exact:false})).toBeVisible();
 await page.goto(home.replace('/workspace','/workspace/setup'));await expect(page).toHaveURL(/\/workspace\?organisation=/);await expect(page.getByText('Procurement workspace /', {exact:false})).toBeVisible();
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:testInfo.outputPath('procurement-home-mobile.png'),fullPage:true});
 await page.getByRole('button',{name:'Sign out',exact:true}).click();await expect(page).toHaveURL(/\/login$/);await login(page,'procurement@example.test');await expect(page.getByText('Procurement workspace /', {exact:false})).toBeVisible();
});
test('Finance gets expense and review tasks while the owner retains explicit setup',async({page})=>{
 await login(page,'reader@example.test');await expect(page.getByText('Finance workspace /', {exact:false})).toBeVisible();
 await expect(page.getByRole('navigation',{name:'Daily work shortcuts'})).toHaveCount(0);await expect(page.getByRole('region',{name:'Needs Attention',exact:true})).toBeVisible();await expect(page.getByRole('link',{name:'Record supplier invoice',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Data & Setup',exact:true})).toHaveCount(0);await expect(page.getByRole('link',{name:'Materials & suppliers',exact:true})).toHaveCount(0);await expect(page.getByRole('link',{name:'Inventory & movements',exact:true})).toHaveCount(0);await expect(page.getByRole('navigation',{name:'Daily work shortcuts'})).toHaveCount(0);
 const financeHome=page.url();await clickNavigation(page,'Waste across centres');await expect(page.getByRole('heading',{name:'Waste across centres',exact:true})).toBeVisible();await expect(page.getByRole('link',{name:'Record waste',exact:true})).toHaveCount(0);await expect(page.getByLabel('Stock centre',{exact:true})).toContainText('All permitted centres');await expect(page.getByLabel('Waste source',{exact:true})).toHaveValue('WASTE');await expect(page.getByRole('link',{name:'Export CSV',exact:true})).toBeVisible();
 for(const path of ['setup','setup/centres','setup/production','setup/standards']){await page.goto(financeHome.replace('/workspace',`/workspace/${path}`));await expect(page.getByText('Finance workspace /', {exact:false})).toBeVisible();}
 await page.getByRole('button',{name:'Sign out',exact:true}).click();await expect(page).toHaveURL(/\/login$/);await login(page,'catalogue@example.test');await expect(page.getByRole('heading',{name:/Good (morning|afternoon|evening)/})).toBeVisible();await clickNavigation(page,'Data & Setup');await expect(page.getByRole('heading',{name:'Your setup journey',exact:true})).toBeVisible();
});
test('Inventory has a receiving home and cannot open supplier invoices',async({page})=>{
 await login(page,'inventory@example.test');await expect(page.getByText('Inventory / Receiving workspace /', {exact:false})).toBeVisible();
 await expect(page.getByRole('link',{name:'Record supplier invoice',exact:true})).toHaveCount(0);await expect(page.getByRole('link',{name:'Supplier invoices',exact:true})).toHaveCount(0);
 await clickNavigation(page,'Goods Received Notes');await expect(page.getByRole('heading',{name:'Goods Received Notes',exact:true})).toBeVisible();
 await expect(page.getByRole('link',{name:'Raise Purchase Order',exact:true})).toHaveCount(0);
 const url=new URL(page.url());url.pathname='/workspace/purchases/invoices';await page.goto(url.href);await expect(page.getByRole('main').getByRole('alert')).toContainText('restricted');
});
