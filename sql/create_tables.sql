create table URLTBL (
	ID		int not null,
        URL		varchar(512) not null,
        TITLE   	varchar(512),
	COOKIES		varchar(512),
	NUM_LINKS       int,
	NUM_EMAILS      int,
	NUM_IMAGES      int,
        SERVER_ID	int,
	LAST_VISITED	int,
	RESPONSE_TIME	int,
        BASE_PAGE_SIZE	int
);

create unique index URLTBL_ID_IDX 		on URLTBL  ( ID );
create unique index URLTBL_URL_IDX 		on URLTBL  ( URL );
create        index URLTBL_TITLE_IDX 		on URLTBL  ( TITLE );
create        index URLTBL_COOKIES_IDX 		on URLTBL  ( COOKIES );
create        index URLTBL_NUM_LINKS_IDX 	on URLTBL  ( NUM_LINKS);
create        index URLTBL_NUM_EMAILS_IDX 	on URLTBL  ( NUM_EMAILS);
create        index URLTBL_NUM_IMAGES_IDX 	on URLTBL  ( NUM_IMAGES);
create        index URLTBL_SERVER_ID_IDX 	on URLTBL  ( SERVER_ID );
create        index URLTBL_LAST_VISITED_IDX 	on URLTBL  ( LAST_VISITED );
create        index URLTBL_RESPONSE_TIME_IDX 	on URLTBL  ( RESPONSE_TIME );
create        index URLTBL_BASE_PAGE_SIZE_IDX 	on URLTBL  ( BASE_PAGE_SIZE );

create table EMAILTBL (
	ID		int not null,
	ADDRESS		varchar(512) not null,
	VERIFIED_AT	int not null
);

create unique index EMAILTBL_ID_IDX		on EMAILTBL ( ID ); 
create unique index EMAILTBL_ADDRESS_IDX	on EMAILTBL ( ADDRESS ); 
create        index EMAILTBL_VERIFIED_AT_IDX	on EMAILTBL ( VERIFIED_AT ); 

create table SERVERTBL (
	ID		 int not null,
	SERVER_TYPE	 varchar(512) not null,
	LAST_ENCOUNTERED int not null
);

create unique index SERVERTBL_ID_IDX		    on SERVERTBL ( ID );
create	      index SERVERTBL_SERVER_TYPE_IDX	    on SERVERTBL ( SERVER_TYPE );
create	      index SERVERTBL_LAST_ENCOUNTERED_IDX  on SERVERTBL ( LAST_ENCOUNTERED );


create table URLRELTBL ( 
	URL_A_ID	int not null,
	URL_B_ID	int not null,
        VERIFIED_AT	int not null
);

create        index URLRELTBL_URL_A_ID_IDX    on URLRELTBL ( URL_A_ID );
create        index URLRELTBL_URL_B_ID_IDX    on URLRELTBL ( URL_B_ID );
create	      index URLRELTBL_VERIFIED_AT_IDX on URLRELTBL ( VERIFIED_AT );

create table EMAILRELTBL (
	URL_ID		int not null,
	EMAIL_ID	int not null,
	VERIFIED_AT	int not null
);

create        index EMAILRELTBL_URL_ID_IDX	   on EMAILRELTBL ( URL_ID );
create        index EMAILRELTBL_EMAIL_ID_IDX	   on EMAILRELTBL ( EMAIL_ID );
create        index EMAILRELTBL_VERIFIED_AT_ID_IDX on EMAILRELTBL ( VERIFIED_AT );
