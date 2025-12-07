create TYPE persona_t AS OBJECT (
    nombre      VARCHAR2(50),
    apellido    VARCHAR2(50),
    edad        NUMBER
)
/

create TYPE T_PREFERENCE_INPUT AS OBJECT (
    preference_code VARCHAR2(100),
    preference_value VARCHAR2(4000)
)
/

create TYPE T_CALENDAR_DAY AS OBJECT (
    CAL_DATE          DATE,
    IS_AVAILABLE    NUMBER(1), -- 1 para sí, 0 para no
    PRICE             NUMBER(12, 2),
    STATUS            VARCHAR2(20) -- 'reserved', 'blocked', 'special', 'default'
)
/

create type T_PREFERENCE_TABLE as table of T_PREFERENCE_INPUT
/

create type T_CALENDAR_DAY_TABLE as table of T_CALENDAR_DAY
/

create table USERS
(
    USER_ID       NUMBER default "SMART"."ISEQ$$_75820".nextval generated as identity
		constraint UQ_USERS_EMAIL
			primary key,
    FIRST_NAME    VARCHAR2(100)          not null,
    LAST_NAME     VARCHAR2(100),
    EMAIL         VARCHAR2(255)          not null
        constraint PK_USERS
            unique,
    DNI           VARCHAR2(9),
    PHONE_NUMBER  VARCHAR2(30),
    STATUS        VARCHAR2(20),
    BLOCKED_UNTIL DATE,
    CREATED_AT    DATE   default SYSDATE not null,
    BIRTH_DATE    DATE,
    UPDATED_AT    DATE
)
/

create trigger TRG_AUTO_CREATE_TENANT
    after insert
    on USERS
    for each row
BEGIN
    -- Inserta el nuevo ID de usuario en la tabla TENANTS
    -- Usamos :NEW.USER_ID para obtener el ID generado en la tabla USERS
    INSERT INTO TENANTS (
        TENANT_ID,
        BIO,
        AVERAGE_RATING,
        REVIEWS_COUNT,
        CREATED_AT,
        UPDATED_AT
    ) VALUES (
        :NEW.USER_ID,  -- Mismo ID que el usuario
        NULL,          -- BIO vacío inicialmente
        0,             -- Rating inicial (aunque tiene default en la tabla, es bueno ser explícito)
        0,             -- Conteo de reviews inicial
        SYSDATE,       -- Fecha de creación
        SYSDATE        -- Fecha de actualización
    );
END;
/

create table USER_AUTH_IDENTITIES
(
    IDENTITY_ID      NUMBER    default "SMART"."ISEQ$$_75824".nextval generated as identity
		constraint PK_USER_AUTH_ID
			primary key,
    USER_ID          NUMBER              not null
        references USERS,
    PROVIDER         VARCHAR2(30)        not null,
    PROVIDER_USER_ID VARCHAR2(255)       not null,
    EMAIL            VARCHAR2(255),
    EMAIL_VERIFIED   NUMBER(1) default 0 not null,
    PASSWORD_HASH    VARCHAR2(255),
    LAST_LOGIN_AT    DATE,
    CREATED_AT       DATE      default SYSDATE
)
/

create table TENANTS
(
    TENANT_ID      NUMBER not null
        constraint PK_TENANTS
            primary key
        references USERS,
    BIO            CLOB,
    AVERAGE_RATING NUMBER(3, 2) default 0,
    REVIEWS_COUNT  NUMBER       default 0,
    CREATED_AT     DATE         default SYSDATE,
    UPDATED_AT     DATE
)
/

create table HOSTS
(
    HOST_ID        NUMBER                 not null
        constraint PK_HOSTS
            primary key
        references USERS,
    DESCRIPTION    CLOB,
    IS_VERIFIED    NUMBER(1)    default 0 not null,
    AVERAGE_RATING NUMBER(3, 2) default 0,
    REVIEWS_COUNT  NUMBER       default 0,
    CREATED_AT     DATE         default SYSDATE,
    UPDATED_AT     DATE
)
/

create table PREFERENCES
(
    PREFERENCE_ID NUMBER       default "SMART"."ISEQ$$_75835".nextval generated as identity
		constraint UQ_PREFERENCES_KEY
			primary key,
    CODE          VARCHAR2(50)                not null
        constraint PK_PREFERENCES
            unique,
    NAME          VARCHAR2(100)               not null,
    DESCRIPTION   CLOB,
    VALUE_TYPE    VARCHAR2(20) default 'text' not null,
    CREATED_AT    DATE         default SYSDATE
)
/

create table TENANT_PREFERENCES
(
    TENANT_ID     NUMBER              not null
        references TENANTS,
    PREFERENCE_ID NUMBER              not null
        references PREFERENCES,
    VALUE_TEXT    VARCHAR2(255),
    VALUE_BOOL    NUMBER(1) default 0 not null,
    VALUE_INT     NUMBER,
    UPDATED_AT    DATE,
    constraint PK_TENANT_PREFS
        primary key (TENANT_ID, PREFERENCE_ID)
)
/

create table PAYMENT_TYPES
(
    PAYMENT_TYPE_ID NUMBER default "SMART"."ISEQ$$_75849".nextval generated as identity
		constraint PK_PAYMENT_TYPES
			primary key,
    NAME            VARCHAR2(50) not null
        constraint UQ_PAYMENT_TYPES_NAME
            unique,
    DESCRIPTION     CLOB,
    CREATED_AT      DATE   default SYSDATE
)
/

create table USER_PAYMENT_METHODS
(
    PAYMENT_METHOD_ID NUMBER    default "SMART"."ISEQ$$_75855".nextval generated as identity
		constraint PK_USER_PAY_METHODS
			primary key,
    USER_ID           NUMBER              not null
        references USERS,
    PAYMENT_TYPE_ID   NUMBER              not null
        references PAYMENT_TYPES,
    PROVIDER          VARCHAR2(50)        not null,
    ACCOUNT_REF       VARCHAR2(100),
    EXP_MONTH         NUMBER,
    EXP_YEAR          NUMBER,
    IS_DEFAULT        NUMBER(1) default 0 not null,
    CREATED_AT        DATE      default SYSDATE,
    UPDATED_AT        DATE
)
/

create table CURRENCIES
(
    CURRENCY_CODE CHAR(3)          not null
        constraint PK_CURRENCIES
            primary key,
    NAME          VARCHAR2(50)     not null,
    EXPONENT      NUMBER default 2 not null,
    CREATED_AT    DATE   default SYSDATE
)
/

create table PROPERTIES
(
    PROPERTY_ID       NUMBER       default "SMART"."ISEQ$$_75860".nextval generated as identity
		constraint PK_PROPERTIES
			primary key,
    HOST_ID           NUMBER        not null
        references HOSTS,
    TITLE             VARCHAR2(150) not null,
    PROPERTY_TYPE     VARCHAR2(30)  not null,
    BASE_PRICE_NIGHT  NUMBER(12, 2) not null,
    CURRENCY_CODE     CHAR(3)       not null
        references CURRENCIES,
    ADDRESS_TEXT      VARCHAR2(255) not null,
    FORMATTED_ADDRESS VARCHAR2(255) not null,
    CITY              VARCHAR2(255) not null,
    STATE_REGION      VARCHAR2(255) not null,
    COUNTRY           VARCHAR2(255) not null,
    POSTAL_CODE       VARCHAR2(255) not null,
    LATITUDE          NUMBER(9, 6)  not null,
    LONGITUDE         NUMBER(9, 6)  not null,
    STATUS            VARCHAR2(20),
    CREATED_AT        DATE         default SYSDATE,
    AVERAGE_RATING    NUMBER(3, 2) default 0,
    REVIEWS_COUNT     NUMBER       default 0
)
/

create index IDX_PROPERTIES_PRICE
    on PROPERTIES (BASE_PRICE_NIGHT)
/

create index IDX_PROPERTIES_CITY
    on PROPERTIES (CITY)
/

create index IDX_PROP_GEO
    on PROPERTIES (LATITUDE, LONGITUDE)
/

create index IDX_PROP_REGION_PRICE
    on PROPERTIES (STATE_REGION, BASE_PRICE_NIGHT)
/

create table PROPERTY_DETAILS
(
    PROPERTY_ID      NUMBER not null
        constraint PK_PROP_DETAILS
            primary key
        references PROPERTIES,
    DESCRIPTION_LONG CLOB,
    HOUSE_RULES      CLOB,
    CHECKIN_TIME     VARCHAR2(5),
    CHECKOUT_TIME    VARCHAR2(5),
    CAPACITY         NUMBER,
    BEDROOMS         NUMBER,
    BATHROOMS        NUMBER,
    BEDS             NUMBER,
    AREA_M2          NUMBER,
    FLOOR_NUMBER     NUMBER,
    CREATED_AT       DATE default SYSDATE,
    UPDATED_AT       DATE,
    MAX_ADULTS       NUMBER,
    MAX_CHILDREN     NUMBER,
    MAX_BABY         NUMBER,
    MAX_PETS         NUMBER
)
/

create table PROPERTY_IMAGES
(
    IMAGE_ID    NUMBER default "SMART"."ISEQ$$_75869".nextval generated as identity
		constraint PK_PROPERTY_IMAGES
			primary key,
    PROPERTY_ID NUMBER           not null
        references PROPERTIES,
    URL         VARCHAR2(500)    not null,
    CAPTION     VARCHAR2(150),
    SORT_ORDER  NUMBER default 0 not null,
    constraint UQ_PROPERTY_IMAGES
        unique (PROPERTY_ID, SORT_ORDER)
)
/

create index IDX_IMG_MAIN_COVERING
    on PROPERTY_IMAGES (PROPERTY_ID, SORT_ORDER, URL)
/

create table AVAILABILITIES
(
    AVAILABILITY_ID NUMBER default "SMART"."ISEQ$$_75874".nextval generated as identity
		constraint PK_AVAILABILITIES
			primary key,
    PROPERTY_ID     NUMBER not null
        references PROPERTIES,
    START_DATE      DATE   not null,
    END_DATE        DATE   not null,
    KIND            VARCHAR2(30),
    PRICE_PER_NIGHT NUMBER(12, 2),
    CREATED_AT      DATE   default SYSDATE
)
/

create table BOOKINGS
(
    BOOKING_ID    NUMBER        default "SMART"."ISEQ$$_75877".nextval generated as identity
		constraint PK_BOOKINGS
			primary key,
    PROPERTY_ID   NUMBER                          not null
        references PROPERTIES,
    TENANT_ID     NUMBER                          not null
        references TENANTS,
    CHECKIN_DATE  DATE                            not null,
    CHECKOUT_DATE DATE                            not null,
    GUEST_COUNT   NUMBER                          not null,
    CURRENCY_CODE CHAR(3)                         not null
        references CURRENCIES,
    NIGHT_COUNT   NUMBER                          not null,
    PRICE_NIGHTS  NUMBER(12, 2)                   not null,
    CLEANING_FEE  NUMBER(12, 2) default 0,
    SERVICE_FEE   NUMBER(12, 2) default 0,
    TAXES         NUMBER(12, 2) default 0,
    TOTAL_AMOUNT  NUMBER(12, 2)                   not null,
    STATUS        VARCHAR2(20)  default 'PENDING' not null
        constraint BOOKINGS_STATUS_CHK
            check (STATUS IN ('PENDING', 'COMPLETED', 'CANCELLED', 'ACCEPTED', 'DECLINED')),
    CREATED_AT    DATE          default SYSDATE,
    ACCEPTED_AT   DATE,
    DECLINED_AT   DATE,
    COMPLETED_AT  DATE,
    CHECKIN_CODE  VARCHAR2(50),
    HOST_NOTE     CLOB,
    TENANT_NOTE   CLOB
)
/

create index IDX_BOOKINGS_PROP_ID
    on BOOKINGS (PROPERTY_ID)
/

create index IDX_BOOKINGS_TENANT_ID
    on BOOKINGS (TENANT_ID)
/

create index IDX_BOOKINGS_AVAILABILITY
    on BOOKINGS (PROPERTY_ID, CHECKIN_DATE, CHECKOUT_DATE)
/

create index IDX_BOOKINGS_OVERLAP
    on BOOKINGS (PROPERTY_ID, CHECKOUT_DATE, CHECKIN_DATE)
/

create trigger TRG_BOOKING_COMPLETED_REVIEWS
    after update of STATUS
    on BOOKINGS
    for each row
    when (UPPER(NEW.STATUS) = 'COMPLETED' AND UPPER(OLD.STATUS) != 'COMPLETED')
DECLARE
  v_host_id NUMBER;
  v_tenant_id NUMBER;
BEGIN
  -- 1. Obtener el HOST_ID de la propiedad asociada al booking
  -- Usamos un bloque anónimo para capturar si no existe la propiedad (seguridad extra)
  BEGIN
      SELECT h.HOST_ID
      INTO v_host_id
      FROM PROPERTIES p
      INNER JOIN HOSTS h ON p.HOST_ID = h.HOST_ID
      WHERE p.PROPERTY_ID = :NEW.PROPERTY_ID;
  EXCEPTION
      WHEN NO_DATA_FOUND THEN
          -- Si por alguna razón corrupta no hay host, salimos para no romper el update
          RETURN;
  END;

  -- 2. El TENANT_ID ya está en el booking
  v_tenant_id := :NEW.TENANT_ID;

  -- 3. Crear placeholder para el TENANT (Opina sobre el Host/Propiedad)
  BEGIN
    INSERT INTO REVIEWS (
      BOOKING_ID,
      PROPERTY_ID,
      AUTHOR_USER_ID,
      TARGET_USER_ID,
      FOR_HOST,
      RATING,
      COMMENTS, -- Asegúrate que tu columna se llame COMMENTS (plural)
      CREATED_AT,
      IS_PUBLISHED
    ) VALUES (
      :NEW.BOOKING_ID,
      :NEW.PROPERTY_ID,
      v_tenant_id,      -- Autor: Tenant
      v_host_id,        -- Target: Host
      0,                -- For Host: 0
      0,                -- Rating: 0 (Pendiente)
      NULL,
      SYSTIMESTAMP,
      0
    );
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN NULL; -- Ya existe, ignorar
  END;

  -- 4. Crear placeholder para el HOST (Opina sobre el Tenant)
  BEGIN
    INSERT INTO REVIEWS (
      BOOKING_ID,
      PROPERTY_ID,
      AUTHOR_USER_ID,
      TARGET_USER_ID,
      FOR_HOST,
      RATING,
      COMMENTS, -- Asegúrate que tu columna se llame COMMENTS (plural)
      CREATED_AT,
      IS_PUBLISHED
    ) VALUES (
      :NEW.BOOKING_ID,
      :NEW.PROPERTY_ID,
      v_host_id,        -- Autor: Host
      v_tenant_id,      -- Target: Tenant
      1,                -- For Host: 1
      0,                -- Rating: 0 (Pendiente)
      NULL,
      SYSTIMESTAMP,
      0
    );
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN NULL; -- Ya existe, ignorar
  END;

EXCEPTION
  WHEN OTHERS THEN
    -- Imprimir error en consola para depuración, pero no detener la transacción
    DBMS_OUTPUT.PUT_LINE('Error en trigger TRG_BOOKING_COMPLETED_REVIEWS: ' || SQLERRM);
END;
/

create trigger TRG_AUDIT_BOOKINGS
    after insert or update or delete
    on BOOKINGS
    for each row
BEGIN
    -- Caso 1: Nueva Reserva
    IF INSERTING THEN
        INSERT INTO AUDIT_LOGS (table_name, operation, booking_id, new_status, changed_by)
        VALUES ('BOOKINGS', 'INSERT', :NEW.BOOKING_ID, :NEW.status, USER);

    -- Caso 2: Modificación (Cambio de estado/fechas)
    ELSIF UPDATING THEN
        INSERT INTO AUDIT_LOGS (table_name, operation, booking_id, old_status, new_status, changed_by)
        VALUES ('BOOKINGS', 'UPDATE', :OLD.BOOKING_ID, :OLD.status, :NEW.status, USER);

    -- Caso 3: Cancelación definitiva
    ELSIF DELETING THEN
        INSERT INTO AUDIT_LOGS (table_name, operation, booking_id, old_status, changed_by)
        VALUES ('BOOKINGS', 'DELETE', :OLD.BOOKING_ID, :OLD.status, USER);
    END IF;
END;
/

create table PAYMENTS
(
    PAYMENT_ID        NUMBER       default "SMART"."ISEQ$$_75884".nextval generated as identity
		constraint PK_PAYMENTS
			primary key,
    BOOKING_ID        NUMBER                         not null
        references BOOKINGS,
    PAYMENT_METHOD_ID NUMBER
        references USER_PAYMENT_METHODS,
    AMOUNT            NUMBER(12, 2)                  not null,
    CURRENCY_CODE     CHAR(3)                        not null
        references CURRENCIES,
    STATUS            VARCHAR2(20) default 'pending' not null,
    DIRECTION         VARCHAR2(10) default 'charge'  not null,
    EXTERNAL_ID       VARCHAR2(150),
    MESSAGE           VARCHAR2(255),
    CREATED_AT        DATE         default SYSDATE,
    PROCESSED_AT      DATE
)
/

create table PAYMENT_DETAILS
(
    DETAIL_ID     NUMBER default "SMART"."ISEQ$$_75887".nextval generated as identity
		constraint PK_PAYMENT_DETAILS
			primary key,
    PAYMENT_ID    NUMBER        not null
        references PAYMENTS,
    CURRENCY_CODE CHAR(3)       not null
        references CURRENCIES,
    TOTAL_GROSS   NUMBER(12, 2) not null,
    HOST_PAYOUT   NUMBER(12, 2) not null,
    PLATFORM_FEE  NUMBER(12, 2) not null,
    TAX_IGV       NUMBER(12, 2) not null,
    CREATED_AT    DATE   default SYSDATE
)
/

create table REVIEWS
(
    REVIEW_ID      NUMBER    default "SMART"."ISEQ$$_75890".nextval generated as identity
		constraint PK_REVIEWS
			primary key,
    BOOKING_ID     NUMBER              not null
        references BOOKINGS,
    PROPERTY_ID    NUMBER              not null
        references PROPERTIES,
    AUTHOR_USER_ID NUMBER              not null
        references USERS,
    TARGET_USER_ID NUMBER              not null
        references USERS,
    FOR_HOST       NUMBER(1) default 0 not null,
    RATING         NUMBER              not null,
    COMMENTS       CLOB,
    CREATED_AT     DATE      default SYSDATE,
    PUBLISHABLE_AT DATE,
    PUBLISHED_AT   DATE,
    IS_PUBLISHED   NUMBER(1) default 0 not null
)
/

create index IDX_REVIEWS_PROP_ID
    on REVIEWS (PROPERTY_ID)
/

create index IDX_REVIEW_AUTHOR
    on REVIEWS (AUTHOR_USER_ID)
/

create index IDX_REVIEW_BOOKING
    on REVIEWS (BOOKING_ID)
/

create index IDX_REVIEW_TARGET
    on REVIEWS (TARGET_USER_ID)
/

create index IDX_REVIEW_FOR_HOST
    on REVIEWS (FOR_HOST)
/

create index IDX_REVIEW_PUBLISHED
    on REVIEWS (IS_PUBLISHED, AUTHOR_USER_ID)
/

create trigger TRG_UPDATE_TENANT_STATS
    after insert or update of IS_PUBLISHED
    on REVIEWS
    for each row
declare
    v_new_avg NUMBER(3, 2);
    v_count   NUMBER;
begin
    -- CASO: El Host escribe la reseña (FOR_HOST = 1) -> El "Target" es el Tenant
    -- Solo procesamos si la reseña ya es pública (IS_PUBLISHED = 1)
    IF :NEW.FOR_HOST = 1 AND :NEW.IS_PUBLISHED = 1 THEN

        -- 1. Calculamos el nuevo promedio y conteo para ese USUARIO (Tenant)
        SELECT NVL(AVG(RATING), 0), COUNT(*)
        INTO v_new_avg, v_count
        FROM REVIEWS
        WHERE TARGET_USER_ID = :NEW.TARGET_USER_ID -- Buscamos al usuario objetivo
          AND FOR_HOST = 1                         -- Solo reseñas escritas por hosts
          AND IS_PUBLISHED = 1;                    -- Solo las visibles

        -- 2. Actualizamos la tabla TENANTS
        UPDATE TENANTS
        SET AVERAGE_RATING = v_new_avg,
            REVIEWS_COUNT  = v_count,
            UPDATED_AT     = SYSDATE
        WHERE TENANT_ID = :NEW.TARGET_USER_ID;

    END IF;
end;
/

create trigger TRG_UPDATE_PROPERTY_STATS
    after insert or update of IS_PUBLISHED
    on REVIEWS
    for each row
declare
    v_new_avg NUMBER(3, 2);
    v_count   NUMBER;
begin
    -- CASO: El Tenant escribe la reseña (FOR_HOST = 0)
    -- Solo procesamos si la reseña ya es pública (IS_PUBLISHED = 1)
    IF :NEW.FOR_HOST = 0 AND :NEW.IS_PUBLISHED = 1 THEN

        -- 1. Calculamos el nuevo promedio y conteo solo de esta propiedad
        SELECT NVL(AVG(RATING), 0), COUNT(*)
        INTO v_new_avg, v_count
        FROM REVIEWS
        WHERE PROPERTY_ID = :NEW.PROPERTY_ID  -- Buscamos por la propiedad
          AND FOR_HOST = 0                    -- Solo reseñas de inquilinos
          AND IS_PUBLISHED = 1;               -- Solo las visibles

        -- 2. Actualizamos la tabla PROPERTIES
        UPDATE PROPERTIES
        SET AVERAGE_RATING = v_new_avg,
            REVIEWS_COUNT  = v_count
            -- UPDATED_AT     = SYSDATE  -- Descomenta si tienes esta columna
        WHERE PROPERTY_ID = :NEW.PROPERTY_ID;

    END IF;
end;
/

create table CONVERSATIONS
(
    CONVERSATION_ID NUMBER       default "SMART"."ISEQ$$_75895".nextval generated as identity
		constraint PK_CONVERSATIONS
			primary key,
    PROPERTY_ID     NUMBER
        references PROPERTIES,
    BOOKING_ID      NUMBER
        references BOOKINGS,
    STATUS          VARCHAR2(20) default 'open' not null,
    CREATED_AT      DATE         default SYSDATE,
    CLOSED_AT       DATE
)
/

create table CONVERSATION_PARTICIPANTS
(
    CONVERSATION_ID NUMBER not null
        references CONVERSATIONS (),
    USER_ID         NUMBER not null
        references USERS (),
    ROLE            VARCHAR2(20),
    JOINED_AT       DATE default SYSDATE,
    constraint PK_CONVERSATION_PARTICIPANTS
        primary key (CONVERSATION_ID, USER_ID)
)
/

create table MESSAGES
(
    MESSAGE_ID      NUMBER    default "SMART"."ISEQ$$_75900".nextval generated as identity
		constraint PK_MESSAGES
			primary key,
    CONVERSATION_ID NUMBER              not null
        references CONVERSATIONS,
    AUTHOR_USER_ID  NUMBER              not null
        references USERS,
    CONTENT         CLOB                not null,
    IS_READ         NUMBER(1) default 0 not null,
    SENT_AT         DATE      default SYSDATE,
    READ_AT         DATE
)
/

create index IDX_MESSAGES_CONV_ID
    on MESSAGES (CONVERSATION_ID)
/

create table FX_RATE_QUOTES
(
    FX_QUOTE_ID    NUMBER default "SMART"."ISEQ$$_75905".nextval generated as identity
		constraint PK_FX_RATES
			primary key,
    BASE_CURRENCY  CHAR(3) not null
        references CURRENCIES,
    QUOTE_CURRENCY CHAR(3) not null
        references CURRENCIES,
    RATE_DECIMAL   NUMBER(20, 10),
    SOURCE         VARCHAR2(50),
    QUOTED_AT      DATE    not null,
    CREATED_AT     DATE   default SYSDATE
)
/

create table AMENITIES_CATEGORIES
(
    CATEGORY_ID NUMBER generated as identity
        constraint PK_AMEN_CATEGORIES
            primary key,
    NAME        VARCHAR2(100) not null
)
/

create table AMENITIES
(
    AMENITY_ID          NUMBER default "SMART"."ISEQ$$_75843".nextval generated as identity
		constraint UQ_AMENITIES_NAME
			primary key,
    CODE                VARCHAR2(50)  not null
        constraint PK_AMENITIES
            unique,
    NAME                VARCHAR2(100) not null,
    DESCRIPTION         CLOB,
    DISPLAY_ORDER       NUMBER default 0,
    CREATED_AT          DATE   default SYSDATE,
    AMENITY_CATEGORY_ID NUMBER
        constraint FK_AMENITY_CATEGORY
            references AMENITIES_CATEGORIES
)
/

create table PROPERTY_AMENITIES
(
    PROPERTY_ID NUMBER not null
        references PROPERTIES,
    AMENITY_ID  NUMBER not null
        references AMENITIES,
    constraint PK_PROP_AMENITIES
        primary key (PROPERTY_ID, AMENITY_ID)
)
/

create table AUDIT_LOGS
(
    LOG_ID     NUMBER       default "SMART"."ISEQ$$_76990".nextval generated as identity
		primary key,
    TABLE_NAME VARCHAR2(50),
    OPERATION  VARCHAR2(10),
    BOOKING_ID NUMBER,
    OLD_STATUS VARCHAR2(20),
    NEW_STATUS VARCHAR2(20),
    CHANGED_BY VARCHAR2(50),
    CHANGED_AT TIMESTAMP(6) default SYSTIMESTAMP
)
/

create view V_HOST_REVIEW_STATS as
SELECT
  u.USER_ID AS HOST_ID,
  COUNT(r.REVIEW_ID) AS TOTAL_REVIEWS,
  ROUND(AVG(r.RATING), 1) AS AVERAGE_RATING,
  SUM(CASE WHEN r.RATING = 5 THEN 1 ELSE 0 END) AS RATING_5_COUNT,
  SUM(CASE WHEN r.RATING = 4 THEN 1 ELSE 0 END) AS RATING_4_COUNT,
  SUM(CASE WHEN r.RATING = 3 THEN 1 ELSE 0 END) AS RATING_3_COUNT,
  SUM(CASE WHEN r.RATING = 2 THEN 1 ELSE 0 END) AS RATING_2_COUNT,
  SUM(CASE WHEN r.RATING = 1 THEN 1 ELSE 0 END) AS RATING_1_COUNT
FROM USERS u
LEFT JOIN REVIEWS r ON u.USER_ID = r.TARGET_USER_ID
  AND r.FOR_HOST = 0           -- Solo reseñas donde el tenant opina
  AND r.IS_PUBLISHED = 1       -- Solo reseñas publicadas
  AND r.RATING > 0             -- Solo con rating real (no placeholder)
WHERE u.USER_ID IN (SELECT h.HOST_ID FROM HOSTS h)
GROUP BY u.USER_ID
/

create view V_HOST_REVIEWS_DETAIL as
SELECT
    p.HOST_ID,
    r.REVIEW_ID,
    r.BOOKING_ID,
    r.AUTHOR_USER_ID AS REVIEWER_ID,
    r.RATING,
    r.COMMENTS AS COMMENTS,
    r.CREATED_AT,
    -- Información del reviewer (huésped)
    u.FIRST_NAME AS REVIEWER_FIRST_NAME,
    u.LAST_NAME AS REVIEWER_LAST_NAME,
    NULL AS REVIEWER_IMAGE,  -- USERS no tiene columna de imagen de perfil
    -- Información de la propiedad
    p.PROPERTY_ID,
    p.TITLE AS PROPERTY_TITLE,
    -- Información del booking
    b.CHECKIN_DATE,
    b.CHECKOUT_DATE
FROM REVIEWS r
INNER JOIN BOOKINGS b ON r.BOOKING_ID = b.BOOKING_ID
INNER JOIN PROPERTIES p ON b.PROPERTY_ID = p.PROPERTY_ID
INNER JOIN USERS u ON r.AUTHOR_USER_ID = u.USER_ID
WHERE r.FOR_HOST = 0          -- Reseñas sobre propiedades (no sobre huéspedes)
  AND r.IS_PUBLISHED = 1      -- Solo reseñas publicadas
  AND r.RATING > 0
/