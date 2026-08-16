import {
  BadRequestException,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { RemindersService } from './reminders.service';
import { RemindersRepository } from './reminders.repository';
import { TasksService } from '../tasks/tasks.service';
import { CalendarService } from '../calendar/calendar.service';
import { Reminder } from './interfaces/reminder.interface';
import { Task } from '../tasks/interfaces/task.interface';
import { CalendarEvent } from '../calendar/interfaces/calendar-event.interface';

describe('RemindersService', () => {
  let service: RemindersService;
  let repository: jest.Mocked<RemindersRepository>;
  let tasksService: jest.Mocked<TasksService>;
  let calendarService: jest.Mocked<CalendarService>;

  const userId = 'user-1';

  const baseReminder: Reminder = {
    id: 'reminder-1',
    userId,
    taskId: null,
    calendarEventId: null,
    title: 'Stand up',
    triggerType: 'absolute',
    offsetMinutes: null,
    remindAt: '2099-01-01T09:00:00.000Z',
    status: 'pending',
    createdAt: '2026-08-14T00:00:00.000Z',
    updatedAt: '2026-08-14T00:00:00.000Z',
  };

  const baseTask: Task = {
    id: 'task-1',
    userId,
    title: 'Write report',
    description: null,
    status: 'open',
    priority: 'normal',
    dueDate: '2099-01-01',
    dueTime: '17:00',
    createdAt: '2026-08-10T00:00:00.000Z',
    updatedAt: '2026-08-10T00:00:00.000Z',
    completedAt: null,
  };

  const baseEvent: CalendarEvent = {
    id: 'event-1',
    userId,
    title: 'Team sync',
    description: null,
    startAt: '2099-01-01T09:00:00.000Z',
    endAt: '2099-01-01T09:30:00.000Z',
    allDay: false,
    location: null,
    createdAt: '2026-08-13T00:00:00.000Z',
    updatedAt: '2026-08-13T00:00:00.000Z',
  };

  beforeEach(() => {
    repository = {
      findAll: jest.fn(),
      findById: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      setStatus: jest.fn(),
      reactivate: jest.fn(),
    } as unknown as jest.Mocked<RemindersRepository>;

    tasksService = {
      findOne: jest.fn(),
    } as unknown as jest.Mocked<TasksService>;

    calendarService = {
      findOne: jest.fn(),
    } as unknown as jest.Mocked<CalendarService>;

    service = new RemindersService(repository, tasksService, calendarService);
  });

  it('creates an absolute standalone reminder', async () => {
    repository.create.mockResolvedValue(baseReminder);

    const result = await service.create(userId, {
      title: 'Stand up',
      triggerType: 'absolute',
      remindAt: '2099-01-01T09:00:00.000Z',
    });

    expect(repository.create).toHaveBeenCalledWith(userId, {
      title: 'Stand up',
      taskId: null,
      calendarEventId: null,
      triggerType: 'absolute',
      offsetMinutes: null,
      remindAt: '2099-01-01T09:00:00.000Z',
    });
    expect(tasksService.findOne).not.toHaveBeenCalled();
    expect(calendarService.findOne).not.toHaveBeenCalled();
    expect(result).toEqual(baseReminder);
  });

  it('calculates remindAt for a relative calendar reminder from startAt + offsetMinutes', async () => {
    calendarService.findOne.mockResolvedValue(baseEvent);
    repository.create.mockResolvedValue(baseReminder);

    await service.create(userId, {
      title: 'Join the call',
      calendarEventId: baseEvent.id,
      triggerType: 'relative',
      offsetMinutes: -15,
      remindAt: '1970-01-01T00:00:00.000Z', // must be ignored/overridden
    });

    expect(calendarService.findOne).toHaveBeenCalledWith(userId, baseEvent.id);
    expect(repository.create).toHaveBeenCalledWith(
      userId,
      expect.objectContaining({
        calendarEventId: baseEvent.id,
        remindAt: '2099-01-01T08:45:00.000Z', // startAt (09:00) - 15 minutes
      }),
    );
  });

  it('rejects a relative reminder with no linked task or calendar event', async () => {
    await expect(
      service.create(userId, {
        title: 'Standalone relative',
        triggerType: 'relative',
        offsetMinutes: 10,
        remindAt: '2099-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('rejects a reminder linked to both a task and a calendar event', async () => {
    await expect(
      service.create(userId, {
        title: 'Both',
        taskId: baseTask.id,
        calendarEventId: baseEvent.id,
        triggerType: 'relative',
        offsetMinutes: 10,
        remindAt: '2099-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(tasksService.findOne).not.toHaveBeenCalled();
    expect(calendarService.findOne).not.toHaveBeenCalled();
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('rejects an absolute reminder whose remindAt is in the past', async () => {
    await expect(
      service.create(userId, {
        title: 'Too late',
        triggerType: 'absolute',
        remindAt: '2020-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('rejects an absolute reminder that also sets offsetMinutes', async () => {
    await expect(
      service.create(userId, {
        title: 'Bad absolute',
        triggerType: 'absolute',
        offsetMinutes: 10,
        remindAt: '2099-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('rejects a relative task reminder when the task is missing dueDate or dueTime', async () => {
    tasksService.findOne.mockResolvedValue({ ...baseTask, dueTime: null });

    await expect(
      service.create(userId, {
        title: 'Task reminder',
        taskId: baseTask.id,
        triggerType: 'relative',
        offsetMinutes: -30,
        remindAt: '2099-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it(
    'reports (rather than silently guessing) when a relative task reminder ' +
      'would otherwise be calculable -- see the architecture note in ' +
      'ReminderService.calculateRemindAtFromTask',
    async () => {
      tasksService.findOne.mockResolvedValue(baseTask); // has dueDate + dueTime

      await expect(
        service.create(userId, {
          title: 'Task reminder',
          taskId: baseTask.id,
          triggerType: 'relative',
          offsetMinutes: -30,
          remindAt: '2099-01-01T09:00:00.000Z',
        }),
      ).rejects.toThrow(UnprocessableEntityException);
      expect(repository.create).not.toHaveBeenCalled();
    },
  );

  it('propagates NotFoundException when the linked task does not belong to the user', async () => {
    tasksService.findOne.mockRejectedValue(
      new NotFoundException('Task not found'),
    );

    await expect(
      service.create(userId, {
        title: 'Task reminder',
        taskId: 'someone-elses-task',
        triggerType: 'relative',
        offsetMinutes: -30,
        remindAt: '2099-01-01T09:00:00.000Z',
      }),
    ).rejects.toThrow(NotFoundException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('throws NotFoundException when a reminder does not belong to the user', async () => {
    repository.findById.mockResolvedValue(null);

    await expect(service.findOne(userId, 'missing')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('updates a pending reminder after confirming ownership', async () => {
    repository.findById.mockResolvedValue(baseReminder);
    repository.update.mockResolvedValue({
      ...baseReminder,
      title: 'Updated',
    });

    const result = await service.update(userId, baseReminder.id, {
      title: 'Updated',
    });

    expect(result.title).toBe('Updated');
    expect(repository.update).toHaveBeenCalledWith(
      userId,
      baseReminder.id,
      expect.objectContaining({ title: 'Updated' }),
    );
  });

  it('rejects editing a triggered reminder', async () => {
    repository.findById.mockResolvedValue({
      ...baseReminder,
      status: 'triggered',
    });

    await expect(
      service.update(userId, baseReminder.id, { title: 'Updated' }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('rejects editing a cancelled reminder', async () => {
    repository.findById.mockResolvedValue({
      ...baseReminder,
      status: 'cancelled',
    });

    await expect(
      service.update(userId, baseReminder.id, { title: 'Updated' }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('removes a reminder after confirming ownership, regardless of status', async () => {
    repository.findById.mockResolvedValue({
      ...baseReminder,
      status: 'triggered',
    });

    await service.remove(userId, baseReminder.id);

    expect(repository.delete).toHaveBeenCalledWith(userId, baseReminder.id);
  });

  it('cancels a pending reminder', async () => {
    repository.findById.mockResolvedValue(baseReminder);
    repository.setStatus.mockResolvedValue({
      ...baseReminder,
      status: 'cancelled',
    });

    const result = await service.cancel(userId, baseReminder.id);

    expect(repository.setStatus).toHaveBeenCalledWith(
      userId,
      baseReminder.id,
      'cancelled',
    );
    expect(result.status).toBe('cancelled');
  });

  it('is idempotent when cancelling an already-cancelled reminder', async () => {
    const cancelledReminder: Reminder = {
      ...baseReminder,
      status: 'cancelled',
    };
    repository.findById.mockResolvedValue(cancelledReminder);

    const result = await service.cancel(userId, baseReminder.id);

    expect(repository.setStatus).not.toHaveBeenCalled();
    expect(result).toEqual(cancelledReminder);
  });

  it('rejects cancelling a triggered reminder (must not revert to pending)', async () => {
    repository.findById.mockResolvedValue({
      ...baseReminder,
      status: 'triggered',
    });

    await expect(service.cancel(userId, baseReminder.id)).rejects.toThrow(
      BadRequestException,
    );
    expect(repository.setStatus).not.toHaveBeenCalled();
  });

  describe('reactivate', () => {
    it('reactivates a cancelled absolute reminder whose remindAt is still in the future', async () => {
      const cancelledReminder: Reminder = {
        ...baseReminder,
        status: 'cancelled',
      };
      repository.findById.mockResolvedValue(cancelledReminder);
      repository.reactivate.mockResolvedValue({
        ...cancelledReminder,
        status: 'pending',
      });

      const result = await service.reactivate(userId, cancelledReminder.id);

      expect(repository.reactivate).toHaveBeenCalledWith(
        userId,
        cancelledReminder.id,
        cancelledReminder.remindAt, // unchanged for an absolute reminder
      );
      expect(result.status).toBe('pending');
    });

    it('rejects reactivating a cancelled absolute reminder whose remindAt is in the past', async () => {
      const pastCancelledReminder: Reminder = {
        ...baseReminder,
        remindAt: '2020-01-01T09:00:00.000Z',
        status: 'cancelled',
      };
      repository.findById.mockResolvedValue(pastCancelledReminder);

      await expect(
        service.reactivate(userId, pastCancelledReminder.id),
      ).rejects.toThrow(BadRequestException);
      expect(repository.reactivate).not.toHaveBeenCalled();
    });

    it('recalculates remindAt from the CURRENT calendar event startAt for a cancelled relative Calendar reminder', async () => {
      const cancelledRelativeReminder: Reminder = {
        ...baseReminder,
        calendarEventId: baseEvent.id,
        triggerType: 'relative',
        offsetMinutes: -15,
        remindAt: '1970-01-01T00:00:00.000Z', // stale; must be ignored
        status: 'cancelled',
      };
      repository.findById.mockResolvedValue(cancelledRelativeReminder);
      calendarService.findOne.mockResolvedValue(baseEvent); // startAt 09:00
      repository.reactivate.mockResolvedValue({
        ...cancelledRelativeReminder,
        remindAt: '2099-01-01T08:45:00.000Z',
        status: 'pending',
      });

      const result = await service.reactivate(
        userId,
        cancelledRelativeReminder.id,
      );

      expect(calendarService.findOne).toHaveBeenCalledWith(
        userId,
        baseEvent.id,
      );
      expect(repository.reactivate).toHaveBeenCalledWith(
        userId,
        cancelledRelativeReminder.id,
        '2099-01-01T08:45:00.000Z', // current startAt (09:00) - 15 minutes
      );
      expect(result.status).toBe('pending');
    });

    it('rejects reactivating a cancelled relative Calendar reminder whose recalculated remindAt lands in the past', async () => {
      const cancelledRelativeReminder: Reminder = {
        ...baseReminder,
        calendarEventId: baseEvent.id,
        triggerType: 'relative',
        offsetMinutes: -15,
        status: 'cancelled',
      };
      repository.findById.mockResolvedValue(cancelledRelativeReminder);
      calendarService.findOne.mockResolvedValue({
        ...baseEvent,
        startAt: '2020-01-01T09:00:00.000Z', // event itself moved into the past
      });

      await expect(
        service.reactivate(userId, cancelledRelativeReminder.id),
      ).rejects.toThrow(BadRequestException);
      expect(repository.reactivate).not.toHaveBeenCalled();
    });

    it('remains unsupported for a cancelled relative Task reminder, same as create/update', async () => {
      const cancelledTaskReminder: Reminder = {
        ...baseReminder,
        taskId: baseTask.id,
        triggerType: 'relative',
        offsetMinutes: -30,
        status: 'cancelled',
      };
      repository.findById.mockResolvedValue(cancelledTaskReminder);
      tasksService.findOne.mockResolvedValue(baseTask); // has dueDate + dueTime

      await expect(
        service.reactivate(userId, cancelledTaskReminder.id),
      ).rejects.toThrow(UnprocessableEntityException);
      expect(repository.reactivate).not.toHaveBeenCalled();
    });

    it('rejects reactivating a triggered reminder (must never go back to pending)', async () => {
      repository.findById.mockResolvedValue({
        ...baseReminder,
        status: 'triggered',
      });

      await expect(service.reactivate(userId, baseReminder.id)).rejects.toThrow(
        BadRequestException,
      );
      expect(repository.reactivate).not.toHaveBeenCalled();
    });

    it('is idempotent when reactivating an already-pending reminder', async () => {
      repository.findById.mockResolvedValue(baseReminder); // status: pending

      const result = await service.reactivate(userId, baseReminder.id);

      expect(repository.reactivate).not.toHaveBeenCalled();
      expect(result).toEqual(baseReminder);
    });

    it('throws NotFoundException when reactivating a reminder that does not belong to the user', async () => {
      repository.findById.mockResolvedValue(null);

      await expect(service.reactivate(userId, 'missing')).rejects.toThrow(
        NotFoundException,
      );
      expect(repository.reactivate).not.toHaveBeenCalled();
    });
  });
});
