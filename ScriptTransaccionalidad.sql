/*
   ARCHIVO: script_transacciones_acid.sql
   DESCRIPCIÓN: Prueba de 3 flujos transaccionales clave (Auth, Propiedad, Review).
   REQUISITO: Ejecutar con "SET SERVEROUTPUT ON" habilitado.
*/

SET SERVEROUTPUT ON;

--------------------------------------------------------------------------------
-- PREPARACIÓN DEL ENTORNO (SETUP)
-- Evita errores de FK (Moneda) y limpia datos previos si es necesario
--------------------------------------------------------------------------------
DECLARE
    v_count NUMBER;
BEGIN
    -- 1. Asegurar que existe la moneda USD
    SELECT COUNT(*) INTO v_count FROM CURRENCIES WHERE CURRENCY_CODE = 'USD';
    IF v_count = 0 THEN
        INSERT INTO CURRENCIES (CURRENCY_CODE, NAME, EXPONENT) VALUES ('USD', 'US Dollar', 2);
        COMMIT;
    END IF;
    DBMS_OUTPUT.PUT_LINE('--- ENTORNO PREPARADO ---');
END;
/

--------------------------------------------------------------------------------
-- TRANSACCIÓN 1: REGISTRO DE USUARIO
-- ETIQUETA: Atomicidad en Identidad
-- DESCRIPCIÓN: Crea un usuario en la tabla 'USERS' y su credencial en 
-- 'USER_AUTH_IDENTITIES' como una unidad atómica. Si falla la creación de la 
-- identidad (ej. password nulo), se hace ROLLBACK de la creación del usuario.
--------------------------------------------------------------------------------
DECLARE
    v_success    NUMBER;
    v_error_code VARCHAR2(4000);
    v_user_id    NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== 1. PRUEBA: AUTH_PKG.SP_REGISTER_WITH_CREDENTIALS ===');

    AUTH_PKG.SP_REGISTER_WITH_CREDENTIALS(
        p_email         => 'host_user_test@example.com',
        p_password_hash => 'hash_seguro_123',
        p_first_name    => 'Roberto',
        p_last_name     => 'Gomez',
        out_success     => v_success,
        out_error_code  => v_error_code,
        out_user_id     => v_user_id
    );

    IF v_success = 1 THEN
        DBMS_OUTPUT.PUT_LINE('>> ÉXITO: Usuario creado con ID: ' || v_user_id);
        
        -- PASO EXTRA: Convertirlo en HOST para la siguiente prueba
        DECLARE v_host_id NUMBER; BEGIN
            USER_PKG.SP_BECOME_HOST(v_user_id, v_host_id);
            DBMS_OUTPUT.PUT_LINE('>> ROL: Usuario ahora es Host ID: ' || v_host_id);
        END;
    ELSE
        DBMS_OUTPUT.PUT_LINE('>> FALLO: ' || v_error_code);
    END IF;
END;
/

--------------------------------------------------------------------------------
-- TRANSACCIÓN 2: CREACIÓN DE PROPIEDAD
-- ETIQUETA: Consistencia Maestro-Detalle
-- DESCRIPCIÓN: Inserta datos en 4 tablas (Properties, Details, Images, Amenities)
-- dentro de una sola transacción. Parsea JSONs para las tablas hijas. Garantiza
-- que no existan propiedades "huérfanas" sin detalles técnicos.
--------------------------------------------------------------------------------
DECLARE
    v_host_id    NUMBER;
    v_prop_id    NUMBER;
    v_error      VARCHAR2(4000);
    -- JSONs simulados
    v_imgs_json  CLOB := '[{"url":"http://img.com/1.jpg", "caption":"Fachada", "sort_order":1}]';
    v_amen_json  CLOB := '[]'; 
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== 2. PRUEBA: PROPERTY_PKG.SP_CREATE_PROPERTY ===');

    -- Obtener el ID del usuario creado en el paso anterior (por email)
    SELECT USER_ID INTO v_host_id FROM USERS WHERE EMAIL = 'host_user_test@example.com';

    PROPERTY_PKG.SP_CREATE_PROPERTY(
        P_HOST_ID           => v_host_id,
        P_PROPERTY_TYPE     => 'Apartment',
        P_TITLE             => 'Departamento Lujoso en Miraflores',
        P_BASE_PRICE_NIGHT  => 120.00,
        P_CURRENCY_CODE     => 'USD',
        P_ADDRESS_TEXT      => 'Av. Pardo 550',
        P_CITY              => 'Lima',
        P_STATE_REGION      => 'Lima',
        P_COUNTRY           => 'Peru',
        P_BEDROOMS          => 2,
        P_BATHROOMS         => 2,
        P_CAPACITY          => 4,
        P_IMAGES            => v_imgs_json,
        P_AMENITIES         => v_amen_json,
        OUT_PROPERTY_ID     => v_prop_id,
        OUT_ERROR_CODE      => v_error
    );

    IF v_error IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('>> ÉXITO: Propiedad creada con ID: ' || v_prop_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('>> FALLO: ' || v_error);
    END IF;
END;
/

--------------------------------------------------------------------------------
-- TRANSACCIÓN 3: PUBLICACIÓN DE RESEÑA
-- ETIQUETA: Integridad de Negocio
-- DESCRIPCIÓN: Valida que exista una "reseña pendiente" (creada por trigger al
-- completar reserva) y la actualiza con texto/rating. Usa COMMIT explícito.
-- NOTA: Este bloque incluye código de PREPARACIÓN (crear tenant, reserva, pago)
-- para simular el escenario real donde se permite dejar una reseña.
--------------------------------------------------------------------------------
DECLARE
    -- IDs
    v_prop_id     NUMBER;
    v_tenant_id   NUMBER;
    v_booking_id  NUMBER;
    v_review_id   NUMBER;
    
    -- Variables de salida del SP
    v_success     NUMBER;
    v_msg         VARCHAR2(4000);
    
    -- Auxiliar para creación de usuario tenant
    v_dummy_res   NUMBER; v_dummy_err VARCHAR2(4000);
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== 3. PRUEBA: REVIEW_PKG.CREATE_REVIEW ===');

    -- A. SETUP: NECESITAMOS UN TENANT Y UNA RESERVA COMPLETADA
    -- 1. Obtener propiedad creada arriba
    SELECT MAX(PROPERTY_ID) INTO v_prop_id FROM PROPERTIES WHERE TITLE = 'Departamento Lujoso en Miraflores';
    
    -- 2. Crear un Tenant (Usuario diferente al Host)
    AUTH_PKG.SP_REGISTER_WITH_CREDENTIALS(
        'tenant_test@gmail.com', 'pass123', 'Maria', 'Tenant', 
        v_dummy_res, v_dummy_err, v_tenant_id
    );
    -- Insertar en tabla TENANTS (trigger lo hace, pero aseguramos datos)
    UPDATE TENANTS SET BIO = 'Viajera frecuente' WHERE TENANT_ID = v_tenant_id;

    -- 3. Crear una Reserva PENDING -> COMPLETED
    INSERT INTO BOOKINGS (
        PROPERTY_ID, TENANT_ID, CHECKIN_DATE, CHECKOUT_DATE, GUEST_COUNT, 
        CURRENCY_CODE, NIGHT_COUNT, PRICE_NIGHTS, TOTAL_AMOUNT, STATUS
    ) VALUES (
        v_prop_id, v_tenant_id, SYSDATE-5, SYSDATE-1, 2, 
        'USD', 4, 100, 400, 'PENDING'
    ) RETURNING BOOKING_ID INTO v_booking_id;
    
    -- 4. Completar la reserva (Esto dispara TRG_BOOKING_COMPLETED_REVIEWS y crea la reseña placeholder)
    UPDATE BOOKINGS SET STATUS = 'COMPLETED', COMPLETED_AT = SYSDATE WHERE BOOKING_ID = v_booking_id;
    COMMIT; -- Confirmamos la preparación
    
    DBMS_OUTPUT.PUT_LINE('>> SETUP: Reserva ' || v_booking_id || ' completada. Placeholder de reseña generado.');

    -- B. EJECUCIÓN DE LA TRANSACCIÓN DEL SP
    -- El tenant (v_tenant_id) deja una reseña sobre la propiedad
    REVIEW_PKG.CREATE_REVIEW(
        p_booking_id  => v_booking_id,
        p_reviewer_id => v_tenant_id,
        p_review_type => 'guest',   -- 'guest' opina sobre la propiedad/host
        p_rating      => 5,
        p_comment     => 'Excelente estadía, muy limpio y ordenado.',
        p_review_id   => v_review_id,
        p_success     => v_success,
        p_message     => v_msg
    );

    IF v_success = 1 THEN
        DBMS_OUTPUT.PUT_LINE('>> ÉXITO: Reseña publicada ID: ' || v_review_id);
        DBMS_OUTPUT.PUT_LINE('>> MENSAJE: ' || v_msg);
    ELSE
        DBMS_OUTPUT.PUT_LINE('>> FALLO: ' || v_msg);
    END IF;
END;
/