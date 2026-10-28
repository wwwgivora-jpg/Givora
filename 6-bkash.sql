-- GIVORA 6: bKash payment (TrxID) option. Supabase SQL Editor-e paste kore RUN koro
alter table orders add column if not exists pay text default 'cod', add column if not exists trx text;

drop function if exists public.place_order(text,text,text,text,jsonb);
create or replace function public.place_order(p_name text, p_phone text, p_address text, p_area text, p_items jsonb, p_pay text default 'cod', p_trx text default '')
returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; pr products%rowtype; q int; sub int := 0; dl int; lst jsonb := '[]'::jsonb;
begin
  if coalesce(trim(p_name),'') = '' or p_phone !~ '^01\d{9}$' or coalesce(trim(p_address),'') = '' then raise exception 'invalid details'; end if;
  if p_pay not in ('cod','bkash') then raise exception 'bad payment'; end if;
  if p_pay = 'bkash' and length(trim(coalesce(p_trx,''))) < 6 then raise exception 'TrxID lagbe'; end if;
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
  insert into orders(name, phone, address, items, total, area, delivery, user_id, pay, trx)
  values (trim(p_name), p_phone, trim(p_address), lst, sub + dl, p_area, dl, auth.uid(), p_pay, upper(trim(coalesce(p_trx,''))));
end $$;
grant execute on function public.place_order(text,text,text,text,jsonb,text,text) to anon, authenticated;

-- Telegram-e payment/TrxID-o jabe (5-cart-telegram.sql age run kora thakle)
create or replace function public.notify_tg() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare tok text; chat text; msg text;
begin
  select v into tok from app_secrets where k = 'tg_token';
  select v into chat from app_secrets where k = 'tg_chat';
  if tok is null or chat is null then return new; end if;
  if tg_table_name = 'cart_events' then
    msg := '🛒 কার্টে: ' || new.product_name
      || case when coalesce(new.size,'') <> '' then ' [' || new.size || '/' || coalesce(new.color,'') || ']' else '' end
      || ' ×' || new.qty || E'\n' || coalesce(new.email, 'অতিথি');
  else
    msg := '📦 নতুন অর্ডার: ' || new.name || ' ' || new.phone || E'\n' || new.address || E'\nমোট ৳' || new.total
      || E'\n' || case when new.pay = 'bkash' then '💳 bKash TrxID: ' || coalesce(new.trx,'') else '💵 ক্যাশ অন ডেলিভারি' end;
  end if;
  perform net.http_post(url := 'https://api.telegram.org/bot' || tok || '/sendMessage',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('chat_id', chat, 'text', msg));
  return new;
exception when others then return new;
end $$;
