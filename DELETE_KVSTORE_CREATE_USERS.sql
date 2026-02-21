-- ============================================
-- FLEETFLOW DATABASE SETUP
-- Run this in Supabase SQL Editor
-- ============================================

-- ============================================
-- STEP 1: Drop the old kv_store table
-- ============================================
DROP TABLE IF EXISTS public.kv_store_66ef3f16 CASCADE;

-- ============================================
-- STEP 2: Drop old users table if it exists
-- ============================================
DROP TABLE IF EXISTS public.users CASCADE;

-- ============================================
-- STEP 3: Drop old triggers and functions
-- ============================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- ============================================
-- STEP 4: Create the proper USERS table
-- ============================================
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('Fleet Manager', 'Dispatcher', 'Safety Officer', 'Financial Analyst')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- STEP 5: Enable Row Level Security
-- ============================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- ============================================
-- STEP 6: Create RLS Policies
-- ============================================
CREATE POLICY "Users can read own profile"
  ON public.users
  FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.users
  FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Allow insert for authenticated users"
  ON public.users
  FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Service role has full access"
  ON public.users
  FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================
-- STEP 7: Create trigger function for CONFIRMED users
-- This only creates profile when email is confirmed
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create profile if email is confirmed
  IF NEW.email_confirmed_at IS NOT NULL THEN
    INSERT INTO public.users (id, email, name, role)
    VALUES (
      NEW.id,
      NEW.email,
      COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
      COALESCE(NEW.raw_user_meta_data->>'role', 'Fleet Manager')
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- STEP 8: Create triggers for INSERT and UPDATE
-- ============================================
-- Trigger on INSERT (when user signs up)
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger on UPDATE (when email gets confirmed)
CREATE TRIGGER on_auth_user_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  WHEN (OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL)
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- STEP 9: Create indexes
-- ============================================
CREATE INDEX IF NOT EXISTS users_email_idx ON public.users(email);
CREATE INDEX IF NOT EXISTS users_role_idx ON public.users(role);

-- ============================================
-- STEP 10: Grant permissions
-- ============================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON public.users TO anon, authenticated;

-- ============================================
-- DONE! Verify setup
-- ============================================
SELECT 'SUCCESS! Users table created' as status;
SELECT table_name FROM information_schema.tables WHERE table_name = 'users';

-- ============================================
-- IMPORTANT: NEXT STEPS
-- ============================================
-- 1. Go to Supabase Dashboard
-- 2. Click Authentication → Providers → Email
-- 3. Toggle "Confirm email" to ON
-- 4. Set "Mailer secure email change" to enabled
-- 5. Save settings
-- 6. Test by creating a new account!
