# Casos de Prueba - Brisamusic

## CarPlay Plugin

**Fecha:** Noviembre 2025
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
| **Resultado Actual** | ⚠️ La aplicación comienza a reproducir audio por unos segundos y luego se pausa automáticamente. |
| **Estado** | 🔴 FALLA |

---

## TC-002: Reproducción secuencial de cola

| Campo | Descripción |
|-------|-------------|
| **ID** | TC-002 |
| **Nombre** | Reproducción secuencial de playlist/album/artista |
| **Precondiciones** | La aplicación está conectada a CarPlay. Existe una cola de reproducción con múltiples tracks (playlist, album o artista seleccionado). |
| **Pasos** | 1. Seleccionar un elemento para reproducir (playlist, album o artista). 2. Esperar a que termine el primer track. 3. Observar el comportamiento al cambiar al siguiente track. |
| **Resultado Esperado** | Al terminar el primer track, debe comenzar automáticamente el siguiente track y continuar así hasta reproducir todos los tracks de la cola de reproducción. |
| **Resultado Actual** | ⚠️ Al terminar el primer track, carga el segundo track pero queda en estado PAUSE. No continúa la reproducción automáticamente. |
| **Estado** | 🔴 FALLA |

---
