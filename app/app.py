"""EventHub Flask app. AWS behavior is preserved; templates provide the UI."""

import json
from functools import wraps

import boto3
import pymysql
from flask import Flask, flash, jsonify, make_response, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

REGION = "ap-south-1"
SSM_PREFIX = "/eventhub"
SEATS_TABLE = "EventSeats"
REGISTRATIONS_TABLE = "Registrations"

app = Flask(__name__)
ssm = boto3.client("ssm", region_name=REGION)
sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
ddb = boto3.resource("dynamodb", region_name=REGION)
_param_cache = {}


def param(name: str, decrypt: bool = False) -> str:
    """Read and cache a Systems Manager Parameter Store value."""
    key = (name, decrypt)
    if key not in _param_cache:
        response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/{name}", WithDecryption=decrypt
        )
        _param_cache[key] = response["Parameter"]["Value"]
    return _param_cache[key]


app.secret_key = param("flask-secret", decrypt=True)


def db():
    """Open a MySQL connection to the private RDS instance."""
    return pymysql.connect(
        host=param("db-host"),
        user=param("db-user"),
        password=param("db-password", decrypt=True),
        database=param("db-name"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )


def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return redirect(url_for("login"))
        return fn(*args, **kwargs)
    return wrapper


def ensure_notification_subscription(email: str) -> bool:
    """Subscribe the student's address with an email filter so they receive
    only their own notifications. Best effort: never blocks account creation.

    SNS delivers only to confirmed subscribers, so a new student receives a
    one-time AWS confirmation email; after confirming, status updates reach
    them. The workflow publishes an `email` message attribute that the
    filter policy matches against.
    """
    try:
        sns.subscribe(
            TopicArn=param("sns-topic-arn"),
            Protocol="email",
            Endpoint=email,
            Attributes={"FilterPolicy": json.dumps({"email": [email]})},
        )
        app.logger.info("notification subscription requested for %s", email)
        return True
    except Exception:
        app.logger.warning(
            "notification subscription failed for %s", email, exc_info=True
        )
        return False


@app.route("/")
def home():
    if session.get("user_id"):
        return redirect(url_for("events"))
    return render_template("landing.html", page_title="Find your next campus moment")


@app.route("/signup", methods=["GET", "POST"])
def signup():
    if request.method == "POST":
        name = request.form["name"].strip()
        email = request.form["email"].strip().lower()
        password = request.form["password"]
        if len(password) < 8:
            flash("Your password must contain at least 8 characters.", "error")
        else:
            try:
                with db() as conn, conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)",
                        (name, email, generate_password_hash(password)),
                    )
                flash("Your account is ready. Sign in to explore upcoming events.", "success")
                if request.form.get("email_updates") == "on":
                    if ensure_notification_subscription(email):
                        flash("Check your inbox for an AWS subscription confirmation. Confirm it to receive ticket emails.", "info")
                    else:
                        flash("Email updates could not be set up yet. You can request them from My tickets after signing in.", "info")
                return redirect(url_for("login"))
            except pymysql.err.IntegrityError:
                flash("That email is already registered. Try signing in instead.", "error")
    return render_template("auth.html", page_title="Create your account", mode="signup")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        with db() as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM users WHERE email = %s",
                (request.form["email"].strip().lower(),),
            )
            user = cur.fetchone()
        if user and check_password_hash(user["password_hash"], request.form["password"]):
            session.clear()
            session.update(
                user_id=user["id"], user_name=user["name"], user_email=user["email"]
            )
            return redirect(url_for("events"))
        flash("Those details did not match an account. Please try again.", "error")
    return render_template("auth.html", page_title="Welcome back", mode="login")


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been signed out.", "info")
    return redirect(url_for("home"))


@app.route("/events")
@login_required
def events():
    with db() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT e.id, e.title, e.description, e.event_date, e.venue,
                      c.name AS club
               FROM events e JOIN clubs c ON c.id = e.club_id
               ORDER BY e.event_date"""
        )
        rows = cur.fetchall()
    seats_table = ddb.Table(SEATS_TABLE)
    for event in rows:
        item = seats_table.get_item(
            Key={"eventId": str(event["id"])}, ConsistentRead=True
        ).get("Item")
        event["seats"] = int(item["seatsAvailable"]) if item else None
    pending_event_id = request.args.get("pending", type=int)
    if pending_event_id not in {event["id"] for event in rows}:
        pending_event_id = None
    response = make_response(render_template(
        "events.html", page_title="Explore events", events=rows,
        clubs=sorted({event["club"] for event in rows}),
        user_name=session.get("user_name"), pending_event_id=pending_event_id,
    ))
    response.headers["Cache-Control"] = "no-store"
    return response


@app.route("/events/<int:event_id>/register", methods=["POST"])
@login_required
def register(event_id):
    """Queue an intent; Step Functions performs the atomic reservation."""
    with db() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, title, event_date, venue FROM events WHERE id = %s", (event_id,))
        event = cur.fetchone()
        if event is None:
            flash("That event is no longer available.", "error")
            return redirect(url_for("events"))

    existing = ddb.Table(REGISTRATIONS_TABLE).get_item(
        Key={"eventId": str(event_id), "userId": str(session["user_id"])},
        ConsistentRead=True,
    ).get("Item")
    if existing:
        flash("You have already requested a ticket for this event. Check Your tickets for its status.", "info")
        return redirect(url_for("my_registrations"))

    body = {
        "eventId": str(event_id),
        "userId": str(session["user_id"]),
        "email": session["user_email"],
        "eventTitle": event["title"],
        "eventDate": event["event_date"].strftime("%d %b %Y, %I:%M %p"),
        "eventVenue": event["venue"] or "VIT Vellore",
    }
    sqs.send_message(QueueUrl=param("queue-url"), MessageBody=json.dumps(body))
    flash(
        "Request received. Check My tickets for your result; confirmed email subscribers also receive an update.",
        "success",
    )
    return redirect(url_for("events", pending=event_id))


@app.route("/api/events/<int:event_id>/registration-status")
@login_required
def registration_status(event_id):
    """Return this student's workflow result and a fresh seat count."""
    registration = ddb.Table(REGISTRATIONS_TABLE).get_item(
        Key={"eventId": str(event_id), "userId": str(session["user_id"])},
        ConsistentRead=True,
    ).get("Item")
    seat_item = ddb.Table(SEATS_TABLE).get_item(
        Key={"eventId": str(event_id)}, ConsistentRead=True,
    ).get("Item")
    response = jsonify({
        "status": registration.get("status", "PENDING") if registration else "PENDING",
        "seats": int(seat_item["seatsAvailable"]) if seat_item else None,
    })
    response.headers["Cache-Control"] = "no-store"
    return response


@app.route("/notifications/subscribe", methods=["POST"])
@login_required
def subscribe_notifications():
    if ensure_notification_subscription(session["user_email"]):
        flash("Check your inbox for the AWS subscription confirmation if you have not already confirmed it.", "info")
    else:
        flash("Email updates are temporarily unavailable. Your tickets still appear here.", "error")
    return redirect(url_for("my_registrations"))


@app.route("/my")
@login_required
def my_registrations():
    """Read this user's registrations from DynamoDB and resolve event titles."""
    items = ddb.Table(REGISTRATIONS_TABLE).scan(
        FilterExpression="userId = :u",
        ExpressionAttributeValues={":u": str(session["user_id"])},
        ConsistentRead=True,
    )["Items"]
    items.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    titles = {}
    event_ids = [int(item["eventId"]) for item in items]
    if event_ids:
        placeholders = ",".join(["%s"] * len(event_ids))
        with db() as conn, conn.cursor() as cur:
            cur.execute(
                f"SELECT id, title FROM events WHERE id IN ({placeholders})", event_ids
            )
            titles = {str(row["id"]): row["title"] for row in cur.fetchall()}
    for item in items:
        item["title"] = titles.get(item["eventId"], f"Event {item['eventId']}")
    return render_template(
        "registrations.html",
        page_title="Your tickets",
        registrations=items,
        confirmed_count=sum(item.get("status") == "CONFIRMED" for item in items),
        waitlisted_count=sum(item.get("status") == "WAITLISTED" for item in items),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
