import {expect,type Page} from '@playwright/test';
export async function assignFixtureCentreMaterials(page:Page,name:string){
 await page.getByRole('link',{name:`Assign materials to ${name}`,exact:true}).click();
 await page.getByRole('button',{name:'Select all matching materials',exact:true}).click();
 await page.getByRole('checkbox',{name:'I reviewed the materials allowed at this centre.',exact:true}).check();
 await page.getByRole('button',{name:'Save centre materials',exact:true}).click();
 await expect(page.getByRole('status')).toContainText('Centre material list saved');
 await page.getByRole('link',{name:'Back to stock centres',exact:true}).click();
}
