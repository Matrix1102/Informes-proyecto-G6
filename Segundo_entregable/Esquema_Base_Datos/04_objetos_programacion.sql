create or replace PACKAGE AUTH_PKG AS
    PROCEDURE SP_LOGIN_WITH_CREDENTIALS(
        P_USERNAME IN VARCHAR2,
        P_PASSWORD_HASH IN VARCHAR2,
        OUT_SUCCESS OUT NUMBER, -- 1 = success, 0 = failure
        OUT_ERROR_CODE OUT VARCHAR2,
        OUT_USER_CURSOR OUT SYS_REFCURSOR -- devuelve cursor con datos de usuario (si aplica)
    );

    PROCEDURE SP_FIND_OR_CREATE_USER_OAUTH(
        P_EMAIL IN VARCHAR2,
        P_NAME IN VARCHAR2,
        P_PROVIDER IN VARCHAR2,
        P_PROVIDER_ACCOUNT_ID IN VARCHAR2,
        OUT_USER_ID OUT NUMBER, -- devuelve USER_ID creado o existente
        OUT_IDENTITY_ID OUT NUMBER -- devuelve IDENTITY_ID creado o existente
    );

    PROCEDURE SP_UPDATE_LAST_LOGIN(
        P_IDENTITY_ID IN NUMBER
    );
END AUTH_PKG;
/

create or replace PACKAGE BODY AUTH_PKG AS

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
        v_user_id          NUMBER;
        v_validation_error VARCHAR2(100);
    BEGIN
        BEGIN
            SELECT a.USER_ID
            INTO v_user_id
            FROM USER_AUTH_IDENTITIES a
            WHERE (LOWER(a.PROVIDER_USER_ID) = LOWER(p_username) OR LOWER(a.EMAIL) = LOWER(p_username))
              AND a.PASSWORD_HASH = p_password_hash;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                out_success := 0;
                out_error_code := 'INVALID_CREDENTIALS';
                RETURN;
        END;

        v_validation_error := FN_VALIDATE_USER_LOGIN(v_user_id);

        IF v_validation_error IS NOT NULL THEN
            out_success := 0;
            out_error_code := v_validation_error;
            RETURN;
        END IF;

        out_success := 1;
        out_error_code := NULL;
        OPEN out_user_cursor FOR
            SELECT * FROM USERS WHERE USER_ID = v_user_id;

    EXCEPTION
        WHEN OTHERS THEN
            out_success := 0;
            out_error_code := 'INTERNAL_ERROR';
            NULL;
    END SP_LOGIN_WITH_CREDENTIALS;


    -- Implementación del SP público de OAuth (buscar o crear)
    PROCEDURE SP_FIND_OR_CREATE_USER_OAUTH(
        p_email IN VARCHAR2,
        p_name IN VARCHAR2,
        p_provider IN VARCHAR2,
        p_provider_account_id IN VARCHAR2,
        out_user_id OUT NUMBER,
        out_identity_id OUT NUMBER
    ) IS
        v_user_id     NUMBER;
        v_identity_id NUMBER;
        v_first_name  VARCHAR2(100);
        v_last_name   VARCHAR2(100);
    BEGIN
        -- Validar parámetros de entrada
        IF p_email IS NULL THEN RAISE_APPLICATION_ERROR(-20001, 'Email no puede ser NULL'); END IF;
        IF p_provider_account_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Provider Account ID no puede ser NULL');
        END IF;

        -- Paso 1: MANEJAR LA TABLA USERS (BUSCAR O CREAR) - Sin cambios
        BEGIN
            SELECT USER_ID INTO v_user_id FROM USERS WHERE LOWER(TRIM(EMAIL)) = LOWER(TRIM(p_email));
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DECLARE -- Bloque para lógica de división de nombre
                    -- ... (variables v_first_space_pos, v_second_space_pos) ...
                BEGIN
                    -- ... (lógica para dividir p_name en v_first_name, v_last_name) ...

                    INSERT INTO USERS (FIRST_NAME, LAST_NAME, EMAIL, CREATED_AT, STATUS)
                    VALUES (v_first_name, v_last_name, LOWER(TRIM(p_email)), SYSDATE, 'active')
                    RETURNING USER_ID INTO v_user_id;

                    IF v_user_id IS NULL THEN RAISE_APPLICATION_ERROR(-20003, 'No se pudo crear el usuario'); END IF;
                END; -- Fin bloque DECLARE
        END;
        -- Fin bloque BEGIN/EXCEPTION para USERS

        -- A este punto, v_user_id SIEMPRE tiene un valor

        -- *** Paso 2 CORREGIDO: MANEJAR USER_AUTH_IDENTITIES (Buscar primero, luego insertar) ***
        BEGIN
            -- 2.A: Intentar BUSCAR la identidad existente
            SELECT IDENTITY_ID
            INTO v_identity_id
            FROM USER_AUTH_IDENTITIES
            WHERE USER_ID = v_user_id
              AND PROVIDER = p_provider
              AND PROVIDER_USER_ID = p_provider_account_id;

            -- Si la encuentra, v_identity_id ya tiene el valor correcto.

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- 2.B: Si NO la encuentra, INSERTARLA
                INSERT INTO USER_AUTH_IDENTITIES (USER_ID, PROVIDER_USER_ID, PROVIDER,
                                                  PASSWORD_HASH, EMAIL_VERIFIED, EMAIL, CREATED_AT)
                VALUES (v_user_id, p_provider_account_id, p_provider,
                        NULL, 1, LOWER(TRIM(p_email)), SYSDATE)
                RETURNING IDENTITY_ID INTO v_identity_id; -- Capturamos el ID insertado

                IF v_identity_id IS NULL THEN
                    -- Algo muy raro pasó si el INSERT no devolvió un ID
                    RAISE_APPLICATION_ERROR(-20004, 'No se pudo crear la identidad de autenticación');
                END IF;
        END;
        -- Fin del bloque BEGIN/EXCEPTION para USER_AUTH_IDENTITIES

        -- A este punto, v_identity_id SIEMPRE tiene un valor (del SELECT o del INSERT)

        -- 3. ASIGNAR VALORES DE SALIDA
        out_user_id := v_user_id;
        out_identity_id := v_identity_id;

        -- NO SE NECESITA COMMIT; autoCommit=true en Node.js lo maneja

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

END AUTH_PKG;
/

create or replace PACKAGE USER_PKG AS

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

create or replace PACKAGE BODY USER_PKG AS

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

    EXCEPTION
        WHEN OTHERS THEN
            -- Si ocurre cualquier otro error inesperado,
            -- resetea los valores a 0 y relanza el error.
            OUT_IS_TENANT := 0;
            OUT_IS_HOST := 0;
            RAISE; -- Envía el error de vuelta a quien lo llamó

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

create or replace PACKAGE PROPERTY_PKG AS

    /**
     * Procedimiento para actualizar los datos de un recinto (property).
     * Solo actualiza los campos que se envían con un valor (no nulos).
     *
     * @param P_PROPERTY_ID       El ID del recinto a modificar (requerido).
     * @param P_TITLE             (PROPERTIES) El nuevo título.
     * @param P_BASE_PRICE_NIGHT  (PROPERTIES) El nuevo precio base.
     * @param P_ADDRESS_TEXT      (PROPERTIES) La nueva dirección.
     * @param P_CITY              (PROPERTIES) La nueva ciudad.
     * @param P_STATE_REGION      (PROPERTIES) El nuevo estado/región.
     * @param P_COUNTRY           (PROPERTIES) El nuevo país.
     * @param P_POSTAL_CODE       (PROPERTIES) El nuevo código postal.
     * @param P_LATITUDE          (PROPERTIES) La nueva latitud.
     * @param P_LONGITUDE         (PROPERTIES) La nueva longitud.
     *
     * @param P_DESCRIPTION_LONG  (PROPERTY_DETAILS) La nueva descripción larga.
     * @param P_HOUSE_RULES       (PROPERTY_DETAILS) Las nuevas reglas de la casa.
     * @param P_CHECKIN_TIME      (PROPERTY_DETAILS) Hora de check-in (ej. '15:00').
     * @param P_CHECKOUT_TIME     (PROPERTY_DETAILS) Hora de check-out (ej. '11:00').
     * @param P_CAPACITY          (PROPERTY_DETAILS) La nueva capacidad.
     * @param P_BEDROOMS          (PROPERTY_DETAILS) El nuevo número de dormitorios.
     * @param P_BATHROOMS         (PROPERTY_DETAILS) El nuevo número de baños.
     * @param P_BEDS              (PROPERTY_DETAILS) El nuevo número de camas.
     *
     * @param OUT_ERROR_CODE      Variable de salida para mensajes de error.
     */
    PROCEDURE SP_UPDATE_PROPERTY(
        -- Parámetros Requeridos
        P_PROPERTY_ID       IN  PROPERTIES.PROPERTY_ID%TYPE,

        -- Campos de PROPERTIES (Opcionales)
        P_TITLE             IN  PROPERTIES.TITLE%TYPE             DEFAULT NULL,
        P_BASE_PRICE_NIGHT  IN  PROPERTIES.BASE_PRICE_NIGHT%TYPE  DEFAULT NULL,
        P_ADDRESS_TEXT      IN  PROPERTIES.ADDRESS_TEXT%TYPE      DEFAULT NULL,
        P_CITY              IN  PROPERTIES.CITY%TYPE              DEFAULT NULL,
        P_STATE_REGION      IN  PROPERTIES.STATE_REGION%TYPE      DEFAULT NULL,
        P_COUNTRY           IN  PROPERTIES.COUNTRY%TYPE           DEFAULT NULL,
        P_POSTAL_CODE       IN  PROPERTIES.POSTAL_CODE%TYPE       DEFAULT NULL,
        P_LATITUDE          IN  PROPERTIES.LATITUDE%TYPE          DEFAULT NULL,
        P_LONGITUDE         IN  PROPERTIES.LONGITUDE%TYPE         DEFAULT NULL,

        -- Campos de PROPERTY_DETAILS (Opcionales)
        P_DESCRIPTION_LONG  IN  PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES       IN  PROPERTY_DETAILS.HOUSE_RULES%TYPE      DEFAULT NULL,
        P_CHECKIN_TIME      IN  PROPERTY_DETAILS.CHECKIN_TIME%TYPE     DEFAULT NULL,
        P_CHECKOUT_TIME     IN  PROPERTY_DETAILS.CHECKOUT_TIME%TYPE    DEFAULT NULL,
        P_CAPACITY          IN  PROPERTY_DETAILS.CAPACITY%TYPE         DEFAULT NULL,
        P_BEDROOMS          IN  PROPERTY_DETAILS.BEDROOMS%TYPE         DEFAULT NULL,
        P_BATHROOMS         IN  PROPERTY_DETAILS.BATHROOMS%TYPE        DEFAULT NULL,
        P_BEDS              IN  PROPERTY_DETAILS.BEDS%TYPE             DEFAULT NULL,

        -- Salida
        OUT_ERROR_CODE      OUT VARCHAR2
    );

/**
     * Obtiene toda la información necesaria para la página de detalles
     *
     * @param P_PROPERTY_ID             El ID del recinto a consultar.
     * @param OUT_DETAILS_CURSOR        Cursor con los datos (1 fila) de PROPERTIES, DETAILS y HOST.
     * @param OUT_IMAGES_CURSOR         Cursor con la lista de imágenes (N filas).
     * @param OUT_AMENITIES_CURSOR      Cursor con la lista de comodidades (N filas).
     * @param OUT_REVIEWS_SUMMARY_CUR   Cursor con el resumen de reseñas (1 fila: promedios, conteo).
     * @param OUT_REVIEWS_LIST_CURSOR   Cursor con la lista de las últimas N reseñas para el feed.
     * @param OUT_ERROR_CODE            Variable de salida para mensajes de error.
     */
    PROCEDURE SP_GET_PROPERTY_PAGE_DETAILS(
        P_PROPERTY_ID             IN  PROPERTIES.PROPERTY_ID%TYPE,
        OUT_DETAILS_CURSOR        OUT SYS_REFCURSOR,
        OUT_IMAGES_CURSOR         OUT SYS_REFCURSOR,
        OUT_AMENITIES_CURSOR      OUT SYS_REFCURSOR,
        OUT_REVIEWS_SUMMARY_CUR   OUT SYS_REFCURSOR,
        OUT_REVIEWS_LIST_CURSOR   OUT SYS_REFCURSOR,
        OUT_ERROR_CODE            OUT VARCHAR2
    );

END PROPERTY_PKG;
/

create or replace PACKAGE BODY PROPERTY_PKG AS

    PROCEDURE SP_UPDATE_PROPERTY(
        -- Parámetros Requeridos
        P_PROPERTY_ID       IN  PROPERTIES.PROPERTY_ID%TYPE,

        -- Campos de PROPERTIES (Opcionales)
        P_TITLE             IN  PROPERTIES.TITLE%TYPE             DEFAULT NULL,
        P_BASE_PRICE_NIGHT  IN  PROPERTIES.BASE_PRICE_NIGHT%TYPE  DEFAULT NULL,
        P_ADDRESS_TEXT      IN  PROPERTIES.ADDRESS_TEXT%TYPE      DEFAULT NULL,
        P_CITY              IN  PROPERTIES.CITY%TYPE              DEFAULT NULL,
        P_STATE_REGION      IN  PROPERTIES.STATE_REGION%TYPE      DEFAULT NULL,
        P_COUNTRY           IN  PROPERTIES.COUNTRY%TYPE           DEFAULT NULL,
        P_POSTAL_CODE       IN  PROPERTIES.POSTAL_CODE%TYPE       DEFAULT NULL,
        P_LATITUDE          IN  PROPERTIES.LATITUDE%TYPE          DEFAULT NULL,
        P_LONGITUDE         IN  PROPERTIES.LONGITUDE%TYPE         DEFAULT NULL,

        -- Campos de PROPERTY_DETAILS (Opcionales)
        P_DESCRIPTION_LONG  IN  PROPERTY_DETAILS.DESCRIPTION_LONG%TYPE DEFAULT NULL,
        P_HOUSE_RULES       IN  PROPERTY_DETAILS.HOUSE_RULES%TYPE      DEFAULT NULL,
        P_CHECKIN_TIME      IN  PROPERTY_DETAILS.CHECKIN_TIME%TYPE     DEFAULT NULL,
        P_CHECKOUT_TIME     IN  PROPERTY_DETAILS.CHECKOUT_TIME%TYPE    DEFAULT NULL,
        P_CAPACITY          IN  PROPERTY_DETAILS.CAPACITY%TYPE         DEFAULT NULL,
        P_BEDROOMS          IN  PROPERTY_DETAILS.BEDROOMS%TYPE         DEFAULT NULL,
        P_BATHROOMS         IN  PROPERTY_DETAILS.BATHROOMS%TYPE        DEFAULT NULL,
        P_BEDS              IN  PROPERTY_DETAILS.BEDS%TYPE             DEFAULT NULL,

        -- Salida
        OUT_ERROR_CODE      OUT VARCHAR2
    ) IS
    BEGIN
        -- Paso 1: Actualizar la tabla principal PROPERTIES
        -- Se usa NVL(param, columna) para actualizar solo si el parámetro no es nulo.
        -- Se añade la comprobación de HOST_ID por seguridad.
        UPDATE PROPERTIES
        SET
            TITLE            = NVL(P_TITLE, TITLE),
            BASE_PRICE_NIGHT = NVL(P_BASE_PRICE_NIGHT, BASE_PRICE_NIGHT),
            ADDRESS_TEXT     = NVL(P_ADDRESS_TEXT, ADDRESS_TEXT),
            CITY             = NVL(P_CITY, CITY),
            STATE_REGION     = NVL(P_STATE_REGION, STATE_REGION),
            COUNTRY          = NVL(P_COUNTRY, COUNTRY),
            POSTAL_CODE      = NVL(P_POSTAL_CODE, POSTAL_CODE),
            LATITUDE         = NVL(P_LATITUDE, LATITUDE),
            LONGITUDE        = NVL(P_LONGITUDE, LONGITUDE)
        WHERE
            PROPERTY_ID = P_PROPERTY_ID;

        -- Si la fila no existe o no le pertenece al host, SQL%NOTFOUND será TRUE
        IF SQL%NOTFOUND THEN
            -- Lanza un error personalizado. Esto detendrá la ejecución
            -- y será capturado por el bloque EXCEPTION.
            RAISE_APPLICATION_ERROR(-20001, 'Propiedad no encontrada');
        END IF;

        -- Paso 2: Actualizar la tabla de detalles PROPERTY_DETAILS
        UPDATE PROPERTY_DETAILS
        SET
            DESCRIPTION_LONG = NVL(P_DESCRIPTION_LONG, DESCRIPTION_LONG),
            HOUSE_RULES      = NVL(P_HOUSE_RULES, HOUSE_RULES),
            CHECKIN_TIME     = NVL(P_CHECKIN_TIME, CHECKIN_TIME),
            CHECKOUT_TIME    = NVL(P_CHECKOUT_TIME, CHECKOUT_TIME),
            CAPACITY         = NVL(P_CAPACITY, CAPACITY),
            BEDROOMS         = NVL(P_BEDROOMS, BEDROOMS),
            BATHROOMS        = NVL(P_BATHROOMS, BATHROOMS),
            BEDS             = NVL(P_BEDS, BEDS)
        WHERE
            PROPERTY_ID = P_PROPERTY_ID;

        -- Paso 3: Confirmar la transacción
        COMMIT;
        OUT_ERROR_CODE := NULL; -- Éxito, sin error

    EXCEPTION
        WHEN OTHERS THEN
            -- En caso de cualquier error (incluido el RAISE_APPLICATION_ERROR),
            -- deshacemos todos los cambios.
            ROLLBACK;
            -- Devolvemos el mensaje de error de Oracle
            OUT_ERROR_CODE := SQLERRM;

    END SP_UPDATE_PROPERTY;

    ------------------------------------------------------------------------------
    -- PROCEDURE: SP_GET_PROPERTY_PAGE_DETAILS
    -- Devuelve todos los datos necesarios para la página de detalle de una propiedad
    ------------------------------------------------------------------------------
    PROCEDURE SP_GET_PROPERTY_PAGE_DETAILS(
        P_PROPERTY_ID             IN  PROPERTIES.PROPERTY_ID%TYPE,
        OUT_DETAILS_CURSOR        OUT SYS_REFCURSOR,
        OUT_IMAGES_CURSOR         OUT SYS_REFCURSOR,
        OUT_AMENITIES_CURSOR      OUT SYS_REFCURSOR,
        OUT_REVIEWS_SUMMARY_CUR   OUT SYS_REFCURSOR,
        OUT_REVIEWS_LIST_CURSOR   OUT SYS_REFCURSOR,
        OUT_ERROR_CODE            OUT VARCHAR2
    ) IS
        v_img_count   NUMBER := 0;
        v_amen_count  NUMBER := 0;
        v_rev_count   NUMBER := 0;
    BEGIN
        -- 1. Cursor de detalles (Propiedad + Detalles + Host)
        OPEN OUT_DETAILS_CURSOR FOR
            SELECT
                p.TITLE, p.PROPERTY_TYPE, p.BASE_PRICE_NIGHT, p.CURRENCY_CODE,
                p.FORMATTED_ADDRESS, p.CITY, p.STATE_REGION, p.COUNTRY,
                p.LATITUDE, p.LONGITUDE,
                pd.DESCRIPTION_LONG, pd.HOUSE_RULES, pd.CHECKIN_TIME, pd.CHECKOUT_TIME,
                pd.CAPACITY, pd.BEDROOMS, pd.BATHROOMS, pd.BEDS,
                u.FIRST_NAME AS HOST_FIRST_NAME, u.LAST_NAME AS HOST_LAST_NAME,
                h.IS_VERIFIED AS HOST_IS_VERIFIED, h.CREATED_AT AS HOST_JOINED_AT
            FROM PROPERTIES p
                     JOIN PROPERTY_DETAILS pd ON p.PROPERTY_ID = pd.PROPERTY_ID
                     JOIN HOSTS h ON p.HOST_ID = h.HOST_ID
                     JOIN USERS u ON h.HOST_ID = u.USER_ID
            WHERE p.PROPERTY_ID = P_PROPERTY_ID;

        -- 2. Cursor de imágenes
        SELECT COUNT(*) INTO v_img_count
        FROM PROPERTY_IMAGES
        WHERE PROPERTY_ID = P_PROPERTY_ID;

        IF v_img_count > 0 THEN
            OPEN OUT_IMAGES_CURSOR FOR
                SELECT URL, CAPTION
                FROM PROPERTY_IMAGES
                WHERE PROPERTY_ID = P_PROPERTY_ID
                ORDER BY SORT_ORDER ASC;
        ELSE
            OPEN OUT_IMAGES_CURSOR FOR
                SELECT CAST(NULL AS VARCHAR2(500)) AS URL,
                       CAST(NULL AS VARCHAR2(150)) AS CAPTION
                FROM DUAL WHERE 1=0;
        END IF;

        -- 3. Cursor de amenities
        SELECT COUNT(*) INTO v_amen_count
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
                FROM DUAL WHERE 1=0;
        END IF;

        -- 4. Cursor de resumen de reseñas (siempre devuelve una fila)
        OPEN OUT_REVIEWS_SUMMARY_CUR FOR
            SELECT NVL(COUNT(R.REVIEW_ID),0) AS TOTAL_COUNT,
                   NVL(ROUND(AVG(R.RATING), 2),0) AS AVERAGE_RATING
            FROM REVIEWS R
            WHERE R.PROPERTY_ID = P_PROPERTY_ID
              AND R.IS_PUBLISHED = 1
              AND R.FOR_HOST = 0;

        -- 5. Cursor de lista de reseñas (máx 5)
        SELECT COUNT(*) INTO v_rev_count
        FROM REVIEWS
        WHERE PROPERTY_ID = P_PROPERTY_ID
          AND IS_PUBLISHED = 1
          AND FOR_HOST = 0;

        IF v_rev_count > 0 THEN
            OPEN OUT_REVIEWS_LIST_CURSOR FOR
                SELECT R.RATING, R."comment", R.CREATED_AT,
                       U.FIRST_NAME AS AUTHOR_FIRST_NAME, U.LAST_NAME AS AUTHOR_LAST_NAME
                FROM REVIEWS R
                         JOIN USERS U ON R.AUTHOR_USER_ID = U.USER_ID
                WHERE R.PROPERTY_ID = P_PROPERTY_ID
                  AND R.IS_PUBLISHED = 1
                  AND R.FOR_HOST = 0
                ORDER BY R.CREATED_AT DESC
                    FETCH NEXT 5 ROWS ONLY;
        ELSE
            OPEN OUT_REVIEWS_LIST_CURSOR FOR
                SELECT NULL AS RATING, NULL AS "comment", NULL AS CREATED_AT,
                       NULL AS AUTHOR_FIRST_NAME, NULL AS AUTHOR_LAST_NAME
                FROM DUAL WHERE 1=0;
        END IF;

        OUT_ERROR_CODE := NULL;

    EXCEPTION
        WHEN OTHERS THEN
            OUT_ERROR_CODE := 'Error al obtener detalles: ' || SQLERRM;
    END SP_GET_PROPERTY_PAGE_DETAILS;

END PROPERTY_PKG;
/

create or replace PACKAGE FILTER_PKG AS
  PROCEDURE SP_SEARCH_PROPERTIES(
    p_city        IN VARCHAR2 DEFAULT NULL,
    p_min_price   IN NUMBER DEFAULT NULL,
    p_max_price   IN NUMBER DEFAULT NULL,
    p_rooms       IN NUMBER DEFAULT NULL,
    p_beds        IN NUMBER DEFAULT NULL,
    p_baths       IN NUMBER DEFAULT NULL,
    p_capacity_total IN NUMBER DEFAULT NULL,
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

create or replace PACKAGE BODY FILTER_PKG AS

  PROCEDURE SP_SEARCH_PROPERTIES(
    p_city        IN VARCHAR2 DEFAULT NULL,
    p_min_price   IN NUMBER DEFAULT NULL,
    p_max_price   IN NUMBER DEFAULT NULL,
    p_rooms       IN NUMBER DEFAULT NULL,
    p_beds        IN NUMBER DEFAULT NULL,
    p_baths       IN NUMBER DEFAULT NULL,
    p_capacity_total IN NUMBER DEFAULT NULL,
    p_start_date     IN DATE DEFAULT NULL,
    p_end_date       IN DATE DEFAULT NULL,
    p_lat_min     IN NUMBER DEFAULT NULL,
    p_lat_max     IN NUMBER DEFAULT NULL,
    p_lng_min     IN NUMBER DEFAULT NULL,
    p_lng_max     IN NUMBER DEFAULT NULL,
    p_amenities   IN SYS.ODCINUMBERLIST DEFAULT NULL,
    p_result_set  OUT SYS_REFCURSOR
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
        AVG(r.RATING) AS AVG_RATING
      FROM PROPERTIES p
      LEFT JOIN PROPERTY_IMAGES i
             ON p.PROPERTY_ID = i.PROPERTY_ID
            AND i.SORT_ORDER = 0
      LEFT JOIN REVIEWS r
             ON p.PROPERTY_ID = r.PROPERTY_ID
      WHERE (p_city IS NULL OR p.STATE_REGION = p_city)
        AND (p_min_price IS NULL OR p.BASE_PRICE_NIGHT >= p_min_price)
        AND (p_max_price IS NULL OR p.BASE_PRICE_NIGHT <= p_max_price)
        AND (p_rooms IS NULL OR EXISTS (
              SELECT 1 FROM PROPERTY_DETAILS d
               WHERE d.PROPERTY_ID = p.PROPERTY_ID
                 AND d.BEDROOMS >= p_rooms))
        AND (p_beds IS NULL OR EXISTS (
              SELECT 1 FROM PROPERTY_DETAILS d
               WHERE d.PROPERTY_ID = p.PROPERTY_ID
                 AND d.BEDS >= p_beds))
        AND (p_baths IS NULL OR EXISTS (
              SELECT 1 FROM PROPERTY_DETAILS d
               WHERE d.PROPERTY_ID = p.PROPERTY_ID
                 AND d.BATHROOMS >= p_baths))
        AND (p_capacity_total IS NULL OR EXISTS (
              SELECT 1 FROM PROPERTY_DETAILS d
               WHERE d.PROPERTY_ID = p.PROPERTY_ID
                 AND d.CAPACITY >= p_capacity_total))
        AND (
          p_start_date IS NULL
          OR p_end_date IS NULL
          OR EXISTS (
            SELECT 1 FROM AVAILABILITIES a
             WHERE a.PROPERTY_ID = p.PROPERTY_ID
               AND a.START_DATE <= p_start_date
               AND a.END_DATE   >= p_end_date
          )
        )
        AND (p_lat_min IS NULL OR p.LATITUDE BETWEEN p_lat_min AND p_lat_max)
        AND (p_lng_min IS NULL OR p.LONGITUDE BETWEEN p_lng_min AND p_lng_max)
        AND (p_amenities IS NULL OR EXISTS (
              SELECT 1
                FROM PROPERTY_AMENITIES pa
                JOIN TABLE(p_amenities) t
                  ON pa.AMENITY_ID = t.COLUMN_VALUE
               WHERE pa.PROPERTY_ID = p.PROPERTY_ID))
      GROUP BY
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
        i.URL;
  END SP_SEARCH_PROPERTIES;

END FILTER_PKG;
/

