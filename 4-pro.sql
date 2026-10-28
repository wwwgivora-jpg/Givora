-- GIVORA 4: size/color/stock, delivery, tracking. Supabase SQL Editor-e paste kore RUN koro
alter table products
  add column if not exists images text[] default '{}',
  add column if not exists sizes text[] default '{}',
  add column if not exists colors text[] default '{}',
  add column if not exists stock int not null default 50,
  add column if not exists description text;

alter table orders
  add column if not exists area text default 'in',
  add column if not exists delivery int default 0;

-- Delivery charge: Dhaka-r bhitore 60, baire 120 (poriborton korte nicher 120 / 60 bodlao)
create or replace function public.place_order(p_name text, p_phone text, p_address text, p_area text, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; pr products%rowtype; q int; sub int := 0; dl int; lst jsonb := '[]'::jsonb;
begin
  if coalesce(trim(p_name),'') = '' or p_phone !~ '^01\d{9}$' or coalesce(trim(p_address),'') = '' then
    raise exception 'invalid details';
  end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'empty cart'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    q := (it->>'qty')::int;
    if q < 1 then raise exception 'bad quantity'; end if;
    select * into pr from products where id = (it->>'id')::uuid and active for update;
    if not found then raise exception 'product not found'; end if;
    if pr.stock < q then raise exception 'Stock shesh: %', pr.name_bn; end if;
    update products set stock = stock - q where id = pr.id;
    sub := sub + pr.price * q;
    lst := lst || jsonb_build_object('name', pr.name_bn, 'icon', pr.icon, 'qty', q, 'price', pr.price,
             'size', coalesce(it->>'size',''), 'color', coalesce(it->>'color',''));
  end loop;
  dl := case when p_area = 'out' then 120 else 60 end;
  insert into orders(name, phone, address, items, total, area, delivery, user_id)
  values (trim(p_name), p_phone, trim(p_address), lst, sub + dl, p_area, dl, auth.uid());
end $$;

grant execute on function public.place_order(text,text,text,text,jsonb) to anon, authenticated;
