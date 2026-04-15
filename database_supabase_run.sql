-- ============================================================
-- HAAD TECH – SUPABASE COMPLETE SETUP SCRIPT
-- Run this entire file in Supabase SQL Editor
-- ============================================================

-- ========================
-- EXTENSIONS
-- ========================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ========================
-- PROFILES
-- ========================
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID         PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT         UNIQUE NOT NULL,
  full_name   VARCHAR(150) DEFAULT '',
  phone       VARCHAR(20),
  gender      VARCHAR(20)  DEFAULT 'unknown',
  dob         JSONB,                        -- { day, month, year }
  avatar_url  TEXT,
  role        VARCHAR(20)  DEFAULT 'user',  -- 'user' | 'admin'
  is_active   BOOLEAN      DEFAULT TRUE,
  created_at  TIMESTAMPTZ  DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  DEFAULT NOW()
);

-- ========================
-- GEOGRAPHIC TABLES
-- ========================
CREATE TABLE IF NOT EXISTS provinces (
  code       VARCHAR(10)  PRIMARY KEY,
  name       VARCHAR(150) NOT NULL,
  full_name  VARCHAR(200),
  created_at TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS districts (
  code          VARCHAR(10)  PRIMARY KEY,
  name          VARCHAR(150) NOT NULL,
  full_name     VARCHAR(200),
  province_code VARCHAR(10)  REFERENCES provinces(code) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wards (
  code          VARCHAR(10)  PRIMARY KEY,
  name          VARCHAR(150) NOT NULL,
  full_name     VARCHAR(200),
  district_code VARCHAR(10)  REFERENCES districts(code) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_districts_province ON districts(province_code);
CREATE INDEX IF NOT EXISTS idx_wards_district     ON wards(district_code);

-- ========================
-- USER ADDRESSES
-- ========================
CREATE TABLE IF NOT EXISTS user_address (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  address_text TEXT        NOT NULL,   -- JSON: { name, recipient, phone, address, ward, district, city, isDefault, type, provinceCode, districtCode, wardCode }
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_address_user ON user_address(user_id);

-- ========================
-- ORDERS
-- ========================
CREATE TABLE IF NOT EXISTS orders (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  customer_name   VARCHAR(200) NOT NULL,
  phone           VARCHAR(20)  NOT NULL,
  gender          VARCHAR(20)  DEFAULT 'unknown',
  -- address stored as JSON for backward-compatibility with existing code
  address         JSONB,       -- { full_address, city, district, ward, street, note }
  shipping_method VARCHAR(20)  DEFAULT 'standard',
  payment_method  VARCHAR(20)  DEFAULT 'cod',
  -- product stored as JSON; order_items table holds normalised rows
  product_info    JSONB,       -- { id, title, image, price, original_price, quantity }
  product_price   BIGINT       DEFAULT 0,
  shipping_fee    BIGINT       DEFAULT 0,
  discount        BIGINT       DEFAULT 0,
  discount_code   VARCHAR(50),
  total           BIGINT       DEFAULT 0,
  status          VARCHAR(20)  DEFAULT 'pending',
  -- 'pending' | 'processing' | 'shipped' | 'delivered' | 'cancelled' | 'deleted'
  order_date      TIMESTAMPTZ  DEFAULT NOW(),
  created_at      TIMESTAMPTZ  DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ                   -- soft-delete
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id    ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_phone      ON orders(phone);
CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date DESC);

-- ========================
-- ORDER ITEMS
-- ========================
CREATE TABLE IF NOT EXISTS order_items (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id    TEXT,                    -- string ID from any product table
  product_name  VARCHAR(500),
  product_image TEXT,
  quantity      INT         DEFAULT 1,
  price         BIGINT      DEFAULT 0,
  image_url     TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order   ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- ========================
-- CART ITEMS
-- ========================
CREATE TABLE IF NOT EXISTS cart_items (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  product_id     TEXT        NOT NULL,
  product_title  VARCHAR(500),
  product_image  TEXT,
  product_price  BIGINT      DEFAULT 0,
  original_price BIGINT      DEFAULT 0,
  quantity       INT         DEFAULT 1 CHECK (quantity > 0),
  category       VARCHAR(100),
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user ON cart_items(user_id);

-- ========================
-- DISCOUNT CODES
-- ========================
CREATE TABLE IF NOT EXISTS discount_codes (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code            VARCHAR(50) UNIQUE NOT NULL,
  description     TEXT,
  discount_type   VARCHAR(20) DEFAULT 'fixed',   -- 'fixed' | 'percentage'
  discount_value  BIGINT      DEFAULT 0,
  min_order_value BIGINT      DEFAULT 0,
  max_uses        INT,
  used_count      INT         DEFAULT 0,
  is_active       BOOLEAN     DEFAULT TRUE,
  starts_at       TIMESTAMPTZ DEFAULT NOW(),
  expires_at      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_discount_codes_code ON discount_codes(code);

-- ========================
-- CUSTOMER FEEDBACK
-- ========================
CREATE TABLE IF NOT EXISTS customer_feedback (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  full_name   VARCHAR(150) NOT NULL,
  email       VARCHAR(300) NOT NULL,
  phone       VARCHAR(20),
  subject     VARCHAR(300) NOT NULL,
  message     TEXT        NOT NULL,
  status      VARCHAR(20) DEFAULT 'open',
  admin_reply TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ========================
-- TRIGGERS – updated_at
-- ========================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_profiles_updated_at') THEN
    CREATE TRIGGER trg_profiles_updated_at
      BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_updated_at') THEN
    CREATE TRIGGER trg_orders_updated_at
      BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_cart_items_updated_at') THEN
    CREATE TRIGGER trg_cart_items_updated_at
      BEFORE UPDATE ON cart_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_feedback_updated_at') THEN
    CREATE TRIGGER trg_feedback_updated_at
      BEFORE UPDATE ON customer_feedback FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

-- ========================
-- TRIGGER – auto-create profile on new Supabase auth user
-- ========================
CREATE OR REPLACE FUNCTION handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    'user'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user();

-- ========================
-- ROW LEVEL SECURITY
-- ========================

ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_address      ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders            ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE discount_codes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE provinces         ENABLE ROW LEVEL SECURITY;
ALTER TABLE districts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE wards             ENABLE ROW LEVEL SECURITY;

-- Helper function: is current user admin?
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ---- profiles ----
DROP POLICY IF EXISTS "profiles_select" ON profiles;
CREATE POLICY "profiles_select" ON profiles
  FOR SELECT USING (id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "profiles_update" ON profiles;
CREATE POLICY "profiles_update" ON profiles
  FOR UPDATE USING (id = auth.uid());

DROP POLICY IF EXISTS "profiles_insert" ON profiles;
CREATE POLICY "profiles_insert" ON profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- ---- user_address ----
DROP POLICY IF EXISTS "user_address_all" ON user_address;
CREATE POLICY "user_address_all" ON user_address
  FOR ALL USING (user_id = auth.uid() OR is_admin());

-- ---- orders ----
DROP POLICY IF EXISTS "orders_select" ON orders;
CREATE POLICY "orders_select" ON orders
  FOR SELECT USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "orders_insert" ON orders;
CREATE POLICY "orders_insert" ON orders
  FOR INSERT WITH CHECK (TRUE);           -- allow guest checkout

DROP POLICY IF EXISTS "orders_update" ON orders;
CREATE POLICY "orders_update" ON orders
  FOR UPDATE USING (user_id = auth.uid() OR is_admin());

-- ---- order_items ----
DROP POLICY IF EXISTS "order_items_select" ON order_items;
CREATE POLICY "order_items_select" ON order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_items.order_id
        AND (orders.user_id = auth.uid() OR is_admin())
    )
  );

DROP POLICY IF EXISTS "order_items_insert" ON order_items;
CREATE POLICY "order_items_insert" ON order_items
  FOR INSERT WITH CHECK (TRUE);

-- ---- cart_items ----
DROP POLICY IF EXISTS "cart_items_all" ON cart_items;
CREATE POLICY "cart_items_all" ON cart_items
  FOR ALL USING (user_id = auth.uid());

-- ---- discount_codes ----
DROP POLICY IF EXISTS "discount_codes_select" ON discount_codes;
CREATE POLICY "discount_codes_select" ON discount_codes
  FOR SELECT USING (
    is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW())
    OR is_admin()
  );

DROP POLICY IF EXISTS "discount_codes_admin" ON discount_codes;
CREATE POLICY "discount_codes_admin" ON discount_codes
  FOR ALL USING (is_admin());

-- ---- customer_feedback ----
DROP POLICY IF EXISTS "feedback_insert" ON customer_feedback;
CREATE POLICY "feedback_insert" ON customer_feedback
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "feedback_select" ON customer_feedback;
CREATE POLICY "feedback_select" ON customer_feedback
  FOR SELECT USING (user_id = auth.uid() OR is_admin());

DROP POLICY IF EXISTS "feedback_update_admin" ON customer_feedback;
CREATE POLICY "feedback_update_admin" ON customer_feedback
  FOR UPDATE USING (is_admin());

-- ---- geographic tables (public read-only) ----
DROP POLICY IF EXISTS "provinces_select" ON provinces;
CREATE POLICY "provinces_select" ON provinces FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "districts_select" ON districts;
CREATE POLICY "districts_select" ON districts FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "wards_select" ON wards;
CREATE POLICY "wards_select" ON wards FOR SELECT USING (TRUE);

-- ========================
-- SAMPLE DISCOUNT CODES
-- ========================
INSERT INTO discount_codes (code, description, discount_type, discount_value, min_order_value, max_uses, expires_at)
VALUES
  ('HAAD10',   'Giảm 10% cho đơn hàng đầu tiên',        'percentage', 10,     0,        500,  NOW() + INTERVAL '1 year'),
  ('HAAD50K',  'Giảm 50.000đ cho đơn từ 500K',          'fixed',      50000,  500000,   NULL, NOW() + INTERVAL '6 months'),
  ('FREESHIP', 'Miễn phí vận chuyển',                   'fixed',      50000,  0,        1000, NOW() + INTERVAL '3 months'),
  ('SALE200K', 'Giảm 200.000đ cho đơn từ 2 triệu',      'fixed',      200000, 2000000,  200,  NOW() + INTERVAL '2 months')
ON CONFLICT (code) DO NOTHING;
