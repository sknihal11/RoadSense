import React, { useState, useEffect, useRef } from 'react';
import './App.css';

// Initial Mock Reports corresponding to Bengaluru coordinates
const INITIAL_REPORTS = [
  {
    id: 1,
    latitude: 17.7290,
    longitude: 83.3087,
    anomaly_type: 'pothole',
    confidence: 0.84,
    timestamp: '2026-07-03 14:00',
    is_verified: false,
    status: 'pending', // pending, verified, resolved
    reporter: 'Nihal (Driver Profile #421)',
    address: 'RTC Complex Road, Visakhapatnam',
    severity: 'High'
  },
  {
    id: 2,
    latitude: 17.8176,
    longitude: 83.3488,
    anomaly_type: 'crack',
    confidence: 0.72,
    timestamp: '2026-07-03 14:05',
    is_verified: false,
    status: 'pending',
    reporter: 'Aman (Driver Profile #108)',
    address: 'Madhurawada Highway, near IT Hill',
    severity: 'Medium'
  },
  {
    id: 3,
    latitude: 17.9157,
    longitude: 83.3980,
    anomaly_type: 'pothole',
    confidence: 0.91,
    timestamp: '2026-07-03 14:10',
    is_verified: true,
    status: 'verified',
    reporter: 'Rohit (Driver Profile #332)',
    address: 'Anandapuram Junction Bypass',
    severity: 'Critical'
  },
  {
    id: 4,
    latitude: 17.9310,
    longitude: 83.4289,
    anomaly_type: 'crack',
    confidence: 0.65,
    timestamp: '2026-07-03 14:12',
    is_verified: true,
    status: 'resolved',
    reporter: 'Sita (System Audit)',
    address: 'Tagarapuvalasa Bridge Road',
    severity: 'Low'
  }
];

// Helper to map coordinates to SVG space (380x320 viewport)
const mapCoordsToSvg = (lat, lng) => {
  // Bounding boxes coordinates for Visakhapatnam to Vizianagaram Corridor
  // Latitude: 18.25 (North) to 17.55 (South)
  // Longitude: 83.00 (West) to 83.60 (East)
  const latStart = 18.25;
  const latEnd = 17.55;
  const lngStart = 83.00;
  const lngEnd = 83.60;

  const x = ((lng - lngStart) / (lngEnd - lngStart)) * 340 + 20;
  const y = ((latStart - lat) / (latStart - latEnd)) * 280 + 20;

  return { x, y };
};

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'https://secret.webarcade.in';

export default function App() {
  const [reports, setReports] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [activeTab, setActiveTab] = useState('Dashboard');
  const [statusFilter, setStatusFilter] = useState('ALL');
  
  const canvasRef = useRef(null);
  
  const selectedReport = reports.find(r => r.id === selectedId);

  const mapRef = useRef(null);
  const markersRef = useRef({});

  // Fetch Reports from backend API on mount
  useEffect(() => {
    fetch(`${API_BASE_URL}/api/v1/reports/`)
      .then(res => res.json())
      .then(data => {
        const formatted = data.map(r => ({
          ...r,
          reporter: r.reporter_name || 'System Audit',
          timestamp: r.timestamp.replace('T', ' ').substring(0, 16)
        }));
        setReports(formatted);
        if (formatted.length > 0) {
          setSelectedId(formatted[0].id);
        }
      })
      .catch(err => {
        console.error('Error fetching reports from backend, falling back to mock data:', err);
        // Clean fallback
        setReports([]);
      });
  }, []);

  // Initialize Leaflet Map
  useEffect(() => {
    if (!window.L) return;

    if (!mapRef.current) {
      const map = window.L.map('map', {
        zoomControl: true,
        attributionControl: false
      }).setView([17.92, 83.36], 10);

      window.L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19
      }).addTo(map);

      mapRef.current = map;

      // Add a line representing the Visakhapatnam-Vizianagaram corridor route
      const routeCoords = [
        [17.7290, 83.3087], // Visakhapatnam RTC Complex
        [17.8176, 83.3488], // Madhurawada
        [17.9157, 83.3980], // Anandapuram
        [17.9310, 83.4289], // Tagarapuvalasa
        [18.1124, 83.4024], // Vizianagaram
      ];

      window.L.polyline(routeCoords, {
        color: '#6366f1',
        weight: 4,
        opacity: 0.6,
        dashArray: '8, 6'
      }).addTo(map);
    }
  }, []);

  // Update Markers when reports or filters change
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !window.L) return;

    // Clear existing markers if any
    if (map._markerGroup) {
      map._markerGroup.clearLayers();
    } else {
      map._markerGroup = window.L.layerGroup().addTo(map);
    }

    markersRef.current = {};

    reports.forEach(r => {
      // Apply status filter matching the list view
      if (statusFilter !== 'ALL' && r.status !== statusFilter.toLowerCase()) return;

      let markerColor = '#f59e0b'; // Pending
      if (r.status === 'verified') markerColor = '#10b981'; // Verified
      if (r.status === 'resolved') markerColor = '#6b7280'; // Resolved

      const icon = window.L.divIcon({
        className: 'custom-map-pin',
        html: `<div style="
          width: 14px; 
          height: 14px; 
          background-color: ${markerColor}; 
          border: 2px solid #0d121f; 
          border-radius: 50%;
          box-shadow: 0 0 10px ${markerColor};
          transform: translate(-50%, -50%);
        "></div>`,
        iconSize: [14, 14],
        iconAnchor: [7, 7]
      });

      const marker = window.L.marker([r.latitude, r.longitude], { icon })
        .addTo(map._markerGroup)
        .on('click', () => {
          setSelectedId(r.id);
        });

      marker.bindPopup(`
        <div style="font-family: 'Inter', sans-serif; color: #ffffff;">
          <b style="color: #6366f1; font-size: 13px; text-transform: uppercase;">${r.anomaly_type}</b><br>
          <span style="font-size: 12px; opacity: 0.8;">${r.address}</span><br>
          <span style="font-size: 11px; opacity: 0.6;">Confidence: ${(r.confidence * 100).toFixed(0)}%</span>
        </div>
      `);

      markersRef.current[r.id] = marker;
    });
  }, [reports, statusFilter]);

  // Pan map dynamically when selectedReport changes
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !selectedReport) return;

    map.setView([selectedReport.latitude, selectedReport.longitude], 12.5, {
      animate: true,
      duration: 0.8
    });

    const marker = markersRef.current[selectedReport.id];
    if (marker) {
      marker.openPopup();
    }
  }, [selectedId, selectedReport]);

  // Statistics calculations
  const totalReports = reports.length;
  const verifiedHazards = reports.filter(r => r.status === 'verified').length;
  const resolvedAnomalies = reports.filter(r => r.status === 'resolved').length;
  const pendingReports = reports.filter(r => r.status === 'pending').length;

  const countPotholes = reports.filter(r => r.anomaly_type === 'pothole').length;
  const countCracks = reports.filter(r => r.anomaly_type === 'crack').length;

  // Repaint simulated evidence image when selected report changes
  useEffect(() => {
    if (!selectedReport || !canvasRef.current) return;
    
    const ctx = canvasRef.current.getContext('2d');
    const width = canvasRef.current.width;
    const height = canvasRef.current.height;

    // Draw asphalt background texture
    ctx.fillStyle = '#242a38';
    ctx.fillRect(0, 0, width, height);

    // Draw subtle road lane line
    ctx.strokeStyle = 'rgba(245, 245, 245, 0.15)';
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.setLineDash([12, 12]);
    ctx.moveTo(width / 2, 0);
    ctx.lineTo(width / 2, height);
    ctx.stroke();
    ctx.setLineDash([]); // Reset

    // Draw custom anomaly based on type
    if (selectedReport.anomaly_type === 'pothole') {
      // Draw pothole crater (concentric oval rings)
      const grad = ctx.createRadialGradient(width / 2, height / 2, 5, width / 2, height / 2, 50);
      grad.addColorStop(0, '#090d16');
      grad.addColorStop(0.5, '#1e2430');
      grad.addColorStop(1, '#242a38');
      ctx.fillStyle = grad;
      
      ctx.beginPath();
      ctx.ellipse(width / 2, height / 2, 55, 38, 0, 0, 2 * Math.PI);
      ctx.fill();

      // Jagged pothole rim
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.4)';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.ellipse(width / 2, height / 2, 53, 37, 0, 0, 2 * Math.PI);
      ctx.stroke();

      // Inner depth cracks
      ctx.strokeStyle = '#05070a';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(width / 2 - 20, height / 2 - 5);
      ctx.lineTo(width / 2 + 10, height / 2 + 8);
      ctx.moveTo(width / 2 - 10, height / 2 + 10);
      ctx.lineTo(width / 2 + 15, height / 2 - 8);
      ctx.stroke();
    } else {
      // Draw asphalt fissures (jagged lines representing cracks)
      ctx.strokeStyle = '#080d16';
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(40, height / 2 - 20);
      ctx.lineTo(100, height / 2 + 10);
      ctx.lineTo(140, height / 2 - 15);
      ctx.lineTo(200, height / 2 + 30);
      ctx.lineTo(260, height / 2 + 5);
      ctx.stroke();

      // Sub-cracks branches
      ctx.strokeStyle = '#0d131f';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(100, height / 2 + 10);
      ctx.lineTo(120, height / 2 + 40);
      ctx.moveTo(200, height / 2 + 30);
      ctx.lineTo(220, height / 2 - 20);
      ctx.stroke();
    }

    // Overlay AI bounding box visualization on top
    ctx.strokeStyle = selectedReport.anomaly_type === 'pothole' ? '#f59e0b' : '#06b6d4';
    ctx.lineWidth = 2;
    ctx.strokeRect(width / 2 - 70, height / 2 - 50, 140, 100);

    // Box Label text
    ctx.fillStyle = selectedReport.anomaly_type === 'pothole' ? '#f59e0b' : '#06b6d4';
    ctx.font = 'bold 11px Inter';
    ctx.fillRect(width / 2 - 70, height / 2 - 64, 90, 14);
    ctx.fillStyle = '#000000';
    ctx.fillText(
      `${selectedReport.anomaly_type.toUpperCase()} ${(selectedReport.confidence * 100).toFixed(0)}%`,
      width / 2 - 66,
      height / 2 - 53
    );
  }, [selectedId, selectedReport]);

  // Handle Approve action
  const handleApprove = () => {
    fetch(`${API_BASE_URL}/api/v1/verification/verify/${selectedId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        is_verified: true,
        status: 'verified'
      })
    })
      .then(res => {
        if (!res.ok) throw new Error('API failed');
        return res.json();
      })
      .then(() => {
        setReports(prev =>
          prev.map(r => (r.id === selectedId ? { ...r, is_verified: true, status: 'verified' } : r))
        );
      })
      .catch(err => {
        console.error('Error approving report:', err);
        // Fallback
        setReports(prev =>
          prev.map(r => (r.id === selectedId ? { ...r, is_verified: true, status: 'verified' } : r))
        );
      });
  };

  // Handle Reject action
  const handleReject = () => {
    fetch(`${API_BASE_URL}/api/v1/reports/${selectedId}`, {
      method: 'DELETE'
    })
      .then(res => {
        if (!res.ok) throw new Error('API failed');
        return res.json();
      })
      .then(() => {
        setReports(prev => prev.filter(r => r.id !== selectedId));
        const remaining = reports.filter(r => r.id !== selectedId);
        if (remaining.length > 0) {
          setSelectedId(remaining[0].id);
        } else {
          setSelectedId(null);
        }
      })
      .catch(err => {
        console.error('Error rejecting report:', err);
        // Fallback
        setReports(prev => prev.filter(r => r.id !== selectedId));
        const remaining = reports.filter(r => r.id !== selectedId);
        if (remaining.length > 0) {
          setSelectedId(remaining[0].id);
        } else {
          setSelectedId(null);
        }
      });
  };

  // Handle Resolve action
  const handleResolve = () => {
    fetch(`${API_BASE_URL}/api/v1/verification/verify/${selectedId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        is_verified: true,
        status: 'resolved'
      })
    })
      .then(res => {
        if (!res.ok) throw new Error('API failed');
        return res.json();
      })
      .then(() => {
        setReports(prev =>
          prev.map(r => (r.id === selectedId ? { ...r, status: 'resolved' } : r))
        );
      })
      .catch(err => {
        console.error('Error resolving report:', err);
        // Fallback
        setReports(prev =>
          prev.map(r => (r.id === selectedId ? { ...r, status: 'resolved' } : r))
        );
      });
  };

  // Filtered reports
  const filteredReports = reports.filter(r => {
    if (statusFilter === 'ALL') return true;
    return r.status === statusFilter.toLowerCase();
  });

  return (
    <div className="app-container">
      {/* 1. Sidebar */}
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-icon">🛣️</span>
          <span className="brand-name">RoadSense AI</span>
        </div>
        <ul className="nav-menu">
          <li
            className={`nav-item ${activeTab === 'Dashboard' ? 'active' : ''}`}
            onClick={() => setActiveTab('Dashboard')}
          >
            📊 Dashboard
          </li>
          <li
            className={`nav-item ${activeTab === 'Reports' ? 'active' : ''}`}
            onClick={() => setActiveTab('Reports')}
          >
            🚨 Anomaly Queue
          </li>
        </ul>
      </aside>

      {/* 2. Main Workspace */}
      <main className="main-content">
        <header className="header glass-header">
          <h2>Road Quality Control Panel</h2>
          <div style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
            Status: <span style={{ color: 'var(--color-success)', fontWeight: '600' }}>Active Monitoring</span>
          </div>
        </header>

        <div className="dashboard-view">
          {/* A. Statistics Widgets Grid */}
          <section className="stats-grid">
            <div className="stat-card total glass">
              <div className="stat-label">Total Logs</div>
              <div className="stat-value">{totalReports}</div>
            </div>
            <div className="stat-card verified glass">
              <div className="stat-label">Verified Hazards</div>
              <div className="stat-value">{verifiedHazards}</div>
            </div>
            <div className="stat-card potholes glass">
              <div className="stat-label">Potholes</div>
              <div className="stat-value">{countPotholes}</div>
            </div>
            <div className="stat-card cracks glass">
              <div className="stat-label">Road Cracks</div>
              <div className="stat-value">{countCracks}</div>
            </div>
          </section>

          {/* B. Dynamic Split Panels Layout */}
          <section className="dashboard-body">
            
            {/* LEFT COLUMN: Map & Reports Table */}
            <div className="left-panel">
              {/* Map Card */}
              <div className="map-card glass">
                <div className="map-header">
                  <h3>Interactive Vector Map</h3>
                  <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    Visakhapatnam ➔ Vizianagaram NH 16 Corridor Route
                  </span>
                </div>
                
                {/* Leaflet OpenStreetMap Container */}
                <div id="map" className="svg-map-container"></div>
              </div>

              {/* Reports List table Card */}
              <div className="list-card glass">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <h3>Anomaly Queue</h3>
                  {/* Status Filters */}
                  <div style={{ display: 'flex', gap: '8px' }}>
                    {['ALL', 'PENDING', 'VERIFIED', 'RESOLVED'].map(f => (
                      <button
                        key={f}
                        onClick={() => setStatusFilter(f)}
                        style={{
                          padding: '4px 8px',
                          fontSize: '11px',
                          fontWeight: '600',
                          backgroundColor: statusFilter === f ? 'var(--color-primary)' : 'rgba(255,255,255,0.05)',
                          color: '#ffffff',
                          border: 'none',
                          borderRadius: '4px',
                          cursor: 'pointer'
                        }}
                      >
                        {f}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="table-container">
                  <table className="reports-table">
                    <thead>
                      <tr>
                        <th>Type</th>
                        <th>Location</th>
                        <th>Confidence</th>
                        <th>Status</th>
                        <th>Logged At</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredReports.map(r => (
                        <tr
                          key={r.id}
                          className={r.id === selectedId ? 'selected' : ''}
                          onClick={() => setSelectedId(r.id)}
                        >
                          <td>
                            <span className={`badge ${r.anomaly_type}`}>
                              {r.anomaly_type}
                            </span>
                          </td>
                          <td>{r.address}</td>
                          <td>{(r.confidence * 100).toFixed(0)}%</td>
                          <td>
                            <span className="status-indicator">
                              <span className={`status-dot ${r.status}`} />
                              <span style={{ textTransform: 'capitalize' }}>{r.status}</span>
                            </span>
                          </td>
                          <td style={{ color: 'var(--text-secondary)' }}>{r.timestamp.split(' ')[1]}</td>
                        </tr>
                      ))}
                      {filteredReports.length === 0 && (
                        <tr>
                          <td colSpan="5" style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px' }}>
                            No reports matching this filter.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            {/* RIGHT COLUMN: Evidence Inspector Panel */}
            <div className="right-panel">
              <div className="details-card glass">
                {selectedReport ? (
                  <>
                    <h3>Evidence Inspector</h3>
                    
                    {/* Image Viewer (Interactive Canvas Drawing) */}
                    <div className="image-viewer-container">
                      <canvas
                        ref={canvasRef}
                        width={300}
                        height={220}
                        style={{ width: '100%', height: '100%', display: 'block' }}
                      />
                      <div className="confidence-overlay">
                        Conf: {(selectedReport.confidence * 100).toFixed(0)}%
                      </div>
                    </div>

                    {/* Metadata details */}
                    <div className="inspector-info">
                      <div className="info-row">
                        <span className="info-label">Severity Level</span>
                        <span className="info-value" style={{ 
                          color: selectedReport.severity === 'Critical' || selectedReport.severity === 'High' 
                              ? 'var(--color-error)' 
                              : 'var(--text-primary)' 
                        }}>{selectedReport.severity}</span>
                      </div>
                      <div className="info-row">
                        <span className="info-label">Coordinates</span>
                        <span className="info-value">{selectedReport.latitude.toFixed(5)}, {selectedReport.longitude.toFixed(5)}</span>
                      </div>
                      <div className="info-row">
                        <span className="info-label">Address</span>
                        <span className="info-value">{selectedReport.address}</span>
                      </div>
                      <div className="info-row">
                        <span className="info-label">Logged By</span>
                        <span className="info-value">{selectedReport.reporter}</span>
                      </div>
                      <div className="info-row">
                        <span className="info-label">Timestamp</span>
                        <span className="info-value">{selectedReport.timestamp}</span>
                      </div>
                    </div>

                    <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '4px 0' }} />

                    {/* Administrative Controls */}
                    <div className="action-grid">
                      <button
                        className="btn btn-approve"
                        onClick={handleApprove}
                        disabled={selectedReport.status === 'verified'}
                      >
                        {selectedReport.status === 'verified' ? '✓ Verified' : 'Approve Anomaly'}
                      </button>
                      <button
                        className="btn btn-reject"
                        onClick={handleReject}
                      >
                        Reject & Hide
                      </button>
                      <button
                        className="btn btn-resolve"
                        onClick={handleResolve}
                        disabled={selectedReport.status === 'resolved'}
                      >
                        {selectedReport.status === 'resolved' ? '✓ Resolved' : 'Mark Anomaly as Resolved'}
                      </button>
                    </div>
                  </>
                ) : (
                  <div className="empty-details">
                    <span className="empty-details-icon">🔍</span>
                    <span>Select an anomaly from the queue or map to inspect evidence.</span>
                  </div>
                )}
              </div>
            </div>

          </section>
        </div>
      </main>
    </div>
  );
}
