import React from "react";

const Loader = () => (
  <div style={{
    position: "fixed",
    top: 0, left: 0, right: 0, bottom: 0,
    background: "rgba(255,255,255,0.7)",
    zIndex: 9999,
    display: "flex",
    alignItems: "center",
    justifyContent: "center"
  }}>
    <div className="spinner-border text-primary" role="status" style={{width: 60, height: 60}}>
      <span className="visually-hidden">Cargando...</span>
    </div>
  </div>
);

export default Loader;
