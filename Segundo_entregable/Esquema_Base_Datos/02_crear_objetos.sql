create table USERS
(
    USER_ID       NUMBER default "SMART01"."ISEQ$$_76085".nextval generated as identity
		primary key,
    FIRST_NAME    VARCHAR2(100)          not null,
    LAST_NAME     VARCHAR2(100),
    EMAIL         VARCHAR2(255)          not null
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

create trigger TRG_CREATE_DEFAULT_TENANT
    after insert
    on USERS
    for each row
BEGIN
    INSERT INTO TENANTS (TENANT_ID, created_at)
    VALUES (:NEW.USER_ID, SYSDATE); -- :NEW.user_id es el ID del usuario que se acaba de crear
END;
/

create table USER_AUTH_IDENTITIES
(
    IDENTITY_ID      NUMBER    default "SMART01"."ISEQ$$_76089".nextval generated as identity
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
    PREFERENCE_ID NUMBER       default "SMART01"."ISEQ$$_76100".nextval generated as identity
		primary key,
    CODE          VARCHAR2(50)                not null
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
    primary key (TENANT_ID, PREFERENCE_ID)
)
/

create table AMENITIES
(
    AMENITY_ID    NUMBER default "SMART01"."ISEQ$$_76120".nextval generated as identity
		primary key,
    CODE          VARCHAR2(50)  not null
        unique,
    NAME          VARCHAR2(100) not null,
    DESCRIPTION   CLOB,
    DISPLAY_ORDER NUMBER default 0,
    CREATED_AT    DATE   default SYSDATE
)
/

create table PAYMENT_TYPES
(
    PAYMENT_TYPE_ID NUMBER default "SMART01"."ISEQ$$_76138".nextval generated as identity
		primary key,
    NAME            VARCHAR2(50) not null
        unique,
    DESCRIPTION     CLOB,
    CREATED_AT      DATE   default SYSDATE
)
/

create table USER_PAYMENT_METHODS
(
    PAYMENT_METHOD_ID NUMBER    default "SMART01"."ISEQ$$_76144".nextval generated as identity
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
        primary key,
    NAME          VARCHAR2(50)     not null,
    EXPONENT      NUMBER default 2 not null,
    CREATED_AT    DATE   default SYSDATE
)
/

create table PROPERTIES
(
    PROPERTY_ID       NUMBER default "SMART01"."ISEQ$$_76108".nextval generated as identity
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
    CREATED_AT        DATE   default SYSDATE
)
/

create table PROPERTY_DETAILS
(
    PROPERTY_ID      NUMBER not null
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
    UPDATED_AT       DATE
)
/

create table PROPERTY_IMAGES
(
    IMAGE_ID    NUMBER default "SMART01"."ISEQ$$_76117".nextval generated as identity
		primary key,
    PROPERTY_ID NUMBER           not null
        references PROPERTIES,
    URL         VARCHAR2(500)    not null,
    CAPTION     VARCHAR2(150),
    SORT_ORDER  NUMBER default 0 not null
)
/

create table PROPERTY_AMENITIES
(
    PROPERTY_ID NUMBER not null
        references PROPERTIES,
    AMENITY_ID  NUMBER not null
        references AMENITIES,
    primary key (PROPERTY_ID, AMENITY_ID)
)
/

create table AVAILABILITIES
(
    AVAILABILITY_ID NUMBER default "SMART01"."ISEQ$$_76128".nextval generated as identity
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
    BOOKING_ID    NUMBER        default "SMART01"."ISEQ$$_76131".nextval generated as identity
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
    STATUS        VARCHAR2(20)  default 'pending' not null,
    CREATED_AT    DATE          default SYSDATE,
    ACCEPTED_AT   DATE,
    DECLINED_AT   DATE,
    COMPLETED_AT  DATE,
    CHECKIN_CODE  VARCHAR2(50),
    HOST_NOTE     CLOB,
    TENANT_NOTE   CLOB
)
/

create table PAYMENTS
(
    PAYMENT_ID        NUMBER       default "SMART01"."ISEQ$$_76147".nextval generated as identity
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
    DETAIL_ID     NUMBER default "SMART01"."ISEQ$$_76150".nextval generated as identity
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
    REVIEW_ID      NUMBER    default "SMART01"."ISEQ$$_76153".nextval generated as identity
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
    "comment"      CLOB,
    CREATED_AT     DATE      default SYSDATE,
    PUBLISHABLE_AT DATE,
    PUBLISHED_AT   DATE,
    IS_PUBLISHED   NUMBER(1) default 0 not null
)
/

create table CONVERSATIONS
(
    CONVERSATION_ID NUMBER       default "SMART01"."ISEQ$$_76158".nextval generated as identity
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
        references CONVERSATIONS,
    USER_ID         NUMBER not null
        references USERS,
    ROLE            VARCHAR2(20),
    JOINED_AT       DATE default SYSDATE,
    constraint PK_CONVERSATION_PARTICIPANTS
        primary key (CONVERSATION_ID, USER_ID)
)
/

create table MESSAGES
(
    MESSAGE_ID      NUMBER    default "SMART01"."ISEQ$$_76162".nextval generated as identity
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

create table FX_RATE_QUOTES
(
    FX_QUOTE_ID    NUMBER default "SMART01"."ISEQ$$_76169".nextval generated as identity
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

