/*
 * SCRIPT DE PRUEBA DE SEGURIDAD: PREVENCIÓN DE INYECCIÓN SQL
 * Proyecto: SMART
 * Objetivo: Demostrar la robustez de los Paquetes PL/SQL (AUTH_PKG) frente 
 * a ataques de inyección SQL, comparado con SQL dinámico inseguro.
 */

SET SERVEROUTPUT ON;

-- =============================================================================
-- CASO 1: ESCENARIO VULNERABLE (Simulación de "Mala Práctica")
-- Descripción: Así es como hackearían el sistema si usáramos concatenación simple.
-- =============================================================================
DECLARE
    v_user_input  VARCHAR2(100);
    v_query       VARCHAR2(1000);
    v_count       NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('===================================================');
    DBMS_OUTPUT.PUT_LINE('--- 1. PRUEBA DE VULNERABILIDAD (SQL DINÁMICO) ---');
    DBMS_OUTPUT.PUT_LINE('===================================================');
    
    -- EL ATAQUE: El usuario ingresa una comilla para cerrar el string y una condición TRUE
    -- Input normal: "juan@gmail.com"
    -- Input malicioso: "' OR '1'='1"
    v_user_input := ''' OR ''1''=''1'; 
    
    DBMS_OUTPUT.PUT_LINE('Input Malicioso: ' || v_user_input);
    
    -- La consulta se construye pegando texto (PELIGROSO)
    -- Query resultante: SELECT COUNT(*) FROM USERS WHERE EMAIL = '' OR '1'='1'
    v_query := 'SELECT COUNT(*) FROM USERS WHERE EMAIL = ''' || v_user_input || '''';
    
    DBMS_OUTPUT.PUT_LINE('Query Generado: ' || v_query);
    
    BEGIN
        -- Ejecutamos la consulta insegura
        EXECUTE IMMEDIATE v_query INTO v_count;
        
        IF v_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('❌ [PELIGRO] ACCESO CONCEDIDO - INYECCIÓN EXITOSA');
            DBMS_OUTPUT.PUT_LINE('>> El sistema devolvió ' || v_count || ' usuarios (todos).');
            DBMS_OUTPUT.PUT_LINE('>> El atacante ha saltado la autenticación.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('✅ Acceso Denegado');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    END;
END;
/

-- =============================================================================
-- CASO 2: ESCENARIO SEGURO (Implementación Real SMART)
-- Descripción: Intento de ataque contra el paquete AUTH_PKG.
-- =============================================================================
DECLARE
    v_user_input    VARCHAR2(100);
    v_success       NUMBER;
    v_error_code    VARCHAR2(4000);
    v_user_cursor   SYS_REFCURSOR;
BEGIN
    DBMS_OUTPUT.PUT_LINE(CHR(10));
    DBMS_OUTPUT.PUT_LINE('===================================================');
    DBMS_OUTPUT.PUT_LINE('--- 2. PRUEBA DE SEGURIDAD (PL/SQL AUTH_PKG) ---');
    DBMS_OUTPUT.PUT_LINE('===================================================');
    
    -- Usamos EXACTAMENTE el mismo input malicioso
    v_user_input := ''' OR ''1''=''1';
    
    DBMS_OUTPUT.PUT_LINE('Input Malicioso: ' || v_user_input);
    DBMS_OUTPUT.PUT_LINE('Ejecutando AUTH_PKG.SP_LOGIN_WITH_CREDENTIALS...');

    -- Llamada al procedimiento real del sistema
    -- Oracle trata el parámetro P_USERNAME como un literal puro, no como código.
    AUTH_PKG.SP_LOGIN_WITH_CREDENTIALS(
        P_USERNAME      => v_user_input, -- Inyectamos el ataque aquí
        P_PASSWORD_HASH => 'password_cualquiera',
        OUT_SUCCESS     => v_success,
        OUT_ERROR_CODE  => v_error_code,
        OUT_USER_CURSOR => v_user_cursor
    );

    IF v_success = 1 THEN
        DBMS_OUTPUT.PUT_LINE('❌ [FALLO] El sistema permitió el acceso (Esto no debería pasar).');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✅ [SEGURO] ACCESO DENEGADO CORRECTAMENTE');
        DBMS_OUTPUT.PUT_LINE('>> Código de Respuesta: ' || v_error_code);
        DBMS_OUTPUT.PUT_LINE('>> Análisis: Oracle buscó un usuario cuyo email fuera literalmente');
        DBMS_OUTPUT.PUT_LINE('   ["'' OR ''1''=''1"], el cual no existe.');
        DBMS_OUTPUT.PUT_LINE('>> La inyección SQL fue neutralizada.');
    END IF;
    
    -- Cerrar cursor si quedó abierto (buena práctica)
    IF v_user_cursor%ISOPEN THEN CLOSE v_user_cursor; END IF;
END;
/