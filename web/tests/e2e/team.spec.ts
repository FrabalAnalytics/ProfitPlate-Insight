import {clickNavigation} from './navigation';
import { test,expect,type Page } from '@playwright/test';

async function login(page:Page,email='catalogue@example.test') {
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/(workspace|onboarding|admin|join)(\?|$)/);
}
async function team(page:Page) {
 await login(page);await clickNavigation(page,'Users & roles');await expect(page.getByRole('heading',{name:'Users & roles',exact:true})).toBeVisible();
}
async function invite(page:Page,email:string) {
 await page.getByRole('link',{name:'Invite colleague',exact:true}).click();await page.getByLabel('Colleague name',{exact:true}).fill('Test Colleague');await page.getByLabel('Staff email address',{exact:true}).fill(email);
 await page.getByRole('checkbox',{name:'I reviewed these permissions. Create an invitation for this email.',exact:true}).check();
 await page.getByRole('button',{name:'Create invitation',exact:true}).click();
 await expect(page.getByLabel('Invitation link — copy before leaving this page',{exact:true})).toBeVisible();
 return await page.getByLabel('Invitation link — copy before leaving this page',{exact:true}).inputValue();
}
test('administrator invitation survives sign-in, grants exact finance access and can be deactivated',async({page,browser},testInfo)=>{
 await team(page);const link=await invite(page,'staff@example.test');expect(link).toMatch(/\/join#[a-f0-9]{64}$/);
 await page.screenshot({path:testInfo.outputPath('team-invitation-desktop.png'),fullPage:true});
 const context=await browser.newContext();const staff=await context.newPage();
 try{
 await staff.goto(link);await staff.getByRole('button',{name:'Review invitation',exact:true}).click();await expect(staff).toHaveURL(/\/join$/);
 await staff.getByRole('link',{name:'Sign in',exact:true}).click();await staff.getByLabel('Email address',{exact:true}).fill('staff@example.test');await staff.getByLabel('Password',{exact:true}).fill('TestPassword123!');await staff.getByRole('button',{name:'Sign in',exact:true}).click();
 await expect(staff.getByRole('heading',{name:'Join Catalogue Test Restaurant',exact:true})).toBeVisible();await expect(staff.getByText('Finance / Auditor · All business locations',{exact:true})).toBeVisible();
 await staff.getByRole('checkbox').check();await staff.getByRole('button',{name:'Accept invitation',exact:true}).click();await expect(staff).toHaveURL(/\/workspace\?organisation=/);
 await expect(staff.getByText('Finance workspace /',{exact:false})).toBeVisible();
 await expect(staff.getByRole('link',{name:'Data & Setup',exact:true})).toHaveCount(0);
 await clickNavigation(staff,'Sales & summary');await expect(staff.getByText(/You have read-only sales access/)).toBeVisible();
 await expect(staff.getByRole('link',{name:'Users & roles',exact:true})).toHaveCount(0);await staff.goto(page.url().replace('&invite=1',''));await expect(staff.getByRole('heading',{name:'Team administration is restricted.',exact:true})).toBeVisible();
 await page.getByRole('link',{name:'Close',exact:true}).click();
 const members=page.getByRole('heading',{name:'Team members',exact:true}).locator('..').locator('..');const row=members.getByRole('row').filter({has:page.getByRole('rowheader',{name:'Test Colleague staff@example.test / Team member',exact:true})});
 await row.locator('summary').filter({hasText:'Manage access'}).click();await row.getByRole('checkbox',{name:'Active member',exact:true}).uncheck();await row.getByRole('checkbox',{name:'I reviewed this change to access.',exact:true}).check();await row.getByRole('button',{name:'Save team access',exact:true}).click();
 await expect(row.getByText('Inactive',{exact:true})).toBeVisible();
 await staff.goto('/workspace');await expect(staff).toHaveURL(/\/onboarding$/);
 }finally{await context.close();}
});

test('revoked invitations remain in history and cannot be reviewed by the intended account',async({page,browser})=>{
 await team(page);const link=await invite(page,'other@example.test');await page.getByRole('link',{name:'Close',exact:true}).click();
 const history=page.getByRole('heading',{name:'Invitation history',exact:true}).locator('..').locator('..');const row=history.getByRole('row').filter({has:page.getByRole('rowheader',{name:'other@example.test',exact:true})});
 await row.getByRole('button',{name:'Revoke invitation',exact:true}).click();await expect(row.getByText('REVOKED',{exact:true})).toBeVisible();
 const context=await browser.newContext();const other=await context.newPage();try{await login(other,'other@example.test');await other.goto(link);await other.getByRole('button',{name:'Review invitation',exact:true}).click();await expect(other.getByRole('heading',{name:'Invitation unavailable',exact:true})).toBeVisible();}finally{await context.close();}
});

test('mobile team editor supports multiple scoped roles without horizontal overflow',async({page},testInfo)=>{
 await page.setViewportSize({width:375,height:812});await team(page);await page.getByRole('link',{name:'Invite colleague',exact:true}).click();await page.getByRole('button',{name:'Add role',exact:true}).click();
 await page.getByRole('combobox',{name:'Role 2',exact:true}).selectOption('operations');
 const scope=page.getByRole('combobox',{name:'Scope 2',exact:true});const location=await scope.locator('option').nth(1).getAttribute('value');await scope.selectOption(location!);
 await expect(page.locator('.team-invite-form').getByText(/Location-scoped roles apply only/)).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:testInfo.outputPath('team-mobile.png'),fullPage:true});
});
test('administrator can invite a location-scoped Inventory receiver to a dedicated home',async({page,browser})=>{
 await team(page);await page.getByRole('link',{name:'Invite colleague',exact:true}).click();await page.getByLabel('Colleague name',{exact:true}).fill('Receiving Colleague');await page.getByLabel('Staff email address',{exact:true}).fill('receiving-invite@example.test');
 await page.getByRole('combobox',{name:'Role 1',exact:true}).selectOption('stock_receiver');
 const scope=page.getByRole('combobox',{name:'Scope 1',exact:true});const location=await scope.locator('option').nth(1).getAttribute('value');await scope.selectOption(location!);
 await page.getByRole('checkbox',{name:'I reviewed these permissions. Create an invitation for this email.',exact:true}).check();await page.getByRole('button',{name:'Create invitation',exact:true}).click();
 const link=await page.getByLabel('Invitation link — copy before leaving this page',{exact:true}).inputValue();
 const context=await browser.newContext(),receiver=await context.newPage();try{
  await receiver.goto(link);await receiver.getByRole('button',{name:'Review invitation',exact:true}).click();await receiver.getByRole('link',{name:'Sign in',exact:true}).click();
  await receiver.getByLabel('Email address',{exact:true}).fill('receiving-invite@example.test');await receiver.getByLabel('Password',{exact:true}).fill('TestPassword123!');await receiver.getByRole('button',{name:'Sign in',exact:true}).click();
  await expect(receiver.getByRole('heading',{name:'Join Catalogue Test Restaurant',exact:true})).toBeVisible();await expect(receiver.getByText('Stock receiver (optional) · Main outlet',{exact:true})).toBeVisible();await receiver.getByRole('checkbox').check();await receiver.getByRole('button',{name:'Accept invitation',exact:true}).click();
  await expect(receiver.getByText('Stock receiving workspace /',{exact:false})).toBeVisible();await expect(receiver.locator('.welcome-greeting')).toBeVisible();await expect(receiver.getByRole('link',{name:'Supplier invoices',exact:true})).toHaveCount(0);
 }finally{await context.close();}
});
