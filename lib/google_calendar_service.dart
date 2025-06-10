import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;

class TodoEvent {
  final String title;
  final String eventId;
  final DateTime startTime;
  final DateTime endTime;
  final String description;
  final String status;
  final String type;

  TodoEvent({
    required this.title,
    required this.eventId,
    required this.startTime,
    required this.endTime,
    this.description = '',
    this.status = 'New task', // Default status
    this.type = 'Operational', // Default type
  });
}

class GoogleCalendarService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/calendar.events',
      'email',
      'profile',
    ],
    clientId: kIsWeb
        ? '154439154322-vtsk4l33esae700qqjgtcpi24h8qdtj1.apps.googleusercontent.com'
        : null,
    hostedDomain: null, // Set to null to allow any domain
    forceCodeForRefreshToken: true, // This forces refresh token to be returned
  );

  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      debugPrint('Error checking sign in status: $e');
      return false;
    }
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      debugPrint('Attempting to sign in...');
      if (kIsWeb) {
        // For web platform
        try {
          final account = await _googleSignIn.signIn();
          if (account != null) {
            debugPrint('Sign in successful: ${account.email}');
            final auth = await account.authentication;
            debugPrint('Got authentication token');
            debugPrint('Access token: ${auth.accessToken}');
            return account;
          }
          debugPrint('Sign in failed - account is null');
          return null;
        } catch (e) {
          debugPrint('Web sign in error: $e');
          return null;
        }
      } else {
        // For mobile platforms
        return await _googleSignIn.signIn();
      }
    } catch (e) {
      debugPrint('Error during sign in: $e');
      return null;
    }
  }

  Future<calendar.CalendarApi?> _getCalendarApi() async {
    try {
      if (!await isSignedIn()) {
        final account = await signIn();
        if (account == null) return null;
      }

      final currentUser = _googleSignIn.currentUser;
      if (currentUser == null) return null;

      final auth = await currentUser.authentication;
      final headers = {
        'Authorization': 'Bearer ${auth.accessToken}',
        'Accept': 'application/json',
      };

      return calendar.CalendarApi(GoogleAuthClient(headers));
    } catch (e) {
      debugPrint('Error getting Calendar API: $e');
      return null;
    }
  }

  Future<TodoEvent?> addEvent(String title, String description,
      DateTime startTime, DateTime endTime, String status, String type) async {
    if (title.isEmpty) return null;

    try {
      final api = await _getCalendarApi();
      if (api == null) return null;

      final event = calendar.Event()
        ..summary = title
        ..description = description
        ..start = calendar.EventDateTime(
          dateTime: startTime,
          timeZone: 'Asia/Jakarta',
        )
        ..end = calendar.EventDateTime(
          dateTime: endTime,
          timeZone: 'Asia/Jakarta',
        )
        ..reminders = calendar.EventReminders(
          useDefault: false,
          overrides: [
            calendar.EventReminder(
              method: 'email',
              minutes: 4320, // 3 days = 3 * 24 * 60 = 4320 minutes
            ),
            calendar.EventReminder(
              method: 'popup',
              minutes: 4320,
            ),
          ],
        )
        ..extendedProperties = calendar.EventExtendedProperties(
          private: {
            'status': status,
            'type': type,
          },
        );

      final result = await api.events.insert(event, 'primary');
      debugPrint('Event created with ID: ${result.id}');
      return TodoEvent(
        title: title,
        eventId: result.id ?? '',
        startTime: startTime,
        endTime: endTime,
        description: description,
        status: status,
        type: type,
      );
    } catch (e) {
      debugPrint('Error adding event: $e');
      return null;
    }
  }

  Future<bool> updateEvent(
      String eventId,
      String newTitle,
      String newDescription,
      DateTime newStartTime,
      DateTime newEndTime,
      String newStatus,
      String newType) async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return false;

      // Get existing event
      final existingEvent = await api.events.get('primary', eventId);

      // Update event title, description, time, status, and type
      existingEvent.summary = newTitle;
      existingEvent.description = newDescription;
      existingEvent.start = calendar.EventDateTime(
        dateTime: newStartTime,
        timeZone: 'Asia/Jakarta',
      );
      existingEvent.end = calendar.EventDateTime(
        dateTime: newEndTime,
        timeZone: 'Asia/Jakarta',
      );
      existingEvent.reminders = calendar.EventReminders(
        useDefault: false,
        overrides: [
          calendar.EventReminder(
            method: 'email',
            minutes: 4320, // 3 days
          ),
          calendar.EventReminder(
            method: 'popup',
            minutes: 4320,
          ),
        ],
      );
      existingEvent.extendedProperties = calendar.EventExtendedProperties(
        private: {
          'status': newStatus,
          'type': newType,
        },
      );

      // Update event in calendar
      await api.events.update(existingEvent, 'primary', eventId);
      debugPrint('Event updated successfully: $eventId');
      return true;
    } catch (e) {
      debugPrint('Error updating event: $e');
      return false;
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    if (eventId.isEmpty) {
      debugPrint('Event ID tidak boleh kosong');
      return false;
    }

    try {
      final api = await _getCalendarApi();
      if (api == null) {
        debugPrint('Tidak dapat mengakses Google Calendar API');
        return false;
      }

      // Verifikasi event masih ada sebelum dihapus
      try {
        await api.events.get('primary', eventId);
      } catch (e) {
        debugPrint('Event tidak ditemukan: $e');
        return true; // Anggap berhasil jika event memang sudah tidak ada
      }

      await api.events.delete('primary', eventId);
      debugPrint('Event berhasil dihapus: $eventId');
      return true;
    } catch (e) {
      if (e.toString().contains('404')) {
        debugPrint('Event sudah tidak ada: $eventId');
        return true; // Anggap berhasil jika event memang sudah tidak ada
      }
      debugPrint('Error menghapus event: $e');
      return false;
    }
  }

  Future<List<TodoEvent>?> getEvents() async {
    try {
      final api = await _getCalendarApi();
      if (api == null) return null;

      final events = await api.events.list(
        'primary',
        timeMin: DateTime.now().subtract(const Duration(days: 30)).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (events.items == null) return [];

      return events.items!.map((event) {
        final status =
            event.extendedProperties?.private?['status'] ?? 'New task';
        final type =
            event.extendedProperties?.private?['type'] ?? 'Operational';

        return TodoEvent(
          title: event.summary ?? '',
          eventId: event.id ?? '',
          startTime: event.start?.dateTime?.toLocal() ?? DateTime.now(),
          endTime: event.end?.dateTime?.toLocal() ??
              DateTime.now().add(const Duration(hours: 1)),
          description: event.description ?? '',
          status: status,
          type: type,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error getting events: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      debugPrint('Signed out successfully');
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
  }
}
