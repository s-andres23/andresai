import 'task.dart';

/// Payload for updating a task via the NestJS `PATCH /tasks/:id` endpoint.
///
/// The edit UI always submits the full current state of title, description,
/// and priority, so unlike [CreateTaskInput] this always sends `description`
/// (even when `null`) — clearing an existing description must reach the
/// backend as an explicit clear rather than being silently dropped.
class UpdateTaskInput {
  const UpdateTaskInput({
    required this.title,
    this.description,
    required this.priority,
  });

  final String title;
  final String? description;
  final TaskPriority priority;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'priority': priority.name,
    };
  }
}
