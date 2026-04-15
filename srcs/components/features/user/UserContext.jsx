import { createContext, useState, useEffect, useContext, useCallback } from "react";
import { useAuth } from "../auth/AuthContext";
import { supabase } from "@/components/services/supabase";
import { toast } from "react-hot-toast";

const UserContext = createContext();

export function UserProvider({ children }) {
  const { user } = useAuth();
  const [userInfo,           setUserInfo]           = useState(null);
  const [userId,             setUserId]             = useState(null);
  const [cartItems,          setCartItems]          = useState([]);
  const [recentlyAddedItems, setRecentlyAddedItems] = useState([]);
  const [cartCount,          setCartCount]          = useState(0);
  const [isCartLoading,      setIsCartLoading]      = useState(false);
  const [orderCount,         setOrderCount]         = useState({ active: 0, completed: 0, cancelled: 0 });
  const [isOrdersLoading,    setIsOrdersLoading]    = useState(false);

  // ── Sync state when auth user changes ──────────────────────
  useEffect(() => {
    if (user) {
      setUserInfo({
        fullName: user.user_metadata?.full_name || "",
        gender:   user.user_metadata?.gender    || "",
        phone:    user.user_metadata?.phone     || "",
        email:    user.email,
        dob:      user.user_metadata?.dob       || { day: "", month: "", year: "" },
      });
      setUserId(user.id);
      fetchCartItems(user.id);
      fetchOrderCounts(user.id);
    } else {
      setUserInfo(null);
      setUserId(null);
      setCartItems([]);
      setCartCount(0);
      setOrderCount({ active: 0, completed: 0, cancelled: 0 });
    }
  }, [user]);

  // ── Get user ID ─────────────────────────────────────────────
  const getUserId = useCallback(async () => {
    if (userId) return userId;
    const { data: { user: u } } = await supabase.auth.getUser();
    return u?.id || null;
  }, [userId]);

  // ── Order counts ────────────────────────────────────────────
  // DB status values: pending | processing | shipped | delivered | cancelled | deleted
  const fetchOrderCounts = useCallback(async (uid) => {
    if (!uid) return;
    setIsOrdersLoading(true);
    try {
      const [activeRes, completedRes, cancelledRes] = await Promise.all([
        supabase.from('orders').select('id', { count: 'exact', head: true })
          .eq('user_id', uid)
          .in('status', ['pending', 'processing', 'shipped'])
          .is('deleted_at', null),
        supabase.from('orders').select('id', { count: 'exact', head: true })
          .eq('user_id', uid)
          .eq('status', 'delivered')
          .is('deleted_at', null),
        supabase.from('orders').select('id', { count: 'exact', head: true })
          .eq('user_id', uid)
          .eq('status', 'cancelled')
          .is('deleted_at', null),
      ]);

      setOrderCount({
        active:    activeRes.count    || 0,
        completed: completedRes.count || 0,
        cancelled: cancelledRes.count || 0,
      });
    } catch (err) {
      console.error("fetchOrderCounts error:", err);
      setOrderCount({ active: 0, completed: 0, cancelled: 0 });
    } finally {
      setIsOrdersLoading(false);
    }
  }, []);

  // ── Cart: load from DB then merge with localStorage ─────────
  const fetchCartItems = useCallback(async (uid) => {
    if (!uid) return;
    setIsCartLoading(true);
    try {
      const { data, error } = await supabase
        .from('cart_items')
        .select('*')
        .eq('user_id', uid)
        .order('created_at', { ascending: true });

      if (!error && data && data.length > 0) {
        // Use DB as source of truth; merge any unsaved localStorage items
        const dbIds = new Set(data.map(i => i.product_id));
        const local = JSON.parse(localStorage.getItem('cart') || '[]');
        const extras = local.filter(i => !dbIds.has(String(i.id)));

        // Upsert extras into DB
        for (const item of extras) {
          await supabase.from('cart_items').upsert({
            user_id:        uid,
            product_id:     String(item.id),
            product_title:  item.title,
            product_image:  item.image,
            product_price:  parsePrice(item.salePrice),
            original_price: parsePrice(item.originalPrice),
            quantity:       item.quantity || 1,
            category:       item.category || '',
          }, { onConflict: 'user_id,product_id' });
        }

        const merged = [...data.map(dbItemToCartItem), ...extras];
        setCartItems(merged);
        setCartCount(merged.reduce((s, i) => s + (i.quantity || 1), 0));
        localStorage.setItem('cart', JSON.stringify(merged));
      } else {
        // No DB data — fall back to localStorage
        const local = JSON.parse(localStorage.getItem('cart') || '[]');
        setCartItems(local);
        setCartCount(local.reduce((s, i) => s + (i.quantity || 1), 0));
      }
    } catch (err) {
      console.error("fetchCartItems error:", err);
      const local = JSON.parse(localStorage.getItem('cart') || '[]');
      setCartItems(local);
      setCartCount(local.reduce((s, i) => s + (i.quantity || 1), 0));
    } finally {
      setIsCartLoading(false);
    }
  }, []);

  // Convert DB cart row → component cart item shape
  function dbItemToCartItem(row) {
    return {
      id:            row.product_id,
      title:         row.product_title,
      image:         row.product_image,
      salePrice:     formatCurrency(row.product_price),
      originalPrice: formatCurrency(row.original_price),
      quantity:      row.quantity,
      category:      row.category || '',
    };
  }

  function formatCurrency(val) {
    if (!val) return '₫0';
    return `₫${Number(val).toLocaleString('vi-VN')}`;
  }

  function parsePrice(str) {
    if (!str) return 0;
    if (typeof str === 'number') return str;
    return parseInt(str.replace(/[^\d]/g, ''), 10) || 0;
  }

  // ── Add to cart ─────────────────────────────────────────────
  const addToCart = useCallback(async (product, quantity = 1, showToast = true) => {
    if (!product) return false;
    try {
      const uid = await getUserId();

      // Optimistically update state + localStorage
      setCartItems(prev => {
        const idx = prev.findIndex(i => String(i.id) === String(product.id));
        let updated;
        if (idx >= 0) {
          updated = prev.map((i, n) => n === idx ? { ...i, quantity: (i.quantity || 1) + quantity } : i);
        } else {
          updated = [...prev, { ...product, quantity }];
        }
        localStorage.setItem('cart', JSON.stringify(updated));
        setCartCount(updated.reduce((s, i) => s + (i.quantity || 1), 0));
        return updated;
      });

      setRecentlyAddedItems(prev => {
        const filtered = prev.filter(i => i.id !== product.id);
        const updated  = [product, ...filtered].slice(0, 5);
        localStorage.setItem('recentlyAddedItems', JSON.stringify(updated));
        return updated;
      });

      // Persist to DB
      if (uid) {
        const existing = cartItems.find(i => String(i.id) === String(product.id));
        const newQty   = (existing?.quantity || 0) + quantity;
        await supabase.from('cart_items').upsert({
          user_id:        uid,
          product_id:     String(product.id),
          product_title:  product.title,
          product_image:  product.image,
          product_price:  parsePrice(product.salePrice),
          original_price: parsePrice(product.originalPrice),
          quantity:       newQty,
          category:       product.category || '',
        }, { onConflict: 'user_id,product_id' });
      }

      if (showToast) {
        toast.success(`Đã thêm ${quantity} ${product.title || 'sản phẩm'} vào giỏ hàng!`, {
          icon: '🛒', duration: 3000,
        });
      }
      return true;
    } catch (err) {
      console.error("addToCart error:", err);
      if (showToast) toast.error("Không thể thêm sản phẩm vào giỏ hàng.");
      return false;
    }
  }, [cartItems, getUserId]);

  // ── Remove from cart ────────────────────────────────────────
  const removeFromCart = useCallback(async (itemId) => {
    try {
      setCartItems(prev => {
        const updated = prev.filter(i => String(i.id) !== String(itemId));
        localStorage.setItem('cart', JSON.stringify(updated));
        setCartCount(updated.reduce((s, i) => s + (i.quantity || 1), 0));
        return updated;
      });

      const uid = await getUserId();
      if (uid) {
        await supabase.from('cart_items')
          .delete()
          .eq('user_id', uid)
          .eq('product_id', String(itemId));
      }

      toast.success("Sản phẩm đã được xóa khỏi giỏ hàng!");
      return true;
    } catch (err) {
      console.error("removeFromCart error:", err);
      toast.error("Không thể xóa sản phẩm khỏi giỏ hàng.");
      return false;
    }
  }, [getUserId]);

  // ── Update quantity ─────────────────────────────────────────
  const updateCartItemQuantity = useCallback(async (itemId, newQuantity) => {
    try {
      setCartItems(prev => {
        const updated = prev.map(i => String(i.id) === String(itemId) ? { ...i, quantity: newQuantity } : i);
        localStorage.setItem('cart', JSON.stringify(updated));
        setCartCount(updated.reduce((s, i) => s + (i.quantity || 1), 0));
        return updated;
      });

      const uid = await getUserId();
      if (uid) {
        await supabase.from('cart_items')
          .update({ quantity: newQuantity })
          .eq('user_id', uid)
          .eq('product_id', String(itemId));
      }
      return true;
    } catch (err) {
      console.error("updateCartItemQuantity error:", err);
      toast.error("Không thể cập nhật số lượng.");
      return false;
    }
  }, [getUserId]);

  // ── Clear cart ──────────────────────────────────────────────
  const clearCart = useCallback(async () => {
    try {
      setCartItems([]);
      setCartCount(0);
      localStorage.removeItem('cart');

      const uid = await getUserId();
      if (uid) {
        await supabase.from('cart_items').delete().eq('user_id', uid);
      }
      return true;
    } catch (err) {
      console.error("clearCart error:", err);
      return false;
    }
  }, [getUserId]);

  // ── Create order ────────────────────────────────────────────
  const createOrder = useCallback(async (orderData) => {
    try {
      const uid = await getUserId();
      if (!uid) {
        toast.error("Vui lòng đăng nhập để đặt hàng!");
        return false;
      }

      const { data: order, error: orderError } = await supabase
        .from('orders')
        .insert({ ...orderData, user_id: uid, status: 'pending', order_date: new Date().toISOString() })
        .select()
        .single();

      if (orderError) throw orderError;

      // Insert order_items
      const items = Array.isArray(orderData.product_info) ? orderData.product_info : [orderData.product_info];
      const orderItems = items.filter(Boolean).map(item => ({
        order_id:      order.id,
        product_id:    String(item.id),
        product_name:  item.title || item.name,
        product_image: item.image || item.thumbnail,
        quantity:      item.quantity || 1,
        price:         typeof item.price === 'number' ? item.price : parseInt(String(item.price || '0').replace(/[^\d]/g, ''), 10),
        image_url:     item.image || item.thumbnail,
      }));

      if (orderItems.length > 0) {
        const { error: itemsError } = await supabase.from('order_items').insert(orderItems);
        if (itemsError) console.error("order_items insert error:", itemsError);
      }

      await clearCart();
      await fetchOrderCounts(uid);
      toast.success("Đặt hàng thành công!");
      return order.id;
    } catch (err) {
      console.error("createOrder error:", err);
      toast.error("Không thể tạo đơn hàng. Vui lòng thử lại sau.");
      return false;
    }
  }, [getUserId, clearCart, fetchOrderCounts]);

  return (
    <UserContext.Provider value={{
      userInfo,
      setUserInfo,
      getUserId,
      userId,
      cartItems,
      cartCount,
      isCartLoading,
      recentlyAddedItems,
      orderCount,
      isOrdersLoading,
      fetchOrderCounts,
      createOrder,
      addToCart,
      removeFromCart,
      updateCartItemQuantity,
      clearCart,
    }}>
      {children}
    </UserContext.Provider>
  );
}

export function useUser() {
  return useContext(UserContext);
}
