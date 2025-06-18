import React, { useState, useEffect } from "react";
import axios from "axios";
import Loader from "./Loader";
import { FaCheck, FaCalendarDay, FaCalendarAlt, FaRedo, FaSave, FaTimes, FaPlay, FaRegFileAudio } from "react-icons/fa";

const DIAS_SEMANA = [
  { label: "Lunes", value: "mon" },
  { label: "Martes", value: "tue" },
  { label: "Miércoles", value: "wed" },
  { label: "Jueves", value: "thu" },
  { label: "Viernes", value: "fri" },
  { label: "Sábado", value: "sat" },
  { label: "Domingo", value: "sun" },
];

const AlarmaForm = ({ alarmaSeleccionada, onSave, onCancel }) => {
  // Estados del formulario
  const [audio, setAudio] = useState(alarmaSeleccionada ? alarmaSeleccionada.audio : "");
  const [modoRepeticion, setModoRepeticion] = useState(() => {
    if (!alarmaSeleccionada) return "semana";
    if (alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^(mon|tue|wed|thu|fri|sat|sun)(-(mon|tue|wed|thu|fri|sat|sun))*$/)) {
      return "semana";
    } else if (alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^\d{2}-\d{2}$/)) {
      return "anio";
    } else if (alarmaSeleccionada.fecha) {
      return "unica";
    }
    return "semana";
  });
  const [diasSeleccionados, setDiasSeleccionados] = useState(() =>
    alarmaSeleccionada && alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^(mon|tue|wed|thu|fri|sat|sun)(-(mon|tue|wed|thu|fri|sat|sun))*$/)
      ? alarmaSeleccionada.repeticion.split("-")
      : []
  );
  const [fechaAnio, setFechaAnio] = useState(() =>
    alarmaSeleccionada && alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^\d{2}-\d{2}$/)
      ? alarmaSeleccionada.repeticion
      : ""
  );
  const [fechaUnica, setFechaUnica] = useState(() =>
    alarmaSeleccionada && alarmaSeleccionada.fecha ? alarmaSeleccionada.fecha : ""
  );
  const [hora, setHora] = useState(() =>
    alarmaSeleccionada && alarmaSeleccionada.hora ? alarmaSeleccionada.hora : ""
  );
  const [audios, setAudios] = useState([]);
  const [audioPreview, setAudioPreview] = useState(null);
  const [errorAlarma, setErrorAlarma] = useState("");
  const [loading, setLoading] = useState(false);

  // Obtener lista de audios al cargar el formulario
  useEffect(() => {
    const fetchAudios = async () => {
      setLoading(true);
      try {
        const res = await axios.get("/api/audios");
        setAudios(res.data);
      } catch (err) {
        setAudios([]);
      } finally {
        setLoading(false);
      }
    };
    fetchAudios();
  }, []);

  // Sincronizar los estados cuando cambia alarmaSeleccionada
  useEffect(() => {
    if (!alarmaSeleccionada || Object.keys(alarmaSeleccionada).length === 0) {
      setAudio("");
      setModoRepeticion("semana");
      setDiasSeleccionados([]);
      setFechaAnio("");
      setFechaUnica("");
      setHora("");
      return;
    }
    setAudio(alarmaSeleccionada.audio || "");
    if (alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^(mon|tue|wed|thu|fri|sat|sun)(-(mon|tue|wed|thu|fri|sat|sun))*$/)) {
      setModoRepeticion("semana");
      setDiasSeleccionados(alarmaSeleccionada.repeticion.split("-"));
      setFechaAnio("");
      setFechaUnica("");
    } else if (alarmaSeleccionada.repeticion && alarmaSeleccionada.repeticion.match(/^\d{2}-\d{2}$/)) {
      setModoRepeticion("anio");
      setFechaAnio(alarmaSeleccionada.repeticion);
      setDiasSeleccionados([]);
      setFechaUnica("");
    } else if (alarmaSeleccionada.fecha) {
      setModoRepeticion("unica");
      setFechaUnica(alarmaSeleccionada.fecha);
      setDiasSeleccionados([]);
      setFechaAnio("");
    } else {
      setModoRepeticion("semana");
      setDiasSeleccionados([]);
      setFechaAnio("");
      setFechaUnica("");
    }
    setHora(alarmaSeleccionada.hora || "");
  }, [alarmaSeleccionada]);

  const guardarAlarma = async (e) => {
    e.preventDefault();
    setErrorAlarma("");
    setLoading(true);
    let repeticion = null;
    let fecha = null;
    if (modoRepeticion === "semana" && diasSeleccionados.length > 0) {
      repeticion = diasSeleccionados.join("-");
    } else if (modoRepeticion === "anio" && fechaAnio) {
      repeticion = fechaAnio; // formato MM-DD
    } else if (modoRepeticion === "unica" && fechaUnica) {
      fecha = fechaUnica;
    }
    try {
      // Enviar solo el nombre del archivo
      const payload = { hora, audio, repeticion };
      if (fecha) payload.fecha = fecha;
      if (alarmaSeleccionada && alarmaSeleccionada.id) {
        await axios.put(`/api/editar_alarma/${alarmaSeleccionada.id}`, payload);
      } else {
        await axios.post("/api/crear_alarma", payload);
      }
      onSave();
    } catch (error) {
      if (error.response && error.response.data && error.response.data.error) {
        setErrorAlarma(error.response.data.error);
      } else {
        setErrorAlarma("Error al guardar la alarma");
      }
      console.error("Error al guardar la alarma:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleDiaSemana = (dia) => {
    setDiasSeleccionados((prev) =>
      prev.includes(dia) ? prev.filter((d) => d !== dia) : [...prev, dia]
    );
  };

  return (
    <>
      {loading && <Loader />}
      <form onSubmit={guardarAlarma} className="p-3 rounded bg-white shadow-sm w-100" style={{maxWidth: 600, margin: '0 auto'}}>
        <h2 className="mb-3 text-center">{alarmaSeleccionada ? "Editar Alarma" : "Nueva Alarma"}</h2>
        {errorAlarma && (
          <div className="alert alert-danger text-center" role="alert" style={{fontWeight:600, fontSize:17}}>
            {errorAlarma}
          </div>
        )}
        <div className="mb-3">
          <label className="form-label fw-bold fs-5 text-primary">Audio:</label>
          <div className="row g-2 align-items-center">
            <div className="col-12 col-md-8">
              <div className="input-group shadow rounded border border-info bg-white p-2 align-items-center" style={{minHeight: 60}}>
                <span className="input-group-text" style={{fontSize: 22, background: '#0d6efd', color: '#fff', border: 'none'}} title="Menú para seleccionar audio">
                  <FaRegFileAudio style={{color: '#fff'}} />
                </span>
                <select
                  className="form-select border-0 text-dark fw-semibold fs-6"
                  value={audio}
                  onChange={(e) => {
                    setAudio(e.target.value);
                    setAudioPreview(null); // Limpiar preview al cambiar audio
                  }}
                  required
                  aria-label="Seleccionar audio para la alarma"
                  style={{ minHeight: 45, boxShadow: 'none', background: '#f4f4f4', borderRadius: 8, border: '1px solid #adb5bd', cursor: 'pointer' }}
                >
                  <option value="" disabled>Selecciona un audio...</option>
                  {audios.map((a) => (
                    <option key={a.ruta} value={a.ruta}>
                      {a.nombre}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="col-12 col-md-4 d-flex justify-content-center justify-content-md-start">
              {audio && (
                <button
                  type="button"
                  className="btn btn-primary btn-lg d-flex align-items-center px-4 py-2 shadow border-0"
                  onClick={() => setAudioPreview(audio)}
                  style={{ fontWeight: 700, fontSize: 18, borderRadius: 8 }}
                >
                  <FaPlay className="me-2" /> Escuchar
                </button>
              )}
            </div>
          </div>
          {audioPreview && (
            <div className="mt-3 p-2 bg-light border border-info rounded shadow-sm">
              <audio controls autoPlay className="w-100" onEnded={() => setAudioPreview(null)}>
                <source src={`/api/audios/${audioPreview}`} />
                Tu navegador no soporta el elemento de audio.
              </audio>
              <div className="text-center text-info mt-1" style={{fontWeight: 500}}>
                Previsualizando: <span className="fw-bold">{audioPreview}</span>
              </div>
            </div>
          )}
        </div>
        <div className="mb-3">
          <label className="form-label fw-bold fs-5 text-primary">Repetición:</label>
          <div className="mb-3 d-flex flex-wrap gap-2 justify-content-center">
            <button
              type="button"
              className={`btn btn-outline-primary d-flex align-items-center gap-2${modoRepeticion === "semana" ? " active text-white bg-primary border-primary" : ""}`}
              onClick={() => setModoRepeticion("semana")}
              style={{ fontWeight: 600, borderWidth: 2, borderRadius: 8, fontSize: 16, padding: '8px 18px', minWidth: 170 }}
            >
              <FaRedo /> Por semana
            </button>
            <button
              type="button"
              className={`btn btn-outline-dark d-flex align-items-center gap-2${modoRepeticion === "anio" ? " active text-white bg-dark border-dark" : ""}`}
              onClick={() => setModoRepeticion("anio")}
              style={{ fontWeight: 600, borderWidth: 2, borderRadius: 8, fontSize: 16, padding: '8px 18px', minWidth: 170 }}
            >
              <FaCalendarAlt /> Por año
            </button>
            <button
              type="button"
              className={`btn btn-outline-secondary d-flex align-items-center gap-2${modoRepeticion === "unica" ? " active text-white bg-secondary border-secondary" : ""}`}
              onClick={() => setModoRepeticion("unica")}
              style={{ fontWeight: 600, borderWidth: 2, borderRadius: 8, fontSize: 16, padding: '8px 18px', minWidth: 170 }}
            >
              <FaCalendarDay /> Única vez
            </button>
          </div>
          {/* Opciones según modo */}
          {modoRepeticion === "semana" && (
            <div className="mb-2">
              <div className="mb-2 d-flex flex-wrap gap-3 justify-content-center">
                {DIAS_SEMANA.map((dia, idx) => (
                  <button
                    type="button"
                    key={dia.value}
                    className={`btn btn-primary btn-lg d-flex align-items-center gap-2${diasSeleccionados.includes(dia.value) ? " active text-white" : " btn-outline-primary"}`}
                    style={{
                      minWidth: 120,
                      marginBottom: 10,
                      fontWeight: 700,
                      fontSize: 18,
                      borderWidth: 2,
                      borderRadius: 8,
                      color: diasSeleccionados.includes(dia.value) ? "#fff" : "#0d6efd",
                      backgroundColor: diasSeleccionados.includes(dia.value) ? "#0d6efd" : "#fff",
                      letterSpacing: 1
                    }}
                    onClick={() => handleDiaSemana(dia.value)}
                  >
                    {dia.label}
                    {diasSeleccionados.includes(dia.value) && <FaCheck className="ms-1" />}
                  </button>
                ))}
              </div>
              <div className="d-flex flex-column align-items-center mt-2">
                <input
                  type="time"
                  className="form-control form-control-lg border-primary text-center"
                  value={hora}
                  onChange={e => setHora(e.target.value)}
                  required={modoRepeticion === "semana"}
                  style={{fontSize: 22, maxWidth: 200, background: '#e7f3fa', fontWeight: 600, borderRadius: 8}}
                />
                <span className="ms-2 text-info" style={{ fontSize: 15, fontWeight: 500 }}>(elige la hora para los días seleccionados)</span>
              </div>
            </div>
          )}
          {modoRepeticion === "anio" && (
            <div className="mb-2 row g-2 align-items-center justify-content-center">
              <div className="col-12 col-md-6">
                <input
                  type="date"
                  className="form-control form-control-lg border-dark text-center"
                  value={fechaAnio ? `${new Date().getFullYear()}-${fechaAnio}` : ""}
                  onChange={(e) => {
                    const val = e.target.value;
                    if (val) {
                      const [yyyy, mm, dd] = val.split("-");
                      setFechaAnio(`${mm}-${dd}`);
                    } else {
                      setFechaAnio("");
                    }
                  }}
                  placeholder="MM-DD"
                  required={modoRepeticion === "anio"}
                  style={{fontSize: 22, background: '#f4f4f4', fontWeight: 600, borderRadius: 8, color: '#222', borderColor: '#444'}}
                />
              </div>
              <div className="col-12 col-md-6">
                <input
                  type="time"
                  className="form-control form-control-lg border-dark text-center"
                  value={hora}
                  onChange={e => setHora(e.target.value)}
                  required={modoRepeticion === "anio"}
                  style={{fontSize: 22, background: '#f4f4f4', fontWeight: 600, borderRadius: 8, color: '#222', borderColor: '#444'}}
                />
              </div>
              <span className="ms-2 text-dark" style={{ fontSize: 15, fontWeight: 500 }}>(elige un día y hora, se repetirá cada año)</span>
            </div>
          )}
          {modoRepeticion === "unica" && (
            <div className="mb-2 row g-2 align-items-center justify-content-center">
              <div className="col-12 col-md-6">
                <input
                  type="date"
                  className="form-control form-control-lg border-success text-center"
                  value={fechaUnica}
                  onChange={e => setFechaUnica(e.target.value)}
                  required={modoRepeticion === "unica"}
                  style={{fontSize: 22, background: '#f4f4f4', fontWeight: 600, borderRadius: 8, color: '#222', borderColor: '#888'}}
                />
              </div>
              <div className="col-12 col-md-6">
                <input
                  type="time"
                  className="form-control form-control-lg border-success text-center"
                  value={hora}
                  onChange={e => setHora(e.target.value)}
                  required={modoRepeticion === "unica"}
                  style={{fontSize: 22, background: '#f4f4f4', fontWeight: 600, borderRadius: 8, color: '#222', borderColor: '#888'}}
                />
              </div>
              <span className="ms-2 text-dark" style={{ fontSize: 15, fontWeight: 500 }}>(elige una fecha y hora específica, la alarma solo sonará una vez)</span>
            </div>
          )}
        </div>
        <div className="d-flex flex-column flex-md-row justify-content-center gap-3 mt-4">
          <button type="submit" className="btn btn-primary btn-lg d-flex align-items-center gap-2 px-5 py-2 shadow" style={{fontWeight: 700, borderRadius: 8, fontSize: 20}}><FaSave /> Guardar</button>
          <button type="button" className="btn btn-danger btn-lg d-flex align-items-center gap-2 px-5 py-2 shadow" onClick={onCancel} style={{fontWeight: 700, borderRadius: 8, fontSize: 20}}><FaTimes /> Cancelar</button>
        </div>
      </form>
    </>
  );
};

export default AlarmaForm;