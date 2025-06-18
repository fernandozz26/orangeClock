from flask import Flask, request, jsonify, send_from_directory
from apscheduler.schedulers.background import BackgroundScheduler
import pygame
import time
import sqlite3
import os
from flask_cors import CORS
from werkzeug.utils import secure_filename
import platform
from datetime import datetime, timedelta
from waitress import serve

# Variables globales
pygame.init()
app = Flask(__name__)
CORS(app) # Habilitar CORS para todas las rutas
#CORS(app, origins=["http://localhost:3000"])
scheduler = BackgroundScheduler()
scheduler.start()

# Iniciar base de datos
# Agrega el campo fecha a la tabla si no existe

def inicializar_db():
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    # 1. Crear la tabla si no existe (sin la columna fecha extra)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS alarmas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            hora TEXT NOT NULL,
            audio TEXT NOT NULL,
            repeticion TEXT DEFAULT NULL
        )
    ''')
    # 2. Verifica si la columna fecha existe
    cursor.execute("PRAGMA table_info(alarmas)")
    columnas = [col[1] for col in cursor.fetchall()]
    if 'fecha' not in columnas:
        cursor.execute("ALTER TABLE alarmas ADD COLUMN fecha TEXT DEFAULT NULL")
    conn.commit()
    conn.close()

inicializar_db()  # Se ejecuta al inicio del script

# Cambia la ruta base de audios a la raíz orangeClock
def reproducir_audio(audio_path):
    sistema = platform.system().lower()
    if sistema == "windows":
        base_audio = "c:\\orangeClock\\audios"
    else:
        base_audio = "/orangeClock/audios"
    print(f"[CRON] Intentando reproducir: {audio_path}")
    nombre_archivo = os.path.basename(audio_path)
    ruta_final = os.path.join(base_audio, nombre_archivo)
    print(f"[CRON] Ruta absoluta utilizada: {ruta_final}")
    if not os.path.exists(ruta_final):
        print(f"[CRON] ERROR: El archivo no existe: {ruta_final}")
        return
    try:
        pygame.mixer.init()
        pygame.mixer.music.load(ruta_final)
        pygame.mixer.music.play()
        print(f"[CRON] Reproduciendo audio: {ruta_final}")
        time.sleep(10)  # Esperar para que se reproduzca el audio
    except Exception as e:
        print(f"[CRON] Error al reproducir audio: {e}")

def cargar_alarmas():
    # 1. Limpiar todos los jobs existentes
    for job in scheduler.get_jobs():
        scheduler.remove_job(job.id)

    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT id, hora, audio, repeticion, fecha FROM alarmas")
        alarmas = cursor.fetchall()
    except Exception:
        cursor.execute("SELECT id, hora, audio, repeticion FROM alarmas")
        alarmas = [(id, hora, audio, repeticion, None) for id, hora, audio, repeticion in cursor.fetchall()]
    conn.close()

    for id, hora, audio, repeticion, fecha in alarmas:
        def ejecutar_alarma(audio_path=audio):
            reproducir_audio(audio_path)
        try:
            if fecha and fecha != 'None':
                # Alarma de única vez
                from datetime import datetime
                run_date = f"{fecha} {hora}"
                scheduler.add_job(
                    ejecutar_alarma,
                    'date',
                    run_date=datetime.strptime(run_date, "%Y-%m-%d %H:%M"),
                    id=str(id)
                )
            elif repeticion and repeticion != 'None':
                # Alarmas recurrentes
                cron_kwargs = {
                    'hour': hora.split(':')[0],
                    'minute': hora.split(':')[1],
                    'id': str(id)
                }
                # Semanal (ej: mon, tue-wed)
                dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
                if all(d in dias_semana for d in repeticion.split('-')):
                    cron_kwargs['day_of_week'] = repeticion
                # Anual (MM-DD)
                elif len(repeticion) == 5 and repeticion[2] == '-':
                    mes, dia = repeticion.split('-')
                    cron_kwargs['month'] = mes
                    cron_kwargs['day'] = dia
                # Mensual (día del mes)
                elif repeticion.isdigit():
                    cron_kwargs['day'] = repeticion
                scheduler.add_job(ejecutar_alarma, 'cron', **cron_kwargs)
            else:
                # Alarma diaria
                scheduler.add_job(
                    ejecutar_alarma,
                    'cron',
                    hour=hora.split(':')[0],
                    minute=hora.split(':')[1],
                    id=str(id)
                )
        except Exception as e:
            print(f"[CRON] Error al cargar la alarma id={id}, hora={hora}, audio={audio}, rep={repeticion}, fecha={fecha}: {e}")

# Llamar a cargar_alarmas() al inicio
cargar_alarmas()  # Cargar alarmas al inicio

@app.route('/api/crear_alarma', methods=['POST'])
def crear_alarma():
    datos = request.json
    hora = datos.get('hora')
    audio = datos.get('audio')
    repeticion = datos.get('repeticion')
    fecha = datos.get('fecha')

    # Filtro robusto: no permitir alarmas que se crucen en el mismo horario, sin importar tipo
    # Si hay una alarma en la misma hora, no permitir guardar otra, sin importar tipo ni campos
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM alarmas WHERE hora=?", (hora,))
    existe = cursor.fetchone()[0]
    if existe:
        conn.close()
        return jsonify({'error': 'No se puede establecer alarma, ya existe una establecida en este horario'}), 400

    # Guardar en la base de datos (ahora sí guarda fecha si aplica)
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    cursor.execute("INSERT INTO alarmas (hora, audio, repeticion, fecha) VALUES (?, ?, ?, ?)", (hora, audio, repeticion, fecha))
    conn.commit()
    conn.close()

    # Programar la alarma en apscheduler
    def ejecutar_alarma():
        reproducir_audio(audio)

    if fecha:  # Alarma de única vez
        from datetime import datetime
        run_date = f"{fecha} {hora}"
        scheduler.add_job(
            ejecutar_alarma,
            'date',
            run_date=datetime.strptime(run_date, "%Y-%m-%d %H:%M")
        )
    elif repeticion:
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=hora.split(':')[0], 
            minute=hora.split(':')[1], 
            day_of_week=repeticion if repeticion.isalpha() else None, 
            month=repeticion if repeticion.isdigit() else None
        )
    else:
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=hora.split(':')[0], 
            minute=hora.split(':')[1]
        )

    return jsonify({"mensaje": f"Alarma programada para {hora} con repetición '{repeticion}' y guardada en el sistema"}), 201

@app.route('/api/consultar_alarmas', methods=['GET'])
def consultar_alarmas():
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
    dias_semana_es = {
        'mon': 'Lunes',
        'tue': 'Martes',
        'wed': 'Miércoles',
        'thu': 'Jueves',
        'fri': 'Viernes',
        'sat': 'Sábado',
        'sun': 'Domingo'
    }
    try:
        cursor.execute("SELECT id, hora, audio, repeticion, fecha FROM alarmas")
        alarmas = cursor.fetchall()
        resultado = []
        for id, hora, audio, repeticion, fecha in alarmas:
            rep_es = repeticion
            if repeticion and all(d in dias_semana for d in repeticion.split('-')):
                rep_es = '-'.join([dias_semana_es[d] for d in repeticion.split('-')])
            resultado.append({
                "id": id,
                "hora": hora,
                "audio": audio,
                "repeticion": rep_es,
                "fecha": fecha
            })
    except Exception:
        cursor.execute("SELECT id, hora, audio, repeticion FROM alarmas")
        alarmas = cursor.fetchall()
        resultado = []
        for id, hora, audio, repeticion in alarmas:
            rep_es = repeticion
            if repeticion and all(d in dias_semana for d in repeticion.split('-')):
                rep_es = '-'.join([dias_semana_es[d] for d in repeticion.split('-')])
            resultado.append({
                "id": id,
                "hora": hora,
                "audio": audio,
                "repeticion": rep_es,
                "fecha": None
            })
    conn.close()
    return jsonify({"alarmas_programadas": resultado}), 200

@app.route('/api/eliminar_alarma/<int:alarma_id>', methods=['DELETE'])
def eliminar_alarma(alarma_id):
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()

    # Verificar si la alarma existe
    cursor.execute("SELECT id FROM alarmas WHERE id=?", (alarma_id,))
    alarma = cursor.fetchone()
    
    if not alarma:
        conn.close()
        return jsonify({"error": f"No se encontró una alarma con ID {alarma_id}"}), 404

    # Eliminar de la base de datos
    cursor.execute("DELETE FROM alarmas WHERE id=?", (alarma_id,))
    conn.commit()
    conn.close()

    # Eliminar de apscheduler si está activa
    for job in scheduler.get_jobs():
        if job.id == str(alarma_id):  # Verificamos si el ID coincide
            scheduler.remove_job(job.id)

    return jsonify({"mensaje": f"Alarma con ID {alarma_id} eliminada correctamente"}), 200

@app.route('/api/editar_alarma/<int:alarma_id>', methods=['PUT'])
def editar_alarma(alarma_id):
    datos = request.json
    nueva_hora = datos.get('hora')
    nuevo_audio = datos.get('audio')
    nueva_repeticion = datos.get('repeticion')  # Nuevo campo
    nueva_fecha = datos.get('fecha')

    if not nueva_hora or not nuevo_audio:
        return jsonify({"mensaje": "Se requieren los campos 'hora' y 'audio'"}), 400

    # Conexión a la base de datos
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()

    # Verificar si la alarma existe
    cursor.execute("SELECT id FROM alarmas WHERE id=?", (alarma_id,))
    alarma = cursor.fetchone()

    if not alarma:
        conn.close()
        return jsonify({"error": f"No se encontró una alarma con ID {alarma_id}"}), 404

    # Actualizar en la base de datos
    cursor.execute("UPDATE alarmas SET hora=?, audio=?, repeticion=?, fecha=? WHERE id=?", (nueva_hora, nuevo_audio, nueva_repeticion, nueva_fecha, alarma_id))
    conn.commit()
    conn.close()

    # Eliminar el trabajo anterior en APScheduler, si existe
    for job in scheduler.get_jobs():
        if job.id == str(alarma_id):
            scheduler.remove_job(job.id)

    # Programar la nueva alarma en APScheduler
    def ejecutar_alarma():
        reproducir_audio(nuevo_audio)

    if nueva_repeticion:
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=nueva_hora.split(':')[0], 
            minute=nueva_hora.split(':')[1], 
            day_of_week=nueva_repeticion if nueva_repeticion.isalpha() else None, 
            month=nueva_repeticion if nueva_repeticion.isdigit() else None, 
            id=str(alarma_id)
        )
    else:
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=nueva_hora.split(':')[0], 
            minute=nueva_hora.split(':')[1], 
            id=str(alarma_id)
        )

    return jsonify({"mensaje": f"Alarma con ID {alarma_id} actualizada y reprogramada correctamente"}), 200

ALLOWED_EXTENSIONS = {'.mp3', '.wav'}

# Utilidad para validar extensión
def allowed_audio(filename):
    return os.path.splitext(filename)[1].lower() in ALLOWED_EXTENSIONS

# Cambia la ruta de guardado de audios al subir
@app.route('/api/audios', methods=['POST'])
def subir_audio():
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No se envió archivo'}), 400
        file = request.files['file']
        if file.filename == '':
            return jsonify({'error': 'Nombre de archivo vacío'}), 400
        if not allowed_audio(file.filename):
            return jsonify({'error': 'Formato no permitido'}), 400
        # Guardar en la ruta orangeClock
        sistema = platform.system().lower()
        if sistema == "windows":
            audio_folder = "c:\\orangeClock\\audios"
        else:
            audio_folder = "/orangeClock/audios"
        if not os.path.exists(audio_folder):
            os.makedirs(audio_folder)
        filename = secure_filename(file.filename)
        file.save(os.path.join(audio_folder, filename))
        return jsonify({'mensaje': 'Audio guardado', 'ruta': filename}), 201
    except Exception as e:
        print(f"Error al subir audio: {e}")
        return jsonify({'error': f'Error interno: {str(e)}'}), 500

# Cambia la función listar_audios para leer desde la ruta orangeClock
@app.route('/api/audios', methods=['GET'])
def listar_audios():
    sistema = platform.system().lower()
    if sistema == "windows":
        carpeta_audios = "c:\\orangeClock\\audios"
    else:
        carpeta_audios = "/orangeClock/audios"
    if not os.path.exists(carpeta_audios):
        return jsonify([])
    archivos = []
    for nombre in os.listdir(carpeta_audios):
        if nombre.lower().endswith('.mp3') or nombre.lower().endswith('.wav'):
            archivos.append({
                'nombre': os.path.splitext(nombre)[0],  # solo el nombre sin extensión
                'ruta': nombre  # solo el nombre con extensión, sin /audios/
            })
    return jsonify(archivos)

# Servir archivos de audio estaticamente
@app.route('/api/audios/<path:filename>')
def servir_audio(filename):
    sistema = platform.system().lower()
    if sistema == "windows":
        carpeta_audios = "c:\\orangeClock\\audios"
    else:
        carpeta_audios = "/orangeClock/audios"
    return send_from_directory(carpeta_audios, filename)

# Cambia eliminar y renombrar audio para usar la ruta orangeClock
@app.route('/api/audios/<nombre>', methods=['DELETE'])
def eliminar_audio(nombre):
    import platform
    sistema = platform.system().lower()
    if sistema == "windows":
        audio_folder = "c:\\orangeClock\\audios"
    else:
        audio_folder = "/orangeClock/audios"
    filename = secure_filename(nombre)
    path = os.path.join(audio_folder, filename)
    if os.path.exists(path):
        os.remove(path)
        return jsonify({'mensaje': 'Audio eliminado'}), 200
    return jsonify({'error': 'Audio no encontrado'}), 404

@app.route('/api/audios/<nombre>', methods=['PUT'])
def renombrar_audio(nombre):
    import platform
    sistema = platform.system().lower()
    if sistema == "windows":
        audio_folder = "c:\\orangeClock\\audios"
    else:
        audio_folder = "/orangeClock/audios"
    data = request.json
    nuevo_nombre = secure_filename(data.get('nuevo_nombre', ''))
    if not nuevo_nombre:
        return jsonify({'error': 'Nuevo nombre requerido'}), 400
    ext = os.path.splitext(nombre)[1]
    nuevo_nombre_completo = nuevo_nombre + ext
    old_path = os.path.join(audio_folder, secure_filename(nombre))
    new_path = os.path.join(audio_folder, nuevo_nombre_completo)
    if not os.path.exists(old_path):
        return jsonify({'error': 'Audio no encontrado'}), 404
    if os.path.exists(new_path):
        return jsonify({'error': 'Ya existe un audio con ese nombre'}), 400
    os.rename(old_path, new_path)
    return jsonify({'mensaje': 'Audio renombrado', 'ruta': f'/audios/{nuevo_nombre_completo}'}), 200

@app.route('/api/alarmas_proximas', methods=['GET'])
def alarmas_proximas():
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT id, hora, audio, repeticion, fecha FROM alarmas")
        alarmas = cursor.fetchall()
    except Exception:
        cursor.execute("SELECT id, hora, audio, repeticion FROM alarmas")
        alarmas = [(id, hora, audio, repeticion, None) for id, hora, audio, repeticion in cursor.fetchall()]
    conn.close()

    ahora = datetime.now()
    dentro_24h = ahora + timedelta(hours=24)
    resultado = []
    dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
    dias_semana_es = {
        'mon': 'Lunes',
        'tue': 'Martes',
        'wed': 'Miércoles',
        'thu': 'Jueves',
        'fri': 'Viernes',
        'sat': 'Sábado',
        'sun': 'Domingo'
    }
    for id, hora, audio, repeticion, fecha in alarmas:
        # Alarmas de fecha única
        if fecha and fecha != 'None':
            try:
                dt_alarma = datetime.strptime(f"{fecha} {hora}", "%Y-%m-%d %H:%M")
                if ahora <= dt_alarma <= dentro_24h:
                    resultado.append({"id": id, "hora": hora, "audio": audio, "repeticion": repeticion, "fecha": fecha})
            except Exception:
                continue
        # Alarmas semanales
        elif repeticion and repeticion != 'None' and all(d in dias_semana for d in repeticion.split('-')):
            rep_es = '-'.join([dias_semana_es[d] for d in repeticion.split('-')])
            for dia in repeticion.split('-'):
                idx_dia = dias_semana.index(dia)
                hoy_idx = ahora.weekday()
                dias_hasta = (idx_dia - hoy_idx) % 7
                dt_alarma = ahora.replace(hour=int(hora.split(":")[0]), minute=int(hora.split(":")[1]), second=0, microsecond=0) + timedelta(days=dias_hasta)
                if ahora <= dt_alarma <= dentro_24h:
                    resultado.append({"id": id, "hora": hora, "audio": audio, "repeticion": rep_es, "fecha": None})
                    break
        # Alarmas anuales (MM-DD)
        elif repeticion and repeticion != 'None' and len(repeticion) == 5 and repeticion[2] == '-':
            try:
                mes, dia = map(int, repeticion.split('-'))
                dt_alarma = ahora.replace(month=mes, day=dia, hour=int(hora.split(":")[0]), minute=int(hora.split(":")[1]), second=0, microsecond=0)
                # Si la fecha ya pasó este año, calcula para el próximo año
                if dt_alarma < ahora:
                    dt_alarma = dt_alarma.replace(year=ahora.year + 1)
                if ahora <= dt_alarma <= dentro_24h:
                    resultado.append({"id": id, "hora": hora, "audio": audio, "repeticion": repeticion, "fecha": None})
            except Exception:
                continue
        # Alarmas diarias (sin repetición ni fecha)
        elif not repeticion and not fecha:
            dt_alarma = ahora.replace(hour=int(hora.split(":")[0]), minute=int(hora.split(":")[1]), second=0, microsecond=0)
            if dt_alarma < ahora:
                dt_alarma += timedelta(days=1)
            if ahora <= dt_alarma <= dentro_24h:
                resultado.append({"id": id, "hora": hora, "audio": audio, "repeticion": None, "fecha": None})
    return jsonify({"alarmas_proximas": resultado}), 200

# iniciar api Flask tiene que ir al final del script
if __name__ == '__main__':
    #app.run(host='0.0.0.0', port=5000)
    serve(app, host='0.0.0.0', port=5000)
