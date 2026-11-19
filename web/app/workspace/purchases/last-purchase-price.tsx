"use client";
import {useEffect,useId,useState} from 'react';
import type {LastPurchasePrice} from '@/lib/procurement';
import {referenceAmount} from '@/lib/reference-prices';
import {lastPurchasePrice} from './actions';
export function LastPurchasePriceField({organisation,item,unit,date,line}:{organisation:string;item:string;unit:string;date:string;line:number}){
 const id=useId(),[attempt,setAttempt]=useState(0),[result,setResult]=useState<{key:string;value?:LastPurchasePrice;error?:string}|null>(null),key=JSON.stringify([organisation,item,unit,date,attempt]);
 useEffect(()=>{if(!item||!unit)return;let active=true;lastPurchasePrice(organisation,item,unit,date).then(value=>{if(active)setResult({key,...value});}).catch(()=>{if(active)setResult({key,error:'Price could not be loaded. Try again.'});});return()=>{active=false;};},[organisation,item,unit,date,attempt,key]);
 const ready=result?.key===key?result:null,value=ready?.value,price=!item||!unit?'Select a material and unit':!ready?'Loading...':ready.error?'Unavailable':value?.status==='FOUND'?`${referenceAmount(value.unit_price??'',value.currency??'')} / ${value.unit_code}`:value?.status==='CONVERSION_REQUIRED'?'Set up unit conversion':'No purchase price recorded';
 return <div className="setup-field po-last-price"><label htmlFor={id}>Last purchase unit price, line {line}</label><input id={id} readOnly value={price} aria-busy={!!item&&!!unit&&!ready} aria-describedby={`${id}-source`}/><small id={`${id}-source`} aria-live="polite">{ready?.error?<>{ready.error} <button className="inline-link" type="button" onClick={()=>setAttempt(attempt+1)}>Retry price lookup</button></>:value?.status==='FOUND'?<>{value.source==='INITIAL_PRICE'?'Initial price (no invoice)':value.supplier} | {value.date}{value.source==='INVOICE'?` | ${value.price_basis==='INCLUSIVE'?'Includes':'Excludes'} tax; before line discount`:''}</>:value?.status==='CONVERSION_REQUIRED'?'Add a valid conversion for this material and unit.':item&&unit&&ready?'You can still enter the quoted unit price.':'Automatically retrieved for comparison.'}</small></div>;
}
