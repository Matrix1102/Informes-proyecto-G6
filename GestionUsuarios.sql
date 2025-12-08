/*
 * SCRIPT DE GESTIÓN DE USUARIOS Y SEGURIDAD
 * Proyecto: SMART
 * Descripción: Implementación de perfiles de alta disponibilidad, 
 * roles de privilegio mínimo y segregación de esquemas.
 */

-- 1. LIMPIEZA PREVIA (Solo si se requiere reiniciar)
-- DROP USER SMART CASCADE;
-- DROP ROLE ROL_SMART;
-- DROP PROFILE PRF_SMART;

-- 2. PERFIL DE SEGURIDAD (Capa Operativa)
-- Objetivo: Proteger contra fuerza bruta y garantizar alta disponibilidad.
CREATE PROFILE PRF_SMART LIMIT
  FAILED_LOGIN_ATTEMPTS 3        -- Bloquea cuenta tras 3 fallos
  PASSWORD_LIFE_TIME UNLIMITED   -- Evita caducidad en producción
  SESSIONS_PER_USER 50;          -- Límite de concurrencia

-- 3. ROL DE APLICACIÓN (Capa Funcional)
-- Objetivo: Principio de Privilegio Mínimo. Sin permisos DBA.
CREATE ROLE ROL_SMART;

GRANT 
    CREATE SESSION,      -- Conexión
    CREATE TABLE,        -- Estructura
    CREATE VIEW,         -- Vistas
    CREATE SEQUENCE,     -- Identificadores
    CREATE PROCEDURE,    -- Lógica de Negocio
    CREATE TRIGGER,      -- Automatización
    CREATE TYPE          -- Tipos de datos
TO ROL_SMART;

-- 4. USUARIO DEL SISTEMA (Capa de Identidad)
-- Objetivo: Aislamiento físico en Tablespaces dedicados.
CREATE USER SMART IDENTIFIED BY "Smart_Pass_2025"
  DEFAULT TABLESPACE TS_SMART
  TEMPORARY TABLESPACE TS_SMART_TEMP
  PROFILE PRF_SMART
  QUOTA UNLIMITED ON TS_SMART
  QUOTA UNLIMITED ON TS_SMART_IDX;

-- 5. ASIGNACIÓN DE ROL
GRANT ROL_SMART TO SMART;