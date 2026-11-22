import {expect,type Page} from '@playwright/test';
export async function approveRestaurantFixture(page:Page){
 await expect(page).toHaveURL(/account-access\?organisation=/);
 await expect(page.getByRole('heading',{name:'Your restaurant is awaiting approval.',exact:true})).toBeVisible();
 const org=new URL(page.url()).searchParams.get('organisation')!;
 const fixture='http://127.0.0.1:54398';
 const token=await(await page.request.post(`${fixture}/auth/v1/token`,{data:{email:'founder@example.test',password:'TestPassword123!'}})).json();
 const r=await page.request.post(`${fixture}/rest/v1/rpc/set_restaurant_access`,{headers:{Authorization:`Bearer ${token.access_token}`},data:{p_organisation_id:org,p_expected_state:'PENDING',p_state:'ACTIVE',p_reason:'Approve restaurant for browser workflow checks',p_confirmed:true}});
 expect(r.ok(),await r.text()).toBe(true);
 await page.goto(`/workspace/setup?organisation=${org}&welcome=1`);
 return org;
}
