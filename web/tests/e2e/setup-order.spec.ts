import {test,expect} from '@playwright/test';

test('setup puts centres before opening-stock imports and keeps shortcuts compact',async({page},info)=>{
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill('catalogue@example.test');await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
 await page.goto('/workspace/setup');await expect(page.getByRole('heading',{name:'Data & Setup',exact:true})).toBeVisible();
 const journey=page.getByRole('region',{name:'Your setup journey'});
 const headings=await journey.getByRole('heading',{level:3}).allTextContents();
 expect(headings.indexOf('Users & roles')).toBeLessThan(headings.indexOf('Stock centres'));
 expect(headings.indexOf('Stock centres')).toBeLessThan(headings.indexOf('Materials, prices & opening stock'));
 expect(headings.indexOf('Materials, prices & opening stock')).toBeLessThan(headings.indexOf('Recipes'));
 expect(headings).toContain('Food & beverage targets');
 const tools=page.getByRole('navigation',{name:'Setup tools'});await expect(tools.getByRole('link')).toHaveCount(6);await expect(tools.getByRole('link').first()).toHaveText('Centres & team access');
 await expect(tools.getByRole('link',{name:'Processed material setup'})).toBeVisible();
 const links=await tools.getByRole('link').evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect()));expect(links[0].width).toBeLessThan(500);expect(links[0].y).toBe(links[1].y);
 await page.screenshot({path:info.outputPath('setup-order-desktop.png'),fullPage:true});
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath('setup-order-mobile.png'),fullPage:true});
 const href=await tools.getByRole('link',{name:'Centres & team access'}).getAttribute('href');const org=new URL(href!,'http://localhost').searchParams.get('organisation');
 await page.goto(`/workspace/imports?organisation=${org}&kind=MATERIAL`);
 await expect(page.getByRole('region',{name:'Opening stock prerequisite'})).toContainText('three opening-stock fields left blank');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.getByRole('link',{name:'Set up stock centres',exact:true}).click();await expect(page.getByRole('heading',{name:'Centres & team access',exact:true})).toBeVisible();
});
