import { useForm } from "react-hook-form";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/components/services/supabase";

export function useRegisterFormLogic() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const navigate = useNavigate();

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
  } = useForm();

  const onSubmit = async (data) => {
    setLoading(true);
    setError("");
    setSuccess("");
    try {
      const { error: signUpError } = await supabase.auth.signUp({
        email: data.email,
        password: data.password,
        options: {
          data: {
            full_name: data.fullName,
          },
        },
      });

      if (signUpError) {
        if (signUpError.message.includes("already registered")) {
          setError("Email này đã được đăng ký. Vui lòng dùng email khác hoặc đăng nhập.");
        } else {
          setError(signUpError.message || "Đăng ký thất bại.");
        }
        return;
      }

      setSuccess(
        "Đăng ký thành công! Vui lòng kiểm tra email để xác nhận tài khoản."
      );
      setTimeout(() => {
        navigate("/home", { state: { modal: "login" } });
      }, 3000);
    } catch (err) {
      setError("Lỗi hệ thống: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  return {
    register,
    handleSubmit,
    errors,
    watch,
    onSubmit,
    loading,
    error,
    success,
  };
}
