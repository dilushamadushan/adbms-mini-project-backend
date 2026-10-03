from mysql.connector.connection import MySQLConnection

class UserRepository:
    def __init__(self, db: MySQLConnection):
        self.db = db

    def get_by_username(self, username: str):
        cursor = self.db.cursor(dictionary=True)
        cursor.execute(
            "SELECT user_id FROM users WHERE username = %s", 
            (username,)
        )
        return cursor.fetchone()

    def get_user_for_login(self, username: str):
        cursor = self.db.cursor(dictionary=True)
        cursor.execute(
            "SELECT user_id, username, hashed_password FROM users WHERE username = %s", 
            (username,)
        )
        return cursor.fetchone()

    def get_by_all(self):
        cursor = self.db.cursor(dictionary=True)
        cursor.execute(
            "SELECT u.user_id, u.username, d.full_name, d.last_name, d.age "
            "FROM users u JOIN userDetails d ON u.user_id = d.user_id"
        )
        return cursor.fetchall()

    def create(self, username: str, hashed_password: str, full_name: str, last_name: str, age: int):
        cursor = self.db.cursor(dictionary=True)
        
        # Insert into users
        cursor.execute(
            "INSERT INTO users (username, hashed_password) VALUES (%s, %s)",
            (username, hashed_password)
        )
        user_id = cursor.lastrowid
        
        # Insert into userDetails
        cursor.execute(
            "INSERT INTO userDetails (full_name, last_name, age, user_id) VALUES (%s, %s, %s, %s)",
            (full_name, last_name, age, user_id)
        )
        
        # Fetch combined user data
        query = """
            SELECT u.user_id, u.username, d.full_name, d.last_name, d.age 
            FROM users u
            JOIN userDetails d ON u.user_id = d.user_id
            WHERE u.user_id = %s
        """
        cursor.execute(query, (user_id,))
        return cursor.fetchone()
