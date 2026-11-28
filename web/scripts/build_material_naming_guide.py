"""Build the reusable onboarding naming guide and its accessible web companion."""
from pathlib import Path
from html import escape
from zipfile import ZipFile, ZIP_DEFLATED
import xml.etree.ElementTree as ET
import shutil

ROOT = Path(__file__).resolve().parents[1]
PAGES = [
 ('Clear names, confident selection', [
  ('intro', 'ProfitPlate Insights | Material naming guide for every new restaurant'),
  ('p', 'Use this guide before entering or importing your materials, processing baselines, recipes and selling menus. Clear names help your team choose the right stock form and avoid costing a prepared ingredient at its purchased price.'),
  ('h', 'The main rule'),
  ('callout', 'Material family — Physical form. Add the form when it changes what the team buys, holds, processes or uses. Keep a familiar standalone name when it is already clear.'),
  ('table', [('Instead of', 'Use, after confirming the actual form'), ('Beef RM', 'Beef — Whole (only if purchased whole)'), ('Beef Cut SFG', 'Beef — Small cuts / Beef — Large cuts'), ('Semo RM', 'Semo — Dry'), ('Semo Processed', 'Semo — Prepared'), ('Garri RM Processed', 'Garri — Prepared (Eba)'), ('Tomato/Pepper Processed', 'Tomato & Pepper Mix — Prepared'), ('Salt', 'Salt: keep it simple')]),
  ('h', 'A name must describe reality'),
  ('p', 'Processed alone does not tell a user whether meat is cut, cooked or marinated. Check the real transformation with the chef or store manager. Use the same family wording across related forms. Do not automatically rename every prepared item to Cooked.'),
  ('p', 'Preserve local food names and meaningful brands. Two seasoning brands or two meat sizes may be different stock items. Never merge them simply because their names look similar.'),
 ]),
 ('Separate stock, recipes and menus', [
  ('h', 'Three names can describe different things'),
  ('table', [('Record', 'Purpose', 'Example'), ('Material / stock item', 'The physical item counted and moved at a centre', 'Egusi Soup — Prepared'), ('Recipe or processing baseline', 'How inputs produce a defined output', 'Egusi Soup — Standard Batch'), ('Selling menu item', 'What the customer buys', 'Pounded Yam & Egusi')]),
  ('p', 'A recipe is a method, not automatically stock. Link its output to a tracked material and enable its production baseline at the permitted centre when that output will be held, transferred or counted.'),
  ('h', 'Choose forms for your real operation'),
  ('p', 'Use separate materials when the business needs separate stock accountability: whole beef versus cut beef; dry semolina versus prepared semo; purchased tomatoes versus prepared tomato mix. Do not create extra forms for every cooking action if the restaurant does not hold or track that intermediate item.'),
  ('p', 'A prepared item can use several inputs but has one stocked output per baseline. For example, seeds, oil and seasonings can produce Egusi Soup — Prepared. If small and large beef cuts are separate outputs, use separate processing records in the current single-output model; do not consume the same input twice.'),
  ('h', 'Do not put the centre in the material name'),
  ('p', 'Beef — Small cuts can be held in Main Store and Kitchen under the same SKU. Assign it to both permitted centres. Each centre keeps its own balance; a second location does not require a second copy of the material.'),
  ('h', 'Keep the measurement separate'),
  ('p', 'Choose KG, L, PCS or the appropriate configured base unit in the unit field. Define a standard piece or portion in the baseline specification. If two bottle sizes are separately held, name them clearly, for example Tigernut Drink — 350 ml and Tigernut Drink — 500 ml. These are product sizes, not centre names.'),
 ]),
 ('Set up a new restaurant step by step', [
  ('step', '1. List your real centres. Create Main Store, Kitchen, Bar or the names the business actually uses. Assign their responsible people and task permissions.'),
  ('step', '2. List purchased and prepared forms. Ask the store manager and chef what enters the business and what is produced internally. Agree one clear name for each distinct stocked item.'),
  ('step', '3. Choose fixed codes. Use a unique code such as BEEF_WHOLE or BEEF_SMALL. Keep the same code on every centre row of an import. Codes identify records; they are not the everyday display name.'),
  ('step', '4. Enter or import the master data. Supply the correct material type, base unit and stock class. Use Purchased for bought-in stock, Processed for produced stock, or Purchased and processed where both apply. Mark a transforming input Requires processing where appropriate.'),
  ('step', '5. Assign materials to centres. Include both inputs and produced outputs at every centre that needs them. Being in a recipe does not by itself give a centre access to that material.'),
  ('step', '6. Record known prices and openings. Use the template fields for last purchase price/date and each centre’s opening quantity/date. Unknown is blank; known zero is 0. Review and complete the opening-stock recording step. Saving a material alone does not create stock.'),
  ('step', '7. Establish the transformation. Save the input quantities, expected output, specification and permitted production centres. Link the produced SKU. For example, 40 KG of whole fish produces 120 standard cuts. The produced material’s estimated unit cost comes from its linked recipe/baseline.'),
  ('step', '8. Connect recipes and selling menus. Use the correct prepared stock where that is what the kitchen consumes. Choose the menu’s consumption centre and method to avoid consuming the raw inputs again after production has already used them.'),
  ('step', '9. Practise selection. Ask a store user and kitchen user to find the purchased and prepared forms. Check names, units, centre lists, processing outputs and a sample recipe before live use.'),
 ]),
 ('Review before launch', [
  ('h', 'Your naming checklist'),
  ('bullet', 'One distinct physical stock item has one agreed name and one fixed code.'),
  ('bullet', 'Purchased and prepared forms are clearly distinguishable without RM, SFG or vague Processed wording.'),
  ('bullet', 'Names preserve the local food identity, brand and any meaningful product size.'),
  ('bullet', 'Units, categories, centres and prices are entered in their own fields.'),
  ('bullet', 'Input/output links and centre assignments match the actual kitchen and store workflow.'),
  ('bullet', 'Every material that may be counted or used at a centre is assigned there, including known-zero items.'),
  ('bullet', 'A team member can choose the right material without memorising its SKU code.'),
  ('h', 'How selection works'),
  ('p', 'Supported operational forms show material names first. Larger local lists can be searched by name, code or unit; existing recipe/output searches also remain available. Where material type is provided, lists group raw ingredients, prepared ingredients, finished items and packaging. Selected units and supporting details appear separately. Material codes remain available under Material code.'),
  ('p', 'Only materials already eligible for that workflow are offered. Searching does not grant access to another centre’s materials, create stock or make an incomplete production baseline usable. If a name appears twice, inspect its code and unit before choosing and ask an administrator to clarify the names.'),
  ('h', 'For an existing restaurant'),
  ('p', 'Review names with the team, then edit the existing material record. Keep its ID, fixed code, base unit and history. Do not import a new SKU merely to rename an old one. A name correction does not replace a new recipe version when ingredients or quantities change.'),
  ('h', 'Who maintains the standard?'),
  ('p', 'The Restaurant Administrator maintains the agreed list with input from the Inventory Manager and production leads. Brief new colleagues on the same naming rule. Review confusing names as they arise; avoid frequent cosmetic renaming.'),
  ('callout', 'The goal is simple: users should recognise what they are selecting, while the business retains traceable stock, reliable costs and clear responsibility.'),
 ])
]

W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
def paragraph(text, style='Normal', before=False):
 return f'<w:p><w:pPr><w:pStyle w:val="{style}"/>'+('<w:pageBreakBefore/>' if before else '')+f'</w:pPr><w:r><w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>'
def table(rows):
 result='<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders>'+''.join(f'<w:{side} w:val="single" w:sz="4" w:color="D4E2DC"/>' for side in ['top','left','bottom','right','insideH','insideV'])+'</w:tblBorders></w:tblPr>'
 for n,row in enumerate(rows):
  result+='<w:tr>'+('<w:trPr><w:tblHeader/></w:trPr>' if n==0 else '')
  for cell in row:result+='<w:tc><w:tcPr><w:tcW w:w="'+str(9300//len(row))+'" w:type="dxa"/>'+('<w:shd w:fill="EAF2EE"/>' if n==0 else '')+'</w:tcPr>'+paragraph(cell,'TableText')+'</w:tc>'
  result+='</w:tr>'
 return result+'</w:tbl>'

body='';html=[]
for n,(title,blocks) in enumerate(PAGES):
 body+=paragraph(title,'Title',n>0);parts=[f'<h1>{escape(title)}</h1>']
 for kind,text in blocks:
  if kind=='table':body+=table(text);parts.append('<table>'+''.join('<tr>'+''.join(f'<{"th" if i==0 else "td"}>{escape(c)}</{"th" if i==0 else "td"}>' for c in row)+'</tr>' for i,row in enumerate(text))+'</table>')
  else:
   style={'intro':'Subtitle','h':'Heading2','callout':'Callout','bullet':'Bullet','step':'Normal'}.get(kind,'Normal')
   body+=paragraph(('• ' if kind=='bullet' else '')+text,style)
   tag='h2' if kind=='h' else 'p';parts.append(f'<{tag} class="{kind}">{escape(text)}</{tag}>')
 html.append('<section>'+''.join(parts)+'</section>')
document=f'<w:document xmlns:w="{W}"><w:body>'+body+'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="850" w:right="1100" w:bottom="850" w:left="1100"/></w:sectPr></w:body></w:document>'
styles=f'<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:color w:val="243D33"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="130" w:line="260" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
for name,size,color in [('Normal',22,'243D33'),('Title',36,'174F40'),('Heading2',25,'174F40'),('Subtitle',23,'63766C'),('Callout',22,'174F40'),('Bullet',22,'243D33'),('TableText',20,'243D33')]:
 styles+=f'<w:style w:type="paragraph" w:styleId="{name}"><w:name w:val="{name}"/><w:pPr>'+('<w:keepNext/>' if name in ['Title','Heading2'] else '')+('<w:shd w:fill="EAF2EE"/>' if name=='Callout' else '')+f'</w:pPr><w:rPr><w:sz w:val="{size}"/><w:color w:val="{color}"/>'+('<w:b/>' if name in ['Title','Heading2'] else '')+'</w:rPr></w:style>'
styles+='</w:styles>'
files={
 '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
 '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
 'word/_rels/document.xml.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
 'word/document.xml':document,'word/styles.xml':styles}
out=ROOT/'docs/exports/ProfitPlate_Insights_Material_Naming_Guide.docx';out.parent.mkdir(parents=True,exist_ok=True)
with ZipFile(out,'w',ZIP_DEFLATED) as z:
 for name,content in files.items():ET.fromstring(content);z.writestr(name,'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'+content)
public=ROOT/'public/guides';public.mkdir(parents=True,exist_ok=True);shutil.copyfile(out,public/out.name)
page='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Material naming guide | ProfitPlate Insights</title><style>*{box-sizing:border-box}body{margin:0;background:#f4f8f5;color:#243d33;font:16px/1.6 system-ui,sans-serif}main{max-width:920px;margin:auto;padding:28px 20px}header{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:18px}a{color:#174f40;font-weight:600}section{background:#fff;border:1px solid #d4e2dc;border-radius:14px;margin:24px 0;padding:clamp(18px,4vw,36px)}h1{font-size:clamp(24px,4vw,32px);line-height:1.2;color:#174f40}h2{font-size:21px;margin-top:26px}.intro{color:#63766c}.callout{padding:16px;background:#eaf2ee;border-left:3px solid #b39553}table{width:100%;border-collapse:collapse;font-size:15px}th,td{text-align:left;vertical-align:top;border:1px solid #d4e2dc;padding:10px;overflow-wrap:anywhere}th{background:#eaf2ee}.bullet{padding-left:16px;border-left:2px solid #d4e2dc}@media print{body{background:white}main{padding:0}header{display:none}section{border:0;border-radius:0;margin:0;padding:0;break-after:page}section:last-child{break-after:auto}@page{size:A4;margin:18mm}}</style></head><body><main><header><strong>ProfitPlate Insights</strong><a href="ProfitPlate_Insights_Material_Naming_Guide.docx" download>Download Word guide</a></header>'+''.join(html)+'</main></body></html>'
(public/'material-naming.html').write_text(page,encoding='utf-8')
with ZipFile(out) as z:
 assert z.testzip() is None
 for name in z.namelist():ET.fromstring(z.read(name))
 assert 'Madam BigBen' not in ''.join(ET.fromstring(z.read('word/document.xml')).itertext())
print(f'Created {out.name}; 4 authored sections; Word XML validated; web companion created.')
