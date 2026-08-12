/// A task's completion state, matching the backend's `TASK_STATUSES`.
enum TaskStatus { open, completed }

/// A task's priority, matching the backend's `TASK_PRIORITIES`.
enum TaskPriority { low, normal, high }

/// A task belonging to the authenticated user, as returned by the NestJS
/// `GET /tasks` endpoint.
class Task {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.projectId,
    required this.goalId,
    required this.dueDate,
    required this.dueTime,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final String? projectId;
  final String? goalId;

  /// Date-only string (`YYYY-MM-DD`), kept as-is since it has no time
  /// component to parse into a [DateTime].
  final String? dueDate;

  /// Time-only string (`HH:mm` or `HH:mm:ss`), kept as-is for the same
  /// reason as [dueDate].
  final String? dueTime;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: TaskStatus.values.byName(json['status'] as String),
      priority: TaskPriority.values.byName(json['priority'] as String),
      projectId: json['projectId'] as String?,
      goalId: json['goalId'] as String?,
      dueDate: json['dueDate'] as String?,
      dueTime: json['dueTime'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );
  }
}
