import {expect,type Page} from '@playwright/test';
export async function openNavigationGroup(page:Page,name:string|RegExp){
 if(typeof name==='string'&&['Financial report','Monthly close','Sales & margin detail'].includes(name)){
  await(await openNavigationGroup(page,name==='Sales & margin detail'?'Business performance':'Management review')).click();
  const link=page.getByRole('navigation',{name:name==='Sales & margin detail'?'Business performance views':'Management review sections',exact:true}).getByRole('link',{name,exact:true});await expect(link).toBeVisible();return link;
 }
 const navigation=page.locator('.app-frame:visible').getByRole('navigation',{name:'Main navigation',exact:true,includeHidden:true});
 await expect(navigation).toBeAttached();
 if((page.viewportSize()?.width??1440)<=900){
  const menu=page.getByRole('button',{name:'Open navigation',exact:true});await expect(menu).toBeVisible();
  if(await menu.getAttribute('aria-expanded')!=='true')await menu.click();
  await expect(page.getByRole('dialog',{name:'Workspace navigation',exact:true})).toBeVisible();
 }
 const link=navigation.getByRole('link',{name,exact:typeof name==='string',includeHidden:true});
 await expect(link).toBeAttached();
 const group=link.locator('xpath=ancestor::details[1]');
 if(await group.count()){await expect(group).toHaveAttribute('data-ready','true');if(await group.getAttribute('open')===null)await group.locator('summary').click();}
 await expect(link).toBeVisible();return link;
}
export async function clickNavigation(page:Page,name:string|RegExp){await(await openNavigationGroup(page,name)).click();}
export async function moreReportFilters(page:Page){const filters=page.locator('.history-more-filters');if(await filters.getAttribute('open')===null)await filters.locator('summary').click();}
