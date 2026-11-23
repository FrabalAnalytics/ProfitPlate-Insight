import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/catalogue.ts',import.meta.url),'utf8');
const {validateUnit}=await import(`data:text/javascript;base64,${Buffer.from(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}}).outputText).toString('base64')}`);
const base={organisation_id:'10000000-0000-0000-0000-000000000001',code:'DOZEN',name:'Dozen',dimension:'COUNT',factor:'12'};
test('unit form accepts precise units and per-material packages',()=>{assert.deepEqual(validateUnit(base),{});assert.deepEqual(validateUnit({...base,dimension:'PACKAGE',factor:''}),{});assert.deepEqual(validateUnit({...base,dimension:'MASS',factor:'0.000001'}),{});});
test('unit form rejects invalid factors, types and unsafe codes',()=>{for(const factor of ['0','-1','NaN','1e3','0.0000001','1,000'])assert.ok(validateUnit({...base,factor}).factor);assert.ok(validateUnit({...base,dimension:'OTHER'}).dimension);assert.ok(validateUnit({...base,code:'BAD CODE'}).code);assert.ok(validateUnit({...base,name:''}).name);assert.ok(validateUnit({...base,organisation_id:'bad'}).organisation_id);});
