import logging
import os
import smtplib
from pathlib import Path
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_TLS = os.getenv("SMTP_TLS", "True").lower() in ("true", "1", "yes")
EMAILS_FROM_EMAIL = os.getenv("EMAILS_FROM_EMAIL", "noreply@medicore-hms.com")
EMAILS_FROM_NAME = os.getenv("EMAILS_FROM_NAME", "MediCore HMS")

TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"


def send_email(to_email: str, subject: str, template_name: str, context: dict) -> bool:
    """Read HTML template, replace placeholders, and send email."""
    load_dotenv(override=True)
    smtp_host = os.getenv("SMTP_HOST", "")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_user = os.getenv("SMTP_USER", "")
    smtp_password = os.getenv("SMTP_PASSWORD", "").replace(" ", "")
    smtp_tls = os.getenv("SMTP_TLS", "True").lower() in ("true", "1", "yes")
    emails_from_email = os.getenv("EMAILS_FROM_EMAIL", smtp_user or "noreply@medicore-hms.com")
    emails_from_name = os.getenv("EMAILS_FROM_NAME", "MediCore HMS")

    if not smtp_host:
        logger.warning(
            "SMTP not configured in .env. Skipping email to %s (User: %s, Pass: %s)",
            to_email, context.get("username"), context.get("raw_password")
        )
        return False

    try:
        with open(TEMPLATES_DIR / template_name, "r", encoding="utf-8") as f:
            html = f.read()

        for key, val in context.items():
            html = html.replace(f"{{{{{key}}}}}", str(val))

        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"{emails_from_name} <{emails_from_email}>"
        msg["To"] = to_email
        msg.attach(MIMEText(html, "html"))

        server_cls = smtplib.SMTP_SSL if smtp_port == 465 else smtplib.SMTP
        with server_cls(smtp_host, smtp_port, timeout=10) as server:
            if smtp_tls and smtp_port != 465:
                server.starttls()
            if smtp_user and smtp_password:
                server.login(smtp_user, smtp_password)
            server.send_message(msg)

        logger.info("Email sent to %s", to_email)
        return True
    except Exception as exc:
        logger.error("Failed to send email to %s: %s", to_email, exc)
        return False


def send_staff_welcome_email(to_email: str, first_name: str, last_name: str, username: str, raw_password: str, role: str) -> bool:
    return send_email(
        to_email,
        "Welcome to MediCore HMS - Staff Account",
        "staff_welcome_email.html",
        {"first_name": first_name, "last_name": last_name, "username": username, "raw_password": raw_password, "role": role.capitalize()}
    )


def send_patient_welcome_email(to_email: str, first_name: str, last_name: str, username: str, raw_password: str) -> bool:
    return send_email(
        to_email,
        "Welcome to MediCore HMS - Patient Portal",
        "patient_welcome_email.html",
        {"first_name": first_name, "last_name": last_name, "username": username, "raw_password": raw_password}
    )


def send_password_reset_otp_email(to_email: str, username: str, otp_code: str, expire_minutes: int = 10) -> bool:
    return send_email(
        to_email,
        "MediCore HMS - Password Reset Verification Code",
        "password_reset_otp.html",
        {
            "username": username,
            "otp_code": otp_code,
            "expire_minutes": expire_minutes,
        }
    )
