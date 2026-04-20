-- ============================================================
-- SUSHI HOUSE — Supabase Schema v2 (corregido)
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ============================================================

-- Extensiones
create extension if not exists "uuid-ossp";

-- ============================================================
-- ENUM TYPES
-- ============================================================
do $$ begin
  create type order_status as enum (
    'pending','confirmed','preparing','ready','delivering','delivered','cancelled'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type delivery_type as enum ('asap','scheduled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_method as enum ('cash','transfer','mercadopago');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_status as enum ('pending','paid','failed','refunded');
exception when duplicate_object then null; end $$;

-- ============================================================
-- SECUENCIA para números de pedido
-- ============================================================
create sequence if not exists order_number_seq start 1;

-- ============================================================
-- TABLAS
-- ============================================================

create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null,
  phone text,
  email text,
  address_line text,
  address_colonia text,
  address_city text default 'Zapopan',
  address_references text,
  orders_count integer default 0,
  discount_active boolean default false,
  discount_percent integer default 10,
  loyalty_threshold integer default 10,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  description text,
  emoji text,
  sort_order integer default 0,
  active boolean default true,
  created_at timestamptz default now()
);

create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(),
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text,
  price numeric(10,2) not null,
  image_url text,
  available boolean default true,
  featured boolean default false,
  prep_time_min integer default 15,
  sort_order integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.settings (
  id integer primary key default 1 check (id = 1),
  business_name text default 'Sushi House',
  business_phone text,
  whatsapp_number text,
  open_time time default '13:00',
  close_time time default '22:00',
  max_concurrent_orders integer default 8,
  delivery_base_minutes integer default 25,
  delivery_per_zone_minutes integer default 10,
  loyalty_threshold integer default 10,
  discount_percent integer default 10,
  mercadopago_enabled boolean default false,
  mercadopago_public_key text,
  transfer_enabled boolean default true,
  transfer_clabe text,
  transfer_bank text,
  transfer_account_name text,
  cash_enabled boolean default true,
  is_open boolean default true,
  pause_orders boolean default false,
  updated_at timestamptz default now()
);

-- Fila única de configuración
insert into public.settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.orders (
  id uuid primary key default uuid_generate_v4(),
  order_number text unique not null default ('SUH-' || lpad(nextval('order_number_seq')::text, 4, '0')),
  user_id uuid references public.profiles(id) on delete set null,
  guest_name text,
  guest_phone text,
  status order_status default 'pending',
  delivery_type delivery_type default 'asap',
  scheduled_at timestamptz,
  address_line text not null,
  address_colonia text,
  address_references text,
  subtotal numeric(10,2) not null,
  discount_amount numeric(10,2) default 0,
  total numeric(10,2) not null,
  payment_method payment_method default 'cash',
  payment_status payment_status default 'pending',
  mercadopago_preference_id text,
  estimated_minutes integer,
  notes text,
  priority_score integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  product_price numeric(10,2) not null,
  quantity integer not null,
  notes text,
  subtotal numeric(10,2) not null
);

create table if not exists public.notifications (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id) on delete cascade,
  type text not null,
  message text,
  read boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- FUNCIONES (después de las tablas)
-- ============================================================

create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function increment_user_orders()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'delivered' and old.status <> 'delivered' and new.user_id is not null then
    update public.profiles p
    set
      orders_count = p.orders_count + 1,
      discount_active = case
        when (p.orders_count + 1) % (select coalesce(loyalty_threshold, 10) from public.settings where id = 1) = 0
        then true
        else p.discount_active
      end
    where p.id = new.user_id;
  end if;
  return new;
end;
$$;

create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, name, email, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================

drop trigger if exists orders_updated_at on public.orders;
create trigger orders_updated_at
  before update on public.orders
  for each row execute function update_updated_at();

drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at
  before update on public.products
  for each row execute function update_updated_at();

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function update_updated_at();

drop trigger if exists order_delivered_increment on public.orders;
create trigger order_delivered_increment
  after update on public.orders
  for each row execute function increment_user_orders();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.settings enable row level security;
alter table public.notifications enable row level security;

-- Limpiar policies previas para evitar conflictos al re-ejecutar
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- PROFILES
create policy "Users view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users update own profile"
  on public.profiles for update using (auth.uid() = id);
create policy "Admin full access profiles"
  on public.profiles for all using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- CATEGORIES
create policy "Categories public read"
  on public.categories for select using (true);
create policy "Admin manage categories"
  on public.categories for all using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- PRODUCTS
create policy "Products public read"
  on public.products for select using (true);
create policy "Admin manage products"
  on public.products for all using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- ORDERS
create policy "Users view own orders"
  on public.orders for select using (auth.uid() = user_id);
create policy "Anyone can insert orders"
  on public.orders for insert with check (true);
create policy "Admin view all orders"
  on public.orders for select using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );
create policy "Admin update orders"
  on public.orders for update using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- ORDER ITEMS
create policy "Users view own order items"
  on public.order_items for select using (
    exists (
      select 1 from public.orders
      where id = order_items.order_id and user_id = auth.uid()
    )
  );
create policy "Anyone can insert order items"
  on public.order_items for insert with check (true);
create policy "Admin view all order items"
  on public.order_items for select using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- SETTINGS
create policy "Settings public read"
  on public.settings for select using (true);
create policy "Admin update settings"
  on public.settings for update using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- NOTIFICATIONS
create policy "Admin manage notifications"
  on public.notifications for all using (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

-- ============================================================
-- DATOS DE EJEMPLO
-- ============================================================

insert into public.categories (name, description, emoji, sort_order) values
  ('Rolls Especiales', 'Nuestras creaciones exclusivas', '🌟', 1),
  ('Rolls Clásicos', 'Los favoritos de siempre', '🍣', 2),
  ('Nigiris & Sashimi', 'Pescado fresco de primera', '🐟', 3),
  ('Entradas', 'Para comenzar la experiencia', '🥢', 4),
  ('Bebidas', 'Para acompañar tu pedido', '🍵', 5)
on conflict do nothing;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Dragon Roll', 'Camarón tempura, aguacate, anguila, salsa eel', 185.00, true, 18
from public.categories where name = 'Rolls Especiales' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Rainbow Roll', 'California base con sashimi de atún, salmón y aguacate', 195.00, true, 20
from public.categories where name = 'Rolls Especiales' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Spicy Tuna Crunch', 'Atún picante, pepino, sriracha mayo, tenkasu', 175.00, false, 15
from public.categories where name = 'Rolls Especiales' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'California Roll', 'Cangrejo, aguacate, pepino, semillas de sésamo', 120.00, false, 12
from public.categories where name = 'Rolls Clásicos' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Philadelphia Roll', 'Salmón, queso crema, pepino', 130.00, true, 12
from public.categories where name = 'Rolls Clásicos' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Edamame', 'Vainas de soya al vapor con sal de mar', 65.00, false, 5
from public.categories where name = 'Entradas' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Miso Soup', 'Sopa miso tradicional con tofu y wakame', 55.00, false, 5
from public.categories where name = 'Entradas' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Matcha Latte', 'Té verde ceremonial con leche de avena', 75.00, false, 5
from public.categories where name = 'Bebidas' limit 1;

insert into public.products (category_id, name, description, price, featured, prep_time_min)
select id, 'Agua Mineral', '600ml', 25.00, false, 2
from public.categories where name = 'Bebidas' limit 1;

-- ============================================================
-- FIN DEL SCHEMA
-- ============================================================