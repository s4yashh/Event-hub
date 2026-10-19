"""Local route checks without AWS credentials or a live database."""

import importlib.util
import sys
import types
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch
from jinja2 import FileSystemLoader


class BookingStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registrations = Mock()
        cls.seats = Mock()
        tables = {"Registrations": cls.registrations, "EventSeats": cls.seats}
        fake_ssm = Mock()
        fake_ssm.get_parameter.return_value = {"Parameter": {"Value": "test-secret"}}
        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = lambda service, **_: fake_ssm if service == "ssm" else Mock()
        fake_boto3.resource = lambda service, **_: types.SimpleNamespace(Table=lambda name: tables[name])
        fake_pymysql = types.ModuleType("pymysql")
        fake_pymysql.cursors = types.SimpleNamespace(DictCursor=object)
        fake_pymysql.err = types.SimpleNamespace(IntegrityError=Exception)
        app_path = Path(__file__).resolve().parents[1] / "app" / "app.py"
        spec = importlib.util.spec_from_file_location("eventhub_app_for_test", app_path)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"boto3": fake_boto3, "pymysql": fake_pymysql}):
            spec.loader.exec_module(module)
        cls.module = module
        cls.app = module.app
        cls.app.jinja_loader = FileSystemLoader(str(app_path.parent / "templates"))
        cls.app.testing = True

    def setUp(self):
        self.registrations.reset_mock()
        self.seats.reset_mock()
        self.seats.get_item.return_value = {"Item": {"seatsAvailable": 49}}
        self.client = self.app.test_client()
        with self.client.session_transaction() as session:
            session["user_id"] = 7

    def test_confirmed_result_and_fresh_seats(self):
        self.registrations.get_item.return_value = {"Item": {"status": "CONFIRMED"}}
        response = self.client.get("/api/events/2/registration-status")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {"status": "CONFIRMED", "seats": 49})
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.registrations.get_item.assert_called_once_with(
            Key={"eventId": "2", "userId": "7"}, ConsistentRead=True
        )
        self.seats.get_item.assert_called_once_with(
            Key={"eventId": "2"}, ConsistentRead=True
        )

    def test_pending_and_waitlist_do_not_invent_a_seat_change(self):
        self.seats.get_item.return_value = {"Item": {"seatsAvailable": 0}}
        self.registrations.get_item.return_value = {}
        pending = self.client.get("/api/events/3/registration-status")
        self.assertEqual(pending.json, {"status": "PENDING", "seats": 0})
        self.registrations.get_item.return_value = {"Item": {"status": "WAITLISTED"}}
        waitlisted = self.client.get("/api/events/3/registration-status")
        self.assertEqual(waitlisted.json, {"status": "WAITLISTED", "seats": 0})

    def test_status_requires_login(self):
        self.client.get("/logout")
        response = self.client.get("/api/events/2/registration-status")
        self.assertEqual(response.status_code, 302)
        self.assertTrue(response.headers["Location"].endswith("/login"))

    def test_events_page_shows_pending_state_and_current_count(self):
        connection = MagicMock()
        connection.__enter__.return_value = connection
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [{
            "id": 2, "title": "Acoustic Night", "description": "Live music",
            "event_date": datetime(2026, 11, 28, 18, 30),
            "venue": "Anna Auditorium", "club": "Music Club",
        }]
        with patch.object(self.module, "db", return_value=connection):
            response = self.client.get("/events?pending=2")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["Cache-Control"], "no-store")
        self.assertIn(b"49 seats left", response.data)
        self.assertIn(b"Processing request", response.data)
        self.assertIn(b"/api/events/2/registration-status", response.data)


if __name__ == "__main__":
    unittest.main()
