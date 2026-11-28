import {test,expect} from '@playwright/test';
import {clickNavigation} from './navigation';

test('purchasing searches name-first choices without changing the selected material or quote',async({page},info)=>{
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill('procurement@example.test');await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/workspace/);
 await clickNavigation(page,'Purchase Orders');await page.getByRole('link',{name:'Raise Purchase Order',exact:true}).click();
 const form=page.locator('.invoice-entry-form'),choice=form.getByLabel('Material, line 1',{exact:true}),search=form.getByRole('searchbox',{name:'Search materials',exact:true});
 await choice.selectOption({label:'Ingredient 01'});const selected=await choice.inputValue();
 await form.getByLabel('Unit price, line 1',{exact:true}).fill('1500');
 await search.fill('SAMPLE2');expect(await search.evaluate(node=>{const event=new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true});node.dispatchEvent(event);return event.defaultPrevented;})).toBe(true);await expect(choice).toHaveValue(selected);await expect(choice.locator('option:checked')).toHaveText('Ingredient 01');await expect(form.getByLabel('Unit price, line 1',{exact:true})).toHaveValue('1500');
 await expect(choice.locator('option').filter({hasText:'Ingredient 02'})).toHaveCount(1);
 await expect(choice.locator('option').filter({hasText:'Ingredient 03'})).toHaveCount(0);
 await choice.selectOption({label:'Ingredient 02'});await expect(search).toHaveValue('');
 const picker=choice.locator('..');await expect(picker).toContainText('Unit: KG');await picker.getByText('Material code',{exact:true}).click();await expect(picker).toContainText('SAMPLE2');await expect(choice.locator('option:checked')).toHaveText('Ingredient 02');
 await search.fill('nonexistent-material-xyz');await expect(picker.getByRole('status')).toContainText('0 matches');await expect(choice.locator('option:checked')).toHaveText('Ingredient 02');
 await search.fill('');await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:info.outputPath('material-selection-mobile.png'),fullPage:true});
});

test('onboarding naming guidance is readable and the Word guide downloads',async({page,request},info)=>{
 await page.goto('/guides/material-naming.html');await expect(page.getByRole('heading',{name:'Clear names, confident selection'})).toBeVisible();await expect(page.getByRole('heading',{name:'Set up a new restaurant step by step'})).toBeVisible();
 const link=page.getByRole('link',{name:'Download Word guide'});const response=await request.get((await link.getAttribute('href'))?'/guides/ProfitPlate_Insights_Material_Naming_Guide.docx':'/missing');expect(response.ok()).toBe(true);expect((await response.body()).subarray(0,2).toString()).toBe('PK');
 await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath('naming-guide-mobile.png'),fullPage:true});
});
