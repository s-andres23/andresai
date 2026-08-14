import { ReminderSyncService } from './reminder-sync.service';
import { RemindersRepository } from './reminders.repository';
import { Reminder } from './interfaces/reminder.interface';

describe('ReminderSyncService', () => {
  let service: ReminderSyncService;
  let repository: jest.Mocked<RemindersRepository>;

  const userId = 'user-1';
  const calendarEventId = 'event-1';

  function buildReminder(overrides: Partial<Reminder> = {}): Reminder {
    return {
      id: 'reminder-1',
      userId,
      taskId: null,
      calendarEventId,
      title: 'Join the call',
      triggerType: 'relative',
      offsetMinutes: -15,
      remindAt: '2026-08-20T08:45:00.000Z',
      status: 'pending',
      createdAt: '2026-08-14T00:00:00.000Z',
      updatedAt: '2026-08-14T00:00:00.000Z',
      ...overrides,
    };
  }

  beforeEach(() => {
    repository = {
      findPendingRelativeByCalendarEvent: jest.fn(),
      updateRemindAt: jest.fn(),
    } as unknown as jest.Mocked<RemindersRepository>;

    service = new ReminderSyncService(repository);
  });

  it('recalculates a single pending relative reminder from the new startAt', async () => {
    const reminder = buildReminder({ offsetMinutes: -15 });
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([reminder]);
    repository.updateRemindAt.mockResolvedValue(reminder);

    await service.syncCalendarEventReminders(
      userId,
      calendarEventId,
      '2026-08-21T09:00:00.000Z',
    );

    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      userId,
      reminder.id,
      '2026-08-21T08:45:00.000Z', // new startAt (09:00) - 15 minutes
    );
  });

  it('recalculates multiple linked reminders, each with its own offset', async () => {
    const fifteenBefore = buildReminder({
      id: 'reminder-15-before',
      offsetMinutes: -15,
    });
    const oneHourBefore = buildReminder({
      id: 'reminder-60-before',
      offsetMinutes: -60,
    });
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([
      fifteenBefore,
      oneHourBefore,
    ]);
    repository.updateRemindAt.mockResolvedValue(fifteenBefore);

    await service.syncCalendarEventReminders(
      userId,
      calendarEventId,
      '2026-08-21T09:00:00.000Z',
    );

    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      userId,
      fifteenBefore.id,
      '2026-08-21T08:45:00.000Z',
    );
    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      userId,
      oneHourBefore.id,
      '2026-08-21T08:00:00.000Z',
    );
    expect(repository.updateRemindAt).toHaveBeenCalledTimes(2);
  });

  it('handles a positive offset (reminder after the event start) correctly', async () => {
    const reminder = buildReminder({ offsetMinutes: 10 });
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([reminder]);
    repository.updateRemindAt.mockResolvedValue(reminder);

    await service.syncCalendarEventReminders(
      userId,
      calendarEventId,
      '2026-08-21T09:00:00.000Z',
    );

    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      userId,
      reminder.id,
      '2026-08-21T09:10:00.000Z',
    );
  });

  it('relies on the repository query to exclude absolute/triggered/cancelled reminders', async () => {
    // The repository is trusted to have already filtered by
    // trigger_type='relative' and status='pending' (verified at the
    // repository layer); the service just processes whatever it returns.
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([]);

    await service.syncCalendarEventReminders(
      userId,
      calendarEventId,
      '2026-08-21T09:00:00.000Z',
    );

    expect(repository.findPendingRelativeByCalendarEvent).toHaveBeenCalledWith(
      userId,
      calendarEventId,
    );
    expect(repository.updateRemindAt).not.toHaveBeenCalled();
  });

  it('is a no-op when no reminders are linked to the event', async () => {
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([]);

    await expect(
      service.syncCalendarEventReminders(
        userId,
        calendarEventId,
        '2026-08-21T09:00:00.000Z',
      ),
    ).resolves.toBeUndefined();
    expect(repository.updateRemindAt).not.toHaveBeenCalled();
  });

  it('scopes both the lookup and the update to the given user', async () => {
    const reminder = buildReminder();
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([reminder]);
    repository.updateRemindAt.mockResolvedValue(reminder);

    await service.syncCalendarEventReminders(
      'user-2',
      calendarEventId,
      '2026-08-21T09:00:00.000Z',
    );

    expect(repository.findPendingRelativeByCalendarEvent).toHaveBeenCalledWith(
      'user-2',
      calendarEventId,
    );
    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      'user-2',
      reminder.id,
      expect.any(String) as unknown,
    );
  });

  it('skips (without crashing) a reminder with malformed offsetMinutes', async () => {
    const malformed = buildReminder({
      id: 'reminder-malformed',
      offsetMinutes: null,
    });
    const healthy = buildReminder({
      id: 'reminder-healthy',
      offsetMinutes: -5,
    });
    repository.findPendingRelativeByCalendarEvent.mockResolvedValue([
      malformed,
      healthy,
    ]);
    repository.updateRemindAt.mockResolvedValue(healthy);

    await expect(
      service.syncCalendarEventReminders(
        userId,
        calendarEventId,
        '2026-08-21T09:00:00.000Z',
      ),
    ).resolves.toBeUndefined();

    expect(repository.updateRemindAt).toHaveBeenCalledTimes(1);
    expect(repository.updateRemindAt).toHaveBeenCalledWith(
      userId,
      healthy.id,
      '2026-08-21T08:55:00.000Z',
    );
  });
});
