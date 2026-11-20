import {clickNavigation} from './navigation';
import {test,expect,type Page} from '@playwright/test';

async function login(page:Page,email='catalogue@example.test') {
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);
 await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
}
async function catalogue(page:Page) {
 await clickNavigation(page,'Menu & prices');
 await expect(page.getByRole('heading',{name:'Menu profitability',exact:true})).toBeVisible();await page.getByRole('link',{name:'Menu catalogue',exact:true}).click();await expect(page).toHaveURL(/view=catalogue/);
}
async function sellingPrice(page:Page,value='1650',setting='INCLUSIVE') {
 await page.getByRole('link',{name:'Add selling price',exact:true}).click();
 await page.getByLabel('Price sales channel',{exact:true}).selectOption('DINE_IN');
 await page.getByLabel('Selling price (NGN)',{exact:true}).fill(value);
 await page.getByLabel('Selling price tax setting',{exact:true}).selectOption(setting);
 if(setting!=='NONE') await page.getByLabel('Tax rate (%)',{exact:true}).fill('10');
 await page.getByLabel('Price effective from',{exact:true}).fill('2020-01-01');
 await page.getByLabel('Price source / change note',{exact:true}).fill('Fictional profitability comparison');
 await page.getByRole('button',{name:'Save selling price',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Selling price saved'})).toBeVisible();
}

test('menu profitability compares tax-aware serving estimates, retains missing states and opens the dated breakdown',async({page},testInfo)=>{
 await page.setViewportSize({width:1600,height:1000});await login(page);await catalogue(page);
 await page.getByRole('link',{name:'Create menu item',exact:true}).click();
 await page.getByLabel('Menu code',{exact:true}).fill('PROFIT-E2E');await page.getByLabel('Menu item name',{exact:true}).fill('Profitability plate');
 await page.getByLabel('Search saved final recipes',{exact:true}).fill('Menu cost recipe');
 await page.getByLabel('Saved recipe version',{exact:true}).selectOption({label:'Menu cost recipe · v1 (MENU-RECIPE)'});
 await page.getByLabel('Menu version effective from',{exact:true}).fill('2020-01-01');
 await page.getByRole('button',{name:'Publish menu version',exact:true}).click();await expect(page.getByRole('status').filter({hasText:'Menu version published'})).toBeVisible();
 await sellingPrice(page);await page.getByRole('link',{name:'Menu profitability',exact:true}).click();await filters(page);await page.getByLabel('Profitability channel',{exact:true}).selectOption('DINE_IN');await page.getByRole('button',{name:'Update profitability',exact:true}).click();
 await page.getByLabel('Search menu name or code',{exact:true}).fill('PROFIT-E2E');await page.getByRole('button',{name:'Search',exact:true}).click();await filters(page);await page.getByLabel('Profitability date',{exact:true}).fill('2020-02-01');
 await page.getByRole('button',{name:'Update profitability',exact:true}).click();
 const table=page.getByRole('table',{name:'Menu profitability comparison',exact:true});
 const row=table.getByRole('row').filter({has:page.getByRole('rowheader',{name:/Profitability plate/})});
 await expect(row.getByRole('cell').nth(1)).toHaveText('NGN 1,500.00');await expect(row.getByRole('cell').nth(2)).toHaveText('NGN 900.00');
 await expect(row.getByRole('cell').nth(3)).toHaveText('60%');await expect(row.getByRole('cell').nth(5)).toHaveText('NGN 600.00');await expect(row.getByRole('cell').nth(6)).toHaveText('40%');
 await expect(row.getByRole('cell').nth(7)).toContainText('Target not set');
 await page.screenshot({path:testInfo.outputPath('menu-profitability-desktop.png'),fullPage:true});
 await filters(page);await page.getByLabel('Profitability channel',{exact:true}).selectOption('TAKEAWAY');await page.getByRole('button',{name:'Update profitability',exact:true}).click();
 await expect(row.getByRole('cell').nth(2)).toHaveText('NGN 900.00');await expect(row.getByRole('cell').nth(1)).toHaveText('Unavailable');await expect(row).toContainText('Selling price unavailable');
 await filters(page);await page.getByLabel('Profitability date',{exact:true}).fill('2019-01-01');await page.getByRole('button',{name:'Update profitability',exact:true}).click();await expect(row).toContainText('Recipe needed');await expect(row.getByRole('cell').nth(1)).toHaveText('Unavailable');
 await filters(page);await page.getByLabel('Profitability date',{exact:true}).fill('2020-02-01');await page.getByLabel('Profitability channel',{exact:true}).selectOption('DINE_IN');await page.getByRole('button',{name:'Update profitability',exact:true}).click();
 await page.getByRole('link',{name:'View profitability for Profitability plate',exact:true}).click();
 await expect(page).toHaveURL(url=>url.pathname==='/workspace/menus'&&url.searchParams.get('date')==='2020-02-01'&&url.searchParams.has('version'));
 await expect(page.getByLabel('Preview date',{exact:true})).toHaveValue('2020-02-01');
 await expect(page.getByLabel('Preview sales channel',{exact:true})).toHaveValue('DINE_IN');
 await expect(page.locator('.menu-margin-cards')).toContainText('NGN 600.00');
});

test('profitability retains selling revenue with missing ingredient costs and works for Finance on mobile',async({page,browser},testInfo)=>{
 await login(page);await catalogue(page);await page.getByRole('link',{name:'View menu item Sales uncosted dish',exact:true}).click();await sellingPrice(page,'1500','NONE');
 await page.getByRole('link',{name:'Menu profitability',exact:true}).click();await filters(page);await page.getByLabel('Profitability channel',{exact:true}).selectOption('DINE_IN');await page.getByRole('button',{name:'Update profitability',exact:true}).click();await page.getByLabel('Search menu name or code',{exact:true}).fill('SALES-NOCOST');await page.getByRole('button',{name:'Search',exact:true}).click();await filters(page);await page.getByLabel('Profitability date',{exact:true}).fill('2020-02-01');await page.getByRole('button',{name:'Update profitability',exact:true}).click();
 const url=page.url(),context=await browser.newContext({viewport:{width:375,height:812}}),finance=await context.newPage();
 try {
  await login(finance,'reader@example.test');await finance.goto(url);
  const table=finance.getByRole('table',{name:'Menu profitability comparison',exact:true}),row=table.getByRole('row').filter({hasText:'Sales uncosted dish'});
  await expect(row.getByRole('cell').nth(2)).toHaveText('Unavailable');await expect(row.getByRole('cell').nth(1)).toHaveText('NGN 1,500.00');await expect(row.getByRole('cell').nth(3)).toHaveText('Unavailable');await expect(row).toContainText('Material prices missing');
  await expect(finance.getByRole('link',{name:'Create menu item',exact:true})).toHaveCount(0);
  expect(await finance.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await finance.screenshot({path:testInfo.outputPath('menu-profitability-mobile.png'),fullPage:true});
  const organisation=new URL(url).searchParams.get('organisation');
  await finance.getByRole('combobox',{name:'Selling menu or recipes',exact:true}).selectOption('recipes');
  await expect(finance).toHaveURL(/\/workspace\/recipes\?organisation=/);
  expect(new URL(finance.url()).searchParams.get('organisation')).toBe(organisation);
  await expect(finance.getByRole('table',{name:'Recipe library',exact:true})).toBeVisible();
  await expect(finance.getByRole('table',{name:'Menu profitability comparison',exact:true})).toHaveCount(0);
  await expect(finance.getByRole('combobox',{name:'Selling menu or recipes',exact:true})).toHaveValue('recipes');
  expect(await finance.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await finance.screenshot({path:testInfo.outputPath('recipe-only-filter-mobile.png'),fullPage:true});
  await finance.getByRole('combobox',{name:'Selling menu or recipes',exact:true}).selectOption('menu');
  await expect(finance.getByRole('table',{name:'Menu profitability comparison',exact:true})).toBeVisible();
  await expect(finance.getByRole('table',{name:'Recipe library',exact:true})).toHaveCount(0);
  const invalid=new URL(url);invalid.searchParams.set('date','2099-01-01');await finance.goto(invalid.href);await expect(finance.getByRole('main').getByRole('alert')).toContainText('valid outlet, channel, date and status');await expect(finance.getByRole('table',{name:'Menu profitability comparison',exact:true})).toHaveCount(0);
 } finally {await context.close();}
});

test('Inventory cannot open menu profitability through a copied URL',async({page})=>{
 await login(page,'inventory@example.test');await page.goto('/workspace/menus/profitability');
 await expect(page.getByRole('heading',{name:'Menu profitability is unavailable',exact:true})).toBeVisible();
 await expect(page.getByRole('table',{name:'Menu profitability comparison',exact:true})).toHaveCount(0);
});

async function filters(page:Page){const d=page.locator('.menu-scope-filters');if(await d.getAttribute('open')===null)await d.locator('summary').first().click();}
