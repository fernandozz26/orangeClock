import React, { useEffect, useState } from "react";
import axios from "axios";
import { FaEdit, FaTrash, FaCopy } from "react-icons/fa";

const PAGE_SIZE = 10;

// Traducción de días de la semana a español
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

const AlarmaList = ({ onEdit }) => {
  const [alarmas, setAlarmas] = useState([]);
  const [pagina, setPagina] = useState(1);

  // Obtener todas las alarmas programadas desde siempre (no solo próximas)
  useEffect(() => {
    const fetchAlarmas = async () => {
      try {
        const response = await axios.get("/api/consultar_alarmas");
        let alarmas = response.data.alarmas_programadas;
        setAlarmas(alarmas);
      } catch (error) {
        console.error("Error al obtener las alarmas:", error);
      }
    };
    fetchAlarmas();
  }, []);

  // Paginación
  const totalPaginas = Math.ceil(alarmas.length / PAGE_SIZE);
  const alarmasPagina = alarmas.slice((pagina - 1) * PAGE_SIZE, pagina * PAGE_SIZE);

  // Eliminar alarma
  const eliminarAlarma = async (id) => {
    try {
      await axios.delete(`/api/eliminar_alarma/${id}`);
      setAlarmas(alarmas.filter((alarma) => alarma.id !== id));
    } catch (error) {
      console.error("Error al eliminar la alarma:", error);
    }
  };

  return (
    <div className="card shadow-sm p-4 mb-4 bg-white rounded border-0 w-100" style={{maxWidth: 700, margin: '0 auto'}}>
      <h2 className="mb-3 text-center">Alarmas Programadas</h2>
      <ul className="list-group">
        {alarmasPagina.map((alarma) => (
          <li key={alarma.id} className="list-group-item d-flex flex-column flex-md-row align-items-start align-items-md-center justify-content-between gap-2">
            <div className="d-flex flex-column flex-md-row align-items-start align-items-md-center w-100">
              <span className="me-md-3 mb-2 mb-md-0">
                <b>{alarma.hora}</b> - {alarma.fecha && alarma.fecha !== 'None' ? alarma.fecha : (traducirRepeticion(alarma.repeticion) || "-")} - {alarma.audio}
              </span>
              <div className="d-flex flex-row flex-wrap gap-2 align-items-center w-100">
                <button className="btn btn-outline-primary btn-sm me-2 d-flex align-items-center gap-1" onClick={() => onEdit(alarma)} title="Editar">
                  <FaEdit /> <span className="d-none d-md-inline">Editar</span>
                </button>
                <button className="btn btn-outline-secondary btn-sm me-2 d-flex align-items-center gap-1" onClick={async () => {
                  const { id, ...nuevaAlarma } = alarma;
                  try {
                    await axios.post("/api/crear_alarma", nuevaAlarma);
                    const response = await axios.get("/api/consultar_alarmas");
                    let alarmas = response.data.alarmas_programadas;
                    setAlarmas(alarmas);
                  } catch (error) {
                    alert("Error al duplicar la alarma");
                  }
                }} title="Duplicar">
                  <FaCopy /> <span className="d-none d-md-inline">Duplicar</span>
                </button>
                <button className="btn btn-outline-danger btn-sm d-flex align-items-center gap-1" onClick={() => eliminarAlarma(alarma.id)} title="Eliminar">
                  <FaTrash /> <span className="d-none d-md-inline">Eliminar</span>
                </button>
              </div>
            </div>
          </li>
        ))}
      </ul>
      {/* Paginación */}
      {totalPaginas > 1 && (
        <nav className="mt-3">
          <ul className="pagination justify-content-center">
            <li className={`page-item${pagina === 1 ? " disabled" : ""}`}>
              <button className="page-link" onClick={() => setPagina(pagina - 1)}>&laquo;</button>
            </li>
            {Array.from({ length: totalPaginas }, (_, i) => (
              <li key={i+1} className={`page-item${pagina === i+1 ? " active" : ""}`}>
                <button className="page-link" onClick={() => setPagina(i+1)}>{i+1}</button>
              </li>
            ))}
            <li className={`page-item${pagina === totalPaginas ? " disabled" : ""}`}>
              <button className="page-link" onClick={() => setPagina(pagina + 1)}>&raquo;</button>
            </li>
          </ul>
        </nav>
      )}
    </div>
  );
};

export default AlarmaList;