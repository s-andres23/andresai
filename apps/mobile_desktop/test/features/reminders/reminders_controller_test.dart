import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/reminders/create_reminder_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_controller.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';
import 'package:mobile_desktop/features/reminders/update_reminder_input.dart';

Reminder _reminder({
  String id = 'reminder-1',
  String title = 'Call insurance',
  DateTime? remindAt,
  ReminderStatus status = ReminderStatus.pending,
  ReminderTriggerType triggerType = ReminderTriggerType.absolute,
  int? offsetMinutes,
}) {
  return Reminder(
    id: id,
    userId: 'user-1',
    taskId: null,
    calendarEventId: null,
    title: title,
    triggerType: triggerType,
    offsetMinutes: offsetMinutes,
    remindAt: remindAt ?? DateTime.utc(2026, 8, 20, 9),
    status: status,
    createdAt: DateTime.utc(2026, 8, 13),
    updatedAt: DateTime.utc(2026, 8, 13),
  );
}

final _reminder1 = _reminder(id: 'reminder-1');

final _earlyReminder = _reminder(
  id: 'reminder-early',
  title: 'Early reminder',
  remindAt: DateTime.utc(2026, 8, 20, 8),
);

final _midReminder = _reminder(
  id: 'reminder-mid',
  title: 'Mid reminder',
  remindAt: DateTime.utc(2026, 8, 20, 9),
);

final _lateReminder = _reminder(
  id: 'reminder-late',
  title: 'Late reminder',
  remindAt: DateTime.utc(2026, 8, 20, 10),
);

class _FakeRemindersRepository extends RemindersRepository {
  _FakeRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;
}

class _ThrowingRemindersRepository extends RemindersRepository {
  _ThrowingRemindersRepository() : super(Dio());

  @override
  Future<List<Reminder>> fetchReminders() async {
    throw Exception('network error');
  }
}

/// A repository that fetches successfully, and whose `createReminder`
/// succeeds, returning [reminderToCreate] and recording every call.
class _CreatingRemindersRepository extends RemindersRepository {
  _CreatingRemindersRepository(this._reminders, this.reminderToCreate)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToCreate;
  int createCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async {
    createCallCount++;
    return reminderToCreate;
  }
}

class _FailingCreateRemindersRepository extends RemindersRepository {
  _FailingCreateRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async {
    throw Exception('create failed');
  }
}

/// A repository whose `createReminder` doesn't resolve until [complete] is
/// called, so a test can assert on behavior while a create is in flight.
class _DelayedCreateRemindersRepository extends RemindersRepository {
  _DelayedCreateRemindersRepository(this._reminders, this.reminderToCreate)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToCreate;
  final _completer = Completer<void>();
  int createCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async {
    createCallCount++;
    await _completer.future;
    return reminderToCreate;
  }

  void complete() => _completer.complete();
}

class _UpdatingRemindersRepository extends RemindersRepository {
  _UpdatingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;
  int updateCallCount = 0;
  String? lastReminderId;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> updateReminder(
    String reminderId,
    UpdateReminderInput input,
  ) async {
    updateCallCount++;
    lastReminderId = reminderId;
    return reminderToReturn;
  }
}

class _FailingUpdateRemindersRepository extends RemindersRepository {
  _FailingUpdateRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> updateReminder(
    String reminderId,
    UpdateReminderInput input,
  ) async {
    throw Exception('update failed');
  }
}

class _CancellingRemindersRepository extends RemindersRepository {
  _CancellingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;
  int cancelCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> cancelReminder(String reminderId) async {
    cancelCallCount++;
    return reminderToReturn;
  }
}

class _DeletingRemindersRepository extends RemindersRepository {
  _DeletingRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;
  int deleteCallCount = 0;
  String? lastReminderId;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<void> deleteReminder(String reminderId) async {
    deleteCallCount++;
    lastReminderId = reminderId;
  }
}

class _FailingDeleteRemindersRepository extends RemindersRepository {
  _FailingDeleteRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<void> deleteReminder(String reminderId) async {
    throw Exception('delete failed');
  }
}

/// A repository whose `updateReminder` doesn't resolve until
/// [completeUpdate] is called, and whose `cancelReminder` doesn't resolve
/// until [completeCancel] is called -- so a test can verify that different
/// mutation types for the same reminder are mutually exclusive while
/// mutations for *different* reminders proceed independently.
class _DelayedMixedMutationRemindersRepository extends RemindersRepository {
  _DelayedMixedMutationRemindersRepository(this._reminders, this._updateResult)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder _updateResult;
  final _updateCompleter = Completer<void>();
  final _cancelCompleter = Completer<void>();
  int updateCallCount = 0;
  int cancelCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> updateReminder(
    String reminderId,
    UpdateReminderInput input,
  ) async {
    updateCallCount++;
    await _updateCompleter.future;
    return _updateResult;
  }

  @override
  Future<Reminder> cancelReminder(String reminderId) async {
    cancelCallCount++;
    await _cancelCompleter.future;
    return _updateResult;
  }

  void completeUpdate() => _updateCompleter.complete();
  void completeCancel() => _cancelCompleter.complete();
}

/// A repository whose `deleteReminder` doesn't resolve until each call's
/// completer (keyed by reminder ID) is completed -- so a test can verify
/// that two different reminders delete independently and in parallel.
class _IndependentDeleteRemindersRepository extends RemindersRepository {
  _IndependentDeleteRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;
  final Map<String, Completer<void>> completers = {};
  final List<String> deleteCalls = [];

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<void> deleteReminder(String reminderId) async {
    deleteCalls.add(reminderId);
    final completer = completers.putIfAbsent(reminderId, () => Completer());
    await completer.future;
  }
}

void main() {
  test(
    'starts in loading state and resolves to the loaded reminders',
    () async {
      final container = ProviderContainer(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(
            _FakeRemindersRepository([_reminder1]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(remindersControllerProvider),
        isA<AsyncLoading<Object?>>(),
      );

      final reminders = await container.read(
        remindersControllerProvider.future,
      );

      expect(reminders, [_reminder1]);
      expect(container.read(remindersControllerProvider).value, [_reminder1]);
    },
  );

  test('exposes an error state when the repository throws', () async {
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _ThrowingRemindersRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // If automatic retry were still enabled, this would hang for several
    // seconds (Riverpod's default backoff) instead of failing immediately.
    await expectLater(
      container.read(remindersControllerProvider.future),
      throwsException,
    );
    expect(
      container.read(remindersControllerProvider),
      isA<AsyncError<Object?>>(),
    );
  });

  test('refresh() re-fetches reminders from the repository', () async {
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _FakeRemindersRepository([_reminder1]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container.read(remindersControllerProvider.notifier).refresh();

    expect(container.read(remindersControllerProvider).value, [_reminder1]);
  });

  test('createReminder inserts before an existing later reminder', () async {
    final repository = _CreatingRemindersRepository([
      _midReminder,
    ], _earlyReminder);
    final container = ProviderContainer(
      overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .createReminder(
          CreateReminderInput(
            title: _earlyReminder.title,
            triggerType: ReminderTriggerType.absolute,
            remindAt: _earlyReminder.remindAt,
          ),
        );

    expect(repository.createCallCount, 1);
    expect(container.read(remindersControllerProvider).value, [
      _earlyReminder,
      _midReminder,
    ]);
  });

  test('createReminder inserts between two existing reminders, keeping '
      'ascending remindAt order', () async {
    final repository = _CreatingRemindersRepository([
      _earlyReminder,
      _lateReminder,
    ], _midReminder);
    final container = ProviderContainer(
      overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .createReminder(
          CreateReminderInput(
            title: _midReminder.title,
            triggerType: ReminderTriggerType.absolute,
            remindAt: _midReminder.remindAt,
          ),
        );

    expect(container.read(remindersControllerProvider).value, [
      _earlyReminder,
      _midReminder,
      _lateReminder,
    ]);
  });

  test('createReminder surfaces errors to the caller without wiping the '
      'loaded list', () async {
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _FailingCreateRemindersRepository([_reminder1]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    await expectLater(
      container
          .read(remindersControllerProvider.notifier)
          .createReminder(
            CreateReminderInput(
              title: 'Bad reminder',
              triggerType: ReminderTriggerType.absolute,
              remindAt: DateTime.utc(2026, 8, 20),
            ),
          ),
      throwsException,
    );

    expect(
      container.read(remindersControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(remindersControllerProvider).value, [_reminder1]);
  });

  test(
    'createReminder ignores a second call while one is already in flight',
    () async {
      final repository = _DelayedCreateRemindersRepository([
        _midReminder,
      ], _earlyReminder);
      final container = ProviderContainer(
        overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);

      final notifier = container.read(remindersControllerProvider.notifier);
      final input = CreateReminderInput(
        title: _earlyReminder.title,
        triggerType: ReminderTriggerType.absolute,
        remindAt: _earlyReminder.remindAt,
      );
      final first = notifier.createReminder(input);
      final second = notifier.createReminder(input);

      repository.complete();
      await first;
      await second;

      expect(repository.createCallCount, 1);
      expect(container.read(remindersControllerProvider).value, [
        _earlyReminder,
        _midReminder,
      ]);
    },
  );

  test('updateReminder replaces the matching reminder in place when its '
      'remindAt is unchanged', () async {
    final updated = _reminder(
      id: _reminder1.id,
      title: 'Call insurance (renamed)',
      remindAt: _reminder1.remindAt,
    );
    final repository = _UpdatingRemindersRepository([
      _earlyReminder,
      _reminder1,
    ], updated);
    final container = ProviderContainer(
      overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .updateReminder(
          _reminder1.id,
          const UpdateReminderInput(title: 'Call insurance (renamed)'),
        );

    expect(repository.updateCallCount, 1);
    expect(repository.lastReminderId, _reminder1.id);
    expect(container.read(remindersControllerProvider).value, [
      _earlyReminder,
      updated,
    ]);
  });

  test('updateReminder re-sorts the list when the updated remindAt moves the '
      'reminder to a new position', () async {
    final moved = _reminder(
      id: _reminder1.id,
      title: _reminder1.title,
      remindAt: DateTime.utc(2026, 8, 20, 7), // now earlier than _earlyReminder
    );
    final repository = _UpdatingRemindersRepository([
      _earlyReminder,
      _reminder1,
    ], moved);
    final container = ProviderContainer(
      overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .updateReminder(
          _reminder1.id,
          UpdateReminderInput(title: moved.title, remindAt: moved.remindAt),
        );

    expect(container.read(remindersControllerProvider).value, [
      moved,
      _earlyReminder,
    ]);
  });

  test('updateReminder surfaces errors to the caller without wiping the '
      'loaded list', () async {
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _FailingUpdateRemindersRepository([_reminder1]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    await expectLater(
      container
          .read(remindersControllerProvider.notifier)
          .updateReminder(
            _reminder1.id,
            const UpdateReminderInput(title: 'Bad update'),
          ),
      throwsException,
    );

    expect(
      container.read(remindersControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(remindersControllerProvider).value, [_reminder1]);
  });

  test(
    'cancelReminder replaces the reminder locally without a refetch',
    () async {
      final cancelled = _reminder(
        id: _reminder1.id,
        title: _reminder1.title,
        remindAt: _reminder1.remindAt,
        status: ReminderStatus.cancelled,
      );
      final repository = _CancellingRemindersRepository([
        _reminder1,
      ], cancelled);
      final container = ProviderContainer(
        overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);
      await container
          .read(remindersControllerProvider.notifier)
          .cancelReminder(_reminder1.id);

      expect(repository.cancelCallCount, 1);
      expect(container.read(remindersControllerProvider).value, [cancelled]);
      expect(
        container.read(remindersControllerProvider).value!.single.status,
        ReminderStatus.cancelled,
      );
    },
  );

  test('deleteReminder removes the reminder from the loaded list', () async {
    final repository = _DeletingRemindersRepository([
      _earlyReminder,
      _reminder1,
    ]);
    final container = ProviderContainer(
      overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .deleteReminder(_reminder1.id);

    expect(repository.deleteCallCount, 1);
    expect(repository.lastReminderId, _reminder1.id);
    expect(container.read(remindersControllerProvider).value, [_earlyReminder]);
  });

  test('deleteReminder surfaces errors to the caller without wiping the '
      'loaded list', () async {
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _FailingDeleteRemindersRepository([_reminder1]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    await expectLater(
      container
          .read(remindersControllerProvider.notifier)
          .deleteReminder(_reminder1.id),
      throwsException,
    );

    expect(container.read(remindersControllerProvider).value, [_reminder1]);
  });

  test(
    'a pending update blocks a concurrent cancel for the same reminder',
    () async {
      final updated = _reminder(
        id: _reminder1.id,
        title: 'Call insurance (renamed)',
        remindAt: _reminder1.remindAt,
      );
      final repository = _DelayedMixedMutationRemindersRepository([
        _reminder1,
      ], updated);
      final container = ProviderContainer(
        overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);

      final notifier = container.read(remindersControllerProvider.notifier);
      // Started first, so it wins the guard: the concurrent cancel below
      // should be silently ignored rather than racing it.
      final updateFuture = notifier.updateReminder(
        _reminder1.id,
        UpdateReminderInput(title: updated.title),
      );
      final cancelFuture = notifier.cancelReminder(_reminder1.id);

      repository.completeUpdate();
      repository.completeCancel();
      await updateFuture;
      await cancelFuture;

      expect(repository.updateCallCount, 1);
      expect(repository.cancelCallCount, 0);
      expect(container.read(remindersControllerProvider).value, [updated]);
    },
  );

  test(
    'different reminders can mutate in parallel without blocking each other',
    () async {
      final repository = _IndependentDeleteRemindersRepository([
        _earlyReminder,
        _reminder1,
      ]);
      final container = ProviderContainer(
        overrides: [remindersRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);

      final notifier = container.read(remindersControllerProvider.notifier);
      final firstDelete = notifier.deleteReminder(_earlyReminder.id);
      final secondDelete = notifier.deleteReminder(_reminder1.id);

      // Both calls must have reached the repository even though neither has
      // resolved yet -- proving they run independently rather than one
      // blocking on the other.
      expect(
        repository.deleteCalls,
        unorderedEquals([_earlyReminder.id, _reminder1.id]),
      );

      repository.completers[_earlyReminder.id]!.complete();
      repository.completers[_reminder1.id]!.complete();
      await firstDelete;
      await secondDelete;

      expect(container.read(remindersControllerProvider).value, isEmpty);
    },
  );
}
