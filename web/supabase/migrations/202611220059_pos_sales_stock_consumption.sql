-- Imported, already-fulfilled POS sales: dated standard consumption, never a POS checkout.
begin;
alter table private.weekly_counts add column daily_boundary text check(daily_boundary in('BEFORE_OPENING','AFTER_CLOSING'));
alter table public.stock_documents drop constraint stock_documents_kind_check;
alter table public.stock_documents add constraint stock_documents_kind_check check(kind in('OPENING','GRN','DIRECT_RECEIPT','TRANSFER','ISSUE','COUNT','WASTE','CONSUMPTION','PRODUCTION','SALES','SALES_RECONCILIATION'));
create table private.menu_stock_mappings(id uuid primary key default gen_random_uuid(),organisation_id uuid not null,menu_id uuid not null,outlet_id uuid not null,site_id uuid not null,mode text not null check(mode in('RECIPE','FINISHED')),effective_from date not null,version integer not null,request_id uuid not null,input_hash text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(organisation_id,id),unique(organisation_id,request_id),unique(organisation_id,menu_id,outlet_id,version),foreign key(organisation_id,menu_id) references public.menu_items(organisation_id,id),foreign key(organisation_id,outlet_id) references public.locations(organisation_id,id),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
create index menu_stock_effective on private.menu_stock_mappings(organisation_id,menu_id,outlet_id,effective_from desc,version desc);
create table private.sales_stock_jobs(id uuid primary key default gen_random_uuid(),organisation_id uuid not null,sale_line_id uuid not null,site_id uuid,mapping_id uuid,state text not null default 'PENDING' check(state in('PENDING','POSTED','RECONCILED','EXCLUDED')),reason text not null default 'Awaiting stock mapping and validation',document_id uuid,offset_document_id uuid,offset_documents jsonb not null default '[]',plan jsonb,created_by uuid not null,created_at timestamptz not null default now(),completed_at timestamptz,reviewed_by uuid,review_note text,unique(organisation_id,id),unique(organisation_id,sale_line_id),foreign key(organisation_id,sale_line_id) references public.sales_lines(organisation_id,id),foreign key(organisation_id,site_id) references public.stock_locations(organisation_id,id));
create index sales_stock_pending on private.sales_stock_jobs(organisation_id,state,site_id);
create table private.sales_count_reconciliations(organisation_id uuid not null,count_id uuid not null references private.weekly_counts(id),job_id uuid not null,item_id uuid not null,book_delta numeric not null,approved_by uuid not null,approved_at timestamptz not null default now(),primary key(count_id,job_id,item_id),foreign key(organisation_id,job_id) references private.sales_stock_jobs(organisation_id,id),foreign key(organisation_id,item_id) references public.items(organisation_id,id));
revoke all on private.menu_stock_mappings,private.sales_stock_jobs,private.sales_count_reconciliations from public,anon,authenticated;
create trigger restaurant_active_write before insert or update or delete on private.menu_stock_mappings for each row execute function private.pp_require_active_restaurant();
create trigger restaurant_active_write before insert or update or delete on private.sales_stock_jobs for each row execute function private.pp_require_active_restaurant();
create trigger restaurant_active_write before insert or update or delete on private.sales_count_reconciliations for each row execute function private.pp_require_active_restaurant();

create function private.pp_count_review_role(org uuid,site uuid) returns boolean language sql stable security definer set search_path='' as $$select private.pp_inventory_report_site(org,site) and(private.pp_stock_role(org,'ceo',(select outlet_id from public.stock_locations where id=site)) or private.pp_stock_role(org,'finance',(select outlet_id from public.stock_locations where id=site)) or private.pp_operations_site(org,site));$$;
create function public.menu_stock_directory(p_organisation_id uuid,p_menu_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu setup access required.' using errcode='42501';end if;
 return jsonb_build_object('sites',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'outlet_id',outlet_id) order by name) from public.stock_locations where organisation_id=p_organisation_id and is_active),'[]'::jsonb),'routes',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('centre',s.name,'outlet',l.name) order by effective_from desc,version desc) from private.menu_stock_mappings m join public.stock_locations s on s.id=m.site_id join public.locations l on l.id=m.outlet_id where m.organisation_id=p_organisation_id and m.menu_id=p_menu_id),'[]'::jsonb));
end $$;
create function public.save_menu_stock_mapping(p_organisation_id uuid,p_request_id uuid,p_menu_id uuid,p_outlet_id uuid,p_site_id uuid,p_mode text,p_from date) returns uuid language plpgsql security definer set search_path='' as $$declare old private.menu_stock_mappings;saved_id uuid;digest text:=md5(jsonb_build_array(p_menu_id,p_outlet_id,p_site_id,p_mode,p_from)::text);begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Menu setup access required.' using errcode='42501';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 select * into old from private.menu_stock_mappings where organisation_id=p_organisation_id and request_id=p_request_id;
 if found then if old.input_hash<>digest then raise exception 'Refresh before changing a saved mapping.' using errcode='22023';end if;return old.id;end if;
 if p_request_id is null or p_from is null or p_mode not in('RECIPE','FINISHED') or p_mode is null or not exists(select 1 from public.menu_items m join public.locations l on l.organisation_id=m.organisation_id and l.brand_id=m.brand_id join public.stock_locations s on s.organisation_id=l.organisation_id where m.organisation_id=p_organisation_id and m.id=p_menu_id and m.is_active and l.id=p_outlet_id and l.is_active and(m.location_id is null or m.location_id=l.id) and s.id=p_site_id and s.is_active and(s.outlet_id is null or s.outlet_id=l.id)) then raise exception 'Choose a compatible outlet, active stock centre, consumption method and effective date.' using errcode='22023';end if;
 insert into private.menu_stock_mappings(organisation_id,menu_id,outlet_id,site_id,mode,effective_from,version,request_id,input_hash,created_by) select p_organisation_id,p_menu_id,p_outlet_id,p_site_id,p_mode,p_from,coalesce(max(version),0)+1,p_request_id,digest,auth.uid() from private.menu_stock_mappings where organisation_id=p_organisation_id and menu_id=p_menu_id and outlet_id=p_outlet_id returning private.menu_stock_mappings.id into saved_id;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(p_organisation_id,'MENU_STOCK_MAPPING',auth.uid(),saved_id,jsonb_build_object('menu',p_menu_id,'outlet',p_outlet_id,'centre',p_site_id,'method',p_mode,'effective_from',p_from));return saved_id;
end $$;
alter function public.save_menu_entry(uuid,uuid,jsonb) rename to save_menu_entry_before_stock;
create function public.save_menu_entry(p_organisation_id uuid,p_request_id uuid,p_value jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare id uuid;begin
 id:=public.save_menu_entry_before_stock(p_organisation_id,p_request_id,p_value);
 if nullif(p_value->>'stock_site_id','') is not null then perform public.save_menu_stock_mapping(p_organisation_id,md5(p_request_id::text||':stock')::uuid,id,(p_value->>'stock_outlet_id')::uuid,(p_value->>'stock_site_id')::uuid,p_value->>'consumption_mode',coalesce(nullif(p_value->>'stock_from',''),p_value->>'effective_from')::date);end if;return id;
end $$;
revoke all on function public.save_menu_entry_before_stock(uuid,uuid,jsonb) from public,anon,authenticated;

-- Expand virtual sub-recipes, but stop at stocked outputs to avoid consuming their inputs twice.
create function private.pp_sale_recipe_inputs(org uuid,version_id uuid,amount numeric,path uuid[] default '{}') returns table(item_id uuid,quantity numeric) language plpgsql stable security definer set search_path='' as $$declare c record;yield_qty numeric;child_qty numeric;bound uuid;factor numeric;begin
 if version_id=any(path) or cardinality(path)>=20 or amount<=0 then raise exception 'Invalid recipe dependency or output quantity.' using errcode='22023';end if;
 select o.quantity into yield_qty from public.recipe_outputs o where o.organisation_id=org and o.recipe_version_id=version_id;
 if yield_qty is null or yield_qty<=0 then raise exception 'Recipe output is missing.' using errcode='22023';end if;
 for c in select * from public.recipe_components where organisation_id=org and recipe_version_id=version_id order by line_no loop
  child_qty:=round(c.normalised_quantity*amount/yield_qty,12);
  if child_qty<=0 or child_qty>=1e26 then raise exception 'Recipe quantity is outside supported precision.' using errcode='22023';end if;
  if c.item_id is not null then return query select c.item_id,child_qty;
  else
   select b.item_id,u.canonical_factor/v.canonical_factor into bound,factor from public.stock_recipe_bindings b join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id join public.units_of_measure u on u.organisation_id=b.organisation_id and u.id=c.base_uom_id join public.units_of_measure v on v.organisation_id=i.organisation_id and v.id=i.base_uom_id where b.organisation_id=org and b.recipe_version_id=c.child_recipe_version_id;
   if bound is not null then return query select bound,round(child_qty*factor,12);
   else return query select x.item_id,x.quantity from private.pp_sale_recipe_inputs(org,c.child_recipe_version_id,child_qty,path||version_id)x;end if;
  end if;
 end loop;
end $$;
create function private.pp_sales_job_read(org uuid,job uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.sales_stock_jobs j join public.sales_lines l on l.organisation_id=j.organisation_id and l.id=j.sale_line_id join public.sales_headers h on h.id=l.sale_id where j.organisation_id=org and j.id=job and(private.pp_sales_read(org) or private.pp_inventory_report_site(org,j.site_id) or private.pp_operations(org,h.location_id)));
$$;
create function private.pp_sales_stock_plan(org uuid,job uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare j private.sales_stock_jobs;l public.sales_lines;h public.sales_headers;m private.menu_stock_mappings;v public.menu_item_versions;lines jsonb;new_lines jsonb:='[]';counts jsonb:='[]';item_counts jsonb;errors jsonb:='[]';offset_id uuid;offset_date date;out_item uuid;factor numeric;qty numeric;r record;needs boolean:=false;result jsonb;begin
 select * into j from private.sales_stock_jobs where organisation_id=org and id=job;
 if j.id is null then raise exception 'Sales consumption unavailable.' using errcode='42501';end if;
 select * into l from public.sales_lines where organisation_id=org and id=j.sale_line_id;select * into h from public.sales_headers where organisation_id=org and id=l.sale_id;
 select * into m from private.menu_stock_mappings where organisation_id=org and menu_id=l.menu_item_id and outlet_id=h.location_id and effective_from<=h.sale_date order by effective_from desc,version desc limit 1;
 begin
  if m.id is null then raise exception 'Set a stock centre and consumption method effective on the sales date.';end if;
  if not exists(select 1 from public.stock_locations where organisation_id=org and id=m.site_id and is_active) then raise exception 'The mapped stock centre is inactive.';end if;
  select * into v from public.menu_item_versions where organisation_id=org and id=l.menu_version_id;
  qty:=l.quantity*v.recipe_quantity;
  if m.mode='FINISHED' then
   select b.item_id,u.canonical_factor/z.canonical_factor into out_item,factor from public.stock_recipe_bindings b join public.recipe_outputs o on o.organisation_id=b.organisation_id and o.recipe_version_id=b.recipe_version_id join public.items i on i.organisation_id=b.organisation_id and i.id=b.item_id join public.units_of_measure u on u.organisation_id=o.organisation_id and u.id=o.uom_id join public.units_of_measure z on z.organisation_id=i.organisation_id and z.id=i.base_uom_id where b.organisation_id=org and b.recipe_version_id=v.recipe_version_id;
   if out_item is null then raise exception 'Link the saved final recipe to its stocked output SKU before using finished-stock consumption.';end if;
   lines:=jsonb_build_array(jsonb_build_object('item_id',out_item,'quantity',round(qty*factor,12)::text));
  else select jsonb_agg(jsonb_build_object('item_id',item_id,'quantity',quantity::text) order by item_id) into lines from(select x.item_id,sum(x.quantity) quantity from private.pp_sale_recipe_inputs(org,v.recipe_version_id,qty)x group by x.item_id)q;end if;
  if lines is null or jsonb_array_length(lines)>1000 then raise exception 'No usable stock ingredients, or recipe exceeds the consumption line limit.';end if;
  if exists(select 1 from jsonb_array_elements(lines)x where not exists(select 1 from public.items i join public.stock_locations s on s.organisation_id=i.organisation_id where i.organisation_id=org and i.id=(x->>'item_id')::uuid and i.stock_tracked and i.base_uom_id is not null and s.id=m.site_id and(i.location_id is null or s.outlet_id is null or s.outlet_id=i.location_id)) or(x->>'quantity')::numeric<=0) then raise exception 'A recipe ingredient is not stock tracked or is outside this centre scope.';end if;
  if exists(select 1 from private.weekly_counts where organisation_id=org and site_id=m.site_id and count_date=h.sale_date and state in('POSTED','REVIEWED') and daily_boundary is null) then raise exception 'A same-day completed count needs its before-opening or after-closing boundary confirmed by an independent reviewer.';end if;
  for r in select (x->>'item_id')::uuid item,(x->>'quantity')::numeric amount from jsonb_array_elements(lines)x loop
  select c.id,d.document_date into offset_id,offset_date from private.weekly_counts c join public.stock_documents d on d.organisation_id=c.organisation_id and d.id=c.stock_document_id where c.organisation_id=org and c.site_id=m.site_id and c.state='POSTED' and (c.count_date>h.sale_date or(c.count_date=h.sale_date and c.daily_boundary='AFTER_CLOSING')) and exists(select 1 from private.weekly_count_lines cl where cl.count_id=c.id and cl.item_id=r.item) order by c.cutoff,d.document_date limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'date',c.count_date,'state',c.state,'revision',c.revision,'submitter',c.submitted_by,'item_id',r.item) order by c.cutoff),'[]'::jsonb) into item_counts from private.weekly_counts c where c.organisation_id=org and c.site_id=m.site_id and c.state in('POSTED','REVIEWED') and (c.count_date>h.sale_date or(c.count_date=h.sale_date and c.daily_boundary='AFTER_CLOSING')) and(offset_date is null or c.count_date<=offset_date) and exists(select 1 from private.weekly_count_lines cl where cl.count_id=c.id and cl.item_id=r.item);
  counts:=counts||item_counts;
  new_lines:=new_lines||jsonb_build_array(jsonb_build_object('item_id',r.item,'quantity',r.amount::text,'offset_count_id',offset_id,'offset_date',offset_date));
   if exists(with changes as(select occurred_on as movement_day,quantity q from public.stock_ledger where organisation_id=org and location_id=m.site_id and item_id=r.item union all select h.sale_date,-r.amount union all select offset_date,r.amount where offset_date is not null),daily as(select movement_day,sum(q) q from changes group by movement_day),running as(select sum(q)over(order by movement_day) balance from daily) select 1 from running where balance<0) then raise exception 'Insufficient dated stock for %. Check opening balances and receipts before retrying.',(select name from public.items where id=r.item);end if;
   if offset_date is null and private.pp_stock_balance(org,m.site_id,r.item)-r.amount<private.pp_stock_reserved(org,m.site_id,r.item) then raise exception 'Current available stock is reserved or insufficient. Resolve stock records before retrying.';end if;
   if exists(select 1 from private.weekly_count_lines cl where cl.item_id=r.item and cl.count_id in(select(x->>'id')::uuid from jsonb_array_elements(item_counts)x) and cl.book+coalesce((select sum(book_delta) from private.sales_count_reconciliations z where z.count_id=cl.count_id and z.item_id=cl.item_id),0)-r.amount<0) then raise exception 'Late sales would make a saved count book balance negative. Reconcile dated receipts and count evidence first.';end if;
  end loop;
  lines:=new_lines;needs:=jsonb_array_length(counts)>0;
 exception when others then errors:=jsonb_build_array(sqlerrm);end;
 result:=jsonb_build_object('job_id',j.id,'state',j.state,'sale_date',h.sale_date,'outlet_id',h.location_id,'menu_id',l.menu_item_id,'menu',(select name from public.menu_items where id=l.menu_item_id),'sold_quantity',l.quantity::text,'site_id',m.site_id,'centre',(select name from public.stock_locations where id=m.site_id),'mapping_id',m.id,'mode',m.mode,'lines',coalesce((select jsonb_agg(x||jsonb_build_object('name',i.name,'code',i.code,'unit',u.code,'on_hand',private.pp_stock_balance(org,m.site_id,i.id)::text)) from jsonb_array_elements(coalesce(lines,'[]'))x join public.items i on i.id=(x->>'item_id')::uuid join public.units_of_measure u on u.id=i.base_uom_id),'[]'::jsonb),'counts',counts,'offset_count_id',offset_id,'offset_date',offset_date,'errors',errors,'needs_review',needs,'can_reconcile',needs and private.pp_count_review_role(org,m.site_id) and j.created_by<>auth.uid() and not exists(select 1 from jsonb_array_elements(counts)x where x->>'submitter'=auth.uid()::text),'watermark',(select coalesce(max(id),0) from public.stock_ledger where organisation_id=org and location_id=m.site_id));
 return result||jsonb_build_object('evidence',md5(result::text));
end $$;

create function private.pp_post_sales_stock(org uuid,job uuid,review boolean default false,note text default '') returns uuid language plpgsql security definer set search_path='' as $$declare j private.sales_stock_jobs;p jsonb;doc uuid;offset_doc uuid;offset_docs jsonb:='[]';offset_index integer:=0;r jsonb;c jsonb;begin
 perform 1 from public.organisations where id=org for update;select * into j from private.sales_stock_jobs where organisation_id=org and id=job;
 if j.state in('POSTED','RECONCILED','EXCLUDED') then return j.document_id;end if;
 p:=private.pp_sales_stock_plan(org,job);
 if jsonb_array_length(p->'errors')>0 or((p->>'needs_review')::boolean and not review) then update private.sales_stock_jobs set site_id=nullif(p->>'site_id','')::uuid,mapping_id=nullif(p->>'mapping_id','')::uuid,plan=p,reason=case when jsonb_array_length(p->'errors')>0 then p->'errors'->>0 else 'Late sales overlap a completed count. Independent reconciliation required.' end where id=job;return null;end if;
 if review and(not(p->>'can_reconcile')::boolean or length(trim(note))<5) then raise exception 'An independent Owner/CEO, Finance or Operations reviewer must explain the late-sales reconciliation.' using errcode='42501';end if;
 doc:=gen_random_uuid();
 insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,document_date,note,lines,output,state,created_by,completed_by,completed_at) values(doc,org,job,md5(p::text),'SALE-'||upper(substr(replace(job::text,'-',''),1,12)),'SALES',(p->>'site_id')::uuid,(p->>'sale_date')::date,'Standard recipe consumption from imported fulfilled POS sales',p->'lines',jsonb_build_object('sale_line_id',j.sale_line_id,'mapping',p->'mapping_id','basis','SALES_DATE_STANDARD_RECIPE'),'POSTED',j.created_by,auth.uid(),clock_timestamp());
 for r in select value from jsonb_array_elements(p->'lines') loop insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values(org,doc,(p->>'site_id')::uuid,(r->>'item_id')::uuid,-(r->>'quantity')::numeric,(p->>'sale_date')::date);end loop;
 for r in select value from jsonb_array_elements(p->'lines') loop
 if r->>'offset_count_id' is not null then
  offset_index:=offset_index+1;offset_doc:=gen_random_uuid();offset_docs:=offset_docs||jsonb_build_array(offset_doc);
  insert into public.stock_documents(id,organisation_id,request_id,input_hash,reference,kind,source_id,document_date,note,lines,output,state,created_by,approved_by,completed_by,completed_at) values(offset_doc,org,offset_doc,md5(p::text),'SRC-'||upper(substr(replace(job::text,'-',''),1,12))||'-'||offset_index,'SALES_RECONCILIATION',(p->>'site_id')::uuid,(r->>'offset_date')::date,note,jsonb_build_array(r),jsonb_build_object('sale_document',doc,'job_id',job,'count_id',r->>'offset_count_id','basis','Reclassify consumption already reflected in approved physical stock'),'POSTED',j.created_by,auth.uid(),auth.uid(),clock_timestamp());
  insert into public.stock_ledger(organisation_id,document_id,location_id,item_id,quantity,occurred_on) values(org,offset_doc,(p->>'site_id')::uuid,(r->>'item_id')::uuid,(r->>'quantity')::numeric,(r->>'offset_date')::date);
 end if;end loop;
 if review then for c in select value from jsonb_array_elements(p->'counts') loop for r in select value from jsonb_array_elements(p->'lines') loop insert into private.sales_count_reconciliations select org,(c->>'id')::uuid,job,(r->>'item_id')::uuid,-(r->>'quantity')::numeric,auth.uid(),clock_timestamp() where c->>'item_id'=r->>'item_id';end loop;end loop;end if;
 update private.sales_stock_jobs set state=case when review then 'RECONCILED' else 'POSTED' end,site_id=(p->>'site_id')::uuid,mapping_id=(p->>'mapping_id')::uuid,document_id=doc,offset_document_id=offset_doc,offset_documents=offset_docs,plan=p,reason='',reviewed_by=case when review then auth.uid() end,review_note=note,completed_at=clock_timestamp() where id=job;
 insert into public.audit_events(organisation_id,event_type,actor_id,entity_id,details) values(org,case when review then 'SALES_STOCK_RECONCILED' else 'SALES_STOCK_POSTED' end,auth.uid(),job,jsonb_build_object('sale_line',j.sale_line_id,'stock_document',doc,'count_offset',offset_doc,'sales_date',p->>'sale_date','reason',note));return doc;
end $$;
create function private.pp_queue_sale_stock() returns trigger language plpgsql security definer set search_path='' as $$begin insert into private.sales_stock_jobs(organisation_id,sale_line_id,created_by) values(new.organisation_id,new.id,new.created_by) on conflict do nothing;return new;end $$;
create trigger queue_sale_stock after insert on public.sales_lines for each row execute function private.pp_queue_sale_stock();
create function private.pp_finish_sale_stock() returns trigger language plpgsql security definer set search_path='' as $$declare j record;begin
 if new.state='POSTED' and old.state<>'POSTED' then for j in select q.id from private.sales_stock_jobs q join public.sales_lines l on l.id=q.sale_line_id join public.sales_headers h on h.id=l.sale_id where q.organisation_id=new.organisation_id and l.import_batch_id=new.id and q.state='PENDING' order by h.sale_date,l.id loop
  begin perform private.pp_post_sales_stock(new.organisation_id,j.id);exception when others then update private.sales_stock_jobs set reason='Stock posting needs review. Sales remain recorded.' where id=j.id;end;
 end loop;end if;return new;
end $$;
create trigger finish_sale_stock after update of state on public.sales_import_batches for each row execute function private.pp_finish_sale_stock();

create function public.sales_stock_review(p_organisation_id uuid,p_job_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare j private.sales_stock_jobs;begin
 if not private.pp_sales_job_read(p_organisation_id,p_job_id) then raise exception 'Consumption access denied.' using errcode='42501';end if;
 select * into j from private.sales_stock_jobs where organisation_id=p_organisation_id and id=p_job_id;
 if j.state<>'PENDING' then return jsonb_build_object('lines','[]'::jsonb,'counts','[]'::jsonb)||coalesce(j.plan,'{}'::jsonb)||jsonb_build_object('state',j.state,'errors','[]'::jsonb,'needs_review',false,'can_reconcile',false);end if;
 return private.pp_sales_stock_plan(p_organisation_id,p_job_id);
end $$;
create function public.resolve_sales_stock(p_organisation_id uuid,p_job_id uuid,p_evidence text,p_reconcile boolean default false,p_note text default '') returns uuid language plpgsql security definer set search_path='' as $$declare p jsonb;j private.sales_stock_jobs;begin
 perform 1 from public.organisations where id=p_organisation_id for update;
 if not private.pp_sales_job_read(p_organisation_id,p_job_id) then raise exception 'Consumption access denied.' using errcode='42501';end if;
 select * into j from private.sales_stock_jobs where organisation_id=p_organisation_id and id=p_job_id;if j.state<>'PENDING' then return j.document_id;end if;
 p:=private.pp_sales_stock_plan(p_organisation_id,p_job_id);
 if p->>'evidence' is distinct from p_evidence or jsonb_array_length(p->'errors')>0 then raise exception 'Stock, mappings or count evidence changed. Review again.' using errcode='22023';end if;
 if not(private.pp_menu_write(p_organisation_id) or private.pp_count_review_role(p_organisation_id,(p->>'site_id')::uuid) or private.pp_stock_site(p_organisation_id,(p->>'site_id')::uuid,'request')) then raise exception 'Consumption posting access required.' using errcode='42501';end if;
 return private.pp_post_sales_stock(p_organisation_id,p_job_id,p_reconcile,p_note);
end $$;
create function public.sales_stock_queue(p_organisation_id uuid,p_site_id uuid default null,p_from date default null,p_to date default null,p_page integer default 1,p_state text default 'PENDING') returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 if not private.pp_stock_read(p_organisation_id) and not private.pp_sales_read(p_organisation_id) then raise exception 'Consumption report access denied.' using errcode='42501';end if;
 if p_page is null or p_page not between 1 and 100000 or p_state not in('ALL','PENDING','POSTED','RECONCILED','EXCLUDED') or(p_from is not null and p_to is not null and(p_from>p_to or p_to-p_from>366)) then raise exception 'Choose a valid consumption period and status.' using errcode='22023';end if;
 with jobs as materialized(select j.*,h.sale_date,h.transaction_ref,l.quantity,m.name menu,s.name centre from private.sales_stock_jobs j join public.sales_lines l on l.id=j.sale_line_id join public.sales_headers h on h.id=l.sale_id join public.menu_items m on m.id=l.menu_item_id left join public.stock_locations s on s.id=j.site_id where j.organisation_id=p_organisation_id and private.pp_sales_job_read(p_organisation_id,j.id) and(p_site_id is null or j.site_id=p_site_id) and(p_from is null or h.sale_date>=p_from) and(p_to is null or h.sale_date<=p_to)),paged as(select * from jobs where p_state='ALL' or state=p_state order by sale_date,id limit 25 offset(p_page-1)*25)
 select jsonb_build_object('pending',(select count(*) from jobs where state='PENDING'),'posted',(select count(*) from jobs where state in('POSTED','RECONCILED')),'total',(select count(*) from jobs where p_state='ALL' or state=p_state),'rows',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]'::jsonb)) into result;return result;
end $$;
-- Historical imports are opt-in: preparing a backlog never silently changes existing stock.
create function public.prepare_historical_sales_stock(p_organisation_id uuid,p_from date,p_to date) returns integer language plpgsql security definer set search_path='' as $$declare n integer;begin
 if not private.pp_menu_write(p_organisation_id) then raise exception 'Sales import editing access required.' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>92 then raise exception 'Choose at most 93 days.' using errcode='22023';end if;
 perform 1 from public.organisations where id=p_organisation_id for update;
 if(select count(*) from public.sales_lines l join public.sales_headers h on h.id=l.sale_id where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to)>1000 then raise exception 'Narrow the backlog to at most 1,000 sales lines.' using errcode='22023';end if;
 insert into private.sales_stock_jobs(organisation_id,sale_line_id,created_by) select l.organisation_id,l.id,l.created_by from public.sales_lines l join public.sales_headers h on h.id=l.sale_id where l.organisation_id=p_organisation_id and h.sale_date between p_from and p_to on conflict do nothing;get diagnostics n=row_count;return n;
end $$;

do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in('pp_count_review_role','pp_sale_recipe_inputs','pp_sales_job_read','pp_sales_stock_plan','pp_post_sales_stock','pp_queue_sale_stock','pp_finish_sale_stock') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('menu_stock_directory','save_menu_stock_mapping','save_menu_entry','sales_stock_review','resolve_sales_stock','sales_stock_queue','prepare_historical_sales_stock') loop execute 'revoke all on function '||f.signature||' from public,anon';execute 'grant execute on function '||f.signature||' to authenticated';end loop;
end $$;
create or replace function private.pp_menu_import_plan(org uuid,site uuid,rows jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;v jsonb;outlet public.locations;m public.menu_items;rv uuid;n integer:=0;result jsonb:='[]';problem text;unchanged boolean;state jsonb;stock_site uuid;
begin
 if not private.pp_menu_write(org) then raise exception 'Menu editing access denied.' using errcode='42501';end if;
 select * into outlet from public.locations where organisation_id=org and id=site and is_active;
 if not found then raise exception 'Choose an active outlet.' using errcode='22023';end if;
 if rows is null or jsonb_typeof(rows)<>'array' or jsonb_array_length(rows) not between 1 and 100 or octet_length(rows::text)>262144 then raise exception 'Import 1 to 100 menu rows at a time.' using errcode='22023';end if;
 for r in select value from jsonb_array_elements(rows) loop
  n:=n+1;problem:=null;v:=null;state:=null;unchanged:=false;rv:=null;m:=null;stock_site:=null;
  begin
   if exists(select 1 from jsonb_each(r) where jsonb_typeof(value)<>'string') then raise exception 'All CSV fields must be text.';end if;
   if coalesce(r->>'action','') not in('CREATE','UPDATE') then raise exception 'Action must be CREATE or UPDATE.';end if;
   if coalesce(r->>'menu_code','')!~'^[A-Z0-9][A-Z0-9_-]{0,39}$' or length(trim(coalesce(r->>'menu_name',''))) not between 1 and 120 then raise exception 'Enter a menu code and name.';end if;
   if (select count(*) from jsonb_array_elements(rows) a where a->>'menu_code'=r->>'menu_code')>1 then raise exception 'Menu code occurs more than once in this file.';end if;
   select * into m from public.menu_items where organisation_id=org and code=r->>'menu_code';
   if r->>'action'='CREATE' and m.id is not null then raise exception 'Code already exists. Use UPDATE deliberately or remove the duplicate.';end if;
   if r->>'action'='UPDATE' and(m.id is null or not m.is_active or m.brand_id<>outlet.brand_id or(m.location_id is not null and m.location_id<>site)) then raise exception 'Active menu code is unavailable in this outlet/brand.';end if;
   if r->>'major_category' not in('FOOD','DRINK') or not exists(select 1 from public.restaurant_menu_categories where organisation_id=org and major=r->>'major_category' and name=r->>'subcategory' and is_active) then raise exception 'Choose Food/Drink and an active matching subcategory from Menu categories.';end if;
   if coalesce(r->>'recipe_code','')<>'' then
    select v.id into rv from public.recipe_versions v join public.recipes a on a.organisation_id=v.organisation_id and a.id=v.recipe_id where a.organisation_id=org and a.code=r->>'recipe_code' and a.recipe_type='FINAL' and(a.location_id is null or a.location_id=site) and (coalesce(r->>'recipe_version','')='' or v.version::text=r->>'recipe_version') and v.effective_from<=(r->>'effective_from')::date order by v.effective_from desc,v.version desc limit 1;
    if rv is null then raise exception 'Final recipe code/version is unavailable in this outlet on the selected date.';end if;
    if coalesce(r->>'recipe_quantity','')!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'recipe_quantity')::numeric<=0 then raise exception 'Recipe quantity must be positive, up to six decimals.';end if;
   elsif coalesce(r->>'recipe_version','')<>'' or coalesce(r->>'recipe_quantity','')<>'' then raise exception 'Supply recipe code and quantity together; version is optional. Leave all blank for an incomplete item.';
   end if;
   if coalesce(r->>'effective_from','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char((r->>'effective_from')::date,'YYYY-MM-DD')<>r->>'effective_from' then raise exception 'Use a valid effective date (YYYY-MM-DD).';end if;
   if coalesce(r->>'selling_price','')<>'' then
    if r->>'selling_price'!~'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$' or(r->>'selling_price')::numeric<=0 or coalesce(r->>'tax_setting','') not in('NONE','INCLUSIVE','EXCLUSIVE') or coalesce(r->>'tax_percent','')!~'^(0|[1-9][0-9]{0,2})(\.[0-9]{1,6})?$' or(r->>'tax_percent')::numeric>100 or(r->>'tax_setting'='NONE' and(r->>'tax_percent')::numeric<>0) then raise exception 'Check the positive selling price and explicit tax treatment/rate.';end if;
   elsif coalesce(r->>'tax_setting','')<>'' or coalesce(r->>'tax_percent','')<>'' then raise exception 'Leave tax fields blank when no price is supplied.';
   end if;
   if rv is not null and exists(select 1 from public.recipe_versions where id=rv and effective_from>(r->>'effective_from')::date) then raise exception 'Menu date is earlier than its recipe version.';end if;
   if m.id is not null then
    state:=jsonb_build_object('menu',to_jsonb(m),'version',(select to_jsonb(x) from public.menu_item_versions x where organisation_id=org and menu_item_id=m.id order by version desc limit 1),'price',(select to_jsonb(x) from public.menu_price_versions x where organisation_id=org and menu_item_id=m.id and location_id=site and channel_code='STANDARD' order by effective_from desc,version desc limit 1));
    unchanged:=m.name=trim(r->>'menu_name') and m.primary_category=r->>'major_category' and m.subcategory=r->>'subcategory'
     and((rv is null and state->'version'='null'::jsonb) or(state->'version'->>'recipe_version_id'=rv::text and(state->'version'->>'recipe_quantity')::numeric=(r->>'recipe_quantity')::numeric and state->'version'->>'effective_from'=r->>'effective_from'))
     and(coalesce(r->>'selling_price','')='' or((state->'price'->>'price')::numeric=(r->>'selling_price')::numeric and state->'price'->>'tax_setting'=r->>'tax_setting' and(state->'price'->>'tax_percent')::numeric=(r->>'tax_percent')::numeric and state->'price'->>'effective_from'=r->>'effective_from' and state->'price'->>'effective_to' is null));
   end if;
   if coalesce(r->>'stock_centre_code','')<>'' then
    select id into stock_site from public.stock_locations where organisation_id=org and code=r->>'stock_centre_code' and is_active and(outlet_id is null or outlet_id=site);
    if stock_site is null or coalesce(r->>'consumption_mode','') not in('RECIPE','FINISHED') then raise exception 'Choose a compatible stock centre code and RECIPE or FINISHED consumption mode.';end if;
    state:=coalesce(state,'{}'::jsonb)||jsonb_build_object('stock_routes',(select jsonb_agg(to_jsonb(x)) from private.menu_stock_mappings x where organisation_id=org and menu_id=m.id and outlet_id=site));
    unchanged:=coalesce(unchanged,false) and exists(select 1 from private.menu_stock_mappings x where x.organisation_id=org and x.menu_id=m.id and x.outlet_id=site and x.site_id=stock_site and x.mode=r->>'consumption_mode' and x.effective_from=(r->>'effective_from')::date and x.version=(select max(z.version) from private.menu_stock_mappings z where z.organisation_id=org and z.menu_id=m.id and z.outlet_id=site));
   elsif coalesce(r->>'consumption_mode','')<>'' then raise exception 'Supply the stock centre code with the consumption mode.';end if;
   v:=jsonb_build_object('menu_id',m.id,'code',r->>'menu_code','name',trim(r->>'menu_name'),'brand_id',outlet.brand_id,'location_id',m.location_id,'primary_category',r->>'major_category','category',r->>'subcategory','recipe_version_id',rv,'recipe_quantity',r->>'recipe_quantity','effective_from',r->>'effective_from','price',r->>'selling_price','price_location_id',site,'tax_setting',r->>'tax_setting','tax_percent',r->>'tax_percent','price_date',r->>'effective_from','stock_site_id',stock_site,'stock_outlet_id',site,'consumption_mode',r->>'consumption_mode','stock_from',r->>'effective_from');
  exception when others then problem:=sqlerrm;end;
  result:=result||jsonb_build_array(jsonb_build_object('row',n,'code',r->>'menu_code','name',r->>'menu_name','major',r->>'major_category','subcategory',r->>'subcategory','price',r->>'selling_price','action',case when problem is not null then 'ERROR' when coalesce(unchanged,false) then 'UNCHANGED' else r->>'action' end,'error',problem,'warning',case when problem is null and rv is null then 'Recipe missing: saves as incomplete.' when problem is null and coalesce(r->>'selling_price','')='' then 'No new selling price supplied; existing prices are retained.' end,'value',v,'fingerprint',md5(coalesce(state::text,'NEW'))));
 end loop;
 return jsonb_build_object('rows',result,'valid',not exists(select 1 from jsonb_array_elements(result) a where a->>'error' is not null));
end $$;
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.inventory_movement_statement(uuid,uuid,date,date,uuid,integer,boolean,text)'::regprocedure);
 definition:=replace(definition,$old$kind<>'COUNT'$old$,$new$kind not in('COUNT','SALES_RECONCILIATION')$new$);
 definition:=replace(definition,$old$kind='COUNT'$old$,$new$kind in('COUNT','SALES_RECONCILIATION')$new$);
 definition:=replace(definition,$old$'consumption',$old$,$new$'sales_consumption',coalesce(-sum(quantity) filter(where occurred_on>=p_from and kind='SALES'),0)::text,'late_sales_reconciliation',coalesce(sum(quantity) filter(where occurred_on>=p_from and kind='SALES_RECONCILIATION'),0)::text,'consumption',$new$);
 execute definition;
end $$;
notify pgrst,'reload schema';commit;
