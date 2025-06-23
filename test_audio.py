#!/usr/bin/env python3
"""
Script de prueba para verificar que el sistema de audio funciona correctamente
en Orange Pi después de reiniciar.
"""

import os
import subprocess
import shutil
import platform
import time

def test_audio_system():
    print("=== PRUEBA DEL SISTEMA DE AUDIO ===")
    
    sistema = platform.system().lower()
    print(f"Sistema operativo: {sistema}")
    
    if sistema != "linux":
        print("Este test está diseñado para Linux/Orange Pi")
        return
    
    # 1. Verificar reproductores disponibles
    print("\n1. Verificando reproductores de audio disponibles:")
    reproductores = {
        'mpg123': 'Reproductor MP3',
        'aplay': 'Reproductor WAV (ALSA)',
        'paplay': 'Reproductor PulseAudio',
        'speaker-test': 'Test de altavoces'
    }
    
    disponibles = []
    for cmd, desc in reproductores.items():
        if shutil.which(cmd):
            print(f"  ✓ {cmd} - {desc}")
            disponibles.append(cmd)
        else:
            print(f"  ✗ {cmd} - {desc} (NO DISPONIBLE)")
    
    if not disponibles:
        print("\n❌ ERROR: No hay reproductores de audio disponibles")
        print("Instala con: sudo apt install mpg123 alsa-utils pulseaudio-utils")
        return False
    
    # 2. Verificar dispositivos de audio
    print("\n2. Verificando dispositivos de audio:")
    try:
        # Listar tarjetas de sonido
        result = subprocess.run(['aplay', '-l'], capture_output=True, text=True)
        if result.returncode == 0:
            print("Tarjetas de audio encontradas:")
            print(result.stdout)
        else:
            print("No se pudieron listar las tarjetas de audio")
    except Exception as e:
        print(f"Error al verificar dispositivos: {e}")
    
    # 3. Test de sonido básico
    print("\n3. Realizando test de sonido:")
    
    if 'speaker-test' in disponibles:
        print("Ejecutando speaker-test (tono de 1000Hz por 2 segundos)...")
        try:
            result = subprocess.run([
                'speaker-test', '-t', 'sine', '-f', '1000', '-l', '1', '-s', '1'
            ], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                print("✓ Test de altavoces exitoso")
            else:
                print(f"✗ Error en test de altavoces: {result.stderr}")
        except subprocess.TimeoutExpired:
            print("✗ Timeout en test de altavoces")
        except Exception as e:
            print(f"✗ Error ejecutando speaker-test: {e}")
    
    # 4. Verificar directorio de audios
    print("\n4. Verificando directorio de audios:")
    audio_dir = "/orangeClock/audios"
    
    if os.path.exists(audio_dir):
        print(f"✓ Directorio existe: {audio_dir}")
        archivos = os.listdir(audio_dir)
        if archivos:
            print(f"Archivos encontrados: {len(archivos)}")
            for archivo in archivos[:5]:  # Mostrar solo los primeros 5
                print(f"  - {archivo}")
        else:
            print("⚠️  Directorio vacío")
    else:
        print(f"✗ Directorio no existe: {audio_dir}")
        print("Creando directorio...")
        os.makedirs(audio_dir, exist_ok=True)
    
    # 5. Verificar permisos
    print("\n5. Verificando permisos:")
    try:
        # Verificar si el usuario actual está en el grupo audio
        import grp
        audio_group = grp.getgrnam('audio')
        current_user = os.getenv('USER', 'unknown')
        
        if current_user in audio_group.gr_mem:
            print(f"✓ Usuario {current_user} está en el grupo 'audio'")
        else:
            print(f"⚠️  Usuario {current_user} NO está en el grupo 'audio'")
            print("Ejecuta: sudo usermod -a -G audio $USER")
    except Exception as e:
        print(f"No se pudo verificar grupo audio: {e}")
    
    # 6. Test de base de datos
    print("\n6. Verificando base de datos:")
    db_path = "alarmas.db"
    if os.path.exists(db_path):
        print(f"✓ Base de datos existe: {db_path}")
        try:
            import sqlite3
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM alarmas")
            count = cursor.fetchone()[0]
            print(f"Alarmas en base de datos: {count}")
            conn.close()
        except Exception as e:
            print(f"Error al leer base de datos: {e}")
    else:
        print(f"⚠️  Base de datos no existe: {db_path}")
    
    print("\n=== FIN DE PRUEBAS ===")
    return True

if __name__ == "__main__":
    test_audio_system()