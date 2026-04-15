import { supabase } from '@/components/services/supabase';

export function formatCurrency(value) {
  if (!value || isNaN(value)) return '₫0';
  return `₫${Number(value).toLocaleString('vi-VN')}`;
}

function buildProductShape(item, categorySlug) {
  const salePrice     = item.sale_price     || 0;
  const originalPrice = item.original_price || Math.round(salePrice * 1.2);
  const discount =
    originalPrice && originalPrice > salePrice
      ? `${Math.round(((originalPrice - salePrice) / originalPrice) * 100)}%`
      : '0%';

  return {
    id:            item.id            || '',
    title:         item.title?.replace(/-/g, ' ') || 'No Title',
    brand:         item.brand         || 'Unknown',
    image:         item.image         || '',
    salePrice:     formatCurrency(salePrice),
    originalPrice: formatCurrency(originalPrice),
    salePriceRaw:  salePrice,
    discount,
    rating:        item.rating        || 0,
    reviewCount:   item.review_count  || 0,
    thumbnail:     item.thumbnails    || '',
    description:   item.description   || '',
    detailImage:   item.detail_image  || '',
    performance:   item.performance   || '',
    extends:       item.extends       || '',
    category:      item.category      || categorySlug || 'product',
  };
}

/**
 * Fetch products from the unified `product` table.
 * When a category slug is given, filter by it; otherwise return all active products.
 */
export async function fetchProducts(category = 'product') {
  let query = supabase
    .from('product')
    .select('*')
    .eq('is_active', true)
    .order('rating', { ascending: false });

  // 'product' means "no category filter" (show all)
  if (category && category !== 'product') {
    query = query.eq('category', category);
  }

  const { data, error } = await query;

  if (error) {
    console.error(`Error fetching products (category=${category}):`, error.message);
    return [];
  }

  return (data || []).map(item => buildProductShape(item, category));
}

/**
 * Get the current authenticated user's ID.
 */
export async function getUserId() {
  try {
    const { data: { user }, error } = await supabase.auth.getUser();
    if (error) return null;
    return user?.id || null;
  } catch {
    return null;
  }
}
