import { Test, TestingModule } from '@nestjs/testing';
import { RemindersController } from './reminders.controller';
import { RemindersService } from './reminders.service';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { Reminder } from './interfaces/reminder.interface';

describe('RemindersController', () => {
  let controller: RemindersController;
  let service: jest.Mocked<RemindersService>;

  const userId = 'user-1';
  const reminder: Reminder = {
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

  beforeEach(async () => {
    const serviceMock = {
      findAll: jest.fn().mockResolvedValue([reminder]),
      findOne: jest.fn().mockResolvedValue(reminder),
      create: jest.fn().mockResolvedValue(reminder),
      update: jest.fn().mockResolvedValue(reminder),
      remove: jest.fn().mockResolvedValue(undefined),
      cancel: jest.fn().mockResolvedValue({ ...reminder, status: 'cancelled' }),
      reactivate: jest
        .fn()
        .mockResolvedValue({ ...reminder, status: 'pending' }),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [RemindersController],
      providers: [{ provide: RemindersService, useValue: serviceMock }],
    })
      .overrideGuard(SupabaseAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<RemindersController>(RemindersController);
    service = module.get(RemindersService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('delegates findAll to the service with the current user', async () => {
    await expect(controller.findAll(userId)).resolves.toEqual([reminder]);
    expect(service.findAll).toHaveBeenCalledWith(userId);
  });

  it('delegates create to the service', async () => {
    const dto = {
      title: 'Stand up',
      triggerType: 'absolute' as const,
      remindAt: '2099-01-01T09:00:00.000Z',
    };

    await controller.create(userId, dto);

    expect(service.create).toHaveBeenCalledWith(userId, dto);
  });

  it('delegates findOne to the service', async () => {
    await expect(controller.findOne(userId, reminder.id)).resolves.toEqual(
      reminder,
    );
    expect(service.findOne).toHaveBeenCalledWith(userId, reminder.id);
  });

  it('delegates update to the service', async () => {
    const dto = { title: 'Updated' };

    await controller.update(userId, reminder.id, dto);

    expect(service.update).toHaveBeenCalledWith(userId, reminder.id, dto);
  });

  it('delegates remove to the service', async () => {
    await controller.remove(userId, reminder.id);

    expect(service.remove).toHaveBeenCalledWith(userId, reminder.id);
  });

  it('delegates cancel to the service', async () => {
    await controller.cancel(userId, reminder.id);

    expect(service.cancel).toHaveBeenCalledWith(userId, reminder.id);
  });

  it('delegates reactivate to the service', async () => {
    await controller.reactivate(userId, reminder.id);

    expect(service.reactivate).toHaveBeenCalledWith(userId, reminder.id);
  });
});
