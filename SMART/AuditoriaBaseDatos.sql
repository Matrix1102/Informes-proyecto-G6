/*
 * SCRIPT DE AUDITORÍA DE BASE DE DATOS (SEGURIDAD ADMINISTRATIVA)
 * Proyecto: SMART
 * Objetivo: Configuración de políticas de auditoría nativa para monitorear 
 * accesos (Logins) y cambios estructurales (DDL) en el entorno de producción.
 */

-- =============================================================================
-- 1. AUDITORÍA DE ACCESOS (LOGIN / SESSION)
-- Objetivo: Detectar intentos de intrusión y monitorear actividad de usuarios.
-- =============================================================================

-- Auditar todos los inicios de sesión (exitosos y fallidos)
-- Permite identificar patrones de uso y accesos fuera de horario.
AUDIT SESSION;

-- Auditar específicamente los fallos de autenticación con prioridad alta
-- Fundamental para detectar ataques de fuerza bruta o diccionarios.
AUDIT SESSION WHENEVER NOT SUCCESSFUL;

-- =============================================================================
-- 2. AUDITORÍA DE OBJETOS DEL ESQUEMA (DDL)
-- Objetivo: Alerta temprana ante modificaciones no autorizadas de la estructura.
-- =============================================================================

-- Vigilamos la creación, modificación o eliminación de objetos críticos
-- por parte del usuario de aplicación 'SMART'.
AUDIT TABLE, VIEW, PROCEDURE, TRIGGER, SEQUENCE 
    BY SMART 
    BY ACCESS;

-- =============================================================================
-- 3. AUDITORÍA DE PRIVILEGIOS CRÍTICOS (SYSTEM)
-- Objetivo: Monitorear escalada de privilegios o acciones destructivas.
-- =============================================================================

-- Auditar si alguien intenta borrar tablas de cualquier esquema
AUDIT DROP ANY TABLE;

-- Auditar cambios en la configuración del sistema o usuarios
AUDIT ALTER SYSTEM;
AUDIT ALTER USER;

-- =============================================================================
-- 4. VISTA DE CONSULTA (EVIDENCIA FORENSE)
-- Script de utilidad para que el Auditor revise los logs generados.
-- =============================================================================
/*
SELECT 
    OS_USER,        -- Usuario del S.O. (quién está en el teclado)
    USERNAME,       -- Usuario de BD (quién dice ser)
    USERHOST,       -- Desde qué PC se conecta
    TIMESTAMP,      -- Cuándo ocurrió
    ACTION_NAME,    -- Qué hizo (LOGON, DROP TABLE, etc.)
    RETURNCODE      -- 0 = Éxito, >0 = Código de Error (Ej. 1017 = Bad Password)
FROM DBA_AUDIT_TRAIL
WHERE USERNAME = 'SMART' OR USERNAME = 'SYSTEM'
ORDER BY TIMESTAMP DESC;
*/