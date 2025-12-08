/*
 * ESTRATEGIA DE RESPALDO Y RECUPERACIÓN (DISASTER RECOVERY)
 * Proyecto: SMART
 * Herramienta: Oracle RMAN (Recovery Manager)
 * Tipo: Hot Backup (Respaldo en Caliente - Sin detener servicio)
 */

-- =============================================================================
-- PARTE 1: CONFIGURACIÓN DE MODO ARCHIVELOG (Pre-requisito)
-- Nota: Esto se ejecuta una sola vez desde SQL*Plus as SYSDBA
-- =============================================================================
/*
    SHUTDOWN IMMEDIATE;
    STARTUP MOUNT;
    ALTER DATABASE ARCHIVELOG;
    ALTER DATABASE OPEN;
    -- Verificar estado:
    ARCHIVE LOG LIST;
*/

-- =============================================================================
-- PARTE 2: SCRIPT DE RESPALDO (RMAN)
-- Ejecutar desde terminal: $ rman target /
-- =============================================================================

-- A. RESPALDO COMPLETO (Full Backup)
-- Respalda la base de datos entera, los archivos de control y los logs archivados.
-- 'AS COMPRESSED BACKUPSET': Comprime para ahorrar espacio en disco.
-- 'PLUS ARCHIVELOG': Incluye las transacciones ocurridas durante el backup.
-- 'DELETE INPUT': Borra los logs viejos tras respaldarlos para liberar espacio.

RUN {
    ALLOCATE CHANNEL ch1 DEVICE TYPE DISK;
    BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG DELETE INPUT;
    RELEASE CHANNEL ch1;
}

-- =============================================================================
-- PARTE 3: ESCENARIO DE RECUPERACIÓN (Disaster Recovery)
-- Caso: Pérdida total de archivos de datos (Datafiles) pero con Controlfile intacto.
-- =============================================================================

/*
RUN {
    SHUTDOWN IMMEDIATE;
    STARTUP MOUNT;
    -- Restaura los archivos físicos desde el último backup
    RESTORE DATABASE;
    -- Aplica los cambios (Redo Logs) ocurridos después del backup hasta el fallo
    RECOVER DATABASE;
    ALTER DATABASE OPEN;
}
*/