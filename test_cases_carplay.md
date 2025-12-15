# Casos de Prueba - Brisamusic

## CarPlay Plugin

**Fecha:** Diciembre 2025
**Plataforma:** iOS / CarPlay
**Entorno de prueba:** Dispositivo físico (no simulador)

---

## TC-001: Conexión inicial a CarPlay con app cerrada

| Campo | Descripción |
|-------|-------------|
| **ID** | TC-001 |
| **Nombre** | Conexión inicial a CarPlay con app cerrada |
| **Precondiciones** | La aplicación Brisamusic está instalada pero cerrada. El dispositivo iOS no está conectado a CarPlay. |
| **Pasos** | 1. Conectar el dispositivo iOS al sistema CarPlay del vehículo con la aplicación cerrada. |
| **Resultado Esperado** | La aplicación debe cargar la navegación, la cola de reproducción y el current track. El estado debe quedar en PAUSE (sin reproducir audio). |
| **Resultado Actual** | ✅ La aplicación carga correctamente la navegación, cola y current track sin iniciar reproducción automática. |
| **Estado** | 🟢 PASA |
| **Fix** | `reloadQueueInternal()` en CDVMusicPlayer.swift ahora carga el track y metadata sin llamar a `play()`. |

---

## TC-002: Reproducción secuencial de cola

| Campo | Descripción |
|-------|-------------|
| **ID** | TC-002 |
| **Nombre** | Reproducción secuencial de playlist/album/artista |
| **Precondiciones** | La aplicación está conectada a CarPlay. Existe una cola de reproducción con múltiples tracks (playlist, album o artista seleccionado). |
| **Pasos** | 1. Seleccionar un elemento para reproducir (playlist, album o artista). 2. Esperar a que termine el primer track. 3. Observar el comportamiento al cambiar al siguiente track. |
| **Resultado Esperado** | Al terminar el primer track, debe comenzar automáticamente el siguiente track y continuar así hasta reproducir todos los tracks de la cola de reproducción. |
| **Resultado Actual** | ✅ Al terminar cada track, el siguiente comienza automáticamente. |
| **Estado** | 🟢 PASA |
| **Fix** | `itemDidPlayToEnd()` llama a `skipToNext()` que incluye `play()` para continuar la reproducción. |

---
