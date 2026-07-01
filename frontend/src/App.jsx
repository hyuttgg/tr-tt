import { useState, useEffect, useCallback, useRef } from "react";
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { fetchStats, fetchAccounts, healthCheck } from "./api";
import { AuthProvider, useAuth } from './context/AuthContext';
import StatsGrid from "./components/StatsGrid";
import AccountsTable from "./components/AccountsTable";
import AccountDetail from "./components/AccountDetail";
import TopCharts from "./components/TopCharts";
import Login from "./components/Login";
import Register from "./components/Register";
import ProtectedRoute from "./components/ProtectedRoute";

const POLL_INTERVAL = 5000; // 5 giây

function Dashboard() {
  const { logout, user } = useAuth();
  // Data state
  const [stats,    setStats]    = useState(null);
  const [accounts, setAccounts] = useState([]);
  const [total,    setTotal]    = useState(0);
  const [loading,  setLoading]  = useState(true);
  const [apiOnline, setApiOnline] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  // Filter state
  const [search,   setSearch]   = useState("");
  const [seaFilter, setSeaFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [sortBy,   setSortBy]   = useState("level");
  const [sortDir,  setSortDir]  = useState("desc");

  // Detail panel
  const [selected, setSelected] = useState(null);

  // Refs for cleanup
  const pollRef = useRef(null);

  // ─── Fetch data ───────────────────────────────────
  const refresh = useCallback(async () => {
    try {
      const [statsData, accData] = await Promise.all([
        fetchStats(),
        fetchAccounts({
          sea:    seaFilter || undefined,
          status: statusFilter || undefined,
          limit:  200,
        }),
      ]);

      setStats(statsData);
      setAccounts(accData.accounts || []);
      setTotal(accData.total || 0);
      setLastUpdated(new Date());
      setApiOnline(true);
    } catch (err) {
      console.error("Fetch error:", err);
      setApiOnline(false);
    } finally {
      setLoading(false);
    }
  }, [seaFilter, statusFilter]);

  // ─── Poll ─────────────────────────────────────────
  useEffect(() => {
    refresh();
    pollRef.current = setInterval(refresh, POLL_INTERVAL);
    return () => clearInterval(pollRef.current);
  }, [refresh]);

  // ─── Sort ─────────────────────────────────────────
  const handleSort = useCallback((key) => {
    setSortBy(prev => {
      if (prev === key) {
        setSortDir(d => d === "asc" ? "desc" : "asc");
        return prev;
      }
      setSortDir("desc");
      return key;
    });
  }, []);

  // ─── Filtered + sorted accounts ───────────────────
  const displayed = (() => {
    let list = [...accounts];

    // Search filter
    if (search.trim()) {
      const q = search.toLowerCase();
      list = list.filter(a =>
        a.username?.toLowerCase().includes(q) ||
        a.fruit?.toLowerCase().includes(q) ||
        a.race?.toLowerCase().includes(q)
      );
    }

    // Sort
    list.sort((a, b) => {
      let va = a[sortBy];
      let vb = b[sortBy];
      if (typeof va === "string") va = va.toLowerCase();
      if (typeof vb === "string") vb = vb.toLowerCase();
      if (va < vb) return sortDir === "asc" ? -1 : 1;
      if (va > vb) return sortDir === "asc" ? 1 : -1;
      return 0;
    });

    return list;
  })();

  // ─── Keyboard: Escape to close detail ─────────────
  useEffect(() => {
    const handler = (e) => {
      if (e.key === "Escape") setSelected(null);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  // ─── Format last updated ──────────────────────────
  const lastUpdatedStr = lastUpdated
    ? lastUpdated.toLocaleTimeString("vi-VN")
    : "—";

  // ─── Render ───────────────────────────────────────
  return (
    <>
      <div className="app-bg" />

      <div className="app-wrapper">

        {/* Header */}
        <header className="header">
          <div className="header-brand">
            <div className="header-logo" aria-hidden="true">🏴‍☠️</div>
            <div>
              <div className="header-title">Blox Fruits Account Manager</div>
              <div className="header-subtitle">Realtime dashboard — cập nhật mỗi 5 giây</div>
            </div>
          </div>

          <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
            <div className="refresh-bar">
              <div className="refresh-dot" />
              <span>Updated {lastUpdatedStr}</span>
            </div>
            <div className="header-status">
              <div className={`status-dot ${apiOnline === false ? "offline" : ""}`} />
              {apiOnline === null ? "Checking..." : apiOnline ? "API Online" : "API Offline"}
            </div>
            <button
              className="btn btn-ghost"
              onClick={refresh}
              id="btn-refresh"
              aria-label="Refresh data"
            >
              🔄 Refresh
            </button>
            <button
              className="btn btn-ghost"
              onClick={() => {
                const script = `loadstring(game:HttpGet("https://tr-tt-5.onrender.com/script?key=${user?.api_key}"))()`;
                navigator.clipboard.writeText(script);
                alert("Đã copy mã script vào clipboard!");
              }}
              style={{color: '#10b981'}}
            >
              📋 Copy Script
            </button>
            <div style={{color: '#9ca3af', fontSize: '14px', marginLeft: '8px', borderLeft: '1px solid #374151', paddingLeft: '12px'}}>
              Hi, {user?.username}
            </div>
            <button
              className="btn btn-ghost"
              onClick={logout}
              style={{color: '#ef4444'}}
            >
              Logout
            </button>
          </div>
        </header>

        {/* Stats */}
        <StatsGrid stats={stats} />

        {/* Top Charts */}
        {stats && (stats.top_fruits?.length > 0 || stats.top_races?.length > 0) && (
          <TopCharts stats={stats} />
        )}

        {/* Filters */}
        <div className="filters-row">
          {/* Search */}
          <div className="search-wrap">
            <span className="search-icon" aria-hidden="true">🔍</span>
            <input
              id="input-search"
              type="text"
              placeholder="Tìm username, fruit, race..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              autoComplete="off"
            />
          </div>

          {/* Sea filter */}
          <div className="filter-group">
            <label className="filter-label" htmlFor="filter-sea">Sea</label>
            <select
              id="filter-sea"
              className="filter-select"
              value={seaFilter}
              onChange={e => setSeaFilter(e.target.value)}
            >
              <option value="">Tất cả</option>
              <option value="1">Sea 1</option>
              <option value="2">Sea 2</option>
              <option value="3">Sea 3</option>
            </select>
          </div>

          {/* Status filter */}
          <div className="filter-group">
            <label className="filter-label" htmlFor="filter-status">Status</label>
            <select
              id="filter-status"
              className="filter-select"
              value={statusFilter}
              onChange={e => setStatusFilter(e.target.value)}
            >
              <option value="">Tất cả</option>
              <option value="online">Online</option>
              <option value="offline">Offline</option>
            </select>
          </div>
        </div>

        {/* Table */}
        <div className="section-header">
          <div className="section-title">Danh sách tài khoản</div>
          <div className="section-count">{displayed.length} / {total}</div>
        </div>

        {loading ? (
          <div className="table-wrap">
            <div className="loading-wrap">
              <div className="loading-spinner" />
              <div className="empty-text">Đang tải dữ liệu...</div>
            </div>
          </div>
        ) : (
          <AccountsTable
            accounts={displayed}
            onSelect={setSelected}
            selectedUsername={selected?.username}
            sortBy={sortBy}
            sortDir={sortDir}
            onSort={handleSort}
          />
        )}

      </div>

      {/* Detail panel */}
      {selected && (
        <AccountDetail
          account={selected}
          onClose={() => setSelected(null)}
        />
      )}
    </>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <Router>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />
          <Route 
            path="/" 
            element={
              <ProtectedRoute>
                <Dashboard />
              </ProtectedRoute>
            } 
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Router>
    </AuthProvider>
  );
}
