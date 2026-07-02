// Blox Fruits Account Manager — API Service
const BASE_URL = import.meta.env.VITE_API_URL || "https://tr-tt-5.onrender.com";

let authToken = null;

export const setAuthToken = (token) => {
  authToken = token;
};

const getHeaders = () => {
  const headers = {
    'Content-Type': 'application/json'
  };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }
  return headers;
};

export async function login(username, password) {
  const res = await fetch(`${BASE_URL}/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ username, password })
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.detail || "Login failed");
  return data;
}

export async function register(username, password) {
  const res = await fetch(`${BASE_URL}/auth/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ username, password })
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.detail || "Registration failed");
  return data;
}
export async function fetchMe() {
  const res = await fetch(`${BASE_URL}/auth/me`, { headers: getHeaders() });
  if (!res.ok) {
    const err = await res.json().catch(()=>({}));
    throw new Error(err.detail || "Failed to fetch user");
  }
  return res.json();
}
export async function fetchStats() {
  const res = await fetch(`${BASE_URL}/stats`, { headers: getHeaders() });
  if (!res.ok) {
    const err = await res.json().catch(()=>({}));
    throw new Error(err.detail || "Failed to fetch stats");
  }
  return res.json();
}

export async function fetchAccounts(filters = {}) {
  const params = new URLSearchParams();
  if (filters.sea) params.set("sea", filters.sea);
  if (filters.min_level) params.set("min_level", filters.min_level);
  if (filters.max_level) params.set("max_level", filters.max_level);
  if (filters.status) params.set("status", filters.status);
  params.set("limit", filters.limit || 100);

  const res = await fetch(`${BASE_URL}/accounts?${params}`, { headers: getHeaders() });
  if (!res.ok) {
    const err = await res.json().catch(()=>({}));
    throw new Error(err.detail || "Failed to fetch accounts");
  }
  return res.json();
}

export async function fetchAccount(username) {
  const res = await fetch(`${BASE_URL}/accounts/${username}`, { headers: getHeaders() });
  if (!res.ok) {
    const err = await res.json().catch(()=>({}));
    throw new Error(err.detail || "Account not found");
  }
  return res.json();
}

export async function fetchOnline() {
  const res = await fetch(`${BASE_URL}/online`, { headers: getHeaders() });
  if (!res.ok) {
    const err = await res.json().catch(()=>({}));
    throw new Error(err.detail || "Failed to fetch online accounts");
  }
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
