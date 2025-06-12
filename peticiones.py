curl -X POST "http://127.0.0.1:5000/crear_alarma" -H "Content-Type: application/json" -d "{\"hora\": \"18:30\", \"audio\": \"C:/ruta/al/archivo.mp3\"}"

curl -X GET "http://127.0.0.1:5000/consultar_alarmas"

curl -X DELETE "http://127.0.0.1:5000/eliminar_alarma/1"