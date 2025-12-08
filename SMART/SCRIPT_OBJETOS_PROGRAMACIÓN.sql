
create PACKAGE AUTH_PKG AS
    PROCEDURE SP_LOGIN_WITH_CREDENTIALS(
        P_USERNAME IN VARCHAR2,
        P_PASSWORD_HASH IN VARCHAR2,
        OUT_SUCCESS OUT NUMBER, -- 1 = success, 0 = failure
        OUT_ERROR_CODE OUT VARCHAR2,
        OUT_USER_CURSOR OUT SYS_REFCURSOR -- devuelve cursor con datos de usuario (si aplica)
    );

    PROCEDURE SP_FIND_OR_CREATE_USER_OAUTH(
        p_email IN VARCHAR2,
        p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2,
        p_provider IN VARCHAR2,
        p_provider_account_id IN VARCHAR2,
        out_user_id OUT NUMBER,
        out_identity_id OUT NUMBER
    );

    PROCEDURE SP_UPDATE_LAST_LOGIN(
        P_IDENTITY_ID IN NUMBER
    );

    PROCEDURE SP_REGISTER_WITH_CREDENTIALS(
        p_email IN VARCHAR2,
        p_password_hash IN VARCHAR2,
        p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2,
        out_success OUT NUMBER,
        out_error_code OUT VARCHAR2,
        out_user_id OUT NUMBER
    );

END AUTH_PKG;
/

create PACKAGE BODY AUTH_PKG AS

    -- Función privada: valida estado del usuario
    FUNCTION FN_VALIDATE_USER_LOGIN(
        p_user_id IN NUMBER
    ) RETURN VARCHAR2 AS
        v_status         USERS.STATUS%TYPE;
        v_email_verified USER_AUTH_IDENTITIES.EMAIL_VERIFIED%TYPE;
    BEGIN
        -- Esta consulta puede fallar con TOO_MANY_ROWS si un usuario
        -- tiene múltiples identidades (ej. 'local' y 'google').
        -- Considera añadir "AND ROWNUM = 1" si eso se convierte en un problema.
        SELECT u.STATUS, a.EMAIL_VERIFIED
        INTO v_status, v_email_verified
        FROM USERS u
                 JOIN USER_AUTH_IDENTITIES a ON u.USER_ID = a.USER_ID
        WHERE u.USER_ID = p_user_id
          AND ROWNUM = 1; -- Añadido para seguridad

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'USER_NOT_FOUND';
    END FN_VALIDATE_USER_LOGIN;


    -- Implementación del SP público de Login con credenciales
    PROCEDURE SP_LOGIN_WITH_CREDENTIALS(
        p_username IN VARCHAR2,
        p_password_hash IN VARCHAR2,
        out_success OUT NUMBER,
        out_error_code OUT VARCHAR2,
        out_user_cursor OUT SYS_REFCURSOR
    ) IS
        v_user_id        USERS.USER_ID%TYPE;
        v_status         USERS.STATUS%TYPE;
        v_email_verified USER_AUTH_IDENTITIES.EMAIL_VERIFIED%TYPE;
    BEGIN

        -- Paso 1: ...
        BEGIN
            SELECT a.USER_ID,
                   u.STATUS,
                   a.EMAIL_VERIFIED
            INTO
                v_user_id,
                v_status,
                v_email_verified
            FROM USER_AUTH_IDENTITIES a
                     JOIN
                 USERS u ON a.USER_ID = u.USER_ID
            WHERE a.PROVIDER = 'credentials'
              AND (LOWER(a.PROVIDER_USER_ID) = LOWER(p_username) OR LOWER(a.EMAIL) = LOWER(p_username))
              AND a.PASSWORD_HASH = p_password_hash;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                out_success := 0;
                out_error_code := 'INVALID_CREDENTIALS';
                out_user_cursor := NULL; -- (Esta ya la tenías)
                RETURN;
        END;

        -- Paso 2: Validar si el usuario está activo.
        IF v_status <> 'active' THEN
            out_success := 0;
            out_error_code := 'USER_INACTIVE';
            out_user_cursor := NULL; -- <-- !! CORRECCIÓN !!
            RETURN;
        END IF;

        -- Paso 3: Validar si el email de esa identidad está verificado.
        IF v_email_verified = 0 THEN
            out_success := 0;
            out_error_code := 'EMAIL_NOT_VERIFIED';
            out_user_cursor := NULL; -- <-- !! CORRECCIÓN !!
            RETURN;
        END IF;

        -- Paso 4: ¡Éxito!
        out_success := 1;
        out_error_code := NULL;
        OPEN out_user_cursor FOR
            SELECT * FROM USERS WHERE USER_ID = v_user_id;

    EXCEPTION
        -- Manejar cualquier otro error inesperado
        WHEN OTHERS THEN
            out_success := 0;
            out_error_code := SQLCODE || ': ' || SQLERRM;
            out_user_cursor := NULL; -- <-- !! CORRECCIÓN !!

    END SP_LOGIN_WITH_CREDENTIALS;


    -- Implementación del SP público de OAuth (buscar o crear)
    PROCEDURE SP_FIND_OR_CREATE_USER_OAUTH(
        p_email IN VARCHAR2,
        p_first_name IN VARCHAR2, -- Recibe el nombre ya dividido
        p_last_name IN VARCHAR2, -- Recibe el apellido ya dividido
        p_provider IN VARCHAR2,
        p_provider_account_id IN VARCHAR2,
        out_user_id OUT NUMBER,
        out_identity_id OUT NUMBER
    ) IS
        v_user_id     NUMBER;
        v_identity_id NUMBER;
        -- Se eliminan las variables v_first_name y v_last_name
    BEGIN
        -- Validar parámetros de entrada
        IF p_email IS NULL THEN RAISE_APPLICATION_ERROR(-20001, 'Email no puede ser NULL'); END IF;
        IF p_provider_account_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Provider Account ID no puede ser NULL');
        END IF;
        -- Ya no validamos p_name, sino que confiamos en lo que envía el código

        -- Paso 1: MANEJAR LA TABLA USERS (BUSCAR O CREAR)
        BEGIN
            -- Buscar usuario existente por email
            SELECT USER_ID INTO v_user_id FROM USERS WHERE LOWER(TRIM(EMAIL)) = LOWER(TRIM(p_email));

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Si no existe, crearlo usando los parámetros recibidos
                -- Se elimina el bloque DECLARE intermedio
                INSERT INTO USERS (FIRST_NAME, LAST_NAME, EMAIL, CREATED_AT, STATUS)
                VALUES (p_first_name, p_last_name, LOWER(TRIM(p_email)), SYSDATE, 'active')
                RETURNING USER_ID INTO v_user_id;

                IF v_user_id IS NULL THEN
                    RAISE_APPLICATION_ERROR(-20003, 'No se pudo crear el usuario');
                END IF;
        END;
        -- Fin bloque BEGIN/EXCEPTION para USERS

        -- A este punto, v_user_id SIEMPRE tiene un valor

        -- Paso 2: MANEJAR USER_AUTH_IDENTITIES (Buscar primero, luego insertar)
        -- (Esta lógica permanece igual que la que proporcionaste)
        BEGIN
            -- Intentar BUSCAR la identidad existente
            SELECT IDENTITY_ID
            INTO v_identity_id
            FROM USER_AUTH_IDENTITIES
            WHERE USER_ID = v_user_id
              AND PROVIDER = p_provider
              AND PROVIDER_USER_ID = p_provider_account_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Si NO la encuentra, INSERTARLA
                INSERT INTO USER_AUTH_IDENTITIES (USER_ID, PROVIDER_USER_ID, PROVIDER,
                                                  PASSWORD_HASH, EMAIL_VERIFIED, EMAIL, CREATED_AT)
                VALUES (v_user_id, p_provider_account_id, p_provider,
                        NULL, 1, LOWER(TRIM(p_email)), SYSDATE)
                RETURNING IDENTITY_ID INTO v_identity_id;

                IF v_identity_id IS NULL THEN
                    RAISE_APPLICATION_ERROR(-20004, 'No se pudo crear la identidad de autenticación');
                END IF;
        END;
        -- Fin del bloque BEGIN/EXCEPTION para USER_AUTH_IDENTITIES

        -- 3. ASIGNAR VALORES DE SALIDA
        out_user_id := v_user_id;
        out_identity_id := v_identity_id;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE; -- Re-lanza la excepción original
    END SP_FIND_OR_CREATE_USER_OAUTH;


    -- Implementación del SP público de actualizar login
    PROCEDURE SP_UPDATE_LAST_LOGIN(
        p_identity_id IN NUMBER
    ) AS
    BEGIN
        UPDATE USER_AUTH_IDENTITIES
        SET LAST_LOGIN_AT = SYSDATE
        WHERE IDENTITY_ID = p_identity_id;
        COMMIT;
    END SP_UPDATE_LAST_LOGIN;

    PROCEDURE SP_REGISTER_WITH_CREDENTIALS(
        p_email IN VARCHAR2,
        p_password_hash IN VARCHAR2,
        p_first_name IN VARCHAR2,
        p_last_name IN VARCHAR2,
        out_success OUT NUMBER,
        out_error_code OUT VARCHAR2,
        out_user_id OUT NUMBER
    ) IS
        v_user_count  NUMBER := 0;
        v_new_user_id users.user_id%TYPE;
    BEGIN
        -- 1. Verificar si el email ya existe
        SELECT COUNT(*)
        INTO v_user_count
        FROM users
        WHERE email = LOWER(p_email);

        IF v_user_count > 0 THEN
            out_success := 0;
            out_error_code := 'EMAIL_ALREADY_EXISTS';
            out_user_id := NULL;
            RETURN;
        END IF;

        -- 2. Iniciar transacción (implícita en PL/SQL)

        -- 3. Crear el usuario en la tabla 'users'
        INSERT INTO users (email, first_name, last_name)
        VALUES (LOWER(p_email), p_first_name, p_last_name)
        RETURNING user_id INTO v_new_user_id;

        -- 4. Crear la identidad en la tabla 'identities'
        INSERT INTO USER_AUTH_IDENTITIES(user_id, provider, EMAIL, password_hash, EMAIL_VERIFIED, PROVIDER_USER_ID)
        VALUES (v_new_user_id, 'credentials', LOWER(p_email), p_password_hash, 1, LOWER(p_email));

        -- 5. Finalizar transacción
        COMMIT;

        out_success := 1;
        out_error_code := NULL;
        out_user_id := v_new_user_id;

    EXCEPTION
        WHEN OTHERS THEN
            -- 6. Revertir todo si algo falla
            ROLLBACK;
            out_success := 0;
            out_error_code := SQLCODE || ': ' || SQLERRM;
            out_user_id := NULL;
    END SP_REGISTER_WITH_CREDENTIALS;

END AUTH_PKG;
/

create PACKAGE USER_PKG AS

    PROCEDURE SP_GET_USER_ROLES(
        P_USER_ID IN users.user_id%TYPE, -- Buena práctica usar %TYPE
        OUT_IS_TENANT OUT NUMBER,
        OUT_IS_HOST OUT NUMBER
    );

    PROCEDURE SP_BECOME_HOST(
        P_USER_ID IN users.user_id%TYPE,
        OUT_HOST_ID OUT hosts.host_id%TYPE
    );

    PROCEDURE SP_GET_USER_PROFILE(
        p_user_id IN NUMBER,
        p_first_name OUT VARCHAR2,
        p_last_name OUT VARCHAR2,
        p_email OUT VARCHAR2,
        p_phone OUT VARCHAR2,
        p_dni OUT VARCHAR2,
        p_birth_date OUT DATE,
        p_created_at OUT DATE,
        p_updated_at OUT DATE
    );

    PROCEDURE SP_GET_PUBLIC_USER_PROFILE(
        p_user_id IN NUMBER,
        p_profile_cursor OUT SYS_REFCURSOR,
        p_preferences_cursor OUT SYS_REFCURSOR
    );

    PROCEDURE SP_UPDATE_PUBLIC_USER_PROFILE(
        p_user_id IN NUMBER,
        p_biography IN CLOB,

        -- Parámetros para las 6 preferencias
        p_interests IN VARCHAR2,
        p_pets IN VARCHAR2,
        p_location IN VARCHAR2,
        p_work IN VARCHAR2,
        p_language IN VARCHAR2,
        p_school IN VARCHAR2
    );

    PROCEDURE SP_UPDATE_USER_PROFILE(
        p_user_id IN NUMBER,
        p_first_name IN VARCHAR2 DEFAULT NULL,
        p_last_name IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL,
        p_phone IN VARCHAR2 DEFAULT NULL,
        p_dni IN VARCHAR2 DEFAULT NULL,
        p_birth_date IN DATE DEFAULT NULL
    );

END USER_PKG;
/

create PACKAGE BODY USER_PKG AS

    PROCEDURE SP_GET_USER_ROLES(
        P_USER_ID IN users.user_id%TYPE,
        OUT_IS_TENANT OUT NUMBER,
        OUT_IS_HOST OUT NUMBER
    ) IS
    BEGIN
        -- Inicializamos ambos roles como 0 (falso)
        OUT_IS_TENANT := 0;
        OUT_IS_HOST := 0;

        -- Bloque 1: Chequear si es Tenant
        -- Usamos un bloque anónimo para que si NO_DATA_FOUND, no detenga el resto.
        BEGIN
            SELECT 1
            INTO OUT_IS_TENANT
            FROM tenants
            WHERE TENANT_ID = P_USER_ID; -- El ID de tenant es el ID de usuario
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                OUT_IS_TENANT := 0; -- No se encontró, confirma que es 0
        END;

        -- Bloque 2: Chequear si es Host
        BEGIN
            SELECT 1
            INTO OUT_IS_HOST
            FROM hosts
            WHERE HOST_ID = P_USER_ID; -- Aquí la FK se llama user_id
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                OUT_IS_HOST := 0; -- No se encontró, confirma que es 0
        END;
    END SP_GET_USER_ROLES;

    PROCEDURE SP_BECOME_HOST(
        P_USER_ID IN users.user_id%TYPE,
        OUT_HOST_ID OUT hosts.host_id%TYPE
    ) IS
        v_already_host_count NUMBER;
    BEGIN
        -- Paso 1: Verificar si el usuario ya es un host.
        -- Esto evita un error de "violación de restricción única" (UNIQUE)
        SELECT COUNT(*)
        INTO v_already_host_count
        FROM hosts
        WHERE HOST_ID = P_USER_ID;

        IF v_already_host_count > 0 THEN
            -- Si ya es host, no hacemos nada, solo devolvemos su ID de host.
            SELECT host_id
            INTO OUT_HOST_ID
            FROM hosts
            WHERE HOST_ID = P_USER_ID;

            RETURN; -- Salimos del procedimiento
        END IF;

        -- Paso 2: Si no es host, lo creamos.
        -- (Asumimos que host_id es IDENTITY y created_at es DEFAULT SYSDATE)
        INSERT INTO hosts (HOST_ID, CREATED_AT)
        VALUES (P_USER_ID, SYSDATE)
        RETURNING host_id INTO OUT_HOST_ID; -- Devuelve el nuevo ID generado

    EXCEPTION
        WHEN OTHERS THEN
            OUT_HOST_ID := NULL; -- En caso de error, devolvemos NULL
            RAISE; -- Relanzamos el error para que la aplicación lo sepa

    END SP_BECOME_HOST;

    PROCEDURE SP_GET_USER_PROFILE(
        p_user_id IN NUMBER,
        p_first_name OUT VARCHAR2,
        p_last_name OUT VARCHAR2,
        p_email OUT VARCHAR2,
        p_phone OUT VARCHAR2,
        p_dni OUT VARCHAR2,
        p_birth_date OUT DATE,
        p_created_at OUT DATE,
        p_updated_at OUT DATE
    )
        IS
    BEGIN
        SELECT first_name,
               last_name,
               email,
               phone_number,
               dni,
               birth_date,
               created_at,
               updated_at
        INTO -- La diferencia clave es el 'INTO'
            p_first_name,
            p_last_name,
            p_email,
            p_phone,
            p_dni,
            p_birth_date,
            p_created_at,
            p_updated_at
        FROM users
        WHERE user_id = p_user_id;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Si el usuario no existe, todos los parámetros OUT
            -- quedarán en NULL automáticamente, lo cual suele ser lo deseado.
            NULL;
        WHEN OTHERS THEN
            RAISE; -- Relanza cualquier otro error
    END SP_GET_USER_PROFILE;

    PROCEDURE SP_GET_PUBLIC_USER_PROFILE(
        p_user_id IN NUMBER,
        p_profile_cursor OUT SYS_REFCURSOR,
        p_preferences_cursor OUT SYS_REFCURSOR
    )
        IS
        v_tenant_id NUMBER;
    BEGIN
        -- 1. Obtenemos el tenant_id del usuario primero. (SIN CAMBIOS)
        BEGIN
            SELECT tenant_id
            INTO v_tenant_id
            FROM tenants
            WHERE TENANT_ID = p_user_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_tenant_id := NULL;
        END;

        -- 2. Cursor 1: Devuelve la información básica (Perfil y Estadísticas)
        -- Se usa una subconsulta (b_agg) para calcular el COUNT sin agrupar por CLOB.
        OPEN p_profile_cursor FOR
            SELECT u.first_name,
                   u.last_name,
                   t.bio,
                   t.AVERAGE_RATING,
                   NVL(b_agg.total_bookings, 0) AS total_bookings -- NVL para 0 si no hay reservas
            FROM users u
                     LEFT JOIN
                 tenants t ON u.user_id = t.TENANT_ID -- Obtiene el bio (CLOB)
                     LEFT JOIN -- JOIN a la subconsulta de agregación
                (SELECT b.TENANT_ID,
                        COUNT(b.BOOKING_ID) AS total_bookings -- Agregación
                 FROM bookings b
                 WHERE b.TENANT_ID = p_user_id -- Importante: Filtrar aquí para la subconsulta
                 GROUP BY b.TENANT_ID -- Se agrupa solo por el ID (no CLOB)
                ) b_agg ON t.TENANT_ID = b_agg.TENANT_ID -- Une la agregación al perfil
            WHERE u.user_id = p_user_id;
        -- Filtro final en el usuario

        -- 3. Cursor 2: Devuelve la lista de preferencias del usuario (SIN CAMBIOS)
        OPEN p_preferences_cursor FOR
            SELECT p.preference_id,
                   p.CODE,
                   p.NAME,
                   p.DESCRIPTION,
                   tp.VALUE_TEXT
            FROM preferences p
                     LEFT JOIN
                 tenant_preferences tp ON p.preference_id = tp.preference_id
                     AND tp.tenant_id = v_tenant_id;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE;

    END SP_GET_PUBLIC_USER_PROFILE;

    PROCEDURE SP_UPDATE_PUBLIC_USER_PROFILE(
        p_user_id IN NUMBER,
        p_biography IN CLOB,

        -- Parámetros para las 6 preferencias
        p_interests IN VARCHAR2,
        p_pets IN VARCHAR2,
        p_location IN VARCHAR2,
        p_work IN VARCHAR2,
        p_language IN VARCHAR2,
        p_school IN VARCHAR2
    )
        IS
        -- Usamos la lógica que el user_id es el tenant_id
        v_tenant_id NUMBER := p_user_id;
    BEGIN

        -- 1. Actualizamos la Biografía en la tabla 'tenants'
        UPDATE tenants
        SET bio = p_biography
        WHERE tenant_id = v_tenant_id;

        -- 2. Procesamos 'INTERESTS'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'INTERESTS') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_interests
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_interests);

        -- 3. Procesamos 'PETS'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'PETS') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_pets
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_pets);

        -- 4. Procesamos 'LOCATION'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'LOCATION') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_location
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_location);

        -- 5. Procesamos 'WORK'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'WORK') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_work
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_work);

        -- 6. Procesamos 'LANGUAGE'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'LANGUAGE') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_language
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_language);

        -- 7. Procesamos 'SCHOOL'
        MERGE INTO tenant_preferences tp
        USING (SELECT preference_id FROM preferences WHERE CODE = 'SCHOOL') p
        ON (tp.tenant_id = v_tenant_id AND tp.preference_id = p.preference_id)
        WHEN MATCHED THEN
            UPDATE SET tp.value_text = p_school
        WHEN NOT MATCHED THEN
            INSERT (tenant_id, preference_id, value_text)
            VALUES (v_tenant_id, p.preference_id, p_school);

        -- 8. Confirmamos todos los cambios
        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK; -- Deshacemos todo si algo sale mal
            RAISE; -- Enviamos el error a la API
    END SP_UPDATE_PUBLIC_USER_PROFILE;

    PROCEDURE sp_update_user_profile(
        p_user_id IN NUMBER,
        p_first_name IN VARCHAR2 DEFAULT NULL,
        p_last_name IN VARCHAR2 DEFAULT NULL,
        p_email IN VARCHAR2 DEFAULT NULL,
        p_phone IN VARCHAR2 DEFAULT NULL,
        p_dni IN VARCHAR2 DEFAULT NULL,
        p_birth_date IN DATE DEFAULT NULL
    )
        IS
    BEGIN
        UPDATE users
        SET first_name   = COALESCE(p_first_name, first_name),
            last_name    = COALESCE(p_last_name, last_name),
            email        = COALESCE(p_email, email),
            PHONE_NUMBER = COALESCE(p_phone, PHONE_NUMBER),
            dni          = COALESCE(p_dni, dni),
            birth_date   = COALESCE(p_birth_date, birth_date)
        WHERE user_id = p_user_id;

        -- No se pone COMMIT aquí; se deja que la aplicación que llama
        -- (tu API) maneje la transacción (COMMIT o ROLLBACK).

    EXCEPTION
        WHEN OTHERS THEN
            RAISE; -- Relanza el error para que la aplicación lo gestione.

    END sp_update_user_profile;

END USER_PKG;
/

create PACKAGE PROPERTY_PKG AS

    PROCEDURE SP_CREATE_PROPERTY(
        -- PROPERTIES (Requeridos)
        P_HOST_ID IN PROPERTIES.HOST_ID%TYPE,
        P_PROPERTY_TYPE IN PROPERTIES.PROPERTY_TYPE%TYPE,
        P_TITLE IN PROPERTIES.TITLE%TYPE,
        P_BASE_PRICE_NIGHT IN PROPERTIES.BASE_PRICE_NIGHT%TYPE,
        P_CURRENCY_CODE IN PROPERTIES.CURRENCY_CODE%TYPE,
        P_ADDRESS_TEXT IN PROPERTIES.ADDRESS_TEXT%TYPE,
        P_CITY IN PROPERTIES.CITY%TYPE,
        P_STATE_REGION IN PROPERTIES.STATE_REGION%TYPE,
        P_COUNTRY IN PROPERTIES.COUNTRY%TYPE,

        -- PROPERTIES (Opcionales)
        P_POSTAL_CODE IN PROPERTIES.POSTAL_CODE%TYPE DEFAULT NULL,
        P_LATITUDE IN PROPERTIES.LATITUDE%TYPE DEFAULT NULL,
        P_LONGITUDE IN PROPERTIES.LONGITUDE%TYPE DEFAULT NULL,

        -- PROPERTY_DETAILS (Casi todos con valor por defecto o NULL)
        P_DESCRIPTION_LONG IN PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES IN PROPERTY_DETAILS.HOUSE_RULES%TYPE DEFAULT NULL,
        P_CHECKIN_TIME IN VARCHAR2 DEFAULT NULL,
        P_CHECKOUT_TIME IN VARCHAR2 DEFAULT NULL,
        P_CAPACITY IN PROPERTY_DETAILS.CAPACITY%TYPE DEFAULT 1,
        P_BEDROOMS IN PROPERTY_DETAILS.BEDROOMS%TYPE DEFAULT 0,
        P_BATHROOMS IN PROPERTY_DETAILS.BATHROOMS%TYPE DEFAULT 0,
        P_BEDS IN PROPERTY_DETAILS.BEDS%TYPE DEFAULT 0,
        P_AREA IN PROPERTY_DETAILS.AREA_M2%TYPE DEFAULT NULL,
        P_FLOOR_NUMBER IN PROPERTY_DETAILS.FLOOR_NUMBER%TYPE DEFAULT NULL,
        P_MAX_ADULTS IN PROPERTY_DETAILS.MAX_ADULTS%TYPE DEFAULT NULL,
        P_MAX_CHILDREN IN PROPERTY_DETAILS.MAX_CHILDREN%TYPE DEFAULT NULL,
        P_MAX_BABY IN PROPERTY_DETAILS.MAX_BABY%TYPE DEFAULT NULL,
        P_MAX_PETS IN PROPERTY_DETAILS.MAX_PETS%TYPE DEFAULT NULL,

        -- JSON (Images y Amenities)
        P_IMAGES IN CLOB DEFAULT NULL,
        P_AMENITIES IN CLOB DEFAULT NULL,

        -- Salida
        OUT_PROPERTY_ID OUT PROPERTIES.PROPERTY_ID%TYPE,
        OUT_ERROR_CODE OUT VARCHAR2
    );

    PROCEDURE SP_UPDATE_PROPERTY(
        -- Parámetros Requeridos
        P_PROPERTY_ID IN PROPERTIES.PROPERTY_ID%TYPE,

        -- Campos de PROPERTIES (Opcionales)
        P_TITLE IN PROPERTIES.TITLE%TYPE DEFAULT NULL,
        P_BASE_PRICE_NIGHT IN PROPERTIES.BASE_PRICE_NIGHT%TYPE DEFAULT NULL,
        P_ADDRESS_TEXT IN PROPERTIES.ADDRESS_TEXT%TYPE DEFAULT NULL,
        P_CITY IN PROPERTIES.CITY%TYPE DEFAULT NULL,
        P_STATE_REGION IN PROPERTIES.STATE_REGION%TYPE DEFAULT NULL,
        P_COUNTRY IN PROPERTIES.COUNTRY%TYPE DEFAULT NULL,
        P_POSTAL_CODE IN PROPERTIES.POSTAL_CODE%TYPE DEFAULT NULL,
        P_LATITUDE IN PROPERTIES.LATITUDE%TYPE DEFAULT NULL,
        P_LONGITUDE IN PROPERTIES.LONGITUDE%TYPE DEFAULT NULL,

        -- Campos de PROPERTY_DETAILS (Opcionales)
        P_DESCRIPTION_LONG IN PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES IN PROPERTY_DETAILS.HOUSE_RULES%TYPE DEFAULT NULL,
        P_CHECKIN_TIME IN PROPERTY_DETAILS.CHECKIN_TIME%TYPE DEFAULT NULL,
        P_CHECKOUT_TIME IN PROPERTY_DETAILS.CHECKOUT_TIME%TYPE DEFAULT NULL,
        P_CAPACITY IN PROPERTY_DETAILS.CAPACITY%TYPE DEFAULT NULL,
        P_BEDROOMS IN PROPERTY_DETAILS.BEDROOMS%TYPE DEFAULT NULL,
        P_BATHROOMS IN PROPERTY_DETAILS.BATHROOMS%TYPE DEFAULT NULL,
        P_BEDS IN PROPERTY_DETAILS.BEDS%TYPE DEFAULT NULL,

        -- Salida
        OUT_ERROR_CODE OUT VARCHAR2
    );

    PROCEDURE SP_GET_PROPERTY_PAGE_DETAILS(
        P_PROPERTY_ID IN PROPERTIES.PROPERTY_ID%TYPE,
        OUT_DETAILS_CURSOR OUT SYS_REFCURSOR,
        OUT_IMAGES_CURSOR OUT SYS_REFCURSOR,
        OUT_AMENITIES_CURSOR OUT SYS_REFCURSOR,
        OUT_REVIEWS_SUMMARY_CUR OUT SYS_REFCURSOR,
        OUT_REVIEWS_LIST_CURSOR OUT SYS_REFCURSOR,
        OUT_ERROR_CODE OUT VARCHAR2
    );

    PROCEDURE SET_AVAILABILITY(
        P_PROPERTY_ID IN AVAILABILITIES.PROPERTY_ID%TYPE,
        P_START_DATE IN AVAILABILITIES.START_DATE%type,
        P_END_DATE IN AVAILABILITIES.END_DATE%type,
        P_KIND IN VARCHAR2,
        P_PRICE_PER_NIGHT IN AVAILABILITIES.PRICE_PER_NIGHT%type,
        P_ERROR_CODE OUT NUMBER
    );

    PROCEDURE SP_REMOVE_AVAILABILITY(
        P_PROPERTY_ID IN NUMBER,
        P_START_DATE IN DATE,
        P_END_DATE IN DATE,
        P_ROWS_DELETED OUT NUMBER,
        P_ERROR_CODE OUT NUMBER
    );

    FUNCTION GET_CALENDAR(
        p_property_id IN PROPERTIES.PROPERTY_ID%TYPE,
        p_month IN NUMBER,
        p_year IN NUMBER
    ) RETURN T_CALENDAR_DAY_TABLE PIPELINED;

    FUNCTION FN_GET_PROPERTIES_BY_HOST(
        P_HOST_ID IN HOSTS.HOST_ID%TYPE
    )
        RETURN SYS_REFCURSOR;


END PROPERTY_PKG;
/

create PACKAGE BODY PROPERTY_PKG AS

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_CREATE_PROPERTY
    -- Crea una nueva propiedad, sus detalles, imágenes y amenities.
    ------------------------------------------------------------------------------
    PROCEDURE SP_CREATE_PROPERTY(
        P_HOST_ID IN PROPERTIES.HOST_ID%TYPE,
        P_PROPERTY_TYPE IN PROPERTIES.PROPERTY_TYPE%TYPE,
        P_TITLE IN PROPERTIES.TITLE%TYPE,
        P_BASE_PRICE_NIGHT IN PROPERTIES.BASE_PRICE_NIGHT%TYPE,
        P_CURRENCY_CODE IN PROPERTIES.CURRENCY_CODE%TYPE,
        P_ADDRESS_TEXT IN PROPERTIES.ADDRESS_TEXT%TYPE,
        P_CITY IN PROPERTIES.CITY%TYPE,
        P_STATE_REGION IN PROPERTIES.STATE_REGION%TYPE,
        P_COUNTRY IN PROPERTIES.COUNTRY%TYPE,
        P_POSTAL_CODE IN PROPERTIES.POSTAL_CODE%TYPE DEFAULT NULL,
        P_LATITUDE IN PROPERTIES.LATITUDE%TYPE DEFAULT NULL,
        P_LONGITUDE IN PROPERTIES.LONGITUDE%TYPE DEFAULT NULL,
        P_DESCRIPTION_LONG IN PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES IN PROPERTY_DETAILS.HOUSE_RULES%TYPE DEFAULT NULL,
        P_CHECKIN_TIME IN VARCHAR2 DEFAULT NULL,
        P_CHECKOUT_TIME IN VARCHAR2 DEFAULT NULL,
        P_CAPACITY IN PROPERTY_DETAILS.CAPACITY%TYPE DEFAULT 1,
        P_BEDROOMS IN PROPERTY_DETAILS.BEDROOMS%TYPE DEFAULT 0,
        P_BATHROOMS IN PROPERTY_DETAILS.BATHROOMS%TYPE DEFAULT 0,
        P_BEDS IN PROPERTY_DETAILS.BEDS%TYPE DEFAULT 0,
        P_AREA IN PROPERTY_DETAILS.AREA_M2%TYPE DEFAULT NULL,
        P_FLOOR_NUMBER IN PROPERTY_DETAILS.FLOOR_NUMBER%TYPE DEFAULT NULL,
        P_MAX_ADULTS IN PROPERTY_DETAILS.MAX_ADULTS%TYPE DEFAULT NULL,
        P_MAX_CHILDREN IN PROPERTY_DETAILS.MAX_CHILDREN%TYPE DEFAULT NULL,
        P_MAX_BABY IN PROPERTY_DETAILS.MAX_BABY%TYPE DEFAULT NULL,
        P_MAX_PETS IN PROPERTY_DETAILS.MAX_PETS%TYPE DEFAULT NULL,
        P_IMAGES IN CLOB DEFAULT NULL,
        P_AMENITIES IN CLOB DEFAULT NULL,
        OUT_PROPERTY_ID OUT PROPERTIES.PROPERTY_ID%TYPE,
        OUT_ERROR_CODE OUT VARCHAR2
    ) IS
        V_NEW_PROPERTY_ID PROPERTIES.PROPERTY_ID%TYPE;
        V_FORMATTED_ADDRESS PROPERTIES.FORMATTED_ADDRESS%TYPE;
        V_CHECKIN_DATE VARCHAR(5);
        V_CHECKOUT_DATE VARCHAR(5);
    BEGIN
        -- Generar la dirección completa (FORMATTED_ADDRESS)
        V_FORMATTED_ADDRESS := P_ADDRESS_TEXT || ', ' || P_CITY || ', ' || P_STATE_REGION || ', ' || P_COUNTRY;

        -- Convertir las horas de entrada/salida de String a DATE/Time
        IF P_CHECKIN_TIME IS NOT NULL THEN
            V_CHECKIN_DATE := SUBSTR(P_CHECKIN_TIME, 1, 5);
        ELSE
            V_CHECKIN_DATE := '15:00'; -- Default
        END IF;

        IF P_CHECKOUT_TIME IS NOT NULL THEN
            V_CHECKOUT_DATE := SUBSTR(P_CHECKOUT_TIME, 1, 5);
        ELSE
            V_CHECKOUT_DATE := '11:00'; -- Default
        END IF;

        -- 1. Obtener el nuevo PROPERTY_ID
        SELECT ISEQ$$_75860.NEXTVAL INTO V_NEW_PROPERTY_ID FROM DUAL;
        OUT_PROPERTY_ID := V_NEW_PROPERTY_ID;

        -- 2. Insertar en PROPERTIES
        INSERT INTO PROPERTIES (
            PROPERTY_ID, HOST_ID, PROPERTY_TYPE, TITLE, BASE_PRICE_NIGHT, CURRENCY_CODE,
            ADDRESS_TEXT, FORMATTED_ADDRESS, CITY, STATE_REGION, COUNTRY, POSTAL_CODE, LATITUDE, LONGITUDE, STATUS,
            CREATED_AT
        )
        VALUES (
            V_NEW_PROPERTY_ID, P_HOST_ID, P_PROPERTY_TYPE, P_TITLE, P_BASE_PRICE_NIGHT, P_CURRENCY_CODE,
            P_ADDRESS_TEXT, V_FORMATTED_ADDRESS, P_CITY, P_STATE_REGION, P_COUNTRY, P_POSTAL_CODE, P_LATITUDE, P_LONGITUDE,
            'ACTIVE',SYSDATE
        );

        -- 3. Insertar en PROPERTY_DETAILS
        INSERT INTO PROPERTY_DETAILS (
            PROPERTY_ID, DESCRIPTION_LONG, HOUSE_RULES, CHECKIN_TIME, CHECKOUT_TIME,
            CAPACITY, BEDROOMS, BATHROOMS, BEDS, AREA_M2, FLOOR_NUMBER,
            MAX_ADULTS, MAX_CHILDREN, MAX_BABY, MAX_PETS
        )
        VALUES (
            V_NEW_PROPERTY_ID, P_DESCRIPTION_LONG, P_HOUSE_RULES, V_CHECKIN_DATE, V_CHECKOUT_DATE,
            P_CAPACITY, P_BEDROOMS, P_BATHROOMS, P_BEDS, P_AREA, P_FLOOR_NUMBER,
            P_MAX_ADULTS, P_MAX_CHILDREN, P_MAX_BABY, P_MAX_PETS
        );

        -- 4. Insertar en PROPERTY_AMENITIES (Usando JSON_TABLE)
        IF P_AMENITIES IS NOT NULL THEN
            INSERT INTO PROPERTY_AMENITIES (PROPERTY_ID, AMENITY_ID)
            SELECT V_NEW_PROPERTY_ID, T.AMENITY_ID
            FROM JSON_TABLE(P_AMENITIES, '$[*]'
                COLUMNS (
                    AMENITY_ID VARCHAR2(10) PATH '$'
                )
            ) T;
        END IF;

        -- 5. Insertar en PROPERTY_IMAGES
        IF P_IMAGES IS NOT NULL THEN
            INSERT INTO PROPERTY_IMAGES (PROPERTY_ID, URL, CAPTION, SORT_ORDER)
            SELECT V_NEW_PROPERTY_ID, T.URL, T.CAPTION, T.SORT_ORDER
            FROM JSON_TABLE(P_IMAGES, '$[*]'
                COLUMNS (
                    URL VARCHAR2(500) PATH '$.url',
                    CAPTION VARCHAR2(150) PATH '$.caption',
                    SORT_ORDER NUMBER PATH '$.sort_order'
                )
            ) T;
        END IF;

        -- 6. Confirmar la transacción
        COMMIT;
        OUT_ERROR_CODE := NULL; -- Éxito

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            OUT_PROPERTY_ID := NULL;
            OUT_ERROR_CODE := SQLERRM;

    END SP_CREATE_PROPERTY;

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_UPDATE_PROPERTY
    ------------------------------------------------------------------------------
    PROCEDURE SP_UPDATE_PROPERTY(
        P_PROPERTY_ID IN PROPERTIES.PROPERTY_ID%TYPE,
        P_TITLE IN PROPERTIES.TITLE%TYPE DEFAULT NULL,
        P_BASE_PRICE_NIGHT IN PROPERTIES.BASE_PRICE_NIGHT%TYPE DEFAULT NULL,
        P_ADDRESS_TEXT IN PROPERTIES.ADDRESS_TEXT%TYPE DEFAULT NULL,
        P_CITY IN PROPERTIES.CITY%TYPE DEFAULT NULL,
        P_STATE_REGION IN PROPERTIES.STATE_REGION%TYPE DEFAULT NULL,
        P_COUNTRY IN PROPERTIES.COUNTRY%TYPE DEFAULT NULL,
        P_POSTAL_CODE IN PROPERTIES.POSTAL_CODE%TYPE DEFAULT NULL,
        P_LATITUDE IN PROPERTIES.LATITUDE%TYPE DEFAULT NULL,
        P_LONGITUDE IN PROPERTIES.LONGITUDE%TYPE DEFAULT NULL,
        P_DESCRIPTION_LONG IN PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES IN PROPERTY_DETAILS.HOUSE_RULES%TYPE DEFAULT NULL,
        P_CHECKIN_TIME IN PROPERTY_DETAILS.CHECKIN_TIME%TYPE DEFAULT NULL,
        P_CHECKOUT_TIME IN PROPERTY_DETAILS.CHECKOUT_TIME%TYPE DEFAULT NULL,
        P_CAPACITY IN PROPERTY_DETAILS.CAPACITY%TYPE DEFAULT NULL,
        P_BEDROOMS IN PROPERTY_DETAILS.BEDROOMS%TYPE DEFAULT NULL,
        P_BATHROOMS IN PROPERTY_DETAILS.BATHROOMS%TYPE DEFAULT NULL,
        P_BEDS IN PROPERTY_DETAILS.BEDS%TYPE DEFAULT NULL,
        OUT_ERROR_CODE OUT VARCHAR2
    ) IS
    BEGIN
        -- Paso 1: Actualizar la tabla principal PROPERTIES
        UPDATE PROPERTIES
        SET TITLE            = NVL(P_TITLE, TITLE),
            BASE_PRICE_NIGHT = NVL(P_BASE_PRICE_NIGHT, BASE_PRICE_NIGHT),
            ADDRESS_TEXT     = NVL(P_ADDRESS_TEXT, ADDRESS_TEXT),
            CITY             = NVL(P_CITY, CITY),
            STATE_REGION     = NVL(P_STATE_REGION, STATE_REGION),
            COUNTRY          = NVL(P_COUNTRY, COUNTRY),
            POSTAL_CODE      = NVL(P_POSTAL_CODE, POSTAL_CODE),
            LATITUDE         = NVL(P_LATITUDE, LATITUDE),
            LONGITUDE        = NVL(P_LONGITUDE, LONGITUDE)
        WHERE PROPERTY_ID = P_PROPERTY_ID;

        IF SQL%NOTFOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'Propiedad no encontrada');
        END IF;

        -- Paso 2: Actualizar la tabla de detalles PROPERTY_DETAILS
        UPDATE PROPERTY_DETAILS
        SET DESCRIPTION_LONG = NVL(P_DESCRIPTION_LONG, DESCRIPTION_LONG),
            HOUSE_RULES      = NVL(P_HOUSE_RULES, HOUSE_RULES),
            CHECKIN_TIME     = NVL(P_CHECKIN_TIME, CHECKIN_TIME),
            CHECKOUT_TIME    = NVL(P_CHECKOUT_TIME, CHECKOUT_TIME),
            CAPACITY         = NVL(P_CAPACITY, CAPACITY),
            BEDROOMS         = NVL(P_BEDROOMS, BEDROOMS),
            BATHROOMS        = NVL(P_BATHROOMS, BATHROOMS),
            BEDS             = NVL(P_BEDS, BEDS)
        WHERE PROPERTY_ID = P_PROPERTY_ID;

        -- Paso 3: Confirmar la transacción
        COMMIT;
        OUT_ERROR_CODE := NULL; -- Éxito

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            OUT_ERROR_CODE := SQLERRM;

    END SP_UPDATE_PROPERTY;

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_GET_PROPERTY_PAGE_DETAILS
    -- Devuelve todos los datos necesarios para la página de detalle de una propiedad
    ------------------------------------------------------------------------------
    PROCEDURE SP_GET_PROPERTY_PAGE_DETAILS(
        P_PROPERTY_ID IN PROPERTIES.PROPERTY_ID%TYPE,
        OUT_DETAILS_CURSOR OUT SYS_REFCURSOR,
        OUT_IMAGES_CURSOR OUT SYS_REFCURSOR,
        OUT_AMENITIES_CURSOR OUT SYS_REFCURSOR,
        OUT_REVIEWS_SUMMARY_CUR OUT SYS_REFCURSOR,
        OUT_REVIEWS_LIST_CURSOR OUT SYS_REFCURSOR,
        OUT_ERROR_CODE OUT VARCHAR2
    ) IS
        v_img_count  NUMBER := 0;
        v_amen_count NUMBER := 0;
        v_rev_count  NUMBER := 0;
    BEGIN
        -- 1. Cursor de detalles (Propiedad + Detalles + Host)
        OPEN OUT_DETAILS_CURSOR FOR
            SELECT p.TITLE,
                   p.PROPERTY_TYPE,
                   p.BASE_PRICE_NIGHT,
                   p.CURRENCY_CODE,
                   p.FORMATTED_ADDRESS,
                   p.CITY,
                   p.STATE_REGION,
                   p.COUNTRY,
                   p.LATITUDE,
                   p.LONGITUDE,
                   pd.DESCRIPTION_LONG,
                   pd.HOUSE_RULES,
                   pd.CHECKIN_TIME,
                   pd.CHECKOUT_TIME,
                   pd.CAPACITY,
                   pd.BEDROOMS,
                   pd.BATHROOMS,
                   pd.BEDS,
                   u.FIRST_NAME  AS HOST_FIRST_NAME,
                   u.LAST_NAME   AS HOST_LAST_NAME,
                   h.IS_VERIFIED AS HOST_IS_VERIFIED,
                   h.CREATED_AT  AS HOST_JOINED_AT
            FROM PROPERTIES p
                     JOIN PROPERTY_DETAILS pd ON p.PROPERTY_ID = pd.PROPERTY_ID
                     JOIN HOSTS h ON p.HOST_ID = h.HOST_ID
                     JOIN USERS u ON h.HOST_ID = u.USER_ID
            WHERE p.PROPERTY_ID = P_PROPERTY_ID;

        -- 2. Cursor de imágenes
        SELECT COUNT(*)
        INTO v_img_count
        FROM PROPERTY_IMAGES
        WHERE PROPERTY_ID = P_PROPERTY_ID;

        IF v_img_count > 0 THEN
            OPEN OUT_IMAGES_CURSOR FOR
                SELECT URL, CAPTION
                FROM PROPERTY_IMAGES
                WHERE PROPERTY_ID = P_PROPERTY_ID
                ORDER BY SORT_ORDER;
        ELSE
            OPEN OUT_IMAGES_CURSOR FOR
                SELECT CAST(NULL AS VARCHAR2(500)) AS URL,
                       CAST(NULL AS VARCHAR2(150)) AS CAPTION
                FROM DUAL
                WHERE 1 = 0;
        END IF;

        -- 3. Cursor de amenities
        SELECT COUNT(*)
        INTO v_amen_count
        FROM PROPERTY_AMENITIES
        WHERE PROPERTY_ID = P_PROPERTY_ID;

        IF v_amen_count > 0 THEN
            OPEN OUT_AMENITIES_CURSOR FOR
                SELECT a.NAME, a.CODE, a.DESCRIPTION
                FROM PROPERTY_AMENITIES pa
                         JOIN AMENITIES a ON pa.AMENITY_ID = a.AMENITY_ID
                WHERE pa.PROPERTY_ID = P_PROPERTY_ID
                ORDER BY a.DISPLAY_ORDER, a.NAME;
        ELSE
            OPEN OUT_AMENITIES_CURSOR FOR
                SELECT NULL AS NAME, NULL AS CODE, NULL AS DESCRIPTION
                FROM DUAL
                WHERE 1 = 0;
        END IF;

        -- 4. Cursor de resumen de reseñas (siempre devuelve una fila)
        OPEN OUT_REVIEWS_SUMMARY_CUR FOR
            SELECT NVL(COUNT(R.REVIEW_ID), 0)      AS TOTAL_COUNT,
                   NVL(ROUND(AVG(R.RATING), 2), 0) AS AVERAGE_RATING
            FROM REVIEWS R
            WHERE R.PROPERTY_ID = P_PROPERTY_ID
              AND R.IS_PUBLISHED = 1
              AND R.FOR_HOST = 0;

        -- 5. Cursor de lista de reseñas (máx 5)
        SELECT COUNT(*)
        INTO v_rev_count
        FROM REVIEWS
        WHERE PROPERTY_ID = P_PROPERTY_ID
          AND IS_PUBLISHED = 1
          AND FOR_HOST = 0;

        IF v_rev_count > 0 THEN
            OPEN OUT_REVIEWS_LIST_CURSOR FOR
                SELECT R.RATING,
                       R.COMMENTS,  -- <<< CORREGIDO: Usando el nombre correcto de la columna
                       R.CREATED_AT,
                       U.FIRST_NAME AS AUTHOR_FIRST_NAME,
                       U.LAST_NAME  AS AUTHOR_LAST_NAME
                FROM REVIEWS R
                         JOIN USERS U ON R.AUTHOR_USER_ID = U.USER_ID
                WHERE R.PROPERTY_ID = P_PROPERTY_ID
                  AND R.IS_PUBLISHED = 1
                  AND R.FOR_HOST = 0
                ORDER BY R.CREATED_AT DESC
                    FETCH NEXT 5 ROWS ONLY;
        ELSE
            OPEN OUT_REVIEWS_LIST_CURSOR FOR
                SELECT NULL AS RATING,
                       NULL AS COMMENTS, -- <<< CORREGIDO: Consistencia en el alias
                       NULL AS CREATED_AT,
                       NULL AS AUTHOR_FIRST_NAME,
                       NULL AS AUTHOR_LAST_NAME
                FROM DUAL
                WHERE 1 = 0;
        END IF;

        OUT_ERROR_CODE := NULL;

    EXCEPTION
        WHEN OTHERS THEN
            OUT_ERROR_CODE := 'Error al obtener detalles: ' || SQLERRM;
    END SP_GET_PROPERTY_PAGE_DETAILS;

    ------------------------------------------------------------------------------
    -- PROCEDURE: SET_AVAILABILITY
    ------------------------------------------------------------------------------
    PROCEDURE SET_AVAILABILITY(
        P_PROPERTY_ID IN AVAILABILITIES.PROPERTY_ID%TYPE,
        P_START_DATE IN AVAILABILITIES.START_DATE%type,
        P_END_DATE IN AVAILABILITIES.END_DATE%type,
        P_KIND IN VARCHAR2,
        P_PRICE_PER_NIGHT IN AVAILABILITIES.PRICE_PER_NIGHT%type,
        P_ERROR_CODE OUT NUMBER
    )
    AS
        v_booking_count NUMBER;
        v_avail_count   NUMBER;
        E_BOOKING_CONFLICT EXCEPTION;
        E_AVAILABILITY_CONFLICT EXCEPTION;
    BEGIN
        p_error_code := 0;

        -- 1. Validación de regla de negocio (Conflictos con RESERVAS)
        IF P_KIND = 'BLOCKED' OR P_KIND = 'MAINTENANCE' THEN
            SELECT COUNT(*)
            INTO v_booking_count
            FROM BOOKINGS b
            WHERE b.PROPERTY_ID = P_PROPERTY_ID
              AND b.status = 'CONFIRMED'
              AND (b.CHECKIN_DATE < p_end_date AND b.CHECKOUT_DATE > p_start_date);

            IF v_booking_count > 0 THEN
                RAISE E_BOOKING_CONFLICT;
            END IF;
        END IF;

        -- 2. Validación: Conflicto con otros AJUSTES
        SELECT COUNT(*)
        INTO v_avail_count
        FROM AVAILABILITIES a
        WHERE a.PROPERTY_ID = P_PROPERTY_ID
          AND (a.START_DATE < p_end_date AND a.END_DATE > p_start_date);

        IF v_avail_count > 0 THEN
            RAISE E_AVAILABILITY_CONFLICT;
        END IF;

        -- 3. Inserción
        INSERT INTO AVAILABILITIES (PROPERTY_ID,
                                    START_DATE,
                                    END_DATE,
                                    KIND,
                                    PRICE_PER_NIGHT)
        VALUES (p_property_id,
                p_start_date,
                p_end_date,
                p_kind,
                P_PRICE_PER_NIGHT);

        COMMIT;

    EXCEPTION
        WHEN E_BOOKING_CONFLICT THEN
            p_error_code := 1;
        WHEN E_AVAILABILITY_CONFLICT THEN
            p_error_code := 2;
        WHEN OTHERS THEN
            ROLLBACK;
            p_error_code := -1;
    END SET_AVAILABILITY;

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_REMOVE_AVAILABILITY
    ------------------------------------------------------------------------------
    PROCEDURE SP_REMOVE_AVAILABILITY(
        P_PROPERTY_ID IN NUMBER,
        P_START_DATE IN DATE,
        P_END_DATE IN DATE,
        P_ROWS_DELETED OUT NUMBER,
        P_ERROR_CODE OUT NUMBER
    ) AS
    BEGIN
        P_ERROR_CODE := 0;
        P_ROWS_DELETED := 0;

        DECLARE
            V_COUNT NUMBER;
        BEGIN
            SELECT COUNT(*)
            INTO V_COUNT
            FROM PROPERTIES
            WHERE PROPERTY_ID = P_PROPERTY_ID;

            IF V_COUNT = 0 THEN
                P_ERROR_CODE := 1;
                RETURN;
            END IF;
        END;

        DELETE
        FROM AVAILABILITIES
        WHERE PROPERTY_ID = P_PROPERTY_ID
          AND KIND NOT IN ('default', 'reserved')
          AND (
            START_DATE <= P_END_DATE
                AND END_DATE >= P_START_DATE
            );

        P_ROWS_DELETED := SQL%ROWCOUNT;

        IF P_ROWS_DELETED = 0 THEN
            P_ERROR_CODE := 2;
            RETURN;
        END IF;

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            P_ERROR_CODE := 99;
            P_ROWS_DELETED := 0;
    END SP_REMOVE_AVAILABILITY;

    ------------------------------------------------------------------------------
    -- FUNCTION: GET_CALENDAR
    ------------------------------------------------------------------------------
    FUNCTION GET_CALENDAR(
        p_property_id IN PROPERTIES.PROPERTY_ID%TYPE,
        p_month IN NUMBER,
        p_year IN NUMBER
    ) RETURN T_CALENDAR_DAY_TABLE PIPELINED
    AS
        v_current_day  DATE           := TO_DATE(p_year || '-' || p_month || '-01', 'YYYY-MM-DD');
        v_end_of_month DATE           := LAST_DAY(v_current_day);
        v_day_status   T_CALENDAR_DAY := T_CALENDAR_DAY(NULL, 0, 0, NULL);
        v_base_price   PROPERTIES.BASE_PRICE_NIGHT%TYPE;
        v_is_reserved  NUMBER;
        v_avail_rec    AVAILABILITIES%ROWTYPE;

    BEGIN
        -- 1. Obtenemos el precio base
        BEGIN
            SELECT p.BASE_PRICE_NIGHT
            INTO v_base_price
            FROM PROPERTIES p
            WHERE p.PROPERTY_ID = p_property_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN;
        END;

        -- 2. Iteramos por cada día del mes
        WHILE v_current_day <= v_end_of_month
            LOOP
                v_day_status.CAL_DATE := v_current_day;
                v_is_reserved := 0;
                v_avail_rec := NULL;

                -- 3. Prioridad #1: ¿Está reservado? (BOOKINGS)
                SELECT COUNT(*)
                INTO v_is_reserved
                FROM BOOKINGS b
                WHERE b.PROPERTY_ID = p_property_id
                  AND b.STATUS = 'CONFIRMED'
                  AND v_current_day >= b.CHECKIN_DATE
                  AND v_current_day < b.CHECKOUT_DATE;

                IF v_is_reserved > 0 THEN
                    v_day_status.IS_AVAILABLE := 0;
                    v_day_status.PRICE := NULL;
                    v_day_status.STATUS := 'reserved';
                ELSE
                    -- 4. Prioridad #2 y #3
                    BEGIN
                        SELECT *
                        INTO v_avail_rec
                        FROM (SELECT a.*
                              FROM AVAILABILITIES a
                              WHERE a.PROPERTY_ID = p_property_id
                                AND v_current_day >= a.START_DATE
                                AND v_current_day <= a.END_DATE
                              ORDER BY a.START_DATE)
                        WHERE ROWNUM = 1;

                        IF v_avail_rec.KIND IN ('blocked', 'maintenance') THEN
                            v_day_status.IS_AVAILABLE := 0;
                            v_day_status.PRICE := NULL;
                            v_day_status.STATUS := v_avail_rec.KIND;
                        ELSIF v_avail_rec.KIND = 'special' THEN
                            v_day_status.IS_AVAILABLE := 1;
                            v_day_status.PRICE := v_avail_rec.PRICE_PER_NIGHT;
                            v_day_status.STATUS := 'special';
                        END IF;

                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            -- 5. Prioridad #3: Precio Default
                            v_day_status.IS_AVAILABLE := 1;
                            v_day_status.PRICE := v_base_price;
                            v_day_status.STATUS := 'default';
                    END;
                END IF;

                PIPE ROW (v_day_status);

                v_current_day := v_current_day + 1;
            END LOOP;

        RETURN;
    END GET_CALENDAR;

    ------------------------------------------------------------------------------
    -- FUNCTION: FN_GET_PROPERTIES_BY_HOST
    ------------------------------------------------------------------------------
    FUNCTION FN_GET_PROPERTIES_BY_HOST(
        P_HOST_ID IN HOSTS.HOST_ID%TYPE
    )
        RETURN SYS_REFCURSOR
    AS
        OUT_PROPERTIES_CURSOR SYS_REFCURSOR;
    BEGIN
        OPEN OUT_PROPERTIES_CURSOR FOR
            SELECT P.PROPERTY_ID,
                   P.TITLE,
                   P.BASE_PRICE_NIGHT,
                   P.CITY,
                   P.LATITUDE,
                   P.LONGITUDE,
                   (SELECT URL
                    FROM PROPERTY_IMAGES
                    WHERE PROPERTY_ID = P.PROPERTY_ID
                    ORDER BY SORT_ORDER
                        FETCH FIRST 1 ROW ONLY)          AS MAIN_IMAGE_URL,
                   (SELECT NVL(ROUND(AVG(RATING), 2), 0)
                    FROM REVIEWS R
                    WHERE R.PROPERTY_ID = P.PROPERTY_ID) AS AVERAGE_RATING
            FROM PROPERTIES P
            WHERE P.HOST_ID = P_HOST_ID
            ORDER BY P.CREATED_AT DESC;

        RETURN OUT_PROPERTIES_CURSOR;

    END FN_GET_PROPERTIES_BY_HOST;

END PROPERTY_PKG;
/

create PACKAGE FILTER_PKG AS
  PROCEDURE SP_SEARCH_PROPERTIES(
    p_city        IN VARCHAR2 DEFAULT NULL,
    p_min_price   IN NUMBER DEFAULT NULL,
    p_max_price   IN NUMBER DEFAULT NULL,
    p_rooms       IN NUMBER DEFAULT NULL,
    p_beds        IN NUMBER DEFAULT NULL,
    p_baths       IN NUMBER DEFAULT NULL,
    p_max_adults IN NUMBER DEFAULT NULL,
    p_max_children IN NUMBER DEFAULT NULL,
    p_max_baby IN NUMBER DEFAULT NULL,
    p_max_pet IN NUMBER DEFAULT NULL,
    p_start_date     IN DATE DEFAULT NULL,
    p_end_date       IN DATE DEFAULT NULL,
    p_lat_min     IN NUMBER DEFAULT NULL,
    p_lat_max     IN NUMBER DEFAULT NULL,
    p_lng_min     IN NUMBER DEFAULT NULL,
    p_lng_max     IN NUMBER DEFAULT NULL,
    p_amenities   IN SYS.ODCINUMBERLIST DEFAULT NULL,
    p_result_set  OUT SYS_REFCURSOR
  );
END FILTER_PKG;
/

create PACKAGE BODY FILTER_PKG AS

  PROCEDURE SP_SEARCH_PROPERTIES(
    p_city         IN VARCHAR2 DEFAULT NULL,
    p_min_price    IN NUMBER DEFAULT NULL,
    p_max_price    IN NUMBER DEFAULT NULL,
    p_rooms        IN NUMBER DEFAULT NULL,
    p_beds         IN NUMBER DEFAULT NULL,
    p_baths        IN NUMBER DEFAULT NULL,
    p_max_adults   IN NUMBER DEFAULT NULL,
    p_max_children IN NUMBER DEFAULT NULL,
    p_max_baby     IN NUMBER DEFAULT NULL,
    p_max_pet      IN NUMBER DEFAULT NULL,
    p_start_date   IN DATE DEFAULT NULL,
    p_end_date     IN DATE DEFAULT NULL,
    p_lat_min      IN NUMBER DEFAULT NULL,
    p_lat_max      IN NUMBER DEFAULT NULL,
    p_lng_min      IN NUMBER DEFAULT NULL,
    p_lng_max      IN NUMBER DEFAULT NULL,
    p_amenities    IN SYS.ODCINUMBERLIST DEFAULT NULL,
    p_result_set   OUT SYS_REFCURSOR
  ) AS
  BEGIN
    OPEN p_result_set FOR
      SELECT
        p.PROPERTY_ID,
        p.TITLE,
        p.BASE_PRICE_NIGHT,
        p.CURRENCY_CODE,
        p.ADDRESS_TEXT,
        p.FORMATTED_ADDRESS,
        p.CITY,
        p.STATE_REGION,
        p.COUNTRY,
        p.POSTAL_CODE,
        p.LATITUDE,
        p.LONGITUDE,
        p.STATUS,
        p.CREATED_AT,
        i.URL AS MAIN_IMAGE,
        -- Optimización 1: Cálculo escalar para evitar GROUP BY masivo
        (SELECT AVG(r.RATING)
           FROM REVIEWS r
          WHERE r.PROPERTY_ID = p.PROPERTY_ID) AS AVG_RATING
      FROM PROPERTIES p
      -- Optimización 2: Un solo JOIN a DETAILS en lugar de 7 subconsultas EXISTS
      JOIN PROPERTY_DETAILS d
        ON p.PROPERTY_ID = d.PROPERTY_ID
      LEFT JOIN PROPERTY_IMAGES i
        ON p.PROPERTY_ID = i.PROPERTY_ID
       AND i.SORT_ORDER = 0
      WHERE
            (p_city IS NULL OR p.STATE_REGION = p_city)
        AND (p_min_price IS NULL OR p.BASE_PRICE_NIGHT >= p_min_price)
        AND (p_max_price IS NULL OR p.BASE_PRICE_NIGHT <= p_max_price)
        -- Filtros directos sobre el alias 'd' (mucho más rápido)
        AND (p_rooms IS NULL OR d.BEDROOMS >= p_rooms)
        AND (p_beds IS NULL OR d.BEDS >= p_beds)
        AND (p_baths IS NULL OR d.BATHROOMS >= p_baths)
        AND (p_max_adults IS NULL OR d.MAX_ADULTS >= p_max_adults)
        AND (p_max_children IS NULL OR d.MAX_CHILDREN >= p_max_children)
        AND (p_max_baby IS NULL OR d.MAX_BABY >= p_max_baby)
        AND (p_max_pet IS NULL OR d.MAX_PETS >= p_max_pet)
        -- Filtro Geográfico
        AND (p_lat_min IS NULL OR p.LATITUDE BETWEEN p_lat_min AND p_lat_max)
        AND (p_lng_min IS NULL OR p.LONGITUDE BETWEEN p_lng_min AND p_lng_max)
        -- Filtro Disponibilidad
        AND (
             p_start_date IS NULL OR p_end_date IS NULL
             OR NOT EXISTS (
                SELECT 1 FROM BOOKINGS b
                 WHERE b.PROPERTY_ID = p.PROPERTY_ID
                   AND b.CHECKOUT_DATE > p_start_date
                   AND b.CHECKIN_DATE < p_end_date
             )
        )
        -- Filtro Amenities (Mantenemos EXISTS porque es una relación 1 a muchos)
        AND (p_amenities IS NULL OR EXISTS (
              SELECT 1
                FROM PROPERTY_AMENITIES pa
                JOIN TABLE(p_amenities) t ON pa.AMENITY_ID = t.COLUMN_VALUE
               WHERE pa.PROPERTY_ID = p.PROPERTY_ID
        ));
  END SP_SEARCH_PROPERTIES;

END FILTER_PKG;
/

create PACKAGE BOOKING_PKG AS

    /**
     * Obtiene todas las reservas hechas por un huésped (guest) específico.
     * p_guest_id: El ID del usuario que hizo las reservas (users.user_id).
     * p_bookings_cur: Un cursor de referencia para devolver el conjunto de resultados.
     */
    PROCEDURE get_bookings_by_tenant(
        p_tenant_id IN users.user_id%TYPE,
        p_bookings_cur OUT SYS_REFCURSOR
    );

    /**
     * Obtiene todas las reservas de las propiedades que pertenecen a un anfitrión (host) específico.
     * p_host_id: El ID del usuario que es dueño de las propiedades (users.user_id).
     * p_bookings_cur: Un cursor de referencia para devolver el conjunto de resultados.
     */
    PROCEDURE   get_bookings_by_host(
        p_host_id IN users.user_id%TYPE,
        p_bookings_cur OUT SYS_REFCURSOR
    );

    /**
    * Obtiene los detalles completos de UNA reserva específica.
    * Incluye una comprobación de autorización para asegurar que el usuario
    * que la solicita sea el huésped (tenant) o el anfitrión (host).
    *
    * p_booking_id: El ID de la reserva a consultar.
    * p_user_id: El ID del usuario que realiza la consulta (para autorización).
    * p_booking_info_cur: Un cursor de referencia para devolver la fila única.
    */
    PROCEDURE get_detailed_booking_info(
        p_booking_id IN bookings.booking_id%TYPE,
        p_user_id IN users.user_id%TYPE,
        p_booking_info_cur OUT SYS_REFCURSOR
    );


END BOOKING_PKG;
/

create PACKAGE BODY BOOKING_PKG AS

    PROCEDURE get_bookings_by_tenant(
        p_tenant_id IN users.user_id%TYPE,
        p_bookings_cur OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_bookings_cur FOR
            SELECT b.BOOKING_ID,
                   b.PROPERTY_ID,
                   b.CHECKIN_DATE,
                   b.CHECKOUT_DATE,
                   b.STATUS,
                   b.GUEST_COUNT,
                   p.TITLE,
                   p.FORMATTED_ADDRESS,
                   p.CITY,
                   p.STATE_REGION,
                   p.COUNTRY,
                   b.TOTAL_AMOUNT,
                   u.FIRST_NAME,
                   u.LAST_NAME,
                   b.HOST_NOTE,
                   (SELECT pi.URL
                    FROM PROPERTY_IMAGES pi
                    WHERE pi.PROPERTY_ID = p.PROPERTY_ID
                      AND pi.SORT_ORDER = 1
                      AND ROWNUM = 1) AS URL
            FROM bookings b
                     JOIN properties p ON b.property_id = p.property_id
                     JOIN users u ON p.HOST_ID = u.user_id
            WHERE b.tenant_id = p_tenant_id;

    END get_bookings_by_tenant;


    PROCEDURE get_bookings_by_host(
        p_host_id IN users.user_id%TYPE,
        p_bookings_cur OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_bookings_cur FOR
            SELECT b.BOOKING_ID,
                   b.CHECKIN_DATE,
                   b.CHECKOUT_DATE,
                   b.STATUS,
                   b.GUEST_COUNT,
                   b.TOTAL_AMOUNT,
                   p.TITLE             AS property_title,
                   u_tenant.FIRST_NAME AS tenant_first_name,
                   u_tenant.LAST_NAME  AS tenant_last_name,
                   pi.URL
            FROM bookings b
                     JOIN properties p ON b.property_id = p.property_id
                -- Traer al Huésped (tenant)
                     JOIN users u_tenant ON b.tenant_id = u_tenant.user_id
                -- Traer la imagen (sin que se rompa si no hay)
                     LEFT JOIN property_images pi ON p.property_id = pi.property_id AND pi.SORT_ORDER = 1
            -- Filtrar por el Anfitrión (Host)
            WHERE p.host_id = p_host_id;

    END get_bookings_by_host;


    PROCEDURE get_detailed_booking_info(
        p_booking_id IN bookings.booking_id%TYPE,
        p_user_id IN users.user_id%TYPE,
        p_booking_info_cur OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_booking_info_cur FOR
            SELECT
                -- Datos de la reserva (BOOKINGS)
                b.BOOKING_ID,
                b.STATUS,
                b.CHECKIN_DATE,
                b.CHECKOUT_DATE,
                b.GUEST_COUNT,
                b.TOTAL_AMOUNT,
                b.PRICE_NIGHTS      AS BASE_PRICE,
                b.SERVICE_FEE,
                b.CLEANING_FEE,
                b.TAXES,
                b.CREATED_AT,
                b.COMPLETED_AT,
                b.HOST_NOTE,
                b.TENANT_NOTE       AS GUEST_MESSAGE,
                b.CHECKIN_CODE,

                -- Datos del Huésped (USERS)
                t.USER_ID           AS TENANT_ID,
                t.FIRST_NAME        AS GUEST_FIRST_NAME,
                t.LAST_NAME         AS GUEST_LAST_NAME,
                t.EMAIL             AS GUEST_EMAIL,
                t.PHONE_NUMBER      AS GUEST_PHONE,
                -- (Se omite profileImageUrl ya que no existe en la tabla USERS)

                -- Datos de la Propiedad (PROPERTIES)
                p.PROPERTY_ID,
                p.TITLE             AS PROPERTY_NAME,
                p.HOST_ID,
                p.FORMATTED_ADDRESS AS PROPERTY_ADDRESS,

                -- Datos de Pagos (PAYMENTS)
                pm.STATUS           AS PAYMENT_STATUS,
                pm.MESSAGE          AS PAYMENT_MESSAGE,

                -- Datos de Reseñas (REVIEWS)
                -- (hasHostReview: ¿El anfitrión (p.HOST_ID) es el autor de una reseña para esta reserva?)
                (
                    CASE
                        WHEN EXISTS (SELECT 1
                                     FROM REVIEWS r
                                     WHERE r.booking_id = b.booking_id
                                       AND r.AUTHOR_USER_ID = p.HOST_ID) THEN 1
                        ELSE 0 END
                    )               AS HAS_HOST_REVIEW,

                -- (hasGuestReview: ¿El huésped (b.TENANT_ID) es el autor de una reseña para esta reserva?)
                (
                    CASE
                        WHEN EXISTS (SELECT 1
                                     FROM REVIEWS r
                                     WHERE r.booking_id = b.booking_id
                                       AND r.AUTHOR_USER_ID = b.TENANT_ID) THEN 1
                        ELSE 0 END
                    )               AS HAS_GUEST_REVIEW

            FROM BOOKINGS b
                     JOIN
                 PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
                     JOIN
                 USERS t ON b.TENANT_ID = t.USER_ID
                     LEFT JOIN -- (Usamos LEFT JOIN por si el pago aún no existe)
                PAYMENTS pm ON b.booking_id = pm.booking_id
            WHERE
              -- 1. Filtra por la reserva específica
                b.BOOKING_ID = p_booking_id

              -- 2. Comprobación de seguridad
              AND (
                -- El que pregunta es el huésped
                b.TENANT_ID = p_user_id
                    -- O el que pregunta es el anfitrión
                    OR p.HOST_ID = p_user_id
                );

    END get_detailed_booking_info;
END BOOKING_PKG;
/

create PACKAGE CALENDAR_AVAILABILITY_PKG AS

  ------------------------------------------------------------------------------
  -- PROCEDURE: SP_GET_PROPERTY_AVAILABILITY
  -- Devuelve la disponibilidad día por día de una propiedad en un rango de fechas
  ------------------------------------------------------------------------------
  PROCEDURE SP_GET_PROPERTY_AVAILABILITY(
    P_PROPERTY_ID             IN NUMBER,
    P_START_DATE              IN VARCHAR2,
    P_END_DATE                IN VARCHAR2,
    OUT_AVAILABILITY_CURSOR   OUT SYS_REFCURSOR,
    OUT_ERROR_CODE            OUT VARCHAR2
  );

  ------------------------------------------------------------------------------
  -- PROCEDURE: SP_CHECK_RANGE_AVAILABILITY
  -- Verifica si un rango de fechas está completamente disponible para reserva
  ------------------------------------------------------------------------------
  PROCEDURE SP_CHECK_RANGE_AVAILABILITY(
    P_PROPERTY_ID     IN NUMBER,
    P_CHECKIN_DATE    IN VARCHAR2,
    P_CHECKOUT_DATE   IN VARCHAR2,
    OUT_IS_AVAILABLE  OUT NUMBER,
    OUT_ERROR_CODE    OUT VARCHAR2
  );

  ------------------------------------------------------------------------------
  -- PROCEDURE: SP_GET_NEXT_AVAILABLE_DATES
  -- Obtiene las próximas N fechas disponibles a partir de hoy
  ------------------------------------------------------------------------------
  PROCEDURE SP_GET_NEXT_AVAILABLE_DATES(
    P_PROPERTY_ID       IN NUMBER,
    P_COUNT             IN NUMBER DEFAULT 5,
    OUT_DATES_CURSOR    OUT SYS_REFCURSOR,
    OUT_ERROR_CODE      OUT VARCHAR2
  );

END CALENDAR_AVAILABILITY_PKG;
/

create PACKAGE BODY CALENDAR_AVAILABILITY_PKG AS

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_GET_PROPERTY_AVAILABILITY
    -- Devuelve la disponibilidad día por día de una propiedad en un rango de fechas
    -- NOTA: ahora considera también STATUS = 'ACCEPTED' como días ocupados.
    ------------------------------------------------------------------------------
    PROCEDURE SP_GET_PROPERTY_AVAILABILITY(
        P_PROPERTY_ID             IN NUMBER,
        P_START_DATE              IN VARCHAR2,
        P_END_DATE                IN VARCHAR2,
        OUT_AVAILABILITY_CURSOR   OUT SYS_REFCURSOR,
        OUT_ERROR_CODE            OUT VARCHAR2
    ) IS
        v_start_date  DATE;
        v_end_date    DATE;
        v_date_count  NUMBER := 0;
    BEGIN
        -- Convertir strings a DATE
        BEGIN
            v_start_date := TO_DATE(P_START_DATE, 'YYYY-MM-DD');
            v_end_date   := TO_DATE(P_END_DATE, 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                OUT_ERROR_CODE := 'Formato de fecha inválido. Use YYYY-MM-DD';
                RETURN;
        END;

        IF v_start_date > v_end_date THEN
            OUT_ERROR_CODE := 'La fecha de inicio debe ser menor o igual a la fecha de fin';
            RETURN;
        END IF;

        v_date_count := v_end_date - v_start_date + 1;

        IF v_date_count > 0 THEN
            OPEN OUT_AVAILABILITY_CURSOR FOR
                WITH date_range AS (
                    SELECT v_start_date + LEVEL - 1 AS check_date
                    FROM DUAL
                    CONNECT BY LEVEL <= v_date_count
                ),
                booked_dates AS (
                    SELECT DISTINCT
                        TRUNC(b.CHECKIN_DATE) + LEVEL - 1 AS occupied_date
                    FROM BOOKINGS b
                    WHERE b.PROPERTY_ID = P_PROPERTY_ID
                      -- incluir ACCEPTED como estado que ocupa fechas
                      AND b.STATUS IN ('CONFIRMED', 'PENDING', 'ACCEPTED')
                      AND b.CHECKOUT_DATE >= v_start_date
                      AND b.CHECKIN_DATE <= v_end_date
                    CONNECT BY LEVEL <= (TRUNC(b.CHECKOUT_DATE) - TRUNC(b.CHECKIN_DATE))
                      AND PRIOR b.BOOKING_ID = b.BOOKING_ID
                      AND PRIOR SYS_GUID() IS NOT NULL
                ),
                availability_rules AS (
                    SELECT a.START_DATE, a.END_DATE, a.KIND
                    FROM AVAILABILITIES a
                    WHERE a.PROPERTY_ID = P_PROPERTY_ID
                      AND a.END_DATE >= v_start_date
                      AND a.START_DATE <= v_end_date
                )
                SELECT
                    TO_CHAR(dr.check_date, 'YYYY-MM-DD') AS DATE_STR,
                    CASE
                        WHEN bd.occupied_date IS NOT NULL THEN 0
                        WHEN EXISTS (
                            SELECT 1
                            FROM availability_rules ar
                            WHERE dr.check_date BETWEEN ar.START_DATE AND ar.END_DATE
                              AND ar.KIND = 'BLOCKED'
                        ) THEN 0
                        WHEN EXISTS (
                            SELECT 1
                            FROM availability_rules ar
                            WHERE dr.check_date BETWEEN ar.START_DATE AND ar.END_DATE
                              AND ar.KIND = 'MAINTENANCE'
                        ) THEN 0
                        ELSE 1
                    END AS IS_AVAILABLE,
                    CASE
                        WHEN bd.occupied_date IS NOT NULL THEN 'booked'
                        WHEN EXISTS (
                            SELECT 1
                            FROM availability_rules ar
                            WHERE dr.check_date BETWEEN ar.START_DATE AND ar.END_DATE
                              AND ar.KIND = 'BLOCKED'
                        ) THEN 'blocked'
                        WHEN EXISTS (
                            SELECT 1
                            FROM availability_rules ar
                            WHERE dr.check_date BETWEEN ar.START_DATE AND ar.END_DATE
                              AND ar.KIND = 'MAINTENANCE'
                        ) THEN 'maintenance'
                        ELSE 'available'
                    END AS REASON
                FROM date_range dr
                LEFT JOIN booked_dates bd ON TRUNC(dr.check_date) = TRUNC(bd.occupied_date)
                ORDER BY dr.check_date;
        ELSE
            OPEN OUT_AVAILABILITY_CURSOR FOR
                SELECT CAST(NULL AS VARCHAR2(10)) AS DATE_STR,
                       CAST(NULL AS NUMBER) AS IS_AVAILABLE,
                       CAST(NULL AS VARCHAR2(20)) AS REASON
                FROM DUAL WHERE 1=0;
        END IF;

        OUT_ERROR_CODE := NULL;

    EXCEPTION
        WHEN OTHERS THEN
            OUT_ERROR_CODE := 'Error al obtener disponibilidad: ' || SQLERRM;
    END SP_GET_PROPERTY_AVAILABILITY;


    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_CHECK_RANGE_AVAILABILITY
    -- Verifica si un rango de fechas está completamente disponible para reserva
    -- NOTA: ahora considera también STATUS = 'ACCEPTED' como días ocupados.
    ------------------------------------------------------------------------------
    PROCEDURE SP_CHECK_RANGE_AVAILABILITY(
        P_PROPERTY_ID     IN NUMBER,
        P_CHECKIN_DATE    IN VARCHAR2,
        P_CHECKOUT_DATE   IN VARCHAR2,
        OUT_IS_AVAILABLE  OUT NUMBER,
        OUT_ERROR_CODE    OUT VARCHAR2
    ) IS
        v_checkin_date       DATE;
        v_checkout_date      DATE;
        v_adjusted_checkout  DATE;
        v_unavailable_days   NUMBER;
    BEGIN
        BEGIN
            v_checkin_date  := TO_DATE(P_CHECKIN_DATE, 'YYYY-MM-DD');
            v_checkout_date := TO_DATE(P_CHECKOUT_DATE, 'YYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                OUT_ERROR_CODE := 'Formato de fecha inválido. Use YYYY-MM-DD';
                OUT_IS_AVAILABLE := 0;
                RETURN;
        END;

        v_adjusted_checkout := v_checkout_date - 1;

        SELECT COUNT(*)
        INTO v_unavailable_days
        FROM (
            WITH date_range AS (
                SELECT v_checkin_date + LEVEL - 1 AS check_date
                FROM DUAL
                CONNECT BY LEVEL <= (v_adjusted_checkout - v_checkin_date + 1)
            ),
            booked_dates AS (
                SELECT DISTINCT
                    TRUNC(b.CHECKIN_DATE) + LEVEL - 1 AS occupied_date
                FROM BOOKINGS b
                WHERE b.PROPERTY_ID = P_PROPERTY_ID
                  -- incluir ACCEPTED aquí también
                  AND b.STATUS IN ('CONFIRMED', 'PENDING', 'ACCEPTED')
                  AND b.CHECKOUT_DATE >= v_checkin_date
                  AND b.CHECKIN_DATE <= v_adjusted_checkout
                CONNECT BY LEVEL <= (TRUNC(b.CHECKOUT_DATE) - TRUNC(b.CHECKIN_DATE))
                  AND PRIOR b.BOOKING_ID = b.BOOKING_ID
                  AND PRIOR SYS_GUID() IS NOT NULL
            ),
            availability_blocks AS (
                SELECT START_DATE, END_DATE, KIND
                FROM AVAILABILITIES
                WHERE PROPERTY_ID = P_PROPERTY_ID
                  AND END_DATE >= v_checkin_date
                  AND START_DATE <= v_adjusted_checkout
            )
            SELECT dr.check_date
            FROM date_range dr
            WHERE (
                EXISTS (SELECT 1 FROM booked_dates bd WHERE bd.occupied_date = TRUNC(dr.check_date))
                OR
                EXISTS (
                    SELECT 1 FROM availability_blocks ab
                    WHERE dr.check_date BETWEEN ab.START_DATE AND ab.END_DATE
                      AND ab.KIND = 'BLOCKED'
                )
                OR
                EXISTS (
                    SELECT 1 FROM availability_blocks ab
                    WHERE dr.check_date BETWEEN ab.START_DATE AND ab.END_DATE
                      AND ab.KIND = 'MAINTENANCE'
                )
            )
        );

        IF v_unavailable_days = 0 THEN
            OUT_IS_AVAILABLE := 1;
        ELSE
            OUT_IS_AVAILABLE := 0;
        END IF;

        OUT_ERROR_CODE := NULL;

    EXCEPTION
        WHEN OTHERS THEN
            OUT_ERROR_CODE := 'Error al verificar disponibilidad: ' || SQLERRM;
            OUT_IS_AVAILABLE := 0;
    END SP_CHECK_RANGE_AVAILABILITY;


    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_GET_NEXT_AVAILABLE_DATES
    -- Obtiene las próximas N fechas disponibles a partir de hoy
    -- NOTA: ahora considera también STATUS = 'ACCEPTED' como días ocupados.
    ------------------------------------------------------------------------------
    PROCEDURE SP_GET_NEXT_AVAILABLE_DATES(
        P_PROPERTY_ID       IN NUMBER,
        P_COUNT             IN NUMBER DEFAULT 5,
        OUT_DATES_CURSOR    OUT SYS_REFCURSOR,
        OUT_ERROR_CODE      OUT VARCHAR2
    ) IS
        v_date_count NUMBER := 0;
    BEGIN
        v_date_count := NVL(P_COUNT, 5);

        IF v_date_count > 0 THEN
            OPEN OUT_DATES_CURSOR FOR
                WITH future_dates AS (
                    SELECT TRUNC(SYSDATE) + LEVEL - 1 AS check_date
                    FROM DUAL
                    CONNECT BY LEVEL <= 90
                ),
                booked_dates AS (
                    SELECT DISTINCT
                        TRUNC(b.CHECKIN_DATE) + LEVEL - 1 AS occupied_date
                    FROM BOOKINGS b
                    WHERE b.PROPERTY_ID = P_PROPERTY_ID
                      -- incluir ACCEPTED también
                      AND b.STATUS IN ('CONFIRMED', 'PENDING', 'ACCEPTED')
                      AND b.CHECKOUT_DATE >= TRUNC(SYSDATE)
                    CONNECT BY LEVEL <= (TRUNC(b.CHECKOUT_DATE) - TRUNC(b.CHECKIN_DATE))
                      AND PRIOR b.BOOKING_ID = b.BOOKING_ID
                      AND PRIOR SYS_GUID() IS NOT NULL
                ),
                availability_blocks AS (
                    SELECT START_DATE, END_DATE, KIND
                    FROM AVAILABILITIES
                    WHERE PROPERTY_ID = P_PROPERTY_ID
                      AND END_DATE >= TRUNC(SYSDATE)
                ),
                available_dates AS (
                    SELECT
                        fd.check_date,
                        CASE
                            WHEN bd.occupied_date IS NOT NULL THEN 0
                            WHEN EXISTS (
                                SELECT 1
                                FROM availability_blocks ab
                                WHERE fd.check_date BETWEEN ab.START_DATE AND ab.END_DATE
                                  AND ab.KIND = 'BLOCKED'
                            ) THEN 0
                            WHEN EXISTS (
                                SELECT 1
                                FROM availability_blocks ab
                                WHERE fd.check_date BETWEEN ab.START_DATE AND ab.END_DATE
                                  AND ab.KIND = 'MAINTENANCE'
                            ) THEN 0
                            ELSE 1
                        END AS is_available
                    FROM future_dates fd
                    LEFT JOIN booked_dates bd ON fd.check_date = bd.occupied_date
                )
                SELECT TO_CHAR(check_date, 'YYYY-MM-DD') AS AVAILABLE_DATE
                FROM available_dates
                WHERE is_available = 1
                  AND ROWNUM <= v_date_count
                ORDER BY check_date;
        ELSE
            OPEN OUT_DATES_CURSOR FOR
                SELECT CAST(NULL AS VARCHAR2(10)) AS AVAILABLE_DATE
                FROM DUAL WHERE 1=0;
        END IF;

        OUT_ERROR_CODE := NULL;

    EXCEPTION
        WHEN OTHERS THEN
            OUT_ERROR_CODE := 'Error al obtener fechas disponibles: ' || SQLERRM;
    END SP_GET_NEXT_AVAILABLE_DATES;

END CALENDAR_AVAILABILITY_PKG;
/

create PACKAGE REVIEW_PKG AS
    -- Procedimiento existente: Obtener pending reviews
    PROCEDURE GET_USER_PENDING_REVIEWS(
        p_user_id       IN  NUMBER,
        p_pending_cursor OUT SYS_REFCURSOR
    );

    -- Procedimiento existente: Crear reseña
    PROCEDURE CREATE_REVIEW(
        p_booking_id    IN  NUMBER,
        p_reviewer_id   IN  NUMBER,
        p_review_type   IN  VARCHAR2,
        p_rating        IN  NUMBER,
        p_comment       IN  CLOB,
        p_review_id     OUT NUMBER,
        p_success       OUT NUMBER,
        p_message       OUT VARCHAR2
    );

    -- Procedimiento actualizado: Obtener reseñas del host (usando vista)
    PROCEDURE GET_HOST_RECEIVED_REVIEWS(
        p_host_id       IN  NUMBER,
        p_reviews_cursor OUT SYS_REFCURSOR
    );

    -- NUEVO: Obtener estadísticas del host (usando V_HOST_REVIEW_STATS)
    PROCEDURE GET_HOST_REVIEW_STATS(
        p_host_id       IN  NUMBER,
        p_stats_cursor  OUT SYS_REFCURSOR
    );

END REVIEW_PKG;
/

create PACKAGE BODY REVIEW_PKG AS

    -- =========================================
    -- Procedimiento: GET_USER_PENDING_REVIEWS
    -- (MANTENER EXACTO COMO ESTÁ)
    -- =========================================
    PROCEDURE GET_USER_PENDING_REVIEWS (
        p_user_id IN NUMBER,
        p_pending_cursor OUT SYS_REFCURSOR
    ) AS
    BEGIN
        OPEN p_pending_cursor FOR
            SELECT
                r.REVIEW_ID,
                r.BOOKING_ID,
                r.AUTHOR_USER_ID AS USER_ID,
                CASE WHEN r.FOR_HOST = 1 THEN 'host' ELSE 'guest' END AS REVIEW_TYPE,
                r.CREATED_AT,
                r.IS_PUBLISHED,
                b.CHECKIN_DATE,
                b.CHECKOUT_DATE,
                b.STATUS AS BOOKING_STATUS,
                prop.PROPERTY_ID,
                NVL(prop.TITLE, 'Propiedad sin nombre') AS PROPERTY_TITLE,
                (SELECT pi.URL
                 FROM PROPERTY_IMAGES pi
                 WHERE pi.PROPERTY_ID = prop.PROPERTY_ID
                 ORDER BY pi.SORT_ORDER
                 FETCH FIRST 1 ROW ONLY) AS PROPERTY_IMAGE,
                NVL(prop.CITY, 'Ciudad') AS CITY,
                NVL(prop.STATE_REGION, 'Región') AS STATE_REGION,
                CASE
                    WHEN r.FOR_HOST = 0 THEN NVL(host.FIRST_NAME, 'Host')
                    WHEN r.FOR_HOST = 1 THEN NVL(tenant.FIRST_NAME, 'Huésped')
                END AS OTHER_USER_FIRST_NAME,
                CASE
                    WHEN r.FOR_HOST = 0 THEN NVL(host.LAST_NAME, '')
                    WHEN r.FOR_HOST = 1 THEN NVL(tenant.LAST_NAME, '')
                END AS OTHER_USER_LAST_NAME,
                CAST(NULL AS VARCHAR2(255)) AS OTHER_USER_IMAGE
            FROM REVIEWS r
            INNER JOIN BOOKINGS b ON r.BOOKING_ID = b.BOOKING_ID
            INNER JOIN PROPERTIES prop ON b.PROPERTY_ID = prop.PROPERTY_ID
            INNER JOIN HOSTS h ON prop.HOST_ID = h.HOST_ID
            INNER JOIN USERS host ON h.HOST_ID = host.USER_ID
            INNER JOIN TENANTS t ON b.TENANT_ID = t.TENANT_ID
            INNER JOIN USERS tenant ON t.TENANT_ID = tenant.USER_ID
            WHERE r.AUTHOR_USER_ID = p_user_id
              AND r.IS_PUBLISHED = 0
              AND r.RATING = 0
              AND UPPER(b.STATUS) = 'COMPLETED'
            ORDER BY r.CREATED_AT DESC;
    END GET_USER_PENDING_REVIEWS;

    -- =========================================
    -- Procedimiento: CREATE_REVIEW
    -- (MANTENER EXACTO COMO ESTÁ)
    -- =========================================
    PROCEDURE CREATE_REVIEW (
        p_booking_id IN NUMBER,
        p_reviewer_id IN NUMBER,
        p_review_type IN VARCHAR2,
        p_rating IN NUMBER,
        p_comment IN CLOB,
        p_review_id OUT NUMBER,
        p_success OUT NUMBER,
        p_message OUT VARCHAR2
    ) AS
        v_for_host NUMBER;
        v_review_count NUMBER;
    BEGIN
        -- Validar rating
        IF p_rating NOT BETWEEN 1 AND 5 THEN
            p_success := 0;
            p_message := 'Rating debe estar entre 1 y 5';
            RETURN;
        END IF;

        -- Convertir review_type a FOR_HOST
        IF p_review_type = 'guest' THEN
            v_for_host := 0;  -- Tenant opina
        ELSIF p_review_type = 'host' THEN
            v_for_host := 1;  -- Host opina
        ELSE
            p_success := 0;
            p_message := 'Tipo de reseña inválido';
            RETURN;
        END IF;

        -- Verificar que existe una reseña pendiente para este usuario
        SELECT COUNT(*)
        INTO v_review_count
        FROM REVIEWS
        WHERE BOOKING_ID = p_booking_id
          AND AUTHOR_USER_ID = p_reviewer_id
          AND FOR_HOST = v_for_host
          AND IS_PUBLISHED = 0
          AND RATING = 0;

        IF v_review_count = 0 THEN
            p_success := 0;
            p_message := 'No existe una reseña pendiente para este booking';
            RETURN;
        END IF;

        -- Actualizar la reseña pendiente
        UPDATE REVIEWS
        SET
            RATING = p_rating,
            COMMENTS = p_comment,
            IS_PUBLISHED = 1,
            PUBLISHED_AT = SYSTIMESTAMP
        WHERE BOOKING_ID = p_booking_id
          AND AUTHOR_USER_ID = p_reviewer_id
          AND FOR_HOST = v_for_host
          AND IS_PUBLISHED = 0
          AND RATING = 0
        RETURNING REVIEW_ID INTO p_review_id;

        COMMIT;
        p_success := 1;
        p_message := 'Reseña publicada exitosamente';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := 0;
            p_message := 'Reseña no encontrada';
        WHEN OTHERS THEN
            ROLLBACK;
            p_success := 0;
            p_message := 'Error al publicar reseña: ' || SQLERRM;
    END CREATE_REVIEW;

    -- =========================================
    -- Procedimiento: GET_HOST_RECEIVED_REVIEWS
    -- ACTUALIZADO: Usa V_HOST_REVIEWS_DETAIL
    -- =========================================
    PROCEDURE GET_HOST_RECEIVED_REVIEWS (
        p_host_id IN NUMBER,
        p_reviews_cursor OUT SYS_REFCURSOR
    ) AS
    BEGIN
        -- Consultar la vista para obtener reseñas detalladas
        OPEN p_reviews_cursor FOR
            SELECT
                REVIEW_ID,
                BOOKING_ID,
                REVIEWER_ID,
                RATING,
                COMMENTS AS REVIEW_COMMENT,  -- Mantener alias consistente
                CREATED_AT,
                REVIEWER_FIRST_NAME,
                REVIEWER_LAST_NAME,
                REVIEWER_IMAGE,
                PROPERTY_ID,
                PROPERTY_TITLE,
                CHECKIN_DATE,
                CHECKOUT_DATE
            FROM V_HOST_REVIEWS_DETAIL
            WHERE HOST_ID = p_host_id
            ORDER BY CREATED_AT DESC;

    EXCEPTION
        WHEN OTHERS THEN
            -- En caso de error, abrir cursor vacío
            OPEN p_reviews_cursor FOR
                SELECT
                    NULL AS REVIEW_ID,
                    NULL AS BOOKING_ID,
                    NULL AS REVIEWER_ID,
                    NULL AS RATING,
                    NULL AS REVIEW_COMMENT,
                    NULL AS CREATED_AT,
                    NULL AS REVIEWER_FIRST_NAME,
                    NULL AS REVIEWER_LAST_NAME,
                    NULL AS REVIEWER_IMAGE,
                    NULL AS PROPERTY_ID,
                    NULL AS PROPERTY_TITLE,
                    NULL AS CHECKIN_DATE,
                    NULL AS CHECKOUT_DATE
                FROM DUAL
                WHERE 1 = 0;
    END GET_HOST_RECEIVED_REVIEWS;

    -- =========================================
    -- Procedimiento: GET_HOST_REVIEW_STATS (NUEVO)
    -- Usa V_HOST_REVIEW_STATS para estadísticas
    -- =========================================
    PROCEDURE GET_HOST_REVIEW_STATS (
        p_host_id IN NUMBER,
        p_stats_cursor OUT SYS_REFCURSOR
    ) AS
    BEGIN
        -- Consultar la vista de estadísticas
        OPEN p_stats_cursor FOR
            SELECT
                HOST_ID,
                TOTAL_REVIEWS,
                AVERAGE_RATING,
                RATING_5_COUNT,
                RATING_4_COUNT,
                RATING_3_COUNT,
                RATING_2_COUNT,
                RATING_1_COUNT
            FROM V_HOST_REVIEW_STATS
            WHERE HOST_ID = p_host_id;

    EXCEPTION
        WHEN OTHERS THEN
            -- En caso de error, retornar valores en cero
            OPEN p_stats_cursor FOR
                SELECT
                    p_host_id AS HOST_ID,
                    0 AS TOTAL_REVIEWS,
                    0 AS AVERAGE_RATING,
                    0 AS RATING_5_COUNT,
                    0 AS RATING_4_COUNT,
                    0 AS RATING_3_COUNT,
                    0 AS RATING_2_COUNT,
                    0 AS RATING_1_COUNT
                FROM DUAL;
    END GET_HOST_REVIEW_STATS;

END REVIEW_PKG;
/

create PACKAGE HOST_DASHBOARD_PKG AS

  -- Tipo de registro para las estadísticas generales del host
  TYPE host_stats_rec IS RECORD (
    total_bookings NUMBER,
    total_revenue NUMBER,
    average_rating NUMBER(3,2),
    average_ticket NUMBER(10,2),
    total_reviews NUMBER,
    total_properties NUMBER,
    active_bookings NUMBER
  );

  -- Procedimiento: Obtener estadísticas generales del host
  PROCEDURE GET_HOST_STATS (
    p_host_id IN NUMBER,
    p_stats_cursor OUT SYS_REFCURSOR
  );

  -- Procedimiento: Obtener actividad reciente del host
  PROCEDURE GET_HOST_RECENT_ACTIVITY (
    p_host_id IN NUMBER,
    p_activity_cursor OUT SYS_REFCURSOR,
    p_limit IN NUMBER DEFAULT 10
  );

END HOST_DASHBOARD_PKG;
/

create PACKAGE BODY HOST_DASHBOARD_PKG AS

  -- Procedimiento: Obtener estadísticas generales del host
  -- =========================================
  PROCEDURE GET_HOST_STATS (
    p_host_id IN NUMBER,
    p_stats_cursor OUT SYS_REFCURSOR
  ) AS
  BEGIN
    OPEN p_stats_cursor FOR
      SELECT
        -- 1. 📅 Reservas Totales (Volumen)
        -- Cantidad de reservas confirmadas o completadas
        (SELECT COUNT(b.BOOKING_ID)
         FROM BOOKINGS b
         INNER JOIN PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
         WHERE p.HOST_ID = p_host_id
           AND UPPER(b.STATUS) IN ('CONFIRMED', 'COMPLETED', 'ACCEPTED')
        ) AS TOTAL_BOOKINGS,

        -- 2. 💰 Ingresos Totales (Rendimiento)
        -- Suma total de dinero generado
        (SELECT NVL(SUM(b.TOTAL_AMOUNT), 0)
         FROM BOOKINGS b
         INNER JOIN PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
         WHERE p.HOST_ID = p_host_id
           AND UPPER(b.STATUS) IN ('CONFIRMED', 'COMPLETED')
        ) AS TOTAL_REVENUE,

        -- 3. ⭐ Calificación Promedio (Calidad)
        -- Promedio de estrellas de reviews publicadas donde el host es el receptor
        (SELECT NVL(ROUND(AVG(r.RATING), 2), 0)
         FROM REVIEWS r
         WHERE r.TARGET_USER_ID = p_host_id
           AND r.FOR_HOST = 0  -- Reviews donde tenant opina sobre host
           AND r.IS_PUBLISHED = 1
           AND r.RATING > 0
        ) AS AVERAGE_RATING,

        -- 4. 🎫 Ticket Promedio (Valor)
        -- Valor promedio de cada reserva
        (SELECT NVL(ROUND(AVG(b.TOTAL_AMOUNT), 2), 0)
         FROM BOOKINGS b
         INNER JOIN PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
         WHERE p.HOST_ID = p_host_id
           AND UPPER(b.STATUS) IN ('CONFIRMED', 'COMPLETED')
           AND b.TOTAL_AMOUNT > 0
        ) AS AVERAGE_TICKET,

        -- MÉTRICAS ADICIONALES

        -- Total de reseñas recibidas (publicadas)
        (SELECT COUNT(r.REVIEW_ID)
         FROM REVIEWS r
         WHERE r.TARGET_USER_ID = p_host_id
           AND r.FOR_HOST = 0
           AND r.IS_PUBLISHED = 1
        ) AS TOTAL_REVIEWS,

        -- Total de propiedades del host
        (SELECT COUNT(p.PROPERTY_ID)
         FROM PROPERTIES p
         WHERE p.HOST_ID = p_host_id
           AND UPPER(NVL(p.STATUS, 'ACTIVE')) = 'ACTIVE'
        ) AS TOTAL_PROPERTIES,

        -- Reservas activas (confirmadas pero no completadas aún)
        (SELECT COUNT(b.BOOKING_ID)
         FROM BOOKINGS b
         INNER JOIN PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
         WHERE p.HOST_ID = p_host_id
           AND UPPER(b.STATUS) IN ('CONFIRMED', 'ACCEPTED')
           AND b.CHECKOUT_DATE >= SYSDATE
        ) AS ACTIVE_BOOKINGS

      FROM DUAL;

  END GET_HOST_STATS;


  -- Procedimiento: Obtener actividad reciente del host
  -- =========================================
  PROCEDURE GET_HOST_RECENT_ACTIVITY (
    p_host_id IN NUMBER,
    p_activity_cursor OUT SYS_REFCURSOR,
    p_limit IN NUMBER DEFAULT 10
  ) AS
  BEGIN
    OPEN p_activity_cursor FOR
      SELECT * FROM (
        -- Reservas confirmadas
        SELECT
          'booking' AS ACTIVITY_TYPE,
          b.BOOKING_ID AS ACTIVITY_ID,
          'Nueva reserva confirmada' AS TITLE,
          u.FIRST_NAME || ' ' || u.LAST_NAME || ' - ' ||
          prop.TITLE || ', ' ||
          TO_CHAR(b.CHECKIN_DATE, 'DD Mon') || '-' ||
          TO_CHAR(b.CHECKOUT_DATE, 'DD Mon') AS DESCRIPTION,
          b.CREATED_AT AS ACTIVITY_DATE,
          'confirmed' AS STATUS
        FROM BOOKINGS b
        INNER JOIN PROPERTIES prop ON b.PROPERTY_ID = prop.PROPERTY_ID
        INNER JOIN TENANTS t ON b.TENANT_ID = t.TENANT_ID
        INNER JOIN USERS u ON t.TENANT_ID = u.USER_ID
        WHERE prop.HOST_ID = p_host_id
          AND UPPER(b.STATUS) IN ('CONFIRMED', 'ACCEPTED')

        UNION ALL

        -- Reseñas recibidas
        SELECT
          'review' AS ACTIVITY_TYPE,
          r.REVIEW_ID AS ACTIVITY_ID,
          'Nueva reseña recibida' AS TITLE,
          r.RATING || ' estrellas de ' ||
          u.FIRST_NAME || ' ' || u.LAST_NAME || ' - ' ||
          prop.TITLE AS DESCRIPTION,
          r.PUBLISHED_AT AS ACTIVITY_DATE,
          'review' AS STATUS
        FROM REVIEWS r
        INNER JOIN BOOKINGS b ON r.BOOKING_ID = b.BOOKING_ID
        INNER JOIN PROPERTIES prop ON b.PROPERTY_ID = prop.PROPERTY_ID
        INNER JOIN USERS u ON r.AUTHOR_USER_ID = u.USER_ID
        WHERE r.TARGET_USER_ID = p_host_id
          AND r.FOR_HOST = 0
          AND r.IS_PUBLISHED = 1

        UNION ALL

        -- Pagos procesados (bookings completados)
        SELECT
          'payment' AS ACTIVITY_TYPE,
          b.BOOKING_ID AS ACTIVITY_ID,
          'Pago procesado' AS TITLE,
          TO_CHAR(b.TOTAL_AMOUNT, 'FM999,999,990.00') || ' transferido a tu cuenta' AS DESCRIPTION,
          b.COMPLETED_AT AS ACTIVITY_DATE,
          'payment' AS STATUS
        FROM BOOKINGS b
        INNER JOIN PROPERTIES prop ON b.PROPERTY_ID = prop.PROPERTY_ID
        WHERE prop.HOST_ID = p_host_id
          AND UPPER(b.STATUS) = 'COMPLETED'
          AND b.COMPLETED_AT IS NOT NULL

        ORDER BY ACTIVITY_DATE DESC
      )
      WHERE ROWNUM <= p_limit;

  END GET_HOST_RECENT_ACTIVITY;

END HOST_DASHBOARD_PKG;
/