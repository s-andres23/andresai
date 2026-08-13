import { Test, TestingModule } from '@nestjs/testing';
import { CalendarController } from './calendar.controller';
import { CalendarService } from './calendar.service';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { CalendarEvent } from './interfaces/calendar-event.interface';

describe('CalendarController', () => {
  let controller: CalendarController;
  let service: jest.Mocked<CalendarService>;

  const userId = 'user-1';
  const event: CalendarEvent = {
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

  beforeEach(async () => {
    const serviceMock = {
      findAll: jest.fn().mockResolvedValue([event]),
      findOne: jest.fn().mockResolvedValue(event),
      create: jest.fn().mockResolvedValue(event),
      update: jest.fn().mockResolvedValue(event),
      remove: jest.fn().mockResolvedValue(undefined),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [CalendarController],
      providers: [{ provide: CalendarService, useValue: serviceMock }],
    })
      .overrideGuard(SupabaseAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<CalendarController>(CalendarController);
    service = module.get(CalendarService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('delegates findAll to the service with the current user and query', async () => {
    const query = {
      from: '2026-08-20T00:00:00.000Z',
      to: '2026-08-21T00:00:00.000Z',
    };

    await expect(controller.findAll(userId, query)).resolves.toEqual([event]);
    expect(service.findAll).toHaveBeenCalledWith(userId, query);
  });

  it('delegates create to the service', async () => {
    const dto = {
      title: 'Team sync',
      startAt: event.startAt,
      endAt: event.endAt,
    };

    await controller.create(userId, dto);

    expect(service.create).toHaveBeenCalledWith(userId, dto);
  });

  it('delegates findOne to the service', async () => {
    await expect(controller.findOne(userId, event.id)).resolves.toEqual(event);
    expect(service.findOne).toHaveBeenCalledWith(userId, event.id);
  });

  it('delegates update to the service', async () => {
    const dto = { title: 'Updated title' };

    await controller.update(userId, event.id, dto);

    expect(service.update).toHaveBeenCalledWith(userId, event.id, dto);
  });

  it('delegates remove to the service', async () => {
    await controller.remove(userId, event.id);

    expect(service.remove).toHaveBeenCalledWith(userId, event.id);
  });
});
