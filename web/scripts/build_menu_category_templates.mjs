import ExcelJS from 'exceljs';
import {writeFile} from 'node:fs/promises';
const headers=['action','menu_code','menu_name','major_category','subcategory','recipe_code','recipe_version','recipe_quantity','selling_price','tax_setting','tax_percent','effective_from','stock_centre_code','consumption_mode'];
const rows=[
 ['CREATE','SNAPPER_PLATE_MENU','Snapper Plate','FOOD','Mains','SNAPPER_PLATE','','1','6000','NONE','0','2026-11-28','',''],
 ['CREATE','JUICE_MENU','Fresh Juice','DRINK','Juices','FRESH_JUICE','','1','2500','NONE','0','2026-11-28','',''],
 ['CREATE','CAKE_MENU','Cake Slice','PASTRY','Cakes','CAKE_SLICE','','1','3000','NONE','0','2026-11-28','',''],
 ['CREATE','BOX_MENU','Takeaway Box','PACKAGING','Boxes','TAKEAWAY_BOX','','1','200','NONE','0','2026-11-28','',''],
];
const csv=[headers,...rows].map(row=>row.map(value=>/[",\n]/.test(value)?`"${value.replaceAll('"','""')}"`:value).join(',')).join('\r\n')+'\r\n';
await writeFile('public/templates/menu-catalogue-import.csv',csv);
const wb=new ExcelJS.Workbook(),sheet=wb.addWorksheet('Import',{views:[{state:'frozen',ySplit:1}]});sheet.addRow(headers);rows.forEach(row=>sheet.addRow(row));sheet.columns.forEach((column,n)=>column.width=n===2?28:22);sheet.getRow(1).eachCell(cell=>{cell.font={bold:true,color:{argb:'FFFFFFFF'}};cell.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF174F40'}};});sheet.getRow(1).height=30;
sheet.getCell('D1').note='Use a main category name or import code configured in Data & Setup > Menu categories. Food, Drink, Pastry and Packaging are examples, not required categories.';
sheet.getCell('E1').note='Use an active subcategory belonging to the selected main category.';
sheet.getCell('F1').note='Use an existing final recipe code. A separately sold box can use a recipe containing its packaging material. Blank recipe fields save an incomplete item.';
sheet.getCell('N1').note='RECIPE consumes ingredients, including stocked preparations. FINISHED consumes the stocked final output. Use with a compatible stock_centre_code.';
await wb.xlsx.writeFile('public/templates/menu-catalogue-import.xlsx');
await writeFile('public/templates/menu-categories-instructions.txt',`SELLING MENU IMPORT\n\nThe four example rows illustrate different main categories. Replace or remove them before uploading.\n\n1. Create your main categories and subcategories in Data & Setup > Menu categories.\n2. Choose Food, Beverage or Non-food reporting treatment for each main category. Pastry can use Food; separately sold packaging uses Non-food.\n3. In major_category, enter the configured category name or its import code. Use its active subcategory in subcategory.\n4. Use real menu and recipe codes, quantities, prices and effective dates. One outlet per reviewed import batch.\n5. Review every proposed creation/update before confirming. The file does not create categories automatically.\n\nPackaging included in a dish remains a recipe cost. Add a Packaging selling-menu row only when the customer is separately charged for it. In that case, put its material in the packaging menu recipe and remove it from the meal recipe so cost and consumption are recorded once.\n\nCSV and XLSX contain equivalent columns and example values.\n`);
const check=new ExcelJS.Workbook();await check.xlsx.readFile('public/templates/menu-catalogue-import.xlsx');if(check.worksheets[0].rowCount!==5)throw new Error('Unexpected template rows');
const actual=Array.from({length:4},(_,n)=>headers.map((_,c)=>check.worksheets[0].getRow(n+2).getCell(c+1).text));if(JSON.stringify(actual)!==JSON.stringify(rows))throw new Error('CSV/XLSX values differ');
console.log('CSV and XLSX menu templates updated with four category examples and instructions.');
