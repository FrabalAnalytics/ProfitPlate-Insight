"""Build the fictional complete-restaurant test pack using only the Python standard library."""
from pathlib import Path
import csv, io, json, shutil, re
from zipfile import ZipFile, ZIP_DEFLATED
from xml.sax.saxutils import escape
from xml.etree import ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'public/templates/complete-restaurant-test-data'
DATE='2026-11-19'
PACK_DATE='2026-11-19'
APP_RELEASE='042-invitation-onboarding'
MIGRATION='042'
DATA={}
def sheet(name,header,rows,folder='manual-entry'):
    DATA[name]={'columns':header.split(','),'rows':rows,'folder':folder}

sheet('business','business_name,concept,country,currency,time_zone,brand_code,brand_name,outlet_code,outlet_name,reporting_week_start,physical_count_day,physical_count_cutoff',[
 ['Training Restaurant - Run 041','FINE_DINING','NG','NGN','Africa/Lagos','PRIMARY','Training Kitchen','PRIMARY','Dining Room','Wednesday','Tuesday','23:30']])
sheet('users','display_name,email_to_replace,role_code,outlet_scope,stock_centre_scope',[
 ['Francis','owner@example.test','restaurant_admin','ALL','ALL'],['Francis','owner@example.test','ceo','ALL','ALL'],['Emeka','inventory@example.test','inventory_manager','ALL','ALL'],['Ada','kitchen@example.test','kitchen_manager','ALL','KITCHEN'],['Bola','bar@example.test','bar_lead','ALL','BAR'],['Tomi','procurement@example.test','procurement','ALL',''],['Chioma','finance@example.test','finance','ALL','']])
sheet('stock-centres','centre_code,centre_name,kind,outlet_code,responsible_name,is_processing_unit',[
 ['MAIN_STORE','Main Store','STORE','','Emeka','false'],['KITCHEN','Kitchen','KITCHEN','PRIMARY','Ada','true'],['BAR','Bar','BAR','PRIMARY','Bola','false']])
sheet('movement-routes','source_centre,destination_centre,movement_type,source_approval_role',[[a,b,'TRANSFER','inventory_manager'] for a,b in [('MAIN_STORE','KITCHEN'),('KITCHEN','MAIN_STORE'),('MAIN_STORE','BAR'),('BAR','MAIN_STORE')]])
sheet('suppliers','supplier_code,supplier_name,email,phone,address',[
 ['FISH_SUP','Training Fish Supplier','fish-supplier@example.test','08000000001','Fictional training address'],['DRY_SUP','Training Dry Goods Supplier','dry-supplier@example.test','08000000002','Fictional training address']])
sheet('materials','material_code,material_name,item_type,category,base_unit,stock_tracked,supply_class,requires_processing,weekly_count_required,outlet_scope',[
 ['WHOLE_SNAPPER','Whole Snapper Fish','RAW','Fish','KG','true','PURCHASED','true','true','ALL'],['SNAPPER_CUT','Snapper Cut','SEMI_FINISHED','Fish','PCS','true','PROCESSED','false','true','ALL'],['RICE','Rice','RAW','Grains','KG','true','PURCHASED','false','true','ALL'],['TOMATO','Tomato','RAW','Vegetables','KG','true','PURCHASED','false','true','ALL'],['ONION','Onion','RAW','Vegetables','KG','true','PURCHASED','false','true','ALL'],['OIL','Cooking Oil','RAW','Oils','L','true','PURCHASED','false','true','ALL'],['BOX','Takeaway Box','PACKAGING','Packaging','PCS','true','PURCHASED','false','true','ALL']])
sheet('unit-conversions','material_code,from_unit,to_unit,factor,effective_from',[['RICE','BAG','KG','50',DATE]])
prices=[['WHOLE_SNAPPER','1','KG','3000',DATE,'Fictional starting price'],['RICE','1','KG','1800',DATE,'Fictional starting price'],['TOMATO','1','KG','1500',DATE,'Fictional starting price'],['ONION','1','KG','1000',DATE,'Fictional starting price'],['OIL','1','L','2500',DATE,'Fictional starting price'],['BOX','1','PCS','100',DATE,'Fictional starting price']]
sheet('initial-material-prices','material_code,quantity,unit_code,total_price,price_date,source_note',prices,'upload-ready')
sheet('processing-baselines','process_code,process_name,input_material,input_quantity,input_unit,output_material,expected_output,output_unit,centre,tolerance_percent,output_spec,effective_from',[
 ['SNAPPER_CUTTING','Snapper cutting','WHOLE_SNAPPER','40','KG','SNAPPER_CUT','120','PCS','KITCHEN','0','Approved uniform snapper cuts',DATE]])
sheet('recipe-headers','recipe_code,recipe_name,recipe_type,yield_quantity,yield_unit,effective_from,notes',[
 ['STEW_BASE','Training Stew Base','SUB_RECIPE','10','L',DATE,'Fictional preparation; estimated cost 11000 per batch'],['SNAPPER_RICE_RECIPE','Training Snapper Rice Plate','FINAL','10','PCS',DATE,'Fictional boxed meal; estimated cost 16800 per batch']])
sheet('recipe-components','recipe_code,line_number,component_type,component_code,child_version,quantity,unit_code',[
 ['STEW_BASE','1','ITEM','TOMATO','','5','KG'],['STEW_BASE','2','ITEM','ONION','','1','KG'],['STEW_BASE','3','ITEM','OIL','','1','L'],['SNAPPER_RICE_RECIPE','1','ITEM','RICE','','2','KG'],['SNAPPER_RICE_RECIPE','2','RECIPE','STEW_BASE','1','2','L'],['SNAPPER_RICE_RECIPE','3','ITEM','SNAPPER_CUT','','10','PCS'],['SNAPPER_RICE_RECIPE','4','ITEM','BOX','','10','PCS']])
sheet('menu-items','menu_code,menu_name,brand_code,primary_category,subcategory,final_recipe_code,final_recipe_version,recipe_quantity_per_sale,effective_from',[
 ['SNAPPER_RICE_MENU','Training Snapper Rice Plate','PRIMARY','FOOD','Mains','SNAPPER_RICE_RECIPE','1','1',DATE]])
sheet('menu-selling-prices','menu_code,outlet_code,channel_code,selling_price,tax_setting,tax_percent,effective_from,source_note',[
 ['SNAPPER_RICE_MENU','PRIMARY','TAKEAWAY','6000','NONE','0',DATE,'Fictional no-tax arithmetic example; use approved tax rules for real data']])
materials=DATA['materials']['rows']
sheet('opening-stock','stock_centre,material_code,quantity,base_unit,opening_date,entry_method',[
 [site,m[0],({'WHOLE_SNAPPER':'40','RICE':'20','TOMATO':'10','ONION':'5','OIL':'10','BOX':'100'}.get(m[0],'0') if site=='MAIN_STORE' else '0'),m[4],DATE,('OPENING_REQUEST' if site=='MAIN_STORE' and m[0]!='SNAPPER_CUT' else 'ZERO_OPENING_CONFIRMATION')] for site in ['MAIN_STORE','KITCHEN','BAR'] for m in materials])
sheet('processing-log','batch_reference,date,centre,process_code,input_material,actual_input,input_unit,output_material,actual_output,output_unit,measured_usable_kg,measured_waste_kg,waste_reason,variance_reason',[
 ['TRAIN-BATCH-001',DATE,'KITCHEN','SNAPPER_CUTTING','WHOLE_SNAPPER','40','KG','SNAPPER_CUT','110','PCS','36','4','Measured trim','Measured output below baseline']])
sheet('waste-log','waste_reference,date,centre,material_code,quantity,unit,submitter_name,category,reason',[
 ['TRAIN-WASTE-MAIN',DATE,'MAIN_STORE','RICE','1','KG','Emeka','Spoilage','Measured Main Store spoilage'],
 ['TRAIN-WASTE-001',DATE,'KITCHEN','SNAPPER_CUT','2','PCS','Ada','Spoilage','Two cuts spoiled after processing; separate from recorded trim']])
headers={key:(ROOT/f'public/templates/{key}.csv').read_text(encoding='utf-8-sig').splitlines()[0] for key in ['purchases-import','sales-import','expense-import']}
sheet('purchases-import',headers['purchases-import'],[
 ['TRAINING','TRAINING_CSV',DATE,'TRAIN-INV-FISH','1','FISH_SUP','WHOLE_SNAPPER','10','KG','3000','0','0','PRIMARY','NGN','RECEIVED'],['TRAINING','TRAINING_CSV',DATE,'TRAIN-INV-RICE','1','DRY_SUP','RICE','5','KG','1800','0','0','PRIMARY','NGN','RECEIVED']],'upload-ready')
sheet('sales-import',headers['sales-import'],[['TRAINING','TRAINING_POS','PRIMARY',DATE,'TRAIN-SALE-001','1','SNAPPER_RICE_MENU','3','18000','0','0','18000','TAKEAWAY','NORMAL','','PAID']],'upload-ready')
sheet('expense-import',headers['expense-import'],[
 ['TRAINING','TRAINING_EXP','TRAIN-WAGES-001','1','WAGES','LOCATION','PRIMARY',DATE,DATE,'ON_DATE',DATE,'600','NGN','Fictional training labour'],['TRAINING','TRAINING_EXP','TRAIN-RENT-001','1','RENT','LOCATION','PRIMARY',DATE,DATE,'ON_DATE',DATE,'500','NGN','Fictional training operating expense']],'upload-ready')
sheet('expected-results','checkpoint,expected_value,unit_or_basis',[
 ['Whole snapper starting estimate','3000','NGN per KG'],['Snapper Cut standard estimate','1000','NGN per PCS'],['Stew base batch estimate','11000','NGN per 10 L'],['Final recipe batch estimate','16800','NGN per 10 servings'],['Final recipe serving estimate','1680','NGN'],['Selling price and example net revenue per plate','6000','NGN; fictional NONE tax setting'],['Menu food cost','28.00','percent'],['Menu estimated food margin per plate','4320','NGN; excludes other costs'],['Menu estimated food gross margin','72.00','percent'],['Main Store whole fish after accepted transfer','0','KG'],['Kitchen whole fish after processing','0','KG'],['Kitchen cuts after processing','110','PCS'],['Processing baseline achievement','91.67','percent'],['Usable weight yield','90.00','percent'],['Recorded processing waste','10.00','percent'],['Kitchen cuts after separate spoilage','108','PCS'],['Main Store rice after standalone waste','19','KG; before separate PO/GRN test'],['Finance combined waste entries','3','minimum entries in the core scenario; 1 processing trim and 2 standalone losses'],['CSV invoice total','39000','NGN; 2 separate invoices'],['CSV sales total','18000','NGN; 3 sold servings'],['CSV estimated food cost','5040','NGN; recipe estimate, not stock depletion'],['CSV estimated food margin','12960','NGN; before labour and operating expenses'],['CSV labour','600','NGN'],['CSV operating expense','500','NGN']],'checks')
sheet('run-details','field,value,notes',[
 ['Pack revision',PACK_DATE,'Use this revision instead of older test packs'],['App release',APP_RELEASE,'Deployment checked before executing'],['Required migration',MIGRATION,'Already applied; do not rerun applied migrations'],['Website','https://profit-plate-insight.vercel.app/',''],['Example transaction date',DATE,'Keep all dependent master/transaction dates aligned'],['Actual execution date','','Date you perform the tests'],['Restaurant name','Training Restaurant - Run 041','Use a fresh restaurant'],['Organisation UUID','','Copy from app URL'],['Lead tester','',''],['Browser / device','',''],['Overall decision','','Record outstanding failures and product gaps']],'checks')
cases=json.loads((ROOT/'docs/product/RESTAURANT_UAT_CASES.json').read_text(encoding='utf-8'))
sheet('test-results','test_id,area,role,prerequisite,steps,expected_result,status,actual_result,evidence_or_screenshot,issue_reference,tester,executed_on',[
 [c['id'],c['area'],c['role'],c['prerequisite'],c['steps'],c['expected'],'Not run','','','','',''] for c in cases],'checks')
README='''# Complete fictional restaurant test data - updated 19 November 2026

Start with the Excel workbook for the whole dataset. Use the Word guide for the step-by-step walkthrough. All figures and people are fictional. Use a separate training restaurant.

IMPORTANT: This is a testing pack, not a universal master-data importer. The XLSX workbook is for review/manual entry; do not upload it to a CSV screen. Files in manual-entry/ are populated collection sheets, not application upload formats. Only the four CSVs in upload-ready/ match implemented import screens, and they still need their prerequisite masters created first.

## Before testing
- Pack revision 19 November 2026; updated for invitation-onboarding release 042 and migrations through 042. Do not rerun applied migrations.
- Complete run-details and test-results in the workbook. This replaces the earlier stock-only/v2 testing instructions.
- Create Training Restaurant, brand Training Kitchen and first outlet Dining Room. Fresh onboarding assigns brand and outlet code PRIMARY; verify these codes in the actual workspace before uploading. Map/replace PRIMARY explicitly if using a different outlet.
- Owner rows in users.csv represent the same existing owner with two roles; do not invite or create the owner twice.
- Replace all example.test user emails with separate email addresses/aliases you control. They are not real logins. Register, verify and accept invitations; the pack contains no passwords.
- Test date: 2026-11-19. Use that date consistently in masters, prices, transactions and filters. If testing later, update dependent CSV/master dates together before setup; do not enter future transactions. Receiver acceptance posts on its actual business date: any later processing/waste must use that date or later, never an earlier date.
- Week/count schedule in business.csv is a fictional choice. Replace it with the restaurant's actual schedule for a real pilot.

## Manual setup order
1. Business/calendar and named users.
2. Centres & team access: save each centre, responsible owner and tasks together. Enable Request materials, Record waste and Accept transfers for Kitchen/Bar owners. Choose Kitchen under Choose where material processing happens. Additional staff & detailed permissions is optional; configure transfer/return routes separately.
3. Suppliers, materials, packaging and conversions.
4. Starting prices (manual OR import the six initial-price rows).
5. SNAPPER_CUTTING processing baseline (40 KG whole fish -> 120 PCS cuts).
6. STEW_BASE sub-recipe, then SNAPPER_RICE_RECIPE final recipe and its component lines.
7. SNAPPER_RICE_MENU selling item, final recipe link and 1 PCS of recipe output per sale; set TAKEAWAY price 6000, NONE tax for this fictional arithmetic test only.
8. Opening stock. Positive rows need reviewed opening requests and posting. Zero rows need explicit zero-opening readiness confirmation, not zero-quantity stock requests. Opening quantities are per centre, not business-wide totals.
9. Transfer 40 KG whole fish Main Store -> Kitchen; manager approves/dispatches and Ada accepts before stock changes.
10. Emeka records 1 KG Main Store rice spoilage with submitter name Emeka (20 -> 19 KG); no approval. Ada records the processing batch and its 4 KG trim once; this production request still needs approval/posting. Ada then records separate 2 PCS spoilage with her name; it posts immediately without waste approval (110 -> 108 PCS).

## Upload the four working CSVs
- initial-material-prices.csv: Initial material prices screen. Six rows; no Snapper Cut purchase price. Reference prices do not add stock.
- purchases-import.csv: Purchase imports screen. Source organisation code TRAINING; source unit-price tax basis EXCLUSIVE; NGN. Separate FISH_SUP and DRY_SUP invoices. Check totals 30000 and 9000 (39000 combined). File Status RECEIVED follows the source contract; invoice import does NOT create a GRN or receive/post physical stock. These invoices must not be posted again manually. If testing a manual PO/GRN/invoice cycle, use a separate reference/delivery.
- sales-import.csv: Sales CSV screen. Source organisation code TRAINING; EXCLUSIVE source tax format; NGN. This fictional file has zero tax/discount and one paid normal receipt: 3 servings, net/customer total 18000. The menu/final recipe versions and selling price must be effective first. Sales imports are not automatic ingredient-stock consumption postings.
- expense-import.csv: Expense CSV screen. Source organisation code TRAINING; existing WAGES and RENT categories; LOCATION scope, outlet PRIMARY, ON_DATE recognition. Review total 1100. Do not enter these same expenses manually too.

Preview every upload, correct unresolved codes and reconcile the app's source totals before confirmation. Current price/transaction CSV screens use reviewed, bounded batches; this pack contains only small samples. Repeat only as an explicit retry test, not as another new transaction.

## Expected results and boundaries
Use checks/expected-results.csv. The expected menu cost is 1680 per plate and food margin is 4320 (72%) at price 6000, before other costs. The illustrative processing batch achieves 110/120 = 91.67% of expected pieces and 36/40 = 90% usable weight; trim is already included in the input consumption. After independent spoilage Kitchen holds 108 cuts; Main Store rice is 19 KG after its separate 1 KG waste entry. Standard SKU recipe estimates are distinct from actual batch unit-cost performance.

The sample sales and expense files test financial records; they do not automatically reduce Kitchen stock to reflect the sold plates. Test recorded consumption/counts separately. Do not sum KG and PCS into one loss quantity. These food margins are estimates, not actual net profit or a complete contribution margin.

Suppliers, materials, conversions, recipe headers/components, menu items/prices, processing baselines and opening stock currently have no bulk upload screen. Their manual-entry sheets must remain labelled as such until the relevant importers are built.
'''
README+='''
## Updated role checks
- Inviting requests a Supabase email sign-in link; copyable backup and resend remain available. Custom SMTP is needed for unrestricted staff delivery.
- Existing centres/tasks can be selected on the invitation. If none exist yet, assign them after joining. Verified pending invitations recover at /join across browsers; staff must not create a restaurant.
- Finance-only: six primary shortcuts maximum; no business/stock setup links or setup access through direct URLs.
- Finance waste: all permitted centres by default, processing plus other waste, centre/date/source/status filters and a CSV that matches those filters. No Record waste action.
- Inventory waste: own responsible centres only, including direct links and exports. Kitchen/Bar: assigned centres only. Test with single-role accounts.
- Invoice: bill and material summary first; unreviewed matching exceptions and pending correction decisions visible; source/resolved history collapsed. PO approval remains excluded.
- Weekly stock-count flag: verify Include in weekly stock counts on each material; do not claim missing weekly count automation is implemented.
- No extra migration is introduced by this documentation pack. The four CSV upload formats remain unchanged.
'''
DEST.mkdir(parents=True,exist_ok=True)
for name,data in DATA.items():
 folder=DEST/data['folder'];folder.mkdir(exist_ok=True)
 with (folder/f'{name}.csv').open('w',newline='',encoding='utf-8-sig') as f:
  writer=csv.writer(f);writer.writerow(data['columns']);writer.writerows(data['rows'])
(DEST/'START-HERE.md').write_text(README,encoding='utf-8')
(DEST/'dataset.json').write_text(json.dumps({'pack_date':PACK_DATE,'app_release':APP_RELEASE,'required_migration':MIGRATION,'test_date':DATE,'source_org':'TRAINING','sheets':DATA},indent=2),encoding='utf-8')
# Regenerate the Word guide from the current Markdown, never copy an old export.
def word_guide(markdown,destination):
    def plain(text):
        text=re.sub(r'\[([^]]+)\]\([^)]+\)',r'\1',text)
        return text.replace('**','').replace('`','')
    def para(text,style='Normal'):
        return f'<w:p><w:pPr><w:pStyle w:val="{style}"/></w:pPr><w:r><w:t xml:space="preserve">{escape(plain(text))}</w:t></w:r></w:p>'
    body=[];lines=markdown.splitlines();i=0
    while i<len(lines):
        line=lines[i].strip()
        if line.startswith('|'):
            table=[]
            while i<len(lines) and lines[i].strip().startswith('|'):
                row=[cell.strip() for cell in lines[i].strip().strip('|').split('|')];i+=1
                if all(re.fullmatch(r'[-: ]+',cell) for cell in row):continue
                table.append('<w:tr>'+''.join('<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>'+para(cell)+'</w:tc>' for cell in row)+'</w:tr>')
            body.append('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/></w:tblPr>'+''.join(table)+'</w:tbl>');continue
        if line:
            level=len(line)-len(line.lstrip('#'))
            body.append(para(line.lstrip('# ').strip(),f'Heading{min(level,3)}' if level else 'Normal'))
        i+=1
    doc='<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+''.join(body)+'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000"/></w:sectPr></w:body></w:document>'
    styles='<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults>'+''.join(f'<w:style w:type="paragraph" w:styleId="Heading{n}"><w:name w:val="heading {n}"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr><w:rPr><w:b/><w:color w:val="194F40"/><w:sz w:val="{34-n*3}"/></w:rPr></w:style>' for n in range(1,4))+'<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders>'+''.join(f'<w:{edge} w:val="single" w:sz="4" w:color="D8E4DE"/>' for edge in ['top','left','bottom','right','insideH','insideV'])+'</w:tblBorders></w:tblPr></w:style></w:styles>'
    relns='http://schemas.openxmlformats.org/package/2006/relationships'
    files={'[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>','_rels/.rels':f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>','word/document.xml':doc,'word/styles.xml':styles,'word/_rels/document.xml.rels':f'<Relationships xmlns="{relns}"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'}
    with ZipFile(destination,'w',ZIP_DEFLATED) as z:
        for name,value in files.items():ET.fromstring(value);z.writestr(name,value.encode('utf-8'))

guide=(ROOT/'docs/product/COMPLETE_RESTAURANT_ONBOARDING_AND_TEST_GUIDE.md').read_text(encoding='utf-8')
(DEST/'Complete_Restaurant_Onboarding_and_Test_Guide.md').write_text(guide,encoding='utf-8')
word_guide(guide,DEST/'Complete_Restaurant_Onboarding_and_Test_Guide.docx')
shutil.copyfile(DEST/'Complete_Restaurant_Onboarding_and_Test_Guide.docx',ROOT/'docs/exports/Complete_Restaurant_Onboarding_and_Test_Guide.docx')
for name in ['CENTRES_AND_TEAM_ACCESS_GUIDE.md','CENTRE_WASTE_REVIEW_GUIDE.md','TEAM_INVITATIONS_AND_EMAIL_SETUP.md']:
    shutil.copyfile(ROOT/'docs/product'/name,DEST/name)
(DEST/'CHANGES-2026-11-19.md').write_text('Updated for invitation-onboarding release 042. Centre and owner tasks save together. Waste requires a submitter and posts without approval. Finance reads combined centre waste and exports filtered results, without setup or waste entry. Inventory retains own-centre waste. Invoice materials and pending decisions remain prominent; supporting history collapses. Added executable test-results and run-details sheets. Master setup coverage and four upload schemas are retained. Example transaction dates are 2026-11-19. Use this pack in place of older instructions. No extra migration required.\n',encoding='utf-8')

# XLSX workbook: all cells are text to preserve codes, phone numbers and source decimals.
def col(n):
 out=''
 while n:n,r=divmod(n-1,26);out=chr(65+r)+out
 return out
sheets=[('START HERE',{'columns':['Instruction'],'rows':[[line] for line in README.splitlines() if line]})]+[(name[:31],data) for name,data in DATA.items()]
ns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
parts={}
for idx,(name,data) in enumerate(sheets,1):
 rows=[]
 for rid,values in enumerate([data['columns']]+data['rows'],1):
  cells=''.join(f'<c r="{col(cid)}{rid}" t="inlineStr" s="{1 if rid==1 else 0}"><is><t xml:space="preserve">{escape(str(value))}</t></is></c>' for cid,value in enumerate(values,1))
  rows.append(f'<row r="{rid}" ht="{30 if rid==1 else 150 if name=='test-results' else 42}" customHeight="1">{cells}</row>')
 validation=f'<dataValidations count="1"><dataValidation type="list" allowBlank="0" showErrorMessage="1" errorTitle="Choose a result" error="Select a listed test status." sqref="G2:G{len(data["rows"])+1}"><formula1>"Not run,Pass,Fail,Blocked,Not available"</formula1></dataValidation></dataValidations>' if name=='test-results' else ''
 width='120' if idx==1 else '24'
 colspec=''.join(f'<col min="{n}" max="{n}" width="{w}" customWidth="1"/>' for n,w in enumerate([16,25,25,22,75,75,18,45,35,25,22,20],1)) if name=='test-results' else f'<col min="1" max="{len(data["columns"])}" width="{width}" customWidth="1"/>'
 parts[f'xl/worksheets/sheet{idx}.xml']=f'<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="{ns}"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>{colspec}</cols><sheetData>{"".join(rows)}</sheetData><autoFilter ref="A1:{col(len(data["columns"]))}{len(data["rows"])+1}"/>{validation}</worksheet>'
parts['xl/workbook.xml']=f'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="{ns}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+''.join(f'<sheet name="{escape(name)}" sheetId="{i}" r:id="rId{i}"/>' for i,(name,_) in enumerate(sheets,1))+'</sheets></workbook>'
parts['xl/_rels/workbook.xml.rels']='<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+''.join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1,len(sheets)+1))+f'<Relationship Id="rId{len(sheets)+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
parts['xl/styles.xml']=f'<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="{ns}"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF194F40"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE7F0EB"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="49" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
parts['_rels/.rels']='<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
parts['[Content_Types].xml']='<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'+''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(1,len(sheets)+1))+'<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
for value in parts.values():ET.fromstring(value)
with ZipFile(DEST/'ProfitPlate_Complete_Test_Data.xlsx','w',ZIP_DEFLATED) as z:
 for name,value in parts.items():z.writestr(name,value.encode('utf-8'))
with ZipFile(DEST/'ProfitPlate_Complete_Test_Data.xlsx') as z:assert z.testzip() is None
for name,data in DATA.items():
 assert all(len(row)==len(data['columns']) for row in data['rows']),name
 if data['folder']=='upload-ready':
  original=(ROOT/f'public/templates/{name}.csv').read_text(encoding='utf-8-sig').splitlines()[0]
  assert ','.join(data['columns'])==original,name
archive=DEST.parent/f'profitplate-complete-test-data-{PACK_DATE}.zip'
with ZipFile(archive,'w',ZIP_DEFLATED) as z:
 for path in sorted(DEST.rglob('*')):
  if path.is_file():z.write(path,path.relative_to(DEST))
print(f'Built {archive.name}: {len(sheets)} workbook sheets, {len(DATA)} populated CSVs, 4 implemented upload formats.')
