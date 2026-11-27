import {test,expect} from '@playwright/test';
import {clickNavigation} from './navigation';
async function login(page:import('@playwright/test').Page,email='catalogue@example.test'){
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/workspace/);
}
test('reports have four clear destinations and detail tabs preserve date and outlet context',async({page},info)=>{
 await login(page);await clickNavigation(page,'Business performance');await expect(page).toHaveURL(/\/workspace\/performance/);
 const nav=page.getByRole('navigation',{name:'Main navigation',exact:true}),reports=nav.locator('details').filter({has:page.locator('summary',{hasText:'Reports'})});
 await expect(reports.getByRole('link')).toHaveText(['Business performance','Management review','Action register','Operational reports']);
 const url=new URL(page.url());const outlet=await page.locator('select[name=location]').locator('option').nth(1).getAttribute('value');url.searchParams.set('location',outlet!);url.searchParams.set('from','2020-07-15');url.searchParams.set('to','2020-07-16');await page.goto(url.href);
 await page.getByRole('navigation',{name:'Business performance views'}).getByRole('link',{name:'Sales & margin detail',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Sales & margin detail',exact:true})).toBeVisible();expect(new URL(page.url()).searchParams.get('from')).toBe('2020-07-15');expect(new URL(page.url()).searchParams.get('location')).toBe(outlet);
 await page.getByRole('navigation',{name:'Business performance views'}).getByRole('link',{name:'Summary',exact:true}).click();await expect(page).toHaveURL(/\/workspace\/performance/);expect(new URL(page.url()).searchParams.get('to')).toBe('2020-07-16');
 await clickNavigation(page,'Management review');const sections=page.getByRole('navigation',{name:'Management review sections'});
 await sections.getByRole('link',{name:'Financial report',exact:true}).click();await expect(page.getByRole('heading',{name:'Executive management report',exact:true})).toBeVisible();
 const reportMonth=new URL(page.url()).searchParams.get('from')!.slice(0,7);await sections.getByRole('link',{name:'Monthly close',exact:true}).click();await expect(page.getByRole('heading',{name:'Monthly close',exact:true})).toBeVisible();expect(new URL(page.url()).searchParams.get('month')).toBe(reportMonth);
 await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath('report-sections-mobile.png'),fullPage:true});
});
test('operational reports remain reachable with filters and exports',async({page},info)=>{
 await login(page);await clickNavigation(page,'Operational reports');await expect(page.getByRole('heading',{name:'Operational reports',exact:true})).toBeVisible();await expect(page.getByLabel('Report',{exact:true})).toBeVisible();await expect(page.getByRole('link',{name:'Export filtered CSV',exact:true})).toBeVisible();
 const event=page.waitForEvent('download');await page.getByRole('link',{name:'Export filtered CSV',exact:true}).click();const file=await event;await file.saveAs(info.outputPath('operational-report.csv'));expect(await file.failure()).toBeNull();
});
test('scoped Operations keeps reviews and close without financial navigation',async({page})=>{
 await login(page,'operations-scoped@example.test');await clickNavigation(page,'Management review');const sections=page.getByRole('navigation',{name:'Management review sections'});
 await expect(sections.getByRole('link',{name:'Financial report',exact:true})).toHaveCount(0);await expect(sections.getByRole('link',{name:'Monthly close',exact:true})).toBeVisible();
});
