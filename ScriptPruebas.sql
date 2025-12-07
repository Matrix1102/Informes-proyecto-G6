DECLARE
    v_success    NUMBER;
    v_error_code VARCHAR2(4000);
    v_user_id    NUMBER;
BEGIN
    -- Intentamos registrar un usuario nuevo
    AUTH_PKG.SP_REGISTER_WITH_CREDENTIALS(
        p_email         => 'test_user@example.com',
        p_password_hash => 'hash_secreto_123',
        p_first_name    => 'Juan',
        p_last_name     => 'Perez',
        out_success     => v_success,
        out_error_code  => v_error_code,
        out_user_id     => v_user_id
    );

    DBMS_OUTPUT.PUT_LINE('Success: ' || v_success);
    DBMS_OUTPUT.PUT_LINE('Error: '   || v_error_code);
    DBMS_OUTPUT.PUT_LINE('User ID: ' || v_user_id);
END;
/

DECLARE
    v_success     NUMBER;
    v_error_code  VARCHAR2(4000);
    v_user_cursor SYS_REFCURSOR;
    -- Variables para leer el cursor
    v_user_row    USERS%ROWTYPE;
BEGIN
    AUTH_PKG.SP_LOGIN_WITH_CREDENTIALS(
        p_username      => 'test_user@example.com',
        p_password_hash => 'hash_secreto_123',
        out_success     => v_success,
        out_error_code  => v_error_code,
        out_user_cursor => v_user_cursor
    );

    DBMS_OUTPUT.PUT_LINE('Login Success: ' || v_success);

    IF v_success = 1 THEN
        LOOP
            FETCH v_user_cursor INTO v_user_row;
            EXIT WHEN v_user_cursor%NOTFOUND;
            DBMS_OUTPUT.PUT_LINE('Bienvenido: ' || v_user_row.FIRST_NAME || ' ' || v_user_row.LAST_NAME);
        END LOOP;
        CLOSE v_user_cursor;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Error Login: ' || v_error_code);
    END IF;
END;
/

DECLARE
    v_user_id     NUMBER;
    v_identity_id NUMBER;
BEGIN
    AUTH_PKG.SP_FIND_OR_CREATE_USER_OAUTH(
        p_email               => 'oauth_user@gmail.com',
        p_first_name          => 'Maria',
        p_last_name           => 'Gomez',
        p_provider            => 'google',
        p_provider_account_id => 'google_unique_id_12345',
        out_user_id           => v_user_id,
        out_identity_id       => v_identity_id
    );

    DBMS_OUTPUT.PUT_LINE('OAuth User ID: ' || v_user_id);
    DBMS_OUTPUT.PUT_LINE('Identity ID: '   || v_identity_id);
END;
/

DECLARE
    v_host_id NUMBER;
BEGIN
    -- Asumimos User ID 1 (creado en el paso anterior)
    USER_PKG.SP_BECOME_HOST(
        P_USER_ID   => 1, 
        OUT_HOST_ID => v_host_id
    );
    DBMS_OUTPUT.PUT_LINE('Nuevo Host ID: ' || v_host_id);
END;
/

DECLARE
    v_is_tenant NUMBER;
    v_is_host   NUMBER;
BEGIN
    USER_PKG.SP_GET_USER_ROLES(
        P_USER_ID     => 1,
        OUT_IS_TENANT => v_is_tenant,
        OUT_IS_HOST   => v_is_host
    );
    DBMS_OUTPUT.PUT_LINE('Es Tenant: ' || v_is_tenant);
    DBMS_OUTPUT.PUT_LINE('Es Host: '   || v_is_host);
END;
/

DECLARE
    v_profile_cur SYS_REFCURSOR;
    v_prefs_cur   SYS_REFCURSOR;
    
    -- Variables temporales para fetch
    v_fname VARCHAR2(100); v_lname VARCHAR2(100); v_bio CLOB; v_rating NUMBER; v_bookings NUMBER;
    v_pref_id NUMBER; v_code VARCHAR2(50); v_name VARCHAR2(100); v_desc CLOB; v_val VARCHAR2(255);
BEGIN
    USER_PKG.SP_GET_PUBLIC_USER_PROFILE(1, v_profile_cur, v_prefs_cur);

    -- Leer Perfil
    DBMS_OUTPUT.PUT_LINE('--- PERFIL ---');
    LOOP
        FETCH v_profile_cur INTO v_fname, v_lname, v_bio, v_rating, v_bookings;
        EXIT WHEN v_profile_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('User: ' || v_fname || ', Rating: ' || v_rating);
    END LOOP;
    CLOSE v_profile_cur;

    -- Leer Preferencias
    DBMS_OUTPUT.PUT_LINE('--- PREFERENCIAS ---');
    LOOP
        FETCH v_prefs_cur INTO v_pref_id, v_code, v_name, v_desc, v_val;
        EXIT WHEN v_prefs_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_name || ': ' || v_val);
    END LOOP;
    CLOSE v_prefs_cur;
END;
/

BEGIN
    USER_PKG.SP_UPDATE_PUBLIC_USER_PROFILE(
        p_user_id   => 1,
        p_biography => 'Me encanta viajar y conocer lugares nuevos.',
        p_interests => 'Musica, Arte',
        p_pets      => 'Tengo un perro',
        p_location  => 'Lima, Peru',
        p_work      => 'Ingeniero',
        p_language  => 'Español, Ingles',
        p_school    => 'UTP'
    );
    DBMS_OUTPUT.PUT_LINE('Perfil público actualizado.');
END;
/

DECLARE
    v_prop_id    NUMBER;
    v_err_code   VARCHAR2(4000);
    -- JSONs simulados
    v_images_json CLOB := '[{"url":"http://img1.com","caption":"Living","sort_order":1}]';
    v_amenities_json CLOB := '[]'; -- Array vacío por simplicidad
BEGIN
    PROPERTY_PKG.SP_CREATE_PROPERTY(
        P_HOST_ID           => 1, -- Asegúrate que el User 1 sea Host
        P_PROPERTY_TYPE     => 'Apartment',
        P_TITLE             => 'Departamento en Miraflores',
        P_BASE_PRICE_NIGHT  => 150.00,
        P_CURRENCY_CODE     => 'USD', -- Asegúrate de crear monedas primero si hay FK
        P_ADDRESS_TEXT      => 'Av. Larco 123',
        P_CITY              => 'Lima',
        P_STATE_REGION      => 'Lima',
        P_COUNTRY           => 'Peru',
        P_CAPACITY          => 4,
        P_IMAGES            => v_images_json,
        P_AMENITIES         => v_amenities_json,
        OUT_PROPERTY_ID     => v_prop_id,
        OUT_ERROR_CODE      => v_err_code
    );
    
    DBMS_OUTPUT.PUT_LINE('Propiedad ID: ' || v_prop_id);
    DBMS_OUTPUT.PUT_LINE('Error: ' || v_err_code);
END;
/

DECLARE
    v_det_cur SYS_REFCURSOR;
    v_img_cur SYS_REFCURSOR;
    v_amn_cur SYS_REFCURSOR;
    v_rev_sum SYS_REFCURSOR;
    v_rev_lst SYS_REFCURSOR;
    v_err     VARCHAR2(4000);
    
    -- Var auxiliar
    v_title   VARCHAR2(150);
    -- (Se omiten el resto de variables de fetch para no hacer el código gigante, 
    -- pero el bloque verifica que la ejecución no falle)
BEGIN
    PROPERTY_PKG.SP_GET_PROPERTY_PAGE_DETAILS(
        P_PROPERTY_ID           => 1, -- ID generado arriba
        OUT_DETAILS_CURSOR      => v_det_cur,
        OUT_IMAGES_CURSOR       => v_img_cur,
        OUT_AMENITIES_CURSOR    => v_amn_cur,
        OUT_REVIEWS_SUMMARY_CUR => v_rev_sum,
        OUT_REVIEWS_LIST_CURSOR => v_rev_lst,
        OUT_ERROR_CODE          => v_err
    );
    
    DBMS_OUTPUT.PUT_LINE('Error Code: ' || v_err);
    
    -- Ejemplo fetch simple del título
    IF v_det_cur IS NOT NULL THEN
       FETCH v_det_cur INTO v_title; -- (Solo fetch del primer campo para probar)
       -- Nota: en PL/SQL estricto debes hacer fetch de TODAS las columnas del cursor
       -- o usar un ROWTYPE. Aquí solo validamos que no explote.
       CLOSE v_det_cur; 
    END IF;
    -- Calla el resto de cursores
    IF v_img_cur IS NOT NULL THEN CLOSE v_img_cur; END IF;
    IF v_amn_cur IS NOT NULL THEN CLOSE v_amn_cur; END IF;
    IF v_rev_sum IS NOT NULL THEN CLOSE v_rev_sum; END IF;
    IF v_rev_lst IS NOT NULL THEN CLOSE v_rev_lst; END IF;
    
    DBMS_OUTPUT.PUT_LINE('Procedimiento ejecutado correctamente.');
END;
/

DECLARE
    v_date DATE;
    v_status VARCHAR2(20);
BEGIN
    -- Iteramos sobre la tabla pipelined
    FOR r IN (
        SELECT CAL_DATE, STATUS, PRICE 
        FROM TABLE(PROPERTY_PKG.GET_CALENDAR(1, 12, 2025)) -- Propiedad 1, Dic 2025
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(TO_CHAR(r.CAL_DATE, 'DD-MM') || ': ' || r.STATUS);
    END LOOP;
END;
/

DECLARE
    v_res_cur SYS_REFCURSOR;
    v_id NUMBER;
    v_title VARCHAR2(150);
    v_price NUMBER;
    -- Variables adicionales para coincidir con la select del cursor
    v_curr CHAR(3); v_addr VARCHAR2(255); v_fmt_addr VARCHAR2(255);
    v_city VARCHAR2(255); v_region VARCHAR2(255); v_country VARCHAR2(255);
    v_zip VARCHAR2(255); v_lat NUMBER; v_lng NUMBER; v_status VARCHAR2(20);
    v_created DATE; v_img VARCHAR2(500); v_rating NUMBER;
BEGIN
    FILTER_PKG.SP_SEARCH_PROPERTIES(
        p_city       => 'Lima',
        p_min_price  => 50,
        p_max_price  => 500,
        p_result_set => v_res_cur
    );

    LOOP
        FETCH v_res_cur INTO v_id, v_title, v_price, v_curr, v_addr, v_fmt_addr, v_city,
                             v_region, v_country, v_zip, v_lat, v_lng, v_status, v_created, v_img, v_rating;
        EXIT WHEN v_res_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('Encontrado: ' || v_title || ' - Precio: ' || v_price);
    END LOOP;
    CLOSE v_res_cur;
END;
/

DECLARE
    v_cur SYS_REFCURSOR;
    -- Variables placeholder para leer el cursor (simplificado)
    v_book_id NUMBER; v_stat VARCHAR2(20); v_in DATE; v_out DATE;
    -- ... (se requieren muchas variables para el fetch completo) ...
BEGIN
    -- Suponiendo Booking ID 1 y User ID 1 (Tenant o Host)
    BOOKING_PKG.get_detailed_booking_info(
        p_booking_id => 1,
        p_user_id    => 1,
        p_booking_info_cur => v_cur
    );
    
    DBMS_OUTPUT.PUT_LINE('Cursor de detalle de reserva abierto correctamente.');
    IF v_cur IS NOT NULL AND v_cur%ISOPEN THEN CLOSE v_cur; END IF;
END;
/

DECLARE
    v_avail    NUMBER;
    v_err      VARCHAR2(4000);
BEGIN
    CALENDAR_AVAILABILITY_PKG.SP_CHECK_RANGE_AVAILABILITY(
        P_PROPERTY_ID    => 1,
        P_CHECKIN_DATE   => '2025-12-20',
        P_CHECKOUT_DATE  => '2025-12-25',
        OUT_IS_AVAILABLE => v_avail,
        OUT_ERROR_CODE   => v_err
    );
    
    DBMS_OUTPUT.PUT_LINE('Disponible (1=Sí, 0=No): ' || v_avail);
    IF v_err IS NOT NULL THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || v_err);
    END IF;
END;
/

DECLARE
    v_cur SYS_REFCURSOR;
    v_err VARCHAR2(4000);
    v_date VARCHAR2(20);
BEGIN
    CALENDAR_AVAILABILITY_PKG.SP_GET_NEXT_AVAILABLE_DATES(
        P_PROPERTY_ID    => 1,
        P_COUNT          => 5,
        OUT_DATES_CURSOR => v_cur,
        OUT_ERROR_CODE   => v_err
    );

    IF v_err IS NULL THEN
        LOOP
            FETCH v_cur INTO v_date;
            EXIT WHEN v_cur%NOTFOUND;
            DBMS_OUTPUT.PUT_LINE('Fecha libre: ' || v_date);
        END LOOP;
        CLOSE v_cur;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Error: ' || v_err);
    END IF;
END;
/

DECLARE
    v_rev_id  NUMBER;
    v_success NUMBER;
    v_msg     VARCHAR2(4000);
BEGIN
    -- Nota: Esto fallará si no hay un booking completado y un registro placeholder en REVIEWS con rating 0.
    REVIEW_PKG.CREATE_REVIEW(
        p_booking_id  => 1,
        p_reviewer_id => 1, -- User ID
        p_review_type => 'guest', -- guest o host
        p_rating      => 5,
        p_comment     => 'Excelente estadía',
        p_review_id   => v_rev_id,
        p_success     => v_success,
        p_message     => v_msg
    );
    
    DBMS_OUTPUT.PUT_LINE('Success: ' || v_success);
    DBMS_OUTPUT.PUT_LINE('Message: ' || v_msg);
END;
/

DECLARE
    v_cur SYS_REFCURSOR;
    -- Vars
    v_bookings NUMBER; v_rev NUMBER; v_avg NUMBER; v_tick NUMBER;
    v_tot_revs NUMBER; v_props NUMBER; v_act NUMBER;
BEGIN
    HOST_DASHBOARD_PKG.GET_HOST_STATS(
        p_host_id      => 1,
        p_stats_cursor => v_cur
    );

    LOOP
        FETCH v_cur INTO v_bookings, v_rev, v_avg, v_tick, v_tot_revs, v_props, v_act;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('Total Ingresos: ' || v_rev);
        DBMS_OUTPUT.PUT_LINE('Rating Promedio: ' || v_avg);
    END LOOP;
    CLOSE v_cur;
END;
/