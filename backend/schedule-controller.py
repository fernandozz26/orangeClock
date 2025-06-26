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
import tkinter as tk
from tkinter import messagebox
import threading
import logging
import sys

# Configurar logging para systemd
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Variables globales
app = Flask(__name__)
CORS(app) # Habilitar CORS para todas las rutas
#CORS(app, origins=["http://localhost:3000"])
scheduler = BackgroundScheduler()

# Inicializar pygame de forma segura
try:
    pygame.init()
    pygame.mixer.init()
except Exception as e:
    print(f"[INIT] Advertencia: Error al inicializar pygame: {e}")

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

def inicializar_sistema():
    """Inicializa todo el sistema de forma ordenada"""
    print("[INIT] Iniciando sistema de alarmas...", flush=True)
    logger.info("[INIT] Iniciando sistema de alarmas...")
    
    # 1. Inicializar base de datos
    inicializar_db()
    
    # 2. Crear directorio de audios si no existe
    sistema = platform.system().lower()
    if sistema == "windows":
        base_audio = "c:\\orangeClock\\audios"
    else:
        base_audio = "/orangeClock/audios"
    
    if not os.path.exists(base_audio):
        os.makedirs(base_audio, exist_ok=True)
        print(f"[INIT] Directorio de audios creado: {base_audio}")
    
    # 3. Iniciar scheduler
    if not scheduler.running:
        scheduler.start()
        print("[INIT] Scheduler iniciado")
    
    # 4. Cargar alarmas con un pequeño delay para asegurar que todo esté listo
    import threading
    import time
    def cargar_con_delay():
        time.sleep(2)  # Esperar 2 segundos
        cargar_alarmas()
    
    thread = threading.Thread(target=cargar_con_delay)
    thread.daemon = True
    thread.start()
    
    print("[INIT] Sistema inicializado correctamente")

# Cambia la ruta base de audios a la raíz orangeClock
def mostrar_mensaje_flotante(titulo, mensaje, tipo="info"):
    """Muestra un mensaje flotante en pantalla que se cierra automáticamente"""
    # Solo mostrar GUI si hay display disponible
    if not os.environ.get('DISPLAY'):
        print(f"[GUI] {tipo.upper()}: {titulo} - {mensaje}")
        return
    
    def crear_ventana():
        try:
            # Verificar que tkinter funcione
            root = tk.Tk()
            root.withdraw()  # Ocultar temporalmente
            
            # Test básico de display
            root.winfo_screenwidth()
            
            # Si llegamos aquí, el display funciona
            root.deiconify()  # Mostrar ventana
            root.title(titulo)
            root.geometry("400x150")
            root.resizable(False, False)
            
            # Centrar ventana
            try:
                root.eval('tk::PlaceWindow . center')
            except:
                pass  # Si falla el centrado, continuar
            
            # Configurar color según tipo
            if tipo == "error":
                bg_color = "#ffebee"
                fg_color = "#c62828"
            elif tipo == "warning":
                bg_color = "#fff3e0"
                fg_color = "#ef6c00"
            else:
                bg_color = "#e8f5e8"
                fg_color = "#2e7d32"
            
            root.configure(bg=bg_color)
            
            # Etiqueta del título
            titulo_label = tk.Label(root, text=titulo, font=("Arial", 12, "bold"), 
                                  bg=bg_color, fg=fg_color)
            titulo_label.pack(pady=10)
            
            # Etiqueta del mensaje
            mensaje_label = tk.Label(root, text=mensaje, font=("Arial", 10), 
                                   bg=bg_color, fg="black", wraplength=350)
            mensaje_label.pack(pady=5)
            
            # Contador regresivo
            contador_label = tk.Label(root, text="Se cerrará en 10 segundos", 
                                    font=("Arial", 8), bg=bg_color, fg="gray")
            contador_label.pack(pady=5)
            
            # Función para actualizar contador
            def actualizar_contador(segundos):
                if segundos > 0:
                    contador_label.config(text=f"Se cerrará en {segundos} segundos")
                    root.after(1000, actualizar_contador, segundos - 1)
                else:
                    root.destroy()
            
            # Iniciar contador
            actualizar_contador(10)
            
            # Permitir cerrar manualmente
            root.protocol("WM_DELETE_WINDOW", root.destroy)
            
            root.mainloop()
            
        except Exception as e:
            print(f"[GUI] {tipo.upper()}: {titulo} - {mensaje}")
            print(f"[GUI] Display no disponible: {e}")
    
    # Ejecutar en hilo separado para no bloquear
    thread = threading.Thread(target=crear_ventana)
    thread.daemon = True
    thread.start()

def reproducir_audio(audio_path):
    import subprocess
    import shutil
    
    sistema = platform.system().lower()
    if sistema == "windows":
        base_audio = "c:\\orangeClock\\audios"
    else:
        base_audio = "/orangeClock/audios"
    
    print(f"[AUDIO] === INICIANDO REPRODUCCIÓN ===")
    print(f"[AUDIO] Sistema: {sistema}")
    print(f"[AUDIO] Audio solicitado: {audio_path}")
    print(f"[AUDIO] Directorio base: {base_audio}")
    
    nombre_archivo = os.path.basename(audio_path)
    ruta_final = os.path.join(base_audio, nombre_archivo)
    print(f"[AUDIO] Nombre archivo: {nombre_archivo}")
    print(f"[AUDIO] Ruta final: {ruta_final}")
    print(f"[AUDIO] Archivo existe: {os.path.exists(ruta_final)}")
    
    if not os.path.exists(ruta_final):
        error_msg = f"Archivo de audio no encontrado: {nombre_archivo}"
        print(f"[CRON] ERROR: Archivo no encontrado: {ruta_final}")
        if os.path.exists(base_audio):
            archivos = os.listdir(base_audio)
            print(f"[CRON] Archivos disponibles: {archivos}")
        mostrar_mensaje_flotante("Error de Alarma", f"No se pudo reproducir el audio: {nombre_archivo}\nMotivo: {error_msg}", "error")
        return False
    
    try:
        if sistema == "windows":
            if not pygame.mixer.get_init():
                pygame.mixer.init()
            pygame.mixer.music.load(ruta_final)
            pygame.mixer.music.play()
            print(f"[AUDIO] ✓ Iniciando pygame para: {nombre_archivo}")
            print(f"[AUDIO] ✓ Reproduciendo con pygame...")
            mostrar_mensaje_flotante("Alarma Ejecutada", f"Se ha reproducido correctamente el audio: {nombre_archivo}")
            print(f"[AUDIO] ✓ Mensaje flotante enviado")
            time.sleep(10)
            print(f"[AUDIO] ✓ Reproducción pygame completada")
            return True
        else:
            ext = os.path.splitext(ruta_final)[1].lower()
            
            if ext == ".mp3" and shutil.which("mpg123"):
                result = subprocess.run(["mpg123", "-q", ruta_final], capture_output=True)
                if result.returncode == 0:
                    print(f"[CRON] ✓ Reproducido con mpg123: {nombre_archivo}")
                    mostrar_mensaje_flotante("Alarma Ejecutada", f"Se ha reproducido correctamente el audio: {nombre_archivo}")
                    return True
            
            if ext == ".wav" and shutil.which("aplay"):
                result = subprocess.run(["aplay", "-q", ruta_final], capture_output=True)
                if result.returncode == 0:
                    print(f"[CRON] ✓ Reproducido con aplay: {nombre_archivo}")
                    mostrar_mensaje_flotante("Alarma Ejecutada", f"Se ha reproducido correctamente el audio: {nombre_archivo}")
                    return True
            
            if shutil.which("paplay"):
                result = subprocess.run(["paplay", ruta_final], capture_output=True)
                if result.returncode == 0:
                    print(f"[CRON] ✓ Reproducido con paplay: {nombre_archivo}")
                    mostrar_mensaje_flotante("Alarma Ejecutada", f"Se ha reproducido correctamente el audio: {nombre_archivo}")
                    return True
            
            error_msg = f"No se encontraron reproductores de audio disponibles"
            print(f"[CRON] ERROR: No se pudo reproducir {nombre_archivo}")
            mostrar_mensaje_flotante("Error de Alarma", f"No se pudo reproducir el audio: {nombre_archivo}\nMotivo: {error_msg}", "error")
            return False
            
    except Exception as e:
        error_msg = f"Error técnico: {str(e)}"
        print(f"[CRON] ERROR al reproducir audio: {e}")
        mostrar_mensaje_flotante("Error de Alarma", f"No se pudo reproducir el audio: {nombre_archivo}\nMotivo: {error_msg}", "error")
        return False

def cargar_alarmas():
    print("[INIT] Iniciando carga de alarmas...")
    
    # Verificar que el scheduler esté disponible
    if not scheduler.running:
        print("[INIT] Iniciando scheduler...")
        scheduler.start()
    
    # 1. Limpiar todos los jobs existentes
    try:
        for job in scheduler.get_jobs():
            scheduler.remove_job(job.id)
        print(f"[INIT] Jobs limpiados: {len(scheduler.get_jobs())}")
    except Exception as e:
        print(f"[INIT] Error al limpiar jobs: {e}")

    # 2. Verificar que la base de datos existe
    if not os.path.exists('alarmas.db'):
        print("[INIT] Base de datos no encontrada, inicializando...")
        inicializar_db()
    
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT id, hora, audio, repeticion, fecha FROM alarmas")
        alarmas = cursor.fetchall()
    except Exception as e:
        print(f"[INIT] Error al leer columna fecha, usando formato anterior: {e}")
        cursor.execute("SELECT id, hora, audio, repeticion FROM alarmas")
        alarmas = [(id, hora, audio, repeticion, None) for id, hora, audio, repeticion in cursor.fetchall()]
    conn.close()

    print(f"[INIT] Encontradas {len(alarmas)} alarmas en la base de datos")
    
    # 3. Verificar directorio de audios
    sistema = platform.system().lower()
    if sistema == "windows":
        base_audio = "c:\\orangeClock\\audios"
    else:
        base_audio = "/orangeClock/audios"
    
    if not os.path.exists(base_audio):
        print(f"[INIT] Creando directorio de audios: {base_audio}")
        os.makedirs(base_audio, exist_ok=True)

    alarmas_cargadas = 0
    for id, hora, audio, repeticion, fecha in alarmas:
        # Verificar que el archivo de audio existe
        nombre_archivo = os.path.basename(audio)
        ruta_audio = os.path.join(base_audio, nombre_archivo)
        if not os.path.exists(ruta_audio):
            print(f"[INIT] ADVERTENCIA: Audio no encontrado para alarma {id}: {ruta_audio}")
            continue
            
        def ejecutar_alarma(audio_path=audio, alarma_id=id, alarma_hora=hora, alarma_rep=repeticion, alarma_fecha=fecha):
            print(f"[CRON] ========== EJECUTANDO ALARMA ===========")
            print(f"[CRON] ID: {alarma_id}")
            print(f"[CRON] Hora programada: {alarma_hora}")
            print(f"[CRON] Audio: {audio_path}")
            print(f"[CRON] Repetición: {alarma_rep}")
            print(f"[CRON] Fecha: {alarma_fecha}")
            print(f"[CRON] Timestamp actual: {datetime.now()}")
            
            try:
                resultado = reproducir_audio(audio_path)
                if resultado:
                    print(f"[CRON] ✓ Alarma {alarma_id} ejecutada exitosamente")
                else:
                    print(f"[CRON] ✗ Alarma {alarma_id} falló en reproducción")
            except Exception as e:
                print(f"[CRON] ✗ ERROR CRITICO en alarma {alarma_id}: {e}")
                import traceback
                traceback.print_exc()
            
            print(f"[CRON] ========== FIN ALARMA {alarma_id} ==========")
            
        try:
            if fecha and fecha != 'None':
                # Alarma de única vez
                from datetime import datetime
                run_date = f"{fecha} {hora}"
                fecha_alarma = datetime.strptime(run_date, "%Y-%m-%d %H:%M")
                # Solo programar si la fecha es futura
                if fecha_alarma > datetime.now():
                    scheduler.add_job(
                        ejecutar_alarma,
                        'date',
                        run_date=fecha_alarma,
                        id=str(id)
                    )
                    alarmas_cargadas += 1
                    print(f"[INIT] Alarma única programada: {id} - {fecha} {hora}")
                else:
                    print(f"[INIT] Alarma única pasada, no programada: {id} - {fecha} {hora}")
            elif repeticion and repeticion != 'None':
                # Alarmas recurrentes
                cron_kwargs = {
                    'hour': int(hora.split(':')[0]),
                    'minute': int(hora.split(':')[1]),
                    'id': str(id)
                }
                # Semanal (ej: mon, tue-wed)
                dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
                if all(d in dias_semana for d in repeticion.split('-')):
                    # Convertir guiones a comas para APScheduler
                    cron_kwargs['day_of_week'] = repeticion.replace('-', ',')
                # Anual (MM-DD)
                elif len(repeticion) == 5 and repeticion[2] == '-':
                    mes, dia = repeticion.split('-')
                    cron_kwargs['month'] = int(mes)
                    cron_kwargs['day'] = int(dia)
                # Mensual (día del mes)
                elif repeticion.isdigit():
                    cron_kwargs['day'] = int(repeticion)
                scheduler.add_job(ejecutar_alarma, 'cron', **cron_kwargs)
                alarmas_cargadas += 1
                print(f"[INIT] Alarma recurrente programada: {id} - {hora} ({repeticion})")
            else:
                # Alarma diaria
                scheduler.add_job(
                    ejecutar_alarma,
                    'cron',
                    hour=int(hora.split(':')[0]),
                    minute=int(hora.split(':')[1]),
                    id=str(id)
                )
                alarmas_cargadas += 1
                print(f"[INIT] Alarma diaria programada: {id} - {hora}")
        except Exception as e:
            print(f"[INIT] ERROR al cargar alarma id={id}, hora={hora}, audio={audio}, rep={repeticion}, fecha={fecha}: {e}")
    
    print(f"[INIT] Carga completada: {alarmas_cargadas}/{len(alarmas)} alarmas programadas")
    print(f"[INIT] Jobs activos en scheduler: {len(scheduler.get_jobs())}")
    
    # Mostrar detalles de todos los jobs activos
    jobs = scheduler.get_jobs()
    if jobs:
        print(f"[INIT] === JOBS ACTIVOS ===")
        for job in jobs:
            print(f"[INIT] Job {job.id}: {job.next_run_time} - {job.trigger}")
        print(f"[INIT] === FIN JOBS ACTIVOS ===")
    else:
        print(f"[INIT] ⚠️  NO HAY JOBS ACTIVOS EN EL SCHEDULER")

# Inicializar sistema completo
inicializar_sistema()

@app.route('/api/crear_alarma', methods=['POST'])
def crear_alarma():
    datos = request.json
    hora = datos.get('hora')
    audio = datos.get('audio')
    repeticion = datos.get('repeticion')
    fecha = datos.get('fecha')
    
    logger.info(f"[API] === CREANDO NUEVA ALARMA ===")
    logger.info(f"[API] Datos recibidos: {datos}")
    logger.info(f"[API] Hora: {hora}")
    logger.info(f"[API] Audio: {audio}")
    logger.info(f"[API] Repetición: {repeticion}")
    logger.info(f"[API] Fecha: {fecha}")
    
    # También print para asegurar que aparezca
    print(f"[API] === CREANDO NUEVA ALARMA ===", flush=True)
    print(f"[API] Datos recibidos: {datos}", flush=True)
    print(f"[API] Hora: {hora}", flush=True)
    print(f"[API] Audio: {audio}", flush=True)
    print(f"[API] Repetición: {repeticion}", flush=True)
    print(f"[API] Fecha: {fecha}", flush=True)

    # Verificar conflictos de horario considerando repetición
    conn = sqlite3.connect('alarmas.db')
    cursor = conn.cursor()
    
    # Obtener alarmas existentes en la misma hora
    cursor.execute("SELECT repeticion, fecha FROM alarmas WHERE hora=?", (hora,))
    alarmas_existentes = cursor.fetchall()
    
    for rep_existente, fecha_existente in alarmas_existentes:
        # Si ambas son alarmas diarias (sin repetición ni fecha)
        if not repeticion and not fecha and not rep_existente and not fecha_existente:
            conn.close()
            return jsonify({'error': 'Ya existe una alarma diaria en este horario'}), 400
        
        # Si ambas tienen fecha específica y es la misma fecha
        if fecha and fecha_existente and fecha == fecha_existente:
            conn.close()
            return jsonify({'error': 'Ya existe una alarma en esta fecha y hora'}), 400
        
        # Si ambas tienen repetición semanal, verificar si hay días en común
        if repeticion and rep_existente:
            dias_nuevos = set(repeticion.split('-'))
            dias_existentes = set(rep_existente.split('-'))
            if dias_nuevos.intersection(dias_existentes):
                conn.close()
                return jsonify({'error': f'Ya existe una alarma en algunos de estos días: {list(dias_nuevos.intersection(dias_existentes))}'}), 400

    # Guardar en la base de datos (ahora sí guarda fecha si aplica)
    # conn ya está abierta desde la verificación anterior
    cursor = conn.cursor()
    cursor.execute("INSERT INTO alarmas (hora, audio, repeticion, fecha) VALUES (?, ?, ?, ?)", (hora, audio, repeticion, fecha))
    conn.commit()
    conn.close()

    # Programar la alarma en apscheduler
    def ejecutar_alarma():
        from datetime import datetime
        logger.info(f"[API-EXEC] ========== EJECUTANDO ALARMA NUEVA ===========")
        logger.info(f"[API-EXEC] Hora: {hora}, Audio: {audio}, Repetición: {repeticion}")
        logger.info(f"[API-EXEC] Timestamp: {datetime.now()}")
        reproducir_audio(audio)
        logger.info(f"[API-EXEC] ========== FIN ALARMA NUEVA ===========")

    if fecha and fecha != 'None':  # Alarma de única vez
        from datetime import datetime
        run_date = f"{fecha} {hora}"
        scheduler.add_job(
            ejecutar_alarma,
            'date',
            run_date=datetime.strptime(run_date, "%Y-%m-%d %H:%M")
        )
    elif repeticion and repeticion != 'None':
        # Alarmas recurrentes
        cron_kwargs = {
            'hour': int(hora.split(':')[0]),
            'minute': int(hora.split(':')[1])
        }
        
        # Semanal (ej: mon, tue-wed)
        dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
        if all(d in dias_semana for d in repeticion.split('-')):
            # Convertir guiones a comas para APScheduler
            cron_kwargs['day_of_week'] = repeticion.replace('-', ',')
        # Anual (MM-DD)
        elif len(repeticion) == 5 and repeticion[2] == '-':
            mes, dia = repeticion.split('-')
            cron_kwargs['month'] = int(mes)
            cron_kwargs['day'] = int(dia)
        # Mensual (día del mes)
        elif repeticion.isdigit():
            cron_kwargs['day'] = int(repeticion)
        
        scheduler.add_job(ejecutar_alarma, 'cron', **cron_kwargs)
    else:
        # Alarma diaria
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=int(hora.split(':')[0]), 
            minute=int(hora.split(':')[1])
        )

    logger.info(f"[API] Jobs totales en scheduler: {len(scheduler.get_jobs())}")
    logger.info(f"[API] === ALARMA CREADA EXITOSAMENTE ===")
    
    print(f"[API] Jobs totales en scheduler: {len(scheduler.get_jobs())}", flush=True)
    print(f"[API] === ALARMA CREADA EXITOSAMENTE ===", flush=True)
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
        cursor.execute("SELECT id, hora, audio, repeticion, fecha FROM alarmas ORDER BY hora")
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
        cursor.execute("SELECT id, hora, audio, repeticion FROM alarmas ORDER BY hora")
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

    if nueva_fecha and nueva_fecha != 'None':  # Alarma de única vez
        from datetime import datetime
        run_date = f"{nueva_fecha} {nueva_hora}"
        scheduler.add_job(
            ejecutar_alarma,
            'date',
            run_date=datetime.strptime(run_date, "%Y-%m-%d %H:%M"),
            id=str(alarma_id)
        )
    elif nueva_repeticion and nueva_repeticion != 'None':
        # Alarmas recurrentes
        cron_kwargs = {
            'hour': int(nueva_hora.split(':')[0]),
            'minute': int(nueva_hora.split(':')[1]),
            'id': str(alarma_id)
        }
        
        # Semanal (ej: mon, tue-wed)
        dias_semana = ['mon','tue','wed','thu','fri','sat','sun']
        if all(d in dias_semana for d in nueva_repeticion.split('-')):
            # Convertir guiones a comas para APScheduler
            cron_kwargs['day_of_week'] = nueva_repeticion.replace('-', ',')
        # Anual (MM-DD)
        elif len(nueva_repeticion) == 5 and nueva_repeticion[2] == '-':
            mes, dia = nueva_repeticion.split('-')
            cron_kwargs['month'] = int(mes)
            cron_kwargs['day'] = int(dia)
        # Mensual (día del mes)
        elif nueva_repeticion.isdigit():
            cron_kwargs['day'] = int(nueva_repeticion)
        
        scheduler.add_job(ejecutar_alarma, 'cron', **cron_kwargs)
    else:
        # Alarma diaria
        scheduler.add_job(
            ejecutar_alarma, 
            'cron', 
            hour=int(nueva_hora.split(':')[0]), 
            minute=int(nueva_hora.split(':')[1]), 
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
    
    # Ordenar por hora
    resultado.sort(key=lambda x: x['hora'])
    return jsonify({"alarmas_proximas": resultado}), 200

# iniciar api Flask tiene que ir al final del script
if __name__ == '__main__':
    print("[MAIN] Iniciando servidor Flask...", flush=True)
    logger.info("[MAIN] Iniciando servidor Flask...")
    #app.run(host='0.0.0.0', port=5000)
    serve(app, host='0.0.0.0', port=5000)
