import { supabase } from "./supabase";

/**
 * Register a new user via Supabase Auth.
 * A profile row is created automatically by the database trigger.
 */
export async function registerUser({ userData }) {
  const { data, error } = await supabase.auth.signUp({
    email:    userData.email,
    password: userData.password,
    options: {
      data: {
        full_name: userData.fullName || userData.full_name || '',
        phone:     userData.phone    || '',
        gender:    userData.gender   || 'unknown',
      },
    },
  });

  if (error) {
    console.error("Lỗi khi đăng ký:", error.message);
    throw error;
  }

  return data;
}
