/*
 * SCRIPT DE CONTROL DE CONCURRENCIA Y BLOQUEOS
 * Proyecto: SMART
 * Objetivo: Implementar "Pessimistic Locking" para evitar el problema de
 * 'Double Booking' (Doble reserva) en situaciones de alta concurrencia.
 */

-- Procedimiento Transaccional Seguro para Reservar
CREATE OR REPLACE PROCEDURE SP_SECURE_BOOKING(
    p_property_id IN NUMBER,
    p_tenant_id   IN NUMBER,
    p_start_date  IN DATE,
    p_end_date    IN DATE,
    out_booking_id OUT NUMBER,
    out_status     OUT VARCHAR2
) IS
    v_dummy_lock NUMBER;
    v_count      NUMBER;
    -- Excepción personalizada para cuando la fila está bloqueada por otro usuario
    e_resource_busy EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_resource_busy, -54);
BEGIN
    -- 1. CONTROL DE CONCURRENCIA (Pessimistic Locking)
    -- Intentamos bloquear la fila de la propiedad específica.
    -- 'FOR UPDATE WAIT 3' intenta bloquear la fila; si está ocupada por otra transacción,
    -- espera 3 segundos. Si sigue ocupada, lanza error ORA-00054.
    -- Esto serializa las reservas para esta propiedad específica.
    SELECT PROPERTY_ID 
    INTO v_dummy_lock
    FROM PROPERTIES 
    WHERE PROPERTY_ID = p_property_id 
    FOR UPDATE WAIT 3;

    -- 2. VERIFICACIÓN DE DISPONIBILIDAD (Dentro de la zona segura/bloqueada)
    -- Al tener el bloqueo, nadie más puede insertar conflictos mientras leemos.
    SELECT COUNT(*)
    INTO v_count
    FROM BOOKINGS
    WHERE PROPERTY_ID = p_property_id
      AND STATUS IN ('CONFIRMED', 'ACCEPTED')
      AND (CHECKIN_DATE < p_end_date AND CHECKOUT_DATE > p_start_date);

    IF v_count > 0 THEN
        ROLLBACK; -- Liberamos el bloqueo
        out_status := 'ERROR: FECHAS NO DISPONIBLES';
        out_booking_id := NULL;
        RETURN;
    END IF;

    -- 3. INSERCIÓN SEGURA
    INSERT INTO BOOKINGS (
        PROPERTY_ID, TENANT_ID, CHECKIN_DATE, CHECKOUT_DATE, 
        GUEST_COUNT, CURRENCY_CODE, NIGHT_COUNT, PRICE_NIGHTS, 
        TOTAL_AMOUNT, STATUS, CREATED_AT
    ) VALUES (
        p_property_id, p_tenant_id, p_start_date, p_end_date,
        1, 'USD', (p_end_date - p_start_date), 100, 
        100 * (p_end_date - p_start_date), 'CONFIRMED', SYSDATE
    ) RETURNING BOOKING_ID INTO out_booking_id;

    -- 4. COMMIT (Libera el bloqueo automáticamente para el siguiente en la fila)
    COMMIT;
    out_status := 'SUCCESS: RESERVA CONFIRMADA';

EXCEPTION
    WHEN e_resource_busy THEN
        ROLLBACK;
        out_status := 'ERROR: SISTEMA OCUPADO, INTENTE NUEVAMENTE';
        -- Aquí el frontend recibiría un aviso de "Alguien más está reservando esto ahora mismo"
    WHEN OTHERS THEN
        ROLLBACK;
        out_status := 'ERROR: ' || SQLERRM;
END;
/