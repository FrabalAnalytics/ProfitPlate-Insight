import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../lib/auth-errors.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext}});
const {signInErrorMessage}=await import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);

test('connection and provider failures never report incorrect credentials',()=>{
 for(const error of [{status:0},{name:'AuthRetryableFetchError'},{status:503},{status:401,code:'bad_jwt'},{}]){
  assert.doesNotMatch(signInErrorMessage(error),/incorrect/);
 }
 assert.match(signInErrorMessage({status:0}),/reach the sign-in service/);
});
test('credential, confirmation and rate-limit responses retain appropriate guidance',()=>{
 assert.match(signInErrorMessage({status:400,code:'invalid_credentials'}),/email or password is incorrect/);
 assert.match(signInErrorMessage({status:400,code:'email_not_confirmed'}),/Confirm your email/);
 assert.match(signInErrorMessage({status:429}),/Too many attempts/);
});
