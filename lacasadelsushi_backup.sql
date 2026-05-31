--
-- PostgreSQL database dump
--

\restrict Nd6eozvgiq6Ne1GL3ehnFAKqjX8kt9TXTUvjANr3EOscCXRjRPDPylt5IXUrrMC

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: delivery_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.delivery_type AS ENUM (
    'asap',
    'scheduled'
);


--
-- Name: order_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.order_status AS ENUM (
    'pending',
    'confirmed',
    'preparing',
    'ready',
    'delivering',
    'delivered',
    'cancelled'
);


--
-- Name: payment_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_method AS ENUM (
    'cash',
    'transfer',
    'mercadopago'
);


--
-- Name: payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_status AS ENUM (
    'pending',
    'paid',
    'failed',
    'refunded'
);


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  BEGIN
    INSERT INTO public.profiles (id, name, email, phone)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email,'@',1)), NEW.email, NEW.raw_user_meta_data->>'phone')
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
  END; $$;


--
-- Name: increment_user_orders(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.increment_user_orders() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  BEGIN
    IF NEW.status = 'delivered' AND OLD.status <> 'delivered' AND NEW.user_id IS NOT NULL THEN
      UPDATE public.profiles p SET
        orders_count = p.orders_count + 1,
        discount_active = CASE WHEN (p.orders_count+1) % (SELECT COALESCE(loyalty_threshold,10) FROM public.settings WHERE id=1) = 0 THEN true ELSE
  p.discount_active END
      WHERE p.id = NEW.user_id;
    END IF;
    RETURN NEW;
  END; $$;


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
  BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username text NOT NULL,
    email text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    description text,
    emoji text,
    sort_order integer DEFAULT 0,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    order_id uuid,
    type text NOT NULL,
    message text,
    read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    order_id uuid,
    product_id uuid,
    product_name text NOT NULL,
    product_price numeric(10,2) NOT NULL,
    quantity integer NOT NULL,
    notes text,
    subtotal numeric(10,2) NOT NULL
);


--
-- Name: order_number_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    order_number text DEFAULT ('SUH-'::text || lpad((nextval('public.order_number_seq'::regclass))::text, 4, '0'::text)) NOT NULL,
    user_id uuid,
    guest_name text,
    guest_phone text,
    status public.order_status DEFAULT 'pending'::public.order_status,
    delivery_type public.delivery_type DEFAULT 'asap'::public.delivery_type,
    scheduled_at timestamp with time zone,
    address_line text NOT NULL,
    address_colonia text,
    address_references text,
    subtotal numeric(10,2) NOT NULL,
    discount_amount numeric(10,2) DEFAULT 0,
    total numeric(10,2) NOT NULL,
    payment_method public.payment_method DEFAULT 'cash'::public.payment_method,
    payment_status public.payment_status DEFAULT 'pending'::public.payment_status,
    mercadopago_preference_id text,
    estimated_minutes integer,
    notes text,
    priority_score integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    internal_note text,
    points_earned integer DEFAULT 0,
    points_spent integer DEFAULT 0,
    redemptions_applied jsonb DEFAULT '[]'::jsonb,
    receipt_url text
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    category_id uuid,
    name text NOT NULL,
    description text,
    price numeric(10,2) NOT NULL,
    image_url text,
    available boolean DEFAULT true,
    featured boolean DEFAULT false,
    prep_time_min integer DEFAULT 15,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    points integer DEFAULT 0,
    custom_options text[] DEFAULT '{}'::text[],
    options_max numeric,
    preview_config jsonb,
    images text[] DEFAULT '{}'::text[]
);


--
-- Name: COLUMN products.options_max; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.products.options_max IS 'Max. Options';


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    email text,
    address_line text,
    address_colonia text,
    address_city text DEFAULT 'Zapopan'::text,
    address_references text,
    orders_count integer DEFAULT 0,
    discount_active boolean DEFAULT false,
    discount_percent integer DEFAULT 10,
    loyalty_threshold integer DEFAULT 10,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    points_total integer DEFAULT 0
);


--
-- Name: redemptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.redemptions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid,
    reward_id uuid,
    order_id uuid,
    reward_name text NOT NULL,
    points_spent integer NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: rewards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rewards (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    description text,
    points_cost integer NOT NULL,
    reward_type text NOT NULL,
    discount_percent integer,
    free_product_id uuid,
    free_product_name text,
    active boolean DEFAULT true,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT rewards_reward_type_check CHECK ((reward_type = ANY (ARRAY['discount_percent'::text, 'free_product'::text])))
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id integer DEFAULT 1 NOT NULL,
    business_name text DEFAULT 'Sushi House'::text,
    business_phone text,
    whatsapp_number text,
    open_time time without time zone DEFAULT '13:00:00'::time without time zone,
    close_time time without time zone DEFAULT '22:00:00'::time without time zone,
    max_concurrent_orders integer DEFAULT 8,
    delivery_base_minutes integer DEFAULT 25,
    delivery_per_zone_minutes integer DEFAULT 10,
    loyalty_threshold integer DEFAULT 10,
    discount_percent integer DEFAULT 10,
    mercadopago_enabled boolean DEFAULT false,
    mercadopago_public_key text,
    transfer_enabled boolean DEFAULT true,
    transfer_clabe text,
    transfer_bank text,
    transfer_account_name text,
    cash_enabled boolean DEFAULT true,
    is_open boolean DEFAULT true,
    pause_orders boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now(),
    open_days integer[] DEFAULT '{1,2,3,4,5,6}'::integer[],
    CONSTRAINT settings_id_check CHECK ((id = 1))
);


--
-- Data for Name: admin_users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.admin_users (id, username, email, created_at) FROM stdin;
8142d098-b451-4884-8cf3-36a69caa4d1b	fabian	fatakerkane@gmail.com	2026-04-20 23:19:02.961848+00
deef5be6-db33-41de-a9a3-553b6915aa4d	leo	leo@panel.admin	2026-04-21 02:42:11.817914+00
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (id, name, description, emoji, sort_order, active, created_at) FROM stdin;
7dd96963-cb38-4599-8498-d33323866bc3	Entradas	Entradas		1	t	2026-04-20 02:48:02.824933+00
1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollos de Sushi Completos	Nuestras creaciones exclusivas		2	t	2026-04-20 02:48:02.824933+00
9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollos de Sushi Combinados	Para los indecisos.		3	t	2026-04-20 02:48:02.824933+00
0457c7ac-268e-4189-8a3d-402bfb3f8b37	Especialidades	La especialidad de la casa		4	t	2026-04-20 02:48:02.824933+00
c0db0005-3270-4539-b296-11e5217778bd	Platillo Especial 	Para acompañar tu pedido		5	t	2026-04-20 02:48:02.824933+00
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, order_id, type, message, read, created_at) FROM stdin;
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_items (id, order_id, product_id, product_name, product_price, quantity, notes, subtotal) FROM stdin;
abd823dc-44db-403e-b0df-ec1c5f358bdd	7f62f815-606a-448f-997a-a5a9fb8aafed	85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	Rollo de Frutas - 12 Pzas.	140.00	1	Sabor: Mango + Plátano macho	140.00
feb135d4-1818-4dfa-ad1e-293927268bde	7f62f815-606a-448f-997a-a5a9fb8aafed	0ccbb292-9f3b-41f6-b01a-618b9813ea15	Rollo de Camarón - 12 Pzas.	180.00	1	\N	180.00
b62a5072-70b0-4cf3-86d8-d55a0539ac54	7b534dfe-4bf9-4e0b-87ce-fe3a13b827b2	0ccbb292-9f3b-41f6-b01a-618b9813ea15	Rollo de Camarón - 12 Pzas.	180.00	1	\N	180.00
b7b45f11-6da9-4b7a-b240-1b9a1e205fe2	d1becb90-503f-48ae-9a59-346e3a782f61	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
86853913-5fac-41bf-9c2e-37c58604de06	6392e099-f569-40dc-82d4-5aefab946031	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
e7700435-4414-473b-8c0c-3f86598a2c10	f57fd455-aee1-434e-a237-f9926d6de5dc	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
6f2c1636-95e8-4d60-9a7f-bdb5e7a245cf	8700ee45-bd29-474a-b72f-3c5026fce26b	06aca312-7237-4be9-ace1-7ed5eb2bc7bd	Rollo Empanizado / Philadelphia - 12 Pzas.	130.00	1	\N	130.00
9d03abee-1e9d-4e69-b5a5-cf7d8c42d910	dbaca91c-f864-4bc1-81b4-76ec0038675f	0c3b63e0-8191-422f-8d1a-d6b0141aa23a	Rollo California - 12 Pzas.	110.00	1	\N	110.00
ef044ebf-d52a-4827-b8bc-5b0008500b8b	b12e2b73-79f1-4bb6-ae04-ce57292d7702	0c3b63e0-8191-422f-8d1a-d6b0141aa23a	Rollo California - 12 Pzas.	110.00	2	\N	220.00
3abeb70e-f3de-4794-b0dc-eaa9f5a7b3f3	b12e2b73-79f1-4bb6-ae04-ce57292d7702	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	2	\N	240.00
94fc6bb7-22dd-4236-b8d7-99ee227c62b3	b12e2b73-79f1-4bb6-ae04-ce57292d7702	4ddc2ae9-4a67-466e-8711-3dfa4f480869	Rollo California / Empanizado - 12 Pzas.	120.00	1	\N	120.00
5ee79ffb-0a21-4094-81e5-3f32f92cf18e	661e6a1f-39e6-4d7f-9866-a4426d84690e	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	1	\N	35.00
418740c8-9027-4be5-9d97-7ee8f96fd77e	661e6a1f-39e6-4d7f-9866-a4426d84690e	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
fea28a7b-c56e-46b0-9f61-2c896e743327	54dad337-8898-4f76-abcf-d15004980afb	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	2	\N	240.00
c366de84-54a4-424b-9eb3-085c1e0c563f	54dad337-8898-4f76-abcf-d15004980afb	06aca312-7237-4be9-ace1-7ed5eb2bc7bd	Rollo Empanizado / Philadelphia - 12 Pzas.	130.00	1	\N	130.00
fb7e30d2-1b4b-4a3e-977e-c44ca3a3091a	4d422ac0-835f-4ab2-9e1e-4a604ed75fb7	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
06bd5e0e-7eab-4a80-a682-6d0b8fa2f202	4d422ac0-835f-4ab2-9e1e-4a604ed75fb7	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	1	\N	50.00
bc9518e8-7caa-468d-b504-8769d7512413	27f7f07a-e4b7-4cc7-94c1-5ec261e780d9	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
54324b51-d7fe-4ff9-8d9b-7209c20979e5	2522c3d9-7d81-4c92-8100-ac23238deb39	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
ead0510e-047a-4aed-adbd-1c9a836543a4	2522c3d9-7d81-4c92-8100-ac23238deb39	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
c0dfc800-e036-4fa0-a551-67d40387842f	91fa8d8c-beaa-439d-853a-35224d87623e	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
1520ea44-cd9d-431e-90a9-467e6644998f	fafd1f2b-b7ae-40b8-b2f6-83bb46085e09	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	sin camarón y sin alga :33	120.00
558a3890-cfa5-44f1-a8fd-e43b28a934fa	54dad337-8898-4f76-abcf-d15004980afb	fc3da0a6-91cb-49d3-aee9-b940b1a4dee6	Charola Surtida - 48 Pzas.	490.00	1	\N	490.00
de8371d6-5f60-4c6e-b450-cda2d2905725	54dad337-8898-4f76-abcf-d15004980afb	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	1	\N	95.00
f432f0b8-9093-48dd-9c9e-b7e14048c5c3	086b70b6-492a-448a-95b2-0b7c51fb04de	85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	Rollo de Frutas - 12 Pzas.	140.00	1	\N	140.00
79dba0b3-b56a-4160-80e2-98f34956c68d	086b70b6-492a-448a-95b2-0b7c51fb04de	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
cbcc6c14-f0c0-4eb1-a778-d6178b852d3b	086b70b6-492a-448a-95b2-0b7c51fb04de	cb538273-33a6-4230-8a1c-2b0afeacd63a	Rollo de Aguacate - 12 Pzas.	140.00	1	\N	140.00
2b240729-b5f0-40c9-8ecb-f5fa6e8f1c58	086b70b6-492a-448a-95b2-0b7c51fb04de	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	1	\N	35.00
345eb498-dde1-4275-a3a4-37a87405a2e0	81375427-d252-48a6-804c-814a411b880d	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	4	\N	480.00
ed0efabc-8158-47da-98dc-fa073d827f27	732658a2-07c2-4a84-88e9-758cf97f6406	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	3	\N	150.00
c0e8315b-d94a-4d32-817c-3c2c2008ae8b	5a2c5091-405c-4afa-b6fe-940fc0307a2c	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	1	\N	50.00
13c98cd4-9452-4852-af23-4c01a86e87f1	5a2c5091-405c-4afa-b6fe-940fc0307a2c	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	1	\N	95.00
792eb55c-7298-4b8f-8363-1485e2514fb2	81375427-d252-48a6-804c-814a411b880d	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	1	\N	95.00
a80aec32-2564-4d32-92ae-5606b7d25e5b	dea4014b-7f71-4f5f-a7b4-3bb6261b326f	9b126e78-7819-4096-8133-8e5ebacdfbc4	Rollo California / Philadelphia - 12 Pzas.	125.00	1	\N	125.00
250bdc0d-8d1c-43de-81b3-dd2ca26a6033	e1563196-8ee2-4c33-b76a-816be87faf34	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
f3829096-32ee-41dd-a066-fb397df41e0c	e1563196-8ee2-4c33-b76a-816be87faf34	85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	Rollo de Frutas - 12 Pzas.	140.00	1	\N	140.00
781fd155-d932-48ed-abe4-25986e041e73	412f95b9-3514-49c8-b0de-e032184326a4	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	1	\N	95.00
9d479cae-c606-437a-8d2b-f245df023852	098b3a58-775c-41d1-98b3-b01b47c787ce	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas. (gratis)	0.00	1	Canje de puntos	0.00
f44cd9aa-268b-4b01-adae-2a1f0213b22d	098b3a58-775c-41d1-98b3-b01b47c787ce	0c3b63e0-8191-422f-8d1a-d6b0141aa23a	Rollo California - 12 Pzas.	110.00	1	\N	110.00
6af99fb0-5c0a-4d8f-8650-fa299b025f0a	098b3a58-775c-41d1-98b3-b01b47c787ce	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
b950cf3a-2e7b-4cdb-92ed-b173bcd445dd	3e418a25-35c1-4b85-a613-eeb6fbd73af4	fc3da0a6-91cb-49d3-aee9-b940b1a4dee6	Charola Surtida - 48 Pzas.	490.00	1	\N	490.00
b4753700-b397-4906-b438-685a1a32d344	3e418a25-35c1-4b85-a613-eeb6fbd73af4	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
a932e986-3652-4d25-99fc-72f1d11cc139	3e418a25-35c1-4b85-a613-eeb6fbd73af4	9d653814-801f-486f-bd46-1a753371de79	Rollo California / Frutas o Aguacat- 12 Pzas.	130.00	1	\N	130.00
aebd4da1-bc2d-4420-aed1-a07ae5d03713	7452600e-8d92-48ef-b585-b21b842f9c51	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	3	\N	150.00
dff5e127-956b-4ffc-81cb-6c26b4da7d1e	7452600e-8d92-48ef-b585-b21b842f9c51	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
27fa12b3-4817-4399-9e3a-00957d484409	7452600e-8d92-48ef-b585-b21b842f9c51	ec2bafa8-1a05-46bf-a975-e2f1f831a576	Rollo Philadelphia / Frutas o Aguacate - 12 Pzas.	140.00	1	\N	140.00
0842b2c4-3454-489d-8279-e57d59149cf5	98523aa3-a079-47fb-a2de-583c91f96612	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
b42889cc-1061-4ad8-a992-16ac1f5f4b52	98523aa3-a079-47fb-a2de-583c91f96612	85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	Rollo de Frutas - 12 Pzas.	140.00	1	\N	140.00
576d107f-ea6e-4846-8650-5ddbe2800b6a	98523aa3-a079-47fb-a2de-583c91f96612	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	6	\N	300.00
c08babb3-beb7-4d61-9d24-51c21a11bf52	653108fa-ec18-4f14-a0a8-fcdbb5fabc79	06aca312-7237-4be9-ace1-7ed5eb2bc7bd	Rollo Empanizado / Philadelphia - 12 Pzas.	130.00	1	\N	130.00
0227519c-660e-44ec-8c22-759189a79775	653108fa-ec18-4f14-a0a8-fcdbb5fabc79	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	1	\N	35.00
995a5c3c-707d-41b1-99ac-2fe0bd77be86	50a29883-15f4-4c2c-89a8-bab0ecd2ce9d	85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	Rollo de Frutas - 12 Pzas.	140.00	1	\N	140.00
4641affc-52a7-4c15-b965-60978487b0cb	bd8a26c6-8113-482f-9d52-a26f98e7aef0	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
ffb4c8f9-1d89-471b-a60e-6d948f400e25	b2c59dbb-ab57-4ae2-b996-ec3497e88530	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
75ee59c1-3228-423c-aa17-448e04093b9b	b2c59dbb-ab57-4ae2-b996-ec3497e88530	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	2	\N	70.00
ee9f8752-1ca2-407c-bfb9-5514cd68009d	9de86714-e9b4-40de-9ce6-7d33a5e81ff6	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
07c35b71-84ca-4ed6-bdd0-a05ec0f7c79e	9de86714-e9b4-40de-9ce6-7d33a5e81ff6	9d653814-801f-486f-bd46-1a753371de79	Rollo California / Frutas o Aguacat- 12 Pzas.	130.00	1	\N	130.00
4a2d0454-1eb6-4b28-9096-b30f294cf08e	30508bbd-3843-4db4-8a74-7638a669b850	fc3da0a6-91cb-49d3-aee9-b940b1a4dee6	Charola Surtida - 48 Pzas.	490.00	1	\N	490.00
de63b171-3db9-4a29-9570-c395af59a25b	10465337-89bc-4bb1-a83f-6b3ef157162e	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	4	\N	480.00
b842082a-26bf-47f8-b175-28361d24842b	10465337-89bc-4bb1-a83f-6b3ef157162e	0c3b63e0-8191-422f-8d1a-d6b0141aa23a	Rollo California - 12 Pzas.	110.00	2	\N	220.00
9e689310-7330-4bbf-9503-3c5797e9e4f7	10465337-89bc-4bb1-a83f-6b3ef157162e	ec2bafa8-1a05-46bf-a975-e2f1f831a576	Rollo Philadelphia / Frutas o Aguacate - 12 Pzas.	140.00	2	\N	280.00
25dfd7d0-aaa6-4b2f-b822-5429f4a627ee	10465337-89bc-4bb1-a83f-6b3ef157162e	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	1	\N	35.00
9b3b675e-dbbc-4123-9216-ad9f81a244e6	10465337-89bc-4bb1-a83f-6b3ef157162e	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	3	\N	150.00
dd4cace5-d25c-4154-bd1e-18d30da37e47	8ed42317-dbc3-40f8-a94b-0500f1d5ad38	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
030bb156-5c07-4a1d-9ef1-cce3154b1933	8ed42317-dbc3-40f8-a94b-0500f1d5ad38	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
80f34e33-ba3a-4aa7-93fd-2d1bb9d084c3	84bc4585-e4ef-40ef-b152-7de7a5340259	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	2	\N	100.00
53293d8a-1028-4ce5-940d-72f309632c10	ea2089e9-8e69-44a6-9fe3-de9e3f5d050e	06aca312-7237-4be9-ace1-7ed5eb2bc7bd	Rollo Empanizado / Philadelphia - 12 Pzas.	130.00	2	\N	260.00
1cf9e01f-7d02-47b4-a691-c29706809b7e	ea2089e9-8e69-44a6-9fe3-de9e3f5d050e	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	1	\N	35.00
10204b32-cf53-4af8-b42b-0e3cc2ce9c76	5de0367b-b3fb-4ca5-b872-da4b97b42577	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	2	\N	240.00
1088e146-eb7f-4597-944e-797c700168b3	5de0367b-b3fb-4ca5-b872-da4b97b42577	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
42f7ff89-563f-422a-b5f0-bd898dd2d2c2	5de0367b-b3fb-4ca5-b872-da4b97b42577	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	1	\N	50.00
52ed97a4-ebfc-4cef-b247-4927ddb29433	7c6638e1-994e-4795-b8b5-e7727b377719	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
982342d4-8ac3-4e14-a4c1-b723bff37fbb	57d2b25a-8b09-4997-91ab-a8c0440aa983	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
12bf36f9-b496-4ae1-8bb6-4e9584af296c	1cf5373e-93fd-4a05-9d39-8fcd7edc3d62	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
18f0fc67-7297-4c04-ba20-1c98faa0cdbc	38d5d7a4-1d35-41e9-b341-b68b3e620686	fc3da0a6-91cb-49d3-aee9-b940b1a4dee6	Charola Surtida - 48 Pzas.	490.00	1	\N	490.00
de6dd9c1-2bba-4a5e-a73f-5087d13b3af6	5a88e038-3460-4371-85c5-8e200176fc42	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
be34a654-c368-4fc4-be12-f026e8041e22	5a88e038-3460-4371-85c5-8e200176fc42	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
b9538134-c9ee-49d1-8888-f1a9e70bb647	5a88e038-3460-4371-85c5-8e200176fc42	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	3	\N	150.00
0eab95d6-f7b0-4599-ab06-2963ce84c46f	7a8a6a23-b6ff-4173-9aa9-a6f74cb3af32	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
c5e6e60f-e456-49d8-a602-7380119e858f	6c2d25ee-1bcb-4661-81e3-cf55fe84a31b	4ddc2ae9-4a67-466e-8711-3dfa4f480869	Rollo California / Empanizado - 12 Pzas.	120.00	2	\N	240.00
18c4b79c-5678-44ea-ad51-f67f517af776	6c2d25ee-1bcb-4661-81e3-cf55fe84a31b	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	1	\N	50.00
fa453b41-c0e8-4291-a470-f9eecdc90036	98eac886-d70c-4c11-90bc-6aaa21b5c6e8	cb538273-33a6-4230-8a1c-2b0afeacd63a	Rollo de Aguacate - 12 Pzas.	140.00	1	\N	140.00
8093473e-3152-4010-ae01-1662566c4946	98eac886-d70c-4c11-90bc-6aaa21b5c6e8	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	2	\N	240.00
9f58593e-25dc-4743-81bc-57d061e74ffd	98eac886-d70c-4c11-90bc-6aaa21b5c6e8	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	1	\N	95.00
0a51794c-8bf7-4715-93a3-a9d8b6a2c48b	57d2b25a-8b09-4997-91ab-a8c0440aa983	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	1	\N	120.00
f31d5a9f-11cf-4e8c-acb2-e9cd1b635b78	57d2b25a-8b09-4997-91ab-a8c0440aa983	633f2fd4-972e-46ce-8304-3cd05031344c	Rollo Philadelphia - 12 Pzas.	130.00	1	\N	130.00
e09845e0-cf73-4d20-8962-082d721d726d	39b83321-1c29-4cb4-b636-b5a002c55bc3	b9b8e783-4574-4d42-8afd-0378f7d394e3	Rollo Empanizado - 12 Pzas.	120.00	4	\N	480.00
e96416c0-45ca-4a06-9b24-03f22939ee0c	39b83321-1c29-4cb4-b636-b5a002c55bc3	69ef84d2-e015-48d5-be14-11378284fde8	Rollo Primavera Especial - 2 Pzas.	50.00	3	\N	150.00
2a1c16c8-6752-4751-a7c5-0087e3a7b9cf	39b83321-1c29-4cb4-b636-b5a002c55bc3	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	35.00	2	\N	70.00
96d88c7a-325d-4642-bc2c-df2083feefd7	39b83321-1c29-4cb4-b636-b5a002c55bc3	621676a8-f9b5-484a-a5f2-e02d7ca585cc	Yakimeshi	95.00	2	\N	190.00
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orders (id, order_number, user_id, guest_name, guest_phone, status, delivery_type, scheduled_at, address_line, address_colonia, address_references, subtotal, discount_amount, total, payment_method, payment_status, mercadopago_preference_id, estimated_minutes, notes, priority_score, created_at, updated_at, internal_note, points_earned, points_spent, redemptions_applied, receipt_url) FROM stdin;
2522c3d9-7d81-4c92-8100-ac23238deb39	SUH-0042	\N	Dentista Ale	\N	delivered	asap	\N	-	\N	\N	250.00	0.00	250.00	cash	pending	\N	40	\N	90	2026-04-25 18:31:15.450782+00	2026-05-16 19:08:48.751759+00	\N	0	0	[]	\N
dea4014b-7f71-4f5f-a7b4-3bb6261b326f	SUH-0049	\N	-	-	delivered	asap	\N	Sta rosa 834	\N	\N	125.00	0.00	125.00	cash	pending	\N	40	\N	90	2026-04-25 21:47:02.885487+00	2026-05-16 19:08:53.899745+00	\N	0	0	[]	\N
e1563196-8ee2-4c33-b76a-816be87faf34	SUH-0050	\N	Cosmeticos	-	delivered	asap	\N	-	\N	\N	260.00	0.00	260.00	cash	pending	\N	40	\N	90	2026-04-25 21:47:29.674317+00	2026-05-16 19:08:56.157968+00	\N	0	0	[]	\N
661e6a1f-39e6-4d7f-9866-a4426d84690e	SUH-0035	87098d86-d293-491d-8295-bc9c3115174a	Diana	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas\r\n		155.00	0.00	155.00	cash	pending	\N	60		40	2026-04-24 05:14:51.862354+00	2026-04-25 18:27:11.634121+00	\N	12	\N	\N	\N
732658a2-07c2-4a84-88e9-758cf97f6406	SUH-0047	\N	-	-	delivered	asap	\N	Cántaros 4494	\N	\N	150.00	0.00	150.00	cash	pending	\N	50	\N	90	2026-04-25 19:51:14.637964+00	2026-04-25 21:46:28.995119+00	\N	0	0	[]	\N
b12e2b73-79f1-4bb6-ae04-ce57292d7702	SUH-0033	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Beto Compras	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		580.00	0.00	580.00	cash	pending	\N	70	Charola (2 Californias y 2 Empanizados) y el combinado es individual.	40	2026-04-24 03:23:08.158352+00	2026-04-25 18:27:12.56278+00	\N	43	\N	\N	\N
dbaca91c-f864-4bc1-81b4-76ec0038675f	SUH-0032	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Miriam Ventas Gob.	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		110.00	0.00	110.00	cash	pending	\N	60		40	2026-04-24 03:20:38.987217+00	2026-04-25 18:27:15.528605+00	\N	8	\N	\N	\N
91fa8d8c-beaa-439d-853a-35224d87623e	SUH-0043	\N	Jesús Carnitas	\N	delivered	asap	\N	-	\N	\N	120.00	0.00	120.00	cash	pending	\N	40	\N	90	2026-04-25 18:31:44.245132+00	2026-04-25 21:44:10.071836+00	\N	0	0	[]	\N
ea2089e9-8e69-44a6-9fe3-de9e3f5d050e	SUH-0077	\N	Circ. Artesanos 1344	-	delivered	asap	\N	-	-	\N	295.00	0.00	295.00	cash	pending	\N	80	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:05.869484+00	\N	0	0	[]	\N
27f7f07a-e4b7-4cc7-94c1-5ec261e780d9	SUH-0041	\N	-	\N	delivered	asap	\N	San Mateo 813	\N	\N	120.00	0.00	120.00	cash	pending	\N	30	Sin alga	90	2026-04-25 18:30:46.39581+00	2026-04-25 21:44:31.204085+00	\N	0	0	[]	\N
8700ee45-bd29-474a-b72f-3c5026fce26b	SUH-0029	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Jenny Compras	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		130.00	0.00	130.00	cash	pending	\N	60		40	2026-04-24 00:05:49.167372+00	2026-04-25 18:27:16.864048+00	\N	9	\N	\N	\N
fafd1f2b-b7ae-40b8-b2f6-83bb46085e09	SUH-0044	82c1676e-9fb8-43e3-ac17-a1b0a9fd4606	Danna Arias	3316322806	cancelled	scheduled	2026-04-25 16:00:00+00	en mi casa	san pedrito		120.00	0.00	120.00	cash	pending	\N	40	Por increíblemente graciosa y genial y cool y divertida	40	2026-04-25 18:40:41.492254+00	2026-04-25 21:53:03.928601+00	Por mono	0	\N	\N	\N
f57fd455-aee1-434e-a237-f9926d6de5dc	SUH-0028	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Gerardo Ventas Gob.	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		120.00	0.00	120.00	cash	pending	\N	50		40	2026-04-24 00:04:41.955211+00	2026-04-25 18:27:18.256439+00	\N	9	\N	\N	\N
7a8a6a23-b6ff-4173-9aa9-a6f74cb3af32	SUH-0074	\N	Sn Pablo 827	-	delivered	asap	\N	-	-	\N	120.00	0.00	120.00	cash	pending	\N	70	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:10.930577+00	\N	0	0	[]	\N
6392e099-f569-40dc-82d4-5aefab946031	SUH-0026	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Janeth Ventas Gob.	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		120.00	0.00	120.00	cash	pending	\N	50		40	2026-04-24 00:02:53.752268+00	2026-04-25 18:27:19.586418+00	\N	9	\N	\N	\N
4d422ac0-835f-4ab2-9e1e-4a604ed75fb7	SUH-0040	\N	Paola Tortas	\N	delivered	asap	\N	-	\N	\N	180.00	0.00	180.00	cash	pending	\N	30	\N	90	2026-04-25 18:30:05.191767+00	2026-04-25 21:44:55.734714+00	\N	0	0	[]	\N
d1becb90-503f-48ae-9a59-346e3a782f61	SUH-0025	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Mary Ramos	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas\r\n		130.00	0.00	130.00	cash	pending	\N	30		40	2026-04-24 00:01:37.874513+00	2026-04-25 18:27:20.646255+00	\N	9	\N	\N	\N
653108fa-ec18-4f14-a0a8-fcdbb5fabc79	SUH-0065	\N	Faby Flores	-	delivered	asap	\N	-	-	\N	165.00	0.00	165.00	cash	pending	\N	40	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:25.89116+00	\N	0	0	[]	\N
7b534dfe-4bf9-4e0b-87ce-fe3a13b827b2	SUH-0024	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Miguel Servin	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		180.00	0.00	180.00	cash	pending	\N	40		40	2026-04-24 00:00:20.159211+00	2026-04-25 18:27:21.704648+00	\N	13	\N	\N	\N
7f62f815-606a-448f-997a-a5a9fb8aafed	SUH-0023	6c7cc117-8a63-49ce-8d51-a44a32d298cd	Ubaldo Tivasani	\N	delivered	scheduled	2026-04-24 10:00:00+00	-	Vitasanitas		320.00	0.00	320.00	cash	pending	\N	40		40	2026-04-23 23:59:31.48129+00	2026-04-25 18:27:23.004038+00	\N	23	\N	\N	\N
086b70b6-492a-448a-95b2-0b7c51fb04de	SUH-0045	\N	Vanessa	-	delivered	scheduled	2026-04-25 15:00:00+00	-	\N	\N	435.00	0.00	435.00	cash	pending	\N	40	Res empanizado y aguacate	40	2026-04-25 19:49:29.592613+00	2026-04-25 21:45:43.03577+00	\N	0	0	[]	\N
54dad337-8898-4f76-abcf-d15004980afb	SUH-0039	\N	-		delivered	asap	\N	Adobes 2252-12			585.00	0.00	585.00	cash	pending	\N	30	2 empanizados\nMedio Philadelphia \n1 y medio fresa, mango aguacate	90	2026-04-25 18:28:55.348889+00	2026-04-25 21:58:13.232816+00	\N	0	0	[]	\N
5a2c5091-405c-4afa-b6fe-940fc0307a2c	SUH-0048	\N	Estética	-	delivered	scheduled	2026-04-25 16:00:00+00	-	\N	\N	145.00	0.00	145.00	cash	pending	\N	50	\N	40	2026-04-25 19:52:33.673316+00	2026-04-25 21:58:15.334261+00	\N	0	0	[]	\N
81375427-d252-48a6-804c-814a411b880d	SUH-0046	\N	-	-	delivered	asap	\N	Sta rosa 756			575.00	0.00	575.00	cash	pending	\N	50		90	2026-04-25 19:50:33.289567+00	2026-04-25 21:46:20.292477+00	\N	0	0	[]	\N
412f95b9-3514-49c8-b0de-e032184326a4	SUH-0060	\N	Oso	24	cancelled	asap	\N	Plato de oso	.		95.00	0.00	95.00	cash	pending	\N	50		90	2026-04-25 22:05:04.99719+00	2026-04-25 22:05:57.272304+00	Porque ya comió mucho	0	\N	\N	\N
6c2d25ee-1bcb-4661-81e3-cf55fe84a31b	SUH-0076	\N	Priv. Hornos 1219	-	delivered	asap	\N	-	-	\N	290.00	0.00	290.00	cash	pending	\N	70	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:07.566201+00	\N	0	0	[]	\N
98523aa3-a079-47fb-a2de-583c91f96612	SUH-0064	\N	Felix - Papá Diana	-	delivered	asap	\N	-	-	\N	560.00	0.00	560.00	cash	pending	\N	30	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:27.433127+00	\N	0	0	[]	\N
7452600e-8d92-48ef-b585-b21b842f9c51	SUH-0063	\N	Fer Pillo	-	delivered	asap	\N	-	-	\N	410.00	0.00	410.00	cash	pending	\N	30	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:28.901166+00	\N	0	0	[]	\N
3e418a25-35c1-4b85-a613-eeb6fbd73af4	SUH-0062	\N	Cuca	-	delivered	asap	\N	-	-	\N	750.00	300.00	450.00	cash	pending	\N	30	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:30.301466+00	\N	0	0	[]	\N
b2c59dbb-ab57-4ae2-b996-ec3497e88530	SUH-0068	\N	Sn Mateo 809	-	delivered	asap	\N	-	-	\N	190.00	0.00	190.00	cash	pending	\N	50	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:21.375855+00	\N	0	0	[]	\N
bd8a26c6-8113-482f-9d52-a26f98e7aef0	SUH-0067	\N	Sn Mateo 791	-	delivered	asap	\N	-	-	\N	120.00	0.00	120.00	cash	pending	\N	40	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:22.999602+00	\N	0	0	[]	\N
50a29883-15f4-4c2c-89a8-bab0ecd2ce9d	SUH-0066	\N	Mafer	-	delivered	asap	\N	-	-	\N	140.00	140.00	0.00	cash	pending	\N	40	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:24.515759+00	\N	0	0	[]	\N
5a88e038-3460-4371-85c5-8e200176fc42	SUH-0073	\N	Sn Ignacio 1321	-	delivered	asap	\N	-	-	\N	400.00	0.00	400.00	cash	pending	\N	60	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:12.261199+00	\N	0	0	[]	\N
8ed42317-dbc3-40f8-a94b-0500f1d5ad38	SUH-0072	\N	Adobes	-	delivered	asap	\N	-	-	\N	250.00	0.00	250.00	cash	pending	\N	60	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:13.794925+00	\N	0	0	[]	\N
10465337-89bc-4bb1-a83f-6b3ef157162e	SUH-0071	\N	Jose Reyes	-	delivered	asap	\N	-	-	\N	1165.00	0.00	1165.00	cash	pending	\N	60	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:15.294854+00	\N	0	0	[]	\N
30508bbd-3843-4db4-8a74-7638a669b850	SUH-0070	\N	Laura Benitez Tapatio	-	delivered	asap	\N	-	-	\N	500.00	0.00	500.00	cash	pending	\N	50	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:17.104431+00	\N	0	0	[]	\N
9de86714-e9b4-40de-9ce6-7d33a5e81ff6	SUH-0069	\N	Sta Rosa 862	-	delivered	asap	\N	-	-	\N	250.00	0.00	250.00	cash	pending	\N	50	\N	90	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:18.619126+00	\N	0	0	[]	\N
7c6638e1-994e-4795-b8b5-e7727b377719	SUH-0079	\N	Cony	-	delivered	asap	\N	-	-	\N	120.00	20.00	100.00	cash	pending	\N	80	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:22:53.877247+00	\N	0	0	[]	\N
5de0367b-b3fb-4ca5-b872-da4b97b42577	SUH-0078	\N	Circ Artesanos 1320	-	delivered	asap	\N	-	-	\N	420.00	0.00	420.00	cash	pending	\N	80	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:22:56.577498+00	\N	0	0	[]	\N
84bc4585-e4ef-40ef-b152-7de7a5340259	SUH-0075	\N	Cántaros 4494	-	delivered	asap	\N	-	-	\N	100.00	0.00	100.00	cash	pending	\N	70	\N	90	2026-05-09 19:22:07.550038+00	2026-05-16 19:23:09.198583+00	\N	0	0	[]	\N
98eac886-d70c-4c11-90bc-6aaa21b5c6e8	SUH-0082	\N	Santa Rosa 862	-	delivered	asap	\N	-	A	\N	475.00	0.00	475.00	cash	pending	\N	30	\N	90	2026-05-16 19:27:48.320806+00	2026-05-30 19:10:18.326601+00	\N	0	0	[]	\N
1cf5373e-93fd-4a05-9d39-8fcd7edc3d62	SUH-0081	\N	San Pablo	-	delivered	asap	\N	-	-	\N	120.00	0.00	120.00	cash	pending	\N	30	\N	90	2026-05-16 19:26:46.872709+00	2026-05-16 19:28:39.547423+00	\N	0	0	[]	\N
57d2b25a-8b09-4997-91ab-a8c0440aa983	SUH-0080	\N	Adobes	-	delivered	asap	\N	-	-		370.00	0.00	370.00	cash	pending	\N	30		90	2026-05-16 19:25:30.853724+00	2026-05-30 19:10:19.446739+00	\N	0	0	[]	\N
39b83321-1c29-4cb4-b636-b5a002c55bc3	SUH-0084	\N	Sra Cuquita	-	delivered	asap	\N	-	-	\N	890.00	0.00	890.00	cash	pending	\N	40	\N	90	2026-05-16 20:32:41.100228+00	2026-05-30 19:10:15.707209+00	\N	0	0	[]	\N
38d5d7a4-1d35-41e9-b341-b68b3e620686	SUH-0083	\N	Sta Rosa 758	-	delivered	asap	\N	-	-	\N	490.00	0.00	490.00	cash	pending	\N	40	\N	90	2026-05-16 19:28:18.610203+00	2026-05-30 19:10:16.625524+00	\N	0	0	[]	\N
098b3a58-775c-41d1-98b3-b01b47c787ce	SUH-0061	87098d86-d293-491d-8295-bc9c3115174a	Fabián Arias	3323286466	cancelled	scheduled	2026-05-12 16:40:00+00	Villas San Mateo 1285	Lomas de San Pedrito		240.00	48.00	192.00	cash	pending	\N	50		40	2026-05-02 19:15:23.010738+00	2026-05-16 19:23:47.377078+00	\N	20	460	"[{\\"id\\":\\"6f9af8b0-069b-48c7-9c5c-7c66376d6fe4\\",\\"name\\":\\"Par de Rollitos Primavera\\",\\"points_cost\\":80,\\"reward_type\\":\\"free_product\\",\\"discount_percent\\":null},{\\"id\\":\\"32ab4408-9269-42c6-bbe6-4148c7b11d4c\\",\\"name\\":\\"20% de descuento\\",\\"points_cost\\":380,\\"reward_type\\":\\"discount_percent\\",\\"discount_percent\\":20}]"	\N
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, category_id, name, description, price, image_url, available, featured, prep_time_min, sort_order, created_at, updated_at, points, custom_options, options_max, preview_config, images) FROM stdin;
63889f4f-ea00-40af-8112-d5fccc1411f7	7dd96963-cb38-4599-8498-d33323866bc3	Rollo Primavera Sencilo - 2 Pzas.	Tortilla de harina frita rellena de col, germinado de soya, zanahoria, carne molida y tocino.	35.00	\N	t	f	15	0	2026-04-20 17:21:51.912208+00	2026-05-31 01:03:15.96287+00	3	{}	\N	{"preview_type": "rollito_sencillo"}	{}
69ef84d2-e015-48d5-be14-11378284fde8	7dd96963-cb38-4599-8498-d33323866bc3	Rollo Primavera Especial - 2 Pzas.	Tortilla de harina frita rellena de col, germinado de soya, zanahoria, carne molida, tocino, camarón y queso crema.	50.00	\N	t	t	15	1	2026-04-20 17:22:44.101498+00	2026-05-31 01:03:20.702049+00	4	{}	\N	{"preview_type": "rollito_especial"}	{}
0c3b63e0-8191-422f-8d1a-d6b0141aa23a	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo California - 12 Pzas.	Rollo cubierto por alga en el exterior - Pepino, zanahoria, queso crema, aguacate y camarón.	110.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780189486240.png	t	f	12	0	2026-04-20 02:48:02.824933+00	2026-05-31 01:05:08.498763+00	8	{}	\N	{"left": {"base": "california", "type": "fixed", "topping_name": null, "topping_color": null}, "right": null, "split": false, "preview_type": "sushi"}	{}
b9b8e783-4574-4d42-8afd-0378f7d394e3	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo Empanizado - 12 Pzas.	Rollo empanizado y frito, relleno de pepino, zanahoria, queso crema, aguacate y camarón.	120.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780189524010.png	t	t	15	1	2026-04-20 16:14:57.942009+00	2026-05-31 01:05:37.479434+00	9	{}	\N	{"left": {"base": "empanizado", "type": "fixed", "topping_name": null, "topping_color": null}, "right": null, "split": false, "preview_type": "sushi"}	{}
4ddc2ae9-4a67-466e-8711-3dfa4f480869	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo California / Empanizado - 12 Pzas.	Rollo combinado california y empanizado (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón.	120.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780193771970.png	t	f	25	0	2026-04-20 17:05:44.240047+00	2026-05-31 02:16:33.723096+00	9	{}	\N	{"left": {"base": "california", "type": "fixed", "topping_name": null, "topping_color": null}, "right": {"base": "empanizado", "type": "fixed", "topping_name": null, "topping_color": null}, "split": true, "preview_type": "sushi"}	{}
633f2fd4-972e-46ce-8304-3cd05031344c	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo Philadelphia - 12 Pzas.	Rollo cubierto con una placa de queso crema - Pepino, zanahoria, queso crema, aguacate y camarón.	130.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780195536039.png	t	t	12	2	2026-04-20 02:48:02.824933+00	2026-05-31 02:45:49.660696+00	9	{}	\N	{"left": {"base": "philadelphia", "type": "fixed", "topping_name": null, "topping_color": null}, "right": null, "split": false, "preview_type": "sushi"}	{}
5546ebf1-9b41-4490-a12b-13ac6cf44d4a	c0db0005-3270-4539-b296-11e5217778bd	Código: A-1	Aún no es momento.	9999.00	\N	f	t	15	0	2026-04-20 17:27:04.690895+00	2026-05-30 23:50:37.188773+00	0	{}	\N	\N	{}
9d653814-801f-486f-bd46-1a753371de79	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo California / Frutas o Aguacate - 12 Pzas.	Rollo combinado california y frutas o aguacate (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón. 	130.00	\N	t	f	25	2	2026-04-20 17:10:55.602854+00	2026-05-30 23:50:37.188773+00	9	{Fresa,Mango,"Plátano macho",Aguacate}	1	\N	{}
b5be0b03-02a5-4243-90c7-e4a9673a7537	0457c7ac-268e-4189-8a3d-402bfb3f8b37	Bola Gohan	Bola de arroz empanizada rellena con pepino, zanahoria, queso crema, aguacate y camarón.	135.00	\N	t	f	25	2	2026-04-20 17:16:19.722754+00	2026-05-30 23:50:37.188773+00	10	{}	\N	\N	{}
621676a8-f9b5-484a-a5f2-e02d7ca585cc	0457c7ac-268e-4189-8a3d-402bfb3f8b37	Yakimeshi	Arroz frito con zanahoria, calabaza, res, pollo y camarón	95.00	\N	t	f	10	0	2026-04-20 17:15:12.69691+00	2026-05-31 01:03:02.353634+00	7	{}	\N	{"preview_type": "yakimeshi"}	{}
cb538273-33a6-4230-8a1c-2b0afeacd63a	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo de Aguacate - 12 Pzas.	Rollo cubierto con una placa de queso crema y forrado con aguacate - Pepino, zanahoria, queso crema, aguacate y camarón.	140.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780191165093.png	t	f	20	4	2026-04-20 02:48:02.824933+00	2026-05-31 01:32:58.421566+00	10	{}	\N	{"left": {"base": "aguacate", "type": "fixed", "topping_name": null, "topping_color": null}, "right": null, "split": false, "preview_type": "sushi"}	{}
fc3da0a6-91cb-49d3-aee9-b940b1a4dee6	0457c7ac-268e-4189-8a3d-402bfb3f8b37	Charola Surtida - 48 Pzas.	Charola con rollos de sushi california, empanizado, philadelphia, aguacate y frutas.	490.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780193849862.jpg	t	t	70	2	2026-04-20 17:17:58.783637+00	2026-05-31 02:20:02.514968+00	28	{Fresa,Mango,"Plátano macho",Aguacate}	1	{"preview_type": "charola"}	{}
ec2bafa8-1a05-46bf-a975-e2f1f831a576	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo Philadelphia / Frutas o Aguacate - 12 Pzas.	Rollo combinado philadelphia y frutas o aguacate (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón.	140.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780195564843.png	t	f	25	0	2026-04-20 17:13:37.744997+00	2026-05-31 02:46:21.628267+00	10	{Fresa,Mango,"Plátano macho",Aguacate}	1	{"left": {"base": "philadelphia", "type": "fixed", "topping_name": null, "topping_color": null}, "right": {"base": null, "type": "options", "topping_name": null, "topping_color": null}, "split": true, "preview_type": "sushi"}	{}
06aca312-7237-4be9-ace1-7ed5eb2bc7bd	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo Empanizado / Philadelphia - 12 Pzas.	Rollo combinado empanizado y philadelphia (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón.	130.00	\N	t	f	25	3	2026-04-20 17:11:44.889839+00	2026-05-30 23:50:37.188773+00	9	{}	\N	\N	{}
0ccbb292-9f3b-41f6-b01a-618b9813ea15	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo de Camarón - 12 Pzas.	Rollo cubierto con una placa de queso crema y forrado de camarones - Pepino, zanahoria, queso crema, aguacate y camarón.	180.00	\N	t	t	18	5	2026-04-20 02:48:02.824933+00	2026-05-30 23:50:37.188773+00	13	{}	\N	\N	{}
9b126e78-7819-4096-8133-8e5ebacdfbc4	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo California / Philadelphia - 12 Pzas.	Rollo combinado california y philadelphia (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón.	125.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780195928256.png	t	f	20	1	2026-04-20 17:08:39.091045+00	2026-05-31 02:52:19.940462+00	9	{}	\N	{"left": {"base": "california", "type": "fixed", "topping_name": null, "topping_color": null}, "right": {"base": "philadelphia", "type": "fixed", "topping_name": null, "topping_color": null}, "split": true, "preview_type": "sushi"}	{}
417143b2-d1b0-4ed8-a280-1b3e96238cb5	9cae5a95-15fd-44b8-817b-f49e3a153f3f	Rollo Empanizado / Frutas o Aguacate- 12 Pzas.	Rollo combinado empanizado y frutas o aguacate (6 pzas. c/u) - Pepino, zanahoria, queso crema, aguacate y camarón.	135.00	\N	t	f	25	4	2026-04-20 17:12:50.096243+00	2026-05-30 23:50:37.188773+00	10	{Fresa,Mango,"Plátano macho",Aguacate}	1	\N	{}
85dc122e-614f-4e6e-8a29-e7e3fcbac6b6	1ddaaa80-ddd6-4870-a86c-9e90996528ae	Rollo de Frutas - 12 Pzas.	Rollo cubierto con una placa de queso crema y forrado con fruta rebanada en la parte de arriba - Pepino, zanahoria, queso crema, aguacate y camarón.	140.00	https://ewwwgnbdzljinsmsaedm.supabase.co/storage/v1/object/public/products/product_1780191150498.png	t	f	15	3	2026-04-20 02:48:02.824933+00	2026-05-31 01:32:40.730633+00	10	{Fresa,Mango,"Plátano macho",Aguacate}	2	{"left": {"base": null, "type": "options", "topping_name": null, "topping_color": null}, "right": {"base": null, "type": "options", "topping_name": null, "topping_color": null}, "split": true, "preview_type": "sushi"}	{}
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.profiles (id, name, phone, email, address_line, address_colonia, address_city, address_references, orders_count, discount_active, discount_percent, loyalty_threshold, created_at, updated_at, points_total) FROM stdin;
6c7cc117-8a63-49ce-8d51-a44a32d298cd	leo	3323286466	leo@panel.admin	Villas San Mateo 1285	Lomas de San Pedrito	Zapopan		9	f	10	10	2026-04-21 02:42:11.817914+00	2026-04-25 18:27:23.004038+00	125
82c1676e-9fb8-43e3-ac17-a1b0a9fd4606	Danna Arias	3316322806	dannaarias427@gmail.com	\N	\N	Zapopan	\N	0	f	10	10	2026-04-25 18:39:36.719612+00	2026-04-25 18:41:30.764512+00	9999999
87098d86-d293-491d-8295-bc9c3115174a	Fabián Arias	3323286466	fatakerkane@gmail.com	Villas San Mateo 1285	Lomas de San Pedrito	Zapopan		2	f	10	10	2026-04-20 02:51:34.852407+00	2026-05-16 19:08:45.426562+00	99999571
b84f1ac5-5713-41a2-bf91-af08871f78a4	Armando Arias Castellanos	\N	arias.castell74@gmail.com	\N	\N	Zapopan	\N	0	f	10	10	2026-04-24 05:03:06.664474+00	2026-04-24 05:03:06.664474+00	0
\.


--
-- Data for Name: redemptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.redemptions (id, user_id, reward_id, order_id, reward_name, points_spent, created_at) FROM stdin;
10fc7b21-7667-4859-9152-52a8f8d5ed6f	87098d86-d293-491d-8295-bc9c3115174a	32ab4408-9269-42c6-bbe6-4148c7b11d4c	\N	20% de descuento	380	2026-04-24 04:52:01.132503+00
8b8757dd-51f3-4b2d-9505-6cc08252ea4d	87098d86-d293-491d-8295-bc9c3115174a	6f9af8b0-069b-48c7-9c5c-7c66376d6fe4	\N	Par de Rollitos Primavera	80	2026-04-24 04:52:01.233684+00
bf561e43-c7d3-4b7c-9a39-d962c288351e	87098d86-d293-491d-8295-bc9c3115174a	6f9af8b0-069b-48c7-9c5c-7c66376d6fe4	098b3a58-775c-41d1-98b3-b01b47c787ce	Par de Rollitos Primavera	80	2026-05-12 16:07:25.708809+00
b37b9be2-3f43-4b75-b2c1-abe97448aa63	87098d86-d293-491d-8295-bc9c3115174a	32ab4408-9269-42c6-bbe6-4148c7b11d4c	098b3a58-775c-41d1-98b3-b01b47c787ce	20% de descuento	380	2026-05-12 16:07:25.803882+00
\.


--
-- Data for Name: rewards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rewards (id, name, description, points_cost, reward_type, discount_percent, free_product_id, free_product_name, active, sort_order, created_at) FROM stdin;
8a6f3522-529a-415d-80b4-3527df4dfa9e	10% de descuento	Aplica 10% de descuento en tu pedido	150	discount_percent	10	\N	\N	t	2	2026-04-24 04:50:09.213095+00
3609a1a4-ff2a-489a-9ebf-743a6be13cbf	15% de descuento	Aplica 15% de descuento en tu pedido	250	discount_percent	15	\N	\N	t	3	2026-04-24 04:50:09.213095+00
32ab4408-9269-42c6-bbe6-4148c7b11d4c	20% de descuento	Aplica 20% de descuento en tu pedido	380	discount_percent	20	\N	\N	t	4	2026-04-24 04:50:09.213095+00
6f9af8b0-069b-48c7-9c5c-7c66376d6fe4	Par de Rollitos Primavera	Dos rollitos primavera sencillos gratis en tu pedido	80	free_product	\N	63889f4f-ea00-40af-8112-d5fccc1411f7	Rollo Primavera Sencilo - 2 Pzas.	t	1	2026-04-24 04:50:09.213095+00
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.settings (id, business_name, business_phone, whatsapp_number, open_time, close_time, max_concurrent_orders, delivery_base_minutes, delivery_per_zone_minutes, loyalty_threshold, discount_percent, mercadopago_enabled, mercadopago_public_key, transfer_enabled, transfer_clabe, transfer_bank, transfer_account_name, cash_enabled, is_open, pause_orders, updated_at, open_days) FROM stdin;
1	La Casa Del Sushi	\N	523323286466	13:00:00	19:00:00	6	30	10	100	10	f	\N	f	168516846841698168168161658	Santander	Armando Arias Castellanos	t	t	f	2026-04-20 02:48:02.824933+00	{6}
\.


--
-- Name: order_number_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.order_number_seq', 85, true);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_username_key UNIQUE (username);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: redemptions redemptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redemptions
    ADD CONSTRAINT redemptions_pkey PRIMARY KEY (id);


--
-- Name: rewards rewards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rewards
    ADD CONSTRAINT rewards_pkey PRIMARY KEY (id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: idx_notifications_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_order_id ON public.notifications USING btree (order_id);


--
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- Name: idx_order_items_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_product_id ON public.order_items USING btree (product_id);


--
-- Name: idx_orders_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);


--
-- Name: idx_products_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_category_id ON public.products USING btree (category_id);


--
-- Name: idx_redemptions_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_redemptions_order_id ON public.redemptions USING btree (order_id);


--
-- Name: idx_redemptions_reward_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_redemptions_reward_id ON public.redemptions USING btree (reward_id);


--
-- Name: idx_redemptions_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_redemptions_user_id ON public.redemptions USING btree (user_id);


--
-- Name: idx_rewards_free_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rewards_free_product_id ON public.rewards USING btree (free_product_id);


--
-- Name: orders order_delivered_increment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER order_delivered_increment AFTER UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.increment_user_orders();


--
-- Name: orders orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: products products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: profiles profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: notifications notifications_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: redemptions redemptions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redemptions
    ADD CONSTRAINT redemptions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: redemptions redemptions_reward_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redemptions
    ADD CONSTRAINT redemptions_reward_id_fkey FOREIGN KEY (reward_id) REFERENCES public.rewards(id) ON DELETE SET NULL;


--
-- Name: redemptions redemptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redemptions
    ADD CONSTRAINT redemptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: rewards rewards_free_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rewards
    ADD CONSTRAINT rewards_free_product_id_fkey FOREIGN KEY (free_product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: profiles Admin full access profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin full access profiles" ON public.profiles USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: categories Admin manage categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin manage categories" ON public.categories USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: notifications Admin manage notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin manage notifications" ON public.notifications USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: products Admin manage products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin manage products" ON public.products USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: orders Admin update orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin update orders" ON public.orders FOR UPDATE USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: settings Admin update settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin update settings" ON public.settings FOR UPDATE USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: order_items Admin view all order items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin view all order items" ON public.order_items FOR SELECT USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: orders Admin view all orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin view all orders" ON public.orders FOR SELECT USING ((( SELECT ((auth.jwt() -> 'user_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: admin_users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_users admin_users_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_users_read ON public.admin_users FOR SELECT USING (true);


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_delete ON public.categories FOR DELETE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: categories categories_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_update ON public.categories FOR UPDATE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: categories categories_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_admin_write ON public.categories FOR INSERT TO authenticated WITH CHECK ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: categories categories_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_read ON public.categories FOR SELECT USING (true);


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_admin ON public.notifications TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items order_items_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_admin_delete ON public.order_items FOR DELETE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: order_items order_items_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_insert ON public.order_items FOR INSERT WITH CHECK (true);


--
-- Name: order_items order_items_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_select ON public.order_items FOR SELECT USING (((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text) OR (EXISTS ( SELECT 1
   FROM public.orders
  WHERE ((orders.id = order_items.order_id) AND (orders.user_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: orders orders_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_admin_delete ON public.orders FOR DELETE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: orders orders_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_insert ON public.orders FOR INSERT WITH CHECK (true);


--
-- Name: orders orders_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_select ON public.orders FOR SELECT USING (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text) OR true));


--
-- Name: orders orders_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_update ON public.orders FOR UPDATE USING (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text)));


--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products products_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_delete ON public.products FOR DELETE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: products products_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_update ON public.products FOR UPDATE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: products products_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_admin_write ON public.products FOR INSERT TO authenticated WITH CHECK ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: products products_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_read ON public.products FOR SELECT USING (true);


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_admin_all ON public.profiles TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: profiles profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select ON public.profiles FOR SELECT USING (((( SELECT auth.uid() AS uid) = id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text)));


--
-- Name: profiles profiles_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update ON public.profiles FOR UPDATE USING (((( SELECT auth.uid() AS uid) = id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text)));


--
-- Name: redemptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.redemptions ENABLE ROW LEVEL SECURITY;

--
-- Name: redemptions redemptions_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY redemptions_admin_all ON public.redemptions TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: redemptions redemptions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY redemptions_insert ON public.redemptions FOR INSERT WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text)));


--
-- Name: redemptions redemptions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY redemptions_select ON public.redemptions FOR SELECT USING (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text)));


--
-- Name: rewards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;

--
-- Name: rewards rewards_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rewards_admin_delete ON public.rewards FOR DELETE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: rewards rewards_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rewards_admin_update ON public.rewards FOR UPDATE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: rewards rewards_admin_write; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rewards_admin_write ON public.rewards FOR INSERT TO authenticated WITH CHECK ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: rewards rewards_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rewards_read ON public.rewards FOR SELECT USING (true);


--
-- Name: settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

--
-- Name: settings settings_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_admin_update ON public.settings FOR UPDATE TO authenticated USING ((( SELECT ((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text)) = 'admin'::text));


--
-- Name: settings settings_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settings_read ON public.settings FOR SELECT USING (true);


--
-- PostgreSQL database dump complete
--

\unrestrict Nd6eozvgiq6Ne1GL3ehnFAKqjX8kt9TXTUvjANr3EOscCXRjRPDPylt5IXUrrMC

