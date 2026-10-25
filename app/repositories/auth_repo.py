from datetime import datetime
from typing import Optional
from mysql.connector.connection import MySQLConnection


def get_user_by_username(conn: MySQLConnection, username: str) -> Optional[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT user_id, username, password_hash, role, is_active FROM Users WHERE username = %s",
            (username,)
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def get_user_by_id(conn: MySQLConnection, user_id: int) -> Optional[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT user_id, username, role, is_active FROM Users WHERE user_id = %s",
            (user_id,)
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def store_refresh_token(
    conn: MySQLConnection,
    user_id: int,
    token_hash: str,
    expires_at: datetime
) -> int:
   
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO Refresh_Tokens (user_id, token_hash, expires_at, revoked)
            VALUES (%s, %s, %s, FALSE)
            """,
            (user_id, token_hash, expires_at)
        )
        return cursor.lastrowid
    finally:
        cursor.close()


def is_token_active_fn(conn: MySQLConnection, token_hash: str) -> bool:
    
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fn_is_token_active(%s)", (token_hash,))
        row = cursor.fetchone()
        return bool(row[0]) if row else False
    finally:
        cursor.close()


def get_active_session_count_fn(conn: MySQLConnection, user_id: int) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT COUNT(*) 
            FROM Refresh_Tokens 
            WHERE user_id = %s 
              AND revoked = FALSE 
              AND expires_at > NOW()
            """,
            (user_id,),
        )
        row = cursor.fetchone()
        return int(row[0]) if row else 0
    finally:
        cursor.close()


def rotate_refresh_token_sp(
    conn: MySQLConnection,
    old_token_hash: str,
    new_token_hash: str,
    new_expires_at: datetime
) -> Optional[dict]:
    
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(
            "sp_rotate_refresh_token",
            (old_token_hash, new_token_hash, new_expires_at)
        )
        user = None
        for result in cursor.stored_results():
            user = result.fetchone()
        return user
    finally:
        cursor.close()


def delete_refresh_token(conn: MySQLConnection, token_hash: str) -> int:
   
    cursor = conn.cursor()
    try:
        cursor.execute(
            "DELETE FROM Refresh_Tokens WHERE token_hash = %s",
            (token_hash,)
        )
        return cursor.rowcount
    finally:
        cursor.close()


revoke_refresh_token = delete_refresh_token


def revoke_all_user_tokens_sp(conn: MySQLConnection, user_id: int) -> int:
    
    cursor = conn.cursor()
    try:
        results = cursor.callproc("sp_revoke_all_user_sessions", (user_id, 0))
        return results[1]
    finally:
        cursor.close()


def get_user_by_email(conn: MySQLConnection, email: str) -> Optional[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT user_id, username, email, password_hash, role, is_active FROM Users WHERE LOWER(email) = LOWER(%s)",
            (email,)
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def create_password_reset_otp(
    conn: MySQLConnection,
    user_id: int,
    email: str,
    otp_code: str,
    expires_at: datetime
) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Password_Reset_OTPs SET is_used = TRUE WHERE user_id = %s AND is_used = FALSE",
            (user_id,)
        )
        cursor.execute(
            """
            INSERT INTO Password_Reset_OTPs (user_id, email, otp_code, expires_at, is_used)
            VALUES (%s, %s, %s, %s, FALSE)
            """,
            (user_id, email, otp_code, expires_at)
        )
        return cursor.lastrowid
    finally:
        cursor.close()


def get_latest_valid_otp(conn: MySQLConnection, email: str) -> Optional[dict]:
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            """
            SELECT otp_id, user_id, email, otp_code, expires_at, is_used, created_at
            FROM Password_Reset_OTPs
            WHERE LOWER(email) = LOWER(%s) AND is_used = FALSE
            ORDER BY otp_id DESC
            LIMIT 1
            """,
            (email,)
        )
        return cursor.fetchone()
    finally:
        cursor.close()


def mark_otp_as_used(conn: MySQLConnection, otp_id: int) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Password_Reset_OTPs SET is_used = TRUE WHERE otp_id = %s",
            (otp_id,)
        )
        return cursor.rowcount
    finally:
        cursor.close()


def update_user_password(conn: MySQLConnection, user_id: int, new_password_hash: str) -> int:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE Users SET password_hash = %s WHERE user_id = %s",
            (new_password_hash, user_id)
        )
        return cursor.rowcount
    finally:
        cursor.close()
