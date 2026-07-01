// Blox Fruits Account Manager — API Service
const BASE_URL = "https://tr-tt-3.onrender.com";

export async function fetchStats() {
  const res = await fetch(`${BASE_URL}/stats`);
  if (!res.ok) throw new Error("Failed to fetch stats");
  return res.json();
}

export async function fetchAccounts(filters = {}) {
  const params = new URLSearchParams();
  if (filters.sea) params.set("sea", filters.sea);
  if (filters.min_level) params.set("min_level", filters.min_level);
  if (filters.max_level) params.set("max_level", filters.max_level);
  if (filters.status) params.set("status", filters.status);
  params.set("limit", filters.limit || 100);

  const res = await fetch(`${BASE_URL}/accounts?${params}`);
  if (!res.ok) throw new Error("Failed to fetch accounts");
  return res.json();
}

export async function fetchAccount(username) {
  const res = await fetch(`${BASE_URL}/accounts/${username}`);
  if (!res.ok) throw new Error("Account not found");
  return res.json();
}

export async function fetchOnline() {
  const res = await fetch(`${BASE_URL}/online`);
  if (!res.ok) throw new Error("Failed to fetch online accounts");
  return res.json();
}

export async function healthCheck() {
  try {
    const res = await fetch(`${BASE_URL}/health`, { signal: AbortSignal.timeout(3000) });
    return res.ok;
  } catch {
    return false;
  }
}
