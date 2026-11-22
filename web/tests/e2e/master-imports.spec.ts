import {test,expect,type Page} from '@playwright/test';
import ExcelJS from 'exceljs';
import {materialImportHeaders,recipeImportHeaders} from '../../lib/master-imports';

async function login(page:Page,email='catalogue@example.test'){
 await page.goto('/login');await page.getByLabel('Email address',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill('TestPassword123!');await page.getByRole('button',{name:'Sign in',exact:true}).click();await expect(page).toHaveURL(/\/workspace/);
}
const quote=(s:string)=>`"${s.replaceAll('"','""')}"`;
function csv(headers:readonly string[],rows:Record<string,string>[]){return [headers.join(','),...rows.map(r=>headers.map(h=>quote(r[h]??'')).join(','))].join('\n');}
async function saveReview(page:Page){await page.getByRole('checkbox',{name:/I reviewed these changes/}).check();await page.getByRole('button',{name:'Save reviewed import',exact:true}).click();await expect(page.getByRole('status').filter({hasText:/saved|published/})).toBeVisible();await expect(page.getByRole('button',{name:'Save reviewed import',exact:true})).toHaveCount(0);}

test('materials, nested recipes and menu prices can be onboarded without retyping masters',async({page},info)=>{
 await login(page);await page.goto('/workspace/materials');await page.getByRole('link',{name:'Import materials',exact:true}).click();await expect(page.getByRole('heading',{name:'Import materials',exact:true})).toBeVisible();
 const org=new URL(page.url()).searchParams.get('organisation')!,day=new Date().toISOString().slice(0,10);
 const material={action:'CREATE',material_code:'BULK_FISH_UI',material_name:'Bulk fish UI',material_type:'RAW',category:'Fish',base_unit:'KG',stock_tracked:'true',weekly_count_required:'true',supply_source:'PURCHASED',requires_processing:'false',last_purchase_unit_price:'3000',last_purchase_date:day};
 await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'materials.csv',mimeType:'text/csv',buffer:Buffer.from(csv(materialImportHeaders,[material]))});await page.getByRole('button',{name:'Review file',exact:true}).click();await expect(page.getByRole('table',{name:'Master import review'})).toContainText('Bulk fish UI');await expect(page.getByRole('table',{name:'Master import review'})).toContainText('CREATE');await saveReview(page);
 await page.goto(`/workspace/imports?organisation=${org}&kind=RECIPE`);
 const header={action:'CREATE',recipe_type:'SUB_RECIPE',yield_quantity:'10',yield_unit:'PCS',effective_from:day,component_kind:'ITEM',component_code:'BULK_FISH_UI',component_quantity:'2',component_unit:'KG'};
 const rows=[{...header,recipe_code:'BULK_PLATE_UI',recipe_name:'Bulk plate UI',recipe_type:'FINAL',yield_quantity:'1',component_kind:'RECIPE',component_code:'BULK_PREP_UI',component_quantity:'1',component_unit:'PCS'},{...header,recipe_code:'BULK_PREP_UI',recipe_name:'Bulk prep UI'}];
 const book=new ExcelJS.Workbook(),sheet=book.addWorksheet('Import');sheet.addRow([...recipeImportHeaders]);for(const r of rows)sheet.addRow(recipeImportHeaders.map(h=>(r as Record<string,string>)[h]??''));
 await page.getByLabel('Recipe file',{exact:true}).setInputFiles({name:'recipes.xlsx',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',buffer:Buffer.from(await book.xlsx.writeBuffer())});await page.getByRole('button',{name:'Review file',exact:true}).click();await expect(page.getByRole('table',{name:'Master import review'})).toContainText('Bulk prep UI');await expect(page.getByRole('table',{name:'Master import review'})).toContainText('Version 1');await page.screenshot({path:info.outputPath('recipe-review.png'),fullPage:true});await saveReview(page);
 await page.goto(`/workspace/menus/import?organisation=${org}`);
 const menu='action,menu_code,menu_name,major_category,subcategory,recipe_code,recipe_version,recipe_quantity,selling_price,tax_setting,tax_percent,effective_from\nCREATE,BULK_MENU_UI,Bulk fish plate,FOOD,Mains,BULK_PLATE_UI,,1,6000,NONE,0,'+day;
 await page.getByLabel('Menu file',{exact:true}).setInputFiles({name:'menu.csv',mimeType:'text/csv',buffer:Buffer.from(menu)});await page.getByRole('button',{name:'Review menu import',exact:true}).click();await expect(page.getByRole('table',{name:'Menu import review'})).toContainText('Bulk fish plate');await page.getByRole('checkbox').check();await page.getByRole('button',{name:'Save reviewed menu items',exact:true}).click();await expect(page.getByRole('status')).toContainText('1 menu items');
 await page.goto(`/workspace/menus?organisation=${org}&q=Bulk+fish+plate`);await expect(page.getByRole('table',{name:'Menu profitability'})).toContainText('NGN 6,000.00');await expect(page.getByRole('table',{name:'Menu profitability'}).getByRole('row')).toHaveCount(2);
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath('imported-menu-mobile.png'),fullPage:true});
});

test('imported centre openings stay visible for Inventory review and invalid files disable saving',async({page})=>{
 await login(page,'weekly-owner@example.test');await page.goto('/workspace/materials');await page.getByRole('link',{name:'Import materials',exact:true}).click();
 await expect(page.getByRole('heading',{name:'Import materials',exact:true})).toBeVisible();
 const day=new Date().toISOString().slice(0,10),org=new URL(page.url()).searchParams.get('organisation')!;
 const r={action:'CREATE',material_code:'OPEN_UI',material_name:'Imported opening fish',material_type:'RAW',category:'Fish',base_unit:'KG',stock_tracked:'true',weekly_count_required:'true',supply_source:'PURCHASED',requires_processing:'false',centre_code:'COUNT_STORE',opening_quantity:'5',opening_date:day};
 await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'opening.csv',mimeType:'text/csv',buffer:Buffer.from(csv(materialImportHeaders,[{...r,base_unit:'UNKNOWN'}]))});await page.getByRole('button',{name:'Review file',exact:true}).click();await expect(page.getByRole('table',{name:'Master import review'})).toContainText('Unknown base unit');await expect(page.getByRole('button',{name:'Save reviewed import',exact:true})).toHaveCount(0);
 await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'opening.csv',mimeType:'text/csv',buffer:Buffer.from(csv(materialImportHeaders,[r]))});await page.getByRole('button',{name:'Review file',exact:true}).click();await saveReview(page);await page.getByRole('link',{name:'Review imported openings',exact:true}).click();await expect(page.getByRole('heading',{name:'Count Store',exact:true})).toBeVisible();await expect(page.getByRole('table',{name:'Count Store imported openings'})).toContainText('Imported opening fish');await expect(page.getByRole('button',{name:'Submit opening for review',exact:true})).toHaveCount(0);
 await page.goto(`/workspace/imports?organisation=${org}&kind=MATERIAL`);await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'duplicate.csv',mimeType:'text/csv',buffer:Buffer.from(csv(materialImportHeaders,[{...r,action:'UPDATE'}]))});await page.getByRole('button',{name:'Review file',exact:true}).click();await expect(page.getByRole('table',{name:'Master import review'})).toContainText('Opening already prepared');
});

test('large import reviews paginate and changing the file hides the previous confirmation',async({page})=>{
 await login(page);await page.goto('/workspace/materials');await page.getByRole('link',{name:'Import materials',exact:true}).click();await expect(page.getByRole('heading',{name:'Import materials',exact:true})).toBeVisible();
 const rows=Array.from({length:30},(_,i)=>({action:'CREATE',material_code:`PAGING_${i}`,material_name:`Review item ${i}`,material_type:'RAW',category:'',base_unit:'KG',stock_tracked:'true',weekly_count_required:'false',supply_source:'PURCHASED',requires_processing:'false'}));
 await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'review.csv',mimeType:'text/csv',buffer:Buffer.from(csv(materialImportHeaders,rows))});await page.getByRole('button',{name:'Review file',exact:true}).click();
 const table=page.getByRole('table',{name:'Master import review'});await expect(table.getByRole('row')).toHaveCount(26);await page.getByRole('button',{name:'Next',exact:true}).click();await expect(table.getByRole('row')).toHaveCount(6);await expect(table).toContainText('PAGING_29');
 await page.getByLabel('Material file',{exact:true}).setInputFiles({name:'invalid.csv',mimeType:'text/csv',buffer:Buffer.from('code,name\nBAD,Bad')});await expect(page.getByRole('button',{name:'Save reviewed import',exact:true})).toHaveCount(0);await page.getByRole('button',{name:'Review file',exact:true}).click();await expect(page.locator('main [role="alert"]')).toContainText('template headers');
});
