/*
 * SCRIPT DE AUDITORÍA DE TRANSACCIONES (NEGOCIO)
 * Proyecto: SMART
 * Objetivo: Trazabilidad completa del ciclo de vida de las reservas (BOOKINGS).
 * Contenido:
 * 1. Tabla AUDIT_LOGS: Repositorio inmutable de historial.
 * 2. Trigger TRG_AUDIT_BOOKINGS: Captura automática de eventos DML.
 */

-- =============================================================================
-- 1. CREACIÓN DE LA TABLA DE AUDITORÍA
-- Estructura basada en el diseño de seguridad (Diapositiva 25)
-- =============================================================================
CREATE TABLE AUDIT_LOGS (
    LOG_ID       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TABLE_NAME   VARCHAR2(50),    -- Nombre de la tabla auditada
    OPERATION    VARCHAR2(20),    -- Tipo: INSERT, UPDATE, DELETE
    BOOKING_ID   NUMBER,          -- ID de la reserva afectada
    OLD_STATUS   VARCHAR2(20),    -- Estado previo (antes del cambio)
    NEW_STATUS   VARCHAR2(20),    -- Estado nuevo (después del cambio)
    CHANGED_BY   VARCHAR2(50),    -- Usuario de BD/App que realizó la acción
    CHANGED_AT   TIMESTAMP DEFAULT SYSTIMESTAMP -- Marca de tiempo exacta
);

-- Comentario para documentación
COMMENT ON TABLE AUDIT_LOGS IS 'Historial inmutable de cambios de estado en reservas para resolución de disputas.';

-- =============================================================================
-- 2. TRIGGER DE AUDITORÍA (Lógica de Negocio)
-- Se dispara automáticamente para registrar la "Historia" de la reserva
-- =============================================================================
CREATE OR REPLACE TRIGGER TRG_AUDIT_BOOKINGS
AFTER INSERT OR UPDATE OR DELETE ON BOOKINGS
FOR EACH ROW
DECLARE
    v_user VARCHAR2(50);
BEGIN
    -- Capturamos quién está haciendo el cambio (ej. SMART, SYSTEM, o usuario web)
    -- Usamos COALESCE para asegurar que nunca quede nulo
    SELECT COALESCE(SYS_CONTEXT('USERENV', 'OS_USER'), USER) 
    INTO v_user 
    FROM DUAL;

    IF INSERTING THEN
        -- CASO 1: Nueva Reserva (Solo hay estado nuevo)
        INSERT INTO AUDIT_LOGS (
            TABLE_NAME, OPERATION, BOOKING_ID, 
            NEW_STATUS, CHANGED_BY
        ) VALUES (
            'BOOKINGS', 'INSERT', :NEW.BOOKING_ID, 
            :NEW.STATUS, v_user
        );
        
    ELSIF UPDATING THEN
        -- CASO 2: Cambio de Estado (El más importante para disputas)
        -- Solo registramos si el estado realmente cambió para ahorrar espacio
        IF :OLD.STATUS != :NEW.STATUS THEN
            INSERT INTO AUDIT_LOGS (
                TABLE_NAME, OPERATION, BOOKING_ID, 
                OLD_STATUS, NEW_STATUS, CHANGED_BY
            ) VALUES (
                'BOOKINGS', 'UPDATE', :NEW.BOOKING_ID, 
                :OLD.STATUS, :NEW.STATUS, v_user
            );
        END IF;
        
    ELSIF DELETING THEN
        -- CASO 3: Eliminación (Hard Delete - Auditoría crítica)
        INSERT INTO AUDIT_LOGS (
            TABLE_NAME, OPERATION, BOOKING_ID, 
            OLD_STATUS, CHANGED_BY
        ) VALUES (
            'BOOKINGS', 'DELETE', :OLD.BOOKING_ID, 
            :OLD.STATUS, v_user
        );
    END IF;
END;
/