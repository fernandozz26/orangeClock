import React, { useState, useEffect } from "react";
import axios from "axios";
import { FaMusic, FaPlay, FaTrash, FaEdit, FaRegFileAudio } from "react-icons/fa";

const AudioPanel = () => {
  const [audios, setAudios] = useState([]);
  const [file, setFile] = useState(null);
  const [nuevoNombre, setNuevoNombre] = useState("");
  const [audioPreview, setAudioPreview] = useState("");
  const [mensaje, setMensaje] = useState("");
  const [audioPreviewInput, setAudioPreviewInput] = useState("");
  const [mostrarPanel, setMostrarPanel] = useState(false);
  const [editandoNombre, setEditandoNombre] = useState("");

  const fetchAudios = async () => {
    try {
      const res = await axios.get("http://127.0.0.1:5000/audios");
      setAudios(res.data);
    } catch {
      setAudios([]);
    }
  };

  useEffect(() => {
    fetchAudios();
  }, []);

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!file) return;
    const formData = new FormData();
    formData.append("file", file);
    try {
      await axios.post("http://127.0.0.1:5000/audios", formData);
      setMensaje("Audio subido correctamente");
      setFile(null);
      fetchAudios();
    } catch (err) {
      if (err.response && err.response.data && err.response.data.error) {
        setMensaje("Error: " + err.response.data.error);
      } else {
        setMensaje("Error al subir el audio");
      }
    }
  };

  const handleDelete = async (ruta) => {
    const nombre = ruta.split("/").pop();
    try {
      await axios.delete(`http://127.0.0.1:5000/audios/${nombre}`);
      setMensaje("Audio eliminado");
      fetchAudios();
    } catch {
      setMensaje("Error al eliminar el audio");
    }
  };

  const handleRename = async (ruta, ext) => {
    const nombre = ruta.split("/").pop();
    if (!nuevoNombre || !nuevoNombre.trim()) {
      setMensaje("Debes ingresar un nuevo nombre válido");
      return;
    }
    const baseName = nuevoNombre.replace(/\.[^/.]+$/, "").trim();
    if (baseName === nombre.replace(ext, "")) {
      setMensaje("El nuevo nombre debe ser diferente al actual");
      return;
    }
    try {
      await axios.put(`http://127.0.0.1:5000/audios/${nombre}`, { nuevo_nombre: baseName });
      setMensaje("Audio renombrado");
      setNuevoNombre("");
      setEditandoNombre("");
      fetchAudios();
    } catch (err) {
      if (err.response && err.response.data && err.response.data.error) {
        setMensaje("Error: " + err.response.data.error);
      } else {
        setMensaje("Error al renombrar el audio");
      }
    }
  };

  return (
    <div style={{maxWidth: 600, margin: '0 auto'}}>
      {/* Panel de gestión de audios SIEMPRE visible, sin botón extra */}
      <div id="panel-audio" className="card shadow-sm p-4 mb-4 bg-white rounded border-0 w-100">
        <h3 className="mb-3 text-center">Gestión de Audios</h3>
        <form onSubmit={handleUpload} className="row g-2 align-items-center mb-3 flex-wrap">
          <div className="col-12 mb-2">
            <label htmlFor="audio-upload" className="form-label w-100 m-0 p-0">
              <input
                id="audio-upload"
                type="file"
                accept="audio/*"
                className="visually-hidden"
                onChange={e => setFile(e.target.files[0])}
              />
              <span
                className="btn btn-outline-primary w-100 d-flex align-items-center justify-content-center gap-2"
                style={{
                  height: 54,
                  fontWeight: 700,
                  fontSize: 18,
                  borderRadius: 12,
                  borderWidth: 2,
                  background: file ? '#e7f3fa' : '#f8fbff',
                  boxShadow: file ? '0 2px 8px #b6e0fc' : '0 2px 8px #e3eaf3',
                  transition: 'background 0.2s, color 0.2s',
                  color: file ? '#0d6efd' : '#495057',
                  cursor: 'pointer',
                  outline: 'none',
                  borderColor: file ? '#0d6efd' : '#b6c6d6',
                  letterSpacing: 0.2
                }}
              >
                <FaRegFileAudio style={{fontSize: 26, color: file ? '#0d6efd' : '#6c757d'}} />
                <span style={{whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 220, fontSize: 17, fontWeight: 700}}>
                  {file ? file.name : 'Seleccionar archivo de audio'}
                </span>
              </span>
            </label>
          </div>
          <div className="col-12 d-grid">
            <button type="submit" className="btn btn-primary btn-lg w-100" style={{height: 54, fontWeight: 700, fontSize: 20, borderRadius: 12}}>
              Subir audio
            </button>
          </div>
        </form>
        {mensaje && <div className="alert alert-info py-2 mb-3 text-center">{mensaje}</div>}
        <ul className="list-group">
          {audios.map(a => (
            <li key={a.ruta} className="list-group-item">
              <div className="w-100">
                <span className="fw-bold d-block text-break mb-2" style={{wordBreak: 'break-all'}} title={a.ruta}>{a.nombre}</span>
                <div className="d-flex flex-row flex-nowrap gap-3 align-items-center justify-content-start w-100 mb-2">
                  <button className="btn btn-outline-primary btn-lg d-flex align-items-center gap-2 px-4 py-2 shadow border-0" onClick={() => setAudioPreview(a.ruta)} title="Escuchar este audio" style={{fontWeight:700, borderRadius:8, fontSize:18, minWidth:130}}>
                    <span className="me-2 d-flex align-items-center"><FaPlay /></span> Escuchar
                  </button>
                  <button className="btn btn-outline-danger btn-lg d-flex align-items-center gap-2 px-4 py-2 shadow border-0" onClick={() => handleDelete(a.ruta)} title="Eliminar este audio" style={{fontWeight:700, borderRadius:8, fontSize:18, minWidth:130}}>
                    <span className="me-2 d-flex align-items-center"><FaTrash /></span> Eliminar
                  </button>
                  <button className="btn btn-outline-warning btn-lg d-flex align-items-center justify-content-center px-4 py-2 shadow border-0" onClick={() => { setEditandoNombre(a.ruta); setNuevoNombre(a.ruta.replace(/\.[^/.]+$/, "")); }} title="Renombrar este audio" style={{fontWeight:700, borderRadius:8, fontSize:22, minWidth:56, minHeight:56, padding:0}}>
                    <FaEdit />
                  </button>
                </div>
                {editandoNombre === a.ruta && (
                  <div className="d-flex flex-row flex-wrap gap-2 align-items-center justify-content-start w-100 mb-2 mt-2">
                    <input
                      type="text"
                      className="form-control form-control-sm border-dark"
                      placeholder="Nuevo nombre"
                      value={nuevoNombre}
                      onChange={e => setNuevoNombre(e.target.value)}
                      style={{ width: 160, minWidth: 90, fontWeight:500, borderRadius:7, fontSize:15 }}
                    />
                    <button className="btn btn-dark btn-sm d-flex align-items-center gap-2 px-3 py-1 shadow border-0" onClick={() => handleRename(a.ruta, a.ruta.substring(a.ruta.lastIndexOf(".")))} title="Guardar nuevo nombre" style={{fontWeight:600, borderRadius:7, fontSize:15}}>
                      <FaEdit className="me-1" /> Guardar
                    </button>
                    <button className="btn btn-outline-secondary btn-sm d-flex align-items-center gap-2 px-3 py-1 shadow border-0" onClick={() => { setEditandoNombre(""); setNuevoNombre(""); }} title="Cancelar" style={{fontWeight:600, borderRadius:7, fontSize:15}}>
                      Cancelar
                    </button>
                  </div>
                )}
                {/* Renderiza un solo control de audio si este audio está siendo previsualizado */}
                {audioPreview === a.ruta && (
                  <audio controls autoPlay className="w-100 mb-2" onEnded={() => setAudioPreview("")}>
                    <source src={`http://localhost:5000/audios/${a.ruta}`} />
                    Tu navegador no soporta el elemento de audio.
                  </audio>
                )}
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
};

export default AudioPanel;
