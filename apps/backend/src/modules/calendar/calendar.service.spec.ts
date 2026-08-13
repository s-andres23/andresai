import { BadRequestException, NotFoundException } from '@nestjs/common';
import { CalendarService } from './calendar.service';
import { CalendarRepository } from './calendar.repository';
import { CalendarEvent } from './interfaces/calendar-event.interface';

describe('CalendarService', () => {
  let service: CalendarService;
  let repository: jest.Mocked<CalendarRepository>;

  const userId = 'user-1';
  const baseEvent: CalendarEvent = {
    id: 'event-1',
    userId,
    title: 'Team sync',
    description: null,
    startAt: '2026-08-20T09:00:00.000Z',
    endAt: '2026-08-20T09:30:00.000Z',
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
    } as unknown as jest.Mocked<CalendarRepository>;

    service = new CalendarService(repository);
  });

  it('returns all events for a user', async () => {
    repository.findAll.mockResolvedValue([baseEvent]);

    await expect(service.findAll(userId, {})).resolves.toEqual([baseEvent]);
    expect(repository.findAll).toHaveBeenCalledWith(
      userId,
      undefined,
      undefined,
    );
  });

  it('passes from/to through to the repository', async () => {
    repository.findAll.mockResolvedValue([]);

    await service.findAll(userId, {
      from: '2026-08-20T00:00:00.000Z',
      to: '2026-08-21T00:00:00.000Z',
    });

    expect(repository.findAll).toHaveBeenCalledWith(
      userId,
      '2026-08-20T00:00:00.000Z',
      '2026-08-21T00:00:00.000Z',
    );
  });

  it('rejects a range query where to is before from', async () => {
    await expect(
      service.findAll(userId, {
        from: '2026-08-21T00:00:00.000Z',
        to: '2026-08-20T00:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.findAll).not.toHaveBeenCalled();
  });

  it('throws NotFoundException when an event does not belong to the user', async () => {
    repository.findById.mockResolvedValue(null);

    await expect(service.findOne(userId, 'missing')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('creates an event via the repository', async () => {
    repository.create.mockResolvedValue(baseEvent);

    await expect(
      service.create(userId, {
        title: 'Team sync',
        startAt: baseEvent.startAt,
        endAt: baseEvent.endAt,
      }),
    ).resolves.toEqual(baseEvent);
    expect(repository.create).toHaveBeenCalledWith(userId, {
      title: 'Team sync',
      startAt: baseEvent.startAt,
      endAt: baseEvent.endAt,
    });
  });

  it('rejects creating an event whose endAt is before startAt', async () => {
    await expect(
      service.create(userId, {
        title: 'Bad event',
        startAt: '2026-08-20T09:00:00.000Z',
        endAt: '2026-08-20T08:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.create).not.toHaveBeenCalled();
  });

  it('updates an event after confirming ownership', async () => {
    repository.findById.mockResolvedValue(baseEvent);
    repository.update.mockResolvedValue({ ...baseEvent, title: 'Updated' });

    await expect(
      service.update(userId, baseEvent.id, { title: 'Updated' }),
    ).resolves.toEqual({ ...baseEvent, title: 'Updated' });
  });

  it('throws NotFoundException when updating an event the user does not own', async () => {
    repository.findById.mockResolvedValue(null);

    await expect(
      service.update(userId, 'missing', { title: 'Updated' }),
    ).rejects.toThrow(NotFoundException);
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('rejects updating only startAt to land after the existing endAt', async () => {
    repository.findById.mockResolvedValue(baseEvent); // endAt: 09:30

    await expect(
      service.update(userId, baseEvent.id, {
        startAt: '2026-08-20T10:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('rejects updating only endAt to land before the existing startAt', async () => {
    repository.findById.mockResolvedValue(baseEvent); // startAt: 09:00

    await expect(
      service.update(userId, baseEvent.id, {
        endAt: '2026-08-20T08:00:00.000Z',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('allows updating only startAt when it still precedes the existing endAt', async () => {
    repository.findById.mockResolvedValue(baseEvent); // endAt: 09:30
    repository.update.mockResolvedValue({
      ...baseEvent,
      startAt: '2026-08-20T09:15:00.000Z',
    });

    await expect(
      service.update(userId, baseEvent.id, {
        startAt: '2026-08-20T09:15:00.000Z',
      }),
    ).resolves.toEqual({ ...baseEvent, startAt: '2026-08-20T09:15:00.000Z' });
    expect(repository.update).toHaveBeenCalledWith(userId, baseEvent.id, {
      startAt: '2026-08-20T09:15:00.000Z',
    });
  });

  it('removes an event after confirming ownership', async () => {
    repository.findById.mockResolvedValue(baseEvent);

    await service.remove(userId, baseEvent.id);

    expect(repository.delete).toHaveBeenCalledWith(userId, baseEvent.id);
  });

  it('throws NotFoundException when removing an event the user does not own', async () => {
    repository.findById.mockResolvedValue(null);

    await expect(service.remove(userId, 'missing')).rejects.toThrow(
      NotFoundException,
    );
    expect(repository.delete).not.toHaveBeenCalled();
  });
});
