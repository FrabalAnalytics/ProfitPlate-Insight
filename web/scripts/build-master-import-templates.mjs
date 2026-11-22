import ExcelJS from 'exceljs';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {Readable} from 'node:stream';
// The checked-in CSV contracts remain the source of truth for both formats.
for(const name of ['material-master-import','recipe-components-import','menu-catalogue-import']){
 const input=await readFile(new URL(`../public/templates/${name}.csv`,import.meta.url),'utf8');
 const book=new ExcelJS.Workbook();
 await book.csv.read(Readable.from([input]),{map:value=>value});
 const data=book.worksheets[0];data.name='Import';data.views=[{state:'frozen',ySplit:1}];
 data.getRow(1).font={bold:true,color:{argb:'FFFFFFFF'}};data.getRow(1).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF174E40'}};
 data.getRow(1).height=30;
 for(let i=1;i<=data.columnCount;i++){data.getColumn(i).width=24;data.getColumn(i).numFmt='@';}
 data.autoFilter={from:{row:1,column:1},to:{row:1,column:data.columnCount}};
 await book.xlsx.writeFile(fileURLToPath(new URL(`../public/templates/${name}.xlsx`,import.meta.url)));
}
