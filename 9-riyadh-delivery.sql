-- GIVORA 9: Riyadh delivery charge (550 / 1020). Supabase SQL Editor-e paste kore RUN koro (4,6,7,8 age run kora thaka dorkar)
-- GIVORA 8: order cancel korle stock auto ferot. Supabase SQL Editor-e paste kore RUN koro (6 ar 7 number age run kora thaka dorkar)
create or replace function public.place_order(p_name text, p_phone text, p_address text, p_area text, p_items jsonb, p_pay text default 'cod', p_trx text default '')
returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; pr products%rowtype; q int; sz text; sub int := 0; dl int; lst jsonb := '[]'::jsonb;
begin
  if coalesce(trim(p_name),'') = '' or p_phone !~ '^01\d{9}$' or coalesce(trim(p_address),'') = '' then raise exception 'invalid details'; end if;
  if p_pay not in ('cod','bkash') then raise exception 'bad payment'; end if;
  if p_pay = 'bkash' and length(trim(coalesce(p_trx,''))) < 6 then raise exception 'TrxID lagbe'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'empty cart'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    q := (it->>'qty')::int;
    sz := coalesce(it->>'size','');
    if q < 1 then raise exception 'bad quantity'; end if;
    select * into pr from products where id = (it->>'id')::uuid and active for update;
    if not found then raise exception 'product not found'; end if;
    if pr.size_stock <> '{}'::jsonb and sz <> '' then
      if coalesce((pr.size_stock->>sz)::int, 0) < q then raise exception 'Stock shesh: % (%)', pr.name_bn, sz; end if;
      update products set size_stock = jsonb_set(size_stock, array[sz], to_jsonb((size_stock->>sz)::int - q)), stock = stock - q where id = pr.id;
    else
      if pr.stock < q then raise exception 'Stock shesh: %', pr.name_bn; end if;
      update products set stock = stock - q where id = pr.id;
    end if;
    sub := sub + pr.price * q;
    lst := lst || jsonb_build_object('id', pr.id, 'name', pr.name_bn, 'icon', pr.icon, 'qty', q, 'price', pr.price,
             'size', sz, 'color', coalesce(it->>'color',''));
  end loop;
  dl := case when p_area = 'out' then 1020 else 550 end;
  insert into orders(name, phone, address, items, total, area, delivery, user_id, pay, trx)
  values (trim(p_name), p_phone, trim(p_address), lst, sub + dl, p_area, dl, auth.uid(), p_pay, upper(trim(coalesce(p_trx,''))));
end $$;
grant execute on function public.place_order(text,text,text,text,jsonb,text,text) to anon, authenticated;

create or replace function public.restock_on_cancel() returns trigger
language plpgsql security definer set search_path = public as $$
declare it jsonb; pid uuid; q int; sz text; sgn int;
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then sgn := 1;
  elsif old.status = 'cancelled' and new.status is distinct from 'cancelled' then sgn := -1;
  else return new; end if;
  for it in select * from jsonb_array_elements(coalesce(new.items, '[]'::jsonb)) loop
    q := coalesce((it->>'qty')::int, 0) * sgn;
    sz := coalesce(it->>'size', '');
    pid := null;
    if it->>'id' is not null then pid := (it->>'id')::uuid;
    else select id into pid from products where name_bn = it->>'name' limit 1; end if;
    continue when pid is null;
    if sz <> '' and exists (select 1 from products where id = pid and size_stock->>sz is not null) then
      update products set
        size_stock = jsonb_set(size_stock, array[sz], to_jsonb(greatest(coalesce((size_stock->>sz)::int, 0) + q, 0))),
        stock = greatest(stock + q, 0)
      where id = pid;
    else
      update products set stock = greatest(stock + q, 0) where id = pid;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists orders_restock on orders;
create trigger orders_restock after update of status on orders
for each row execute function public.restock_on_cancel();
