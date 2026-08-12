import 'task.dart';

/// Maximum lengths accepted by the backend's `CreateTaskDto`.
const _maxTitleLength = 200;
const _maxDescriptionLength = 2000;

/// Payload for creating a task via the NestJS `POST /tasks` endpoint.
///
/// Kept separate from [Task] because the request shape (what the client may
/// send) and the response shape (what the server returns, including
/// server-assigned fields like `id`) are different contracts.
class CreateTaskInput {
  const CreateTaskInput({required this.title, this.description, this.priority});

  final String title;
  final String? description;
  final TaskPriority? priority;

  /// Returns a user-facing error for [title], or `null` if it's valid.
  static String? validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Title is required';
    if (trimmed.length > _maxTitleLength) {
      return 'Title must be $_maxTitleLength characters or fewer';
    }
    return null;
  }

  /// Returns a user-facing error for [description], or `null` if it's valid.
  static String? validateDescription(String description) {
    if (description.length > _maxDescriptionLength) {
      return 'Description must be $_maxDescriptionLength characters or fewer';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      if (priority != null) 'priority': priority!.name,
    };
  }
}
