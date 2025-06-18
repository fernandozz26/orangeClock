import React, { useState } from "react";
import AlarmaList from "./components/AlarmaList";
import AlarmaForm from "./components/AlarmaForm";
import AudioPanel from "./components/AudioPanel";
import { FaClock, FaMusic, FaListUl, FaHourglassHalf } from "react-icons/fa";

const App = () => {
  const [menuActivo, setMenuActivo] = useState("alarmas");
  const [alarmaEditada, setAlarmaEditada] = useState(null);
  const [actualizarLista, setActualizarLista] = useState(false);
  const [alarmasProximas, setAlarmasProximas] = useState([]);
  const [cargandoProximas, setCargandoProximas] = useState(false);
  const [errorProximas, setErrorProximas] = useState("");

  // Consulta alarmas próximas a ejecutarse en las próximas 24 horas
  const consultarAlarmasProximas = async () => {
    setCargandoProximas(true);
    setErrorProximas("");
    try {
      const res = await fetch("/api/alarmas_proximas");
      if (!res.ok) throw new Error("Error al consultar alarmas próximas");
      const data = await res.json();
      setAlarmasProximas(data.alarmas_proximas || []);
    } catch (e) {
      setErrorProximas("No se pudieron consultar las alarmas próximas");
      setAlarmasProximas([]);
    } finally {
      setCargandoProximas(false);
    }
  };

  const manejarEdicion = (alarma) => {
    setAlarmaEditada(alarma);
    setMenuActivo("crear"); // Cambia a la sección de crear para edición
  };

  const manejarGuardado = () => {
    setAlarmaEditada(null);
    setActualizarLista(!actualizarLista);
  };

  // Traducción de días de la semana a español para alarmas próximas
  const DIAS_SEMANA_ES = {
    mon: "Lunes",
    tue: "Martes",
    wed: "Miércoles",
    thu: "Jueves",
    fri: "Viernes",
    sat: "Sábado",
    sun: "Domingo"
  };
  function traducirRepeticion(repeticion) {
    if (!repeticion) return null;
    const dias = repeticion.split("-");
    if (dias.every(d => DIAS_SEMANA_ES[d])) {
      return dias.map(d => DIAS_SEMANA_ES[d]).join("-");
    }
    return repeticion;
  }

  return (
    <div className="container py-4">
      <h1 className="text-center mb-4">Gestor de Alarmas</h1>
      {/* Menú principal con estilo uniforme y tamaño más pequeño */}
      <div className="d-flex flex-wrap justify-content-center mb-4 gap-2 gap-md-3">
        <button
          className={`btn btn-outline-primary d-flex align-items-center gap-2${
            menuActivo === "audios" ? " active" : ""
          }`}
          style={{ minWidth: 140, fontWeight: 600, fontSize: 18, padding: '8px 18px' }}
          onClick={() => setMenuActivo("audios")}
        >
          <FaMusic /> Audios
        </button>
        <button
          className={`btn btn-outline-primary d-flex align-items-center gap-2${
            menuActivo === "crear" ? " active" : ""
          }`}
          style={{ minWidth: 140, fontWeight: 600, fontSize: 18, padding: '8px 18px' }}
          onClick={() => {
            setMenuActivo("crear");
            setAlarmaEditada({});
          }}
        >
          <FaClock /> Crear Alarma
        </button>
        <button
          className={`btn btn-outline-primary d-flex align-items-center gap-2${
            menuActivo === "alarmas" ? " active" : ""
          }`}
          style={{ minWidth: 170, fontWeight: 600, fontSize: 18, padding: '8px 18px' }}
          onClick={() => {
            setMenuActivo("alarmas");
            setAlarmaEditada(null);
          }}
        >
          <FaListUl /> Todas las alarmas
        </button>
        <button
          className={`btn btn-outline-primary d-flex align-items-center gap-2${
            menuActivo === "proximas" ? " active" : ""
          }`}
          style={{ minWidth: 170, fontWeight: 600, fontSize: 18, padding: '8px 18px' }}
          onClick={() => {
            setMenuActivo("proximas");
            consultarAlarmasProximas();
          }}
        >
          <FaHourglassHalf /> Alarmas próximas
        </button>
      </div>
      {/* Paneles según menú */}
      <div className="d-flex justify-content-center">
        {menuActivo === "audios" && (
          <div style={{ minWidth: 350, maxWidth: 500 }}>
            <AudioPanel />
          </div>
        )}
        {menuActivo === "crear" && (
          <div style={{ minWidth: 350, maxWidth: 700 }}>
            <AlarmaForm
              alarmaSeleccionada={alarmaEditada}
              onSave={manejarGuardado}
              onCancel={() => {
                setAlarmaEditada(null);
                setMenuActivo("alarmas");
              }}
            />
          </div>
        )}
        {menuActivo === "alarmas" && !alarmaEditada && (
          <div style={{ minWidth: 350, maxWidth: 700 }}>
            <AlarmaList onEdit={manejarEdicion} key={actualizarLista} />
          </div>
        )}
        {menuActivo === "proximas" && (
          <div style={{ minWidth: 350, maxWidth: 700 }}>
            <div className="card p-4">
              <h4 className="mb-3 text-center">Alarmas próximas a ejecutarse (24h)</h4>
              {cargandoProximas ? (
                <div className="text-center text-muted">Cargando...</div>
              ) : errorProximas ? (
                <div className="text-center text-danger">{errorProximas}</div>
              ) : alarmasProximas.length === 0 ? (
                <div className="text-center text-muted">No hay alarmas próximas.</div>
              ) : (
                <ul className="list-group">
                  {alarmasProximas.map((a) => (
                    <li key={a.id} className="list-group-item d-flex flex-column flex-md-row justify-content-between align-items-center">
                      <span><b>{a.hora}</b> {a.fecha ? `- ${a.fecha}` : ""} {a.repeticion ? `- ${traducirRepeticion(a.repeticion)}` : ""}</span>
                      <span className="badge bg-primary">{a.audio}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default App;