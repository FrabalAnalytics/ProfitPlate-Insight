import {clickNavigation} from './navigation';
import {test,expect,type Page} from '@playwright/test';
async function login(page:Page,email:string){await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/workspace/);}
test('Operations Manager sees compliance first, scoped stock value and practical follow-up links',async({page},info)=>{
 await login(page,'operations@example.test');
 await expect(page.getByText('Operations Manager workspace /',{exact:false})).toBeVisible();
 await expect(page.getByRole('navigation',{name:'Operations tools'})).toHaveCount(0);await expect(page.getByRole('navigation',{name:'Management review shortcuts'})).toHaveCount(0);
 await expect(page.getByRole('region',{name:'Needs Attention',exact:true})).toBeVisible();
 await expect(page.getByLabel("Your centres' current stock value")).toContainText('Count Store');
 await expect(page.getByRole('link',{name:'Data & Setup',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Users & roles',exact:true})).toHaveCount(0);
 await clickNavigation(page,'Operational overview');
 const weeklyPriority=page.getByRole('region',{name:'Operational priorities'}).locator('.operations-count-priority').filter({hasText:'Weekly counts overdue'});
 await weeklyPriority.getByRole('link',{name:/awaiting review/}).click();await expect(page).toHaveURL(/state=SUBMITTED/);await expect(page.getByLabel('Count task',{exact:true})).toHaveValue('SUBMITTED');await expect(page.getByRole('heading',{name:'Weekly stock counts',exact:true})).toBeVisible();await page.getByRole('link',{name:'Back to workspace',exact:true}).click();await expect(page.locator('.welcome-greeting')).toBeVisible();
 await clickNavigation(page,'Operational overview');
 await page.getByText('Purchase price warnings this month',{exact:true}).click();
 await expect(page.getByRole('table',{name:'Operations purchase price warnings'})).toBeVisible();
 await page.evaluate(()=>window.scrollTo(0,0));
 await page.screenshot({path:info.outputPath('operations-desktop.png'),fullPage:true});
 await page.setViewportSize({width:390,height:844});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:info.outputPath('operations-mobile.png'),fullPage:true});
 await clickNavigation(page,'Material Plan');
 await expect(page.getByRole('heading',{name:'Material Plan',exact:true})).toBeVisible();
 await expect(page.locator('main [role=alert]')).toHaveCount(0);
 await page.getByRole('link',{name:'Back to workspace',exact:true}).click();await expect(page.locator('.welcome-greeting')).toBeVisible();
 await clickNavigation(page,'Operational overview');await page.getByRole('link',{name:'Menus above cost target',exact:false}).click();
 await expect(page.getByRole('heading',{name:'Menu profitability',exact:true})).toBeVisible();
});
test('outlet Operations Manager uses profitability without business-wide catalogue or setup controls',async({page})=>{
 await login(page,'operations-scoped@example.test');
 await expect(page.getByText('Operations Manager workspace /',{exact:false})).toBeVisible();
 await clickNavigation(page,'Operational overview');await page.getByRole('link',{name:'Menus above cost target',exact:false}).click();
 await expect(page.getByRole('heading',{name:'Menu profitability',exact:true})).toBeVisible();
 await expect(page.getByLabel('Profitability outlet',{exact:true}).locator('option')).toHaveCount(1);
 await expect(page.getByRole('link',{name:'Menu catalogue',exact:true})).toHaveCount(0);
 await expect(page.getByRole('link',{name:'Create menu item',exact:true})).toHaveCount(0);
 await expect(page.locator('main [role=alert]')).toHaveCount(0);
});
