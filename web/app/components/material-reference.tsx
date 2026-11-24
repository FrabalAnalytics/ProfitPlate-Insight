export function MaterialReference({code}:{code?:string|null}) {
 return code?<small className="material-code-reference">Material code: <span>{code}</span></small>:null;
}
