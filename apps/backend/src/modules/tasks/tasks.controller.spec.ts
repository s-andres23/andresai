import { Test, TestingModule } from '@nestjs/testing';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { Task } from './interfaces/task.interface';

describe('TasksController', () => {
  let controller: TasksController;
  let service: jest.Mocked<TasksService>;

  const userId = 'user-1';
  const task: Task = {
    id: 'task-1',
    userId,
    title: 'Write report',
    description: null,
    status: 'open',
    priority: 'normal',
    dueDate: null,
    dueTime: null,
    createdAt: '2026-08-10T00:00:00.000Z',
    updatedAt: '2026-08-10T00:00:00.000Z',
    completedAt: null,
  };

  beforeEach(async () => {
    const serviceMock = {
      findAll: jest.fn().mockResolvedValue([task]),
      findOne: jest.fn().mockResolvedValue(task),
      create: jest.fn().mockResolvedValue(task),
      update: jest.fn().mockResolvedValue(task),
      remove: jest.fn().mockResolvedValue(undefined),
      complete: jest.fn().mockResolvedValue({ ...task, status: 'completed' }),
      reopen: jest.fn().mockResolvedValue(task),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [TasksController],
      providers: [{ provide: TasksService, useValue: serviceMock }],
    })
      .overrideGuard(SupabaseAuthGuard)
      .useValue({ canActivate: () => true })
      .compile();

    controller = module.get<TasksController>(TasksController);
    service = module.get(TasksService);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('delegates findAll to the service with the current user', async () => {
    await expect(controller.findAll(userId)).resolves.toEqual([task]);
    expect(service.findAll).toHaveBeenCalledWith(userId);
  });

  it('delegates create to the service', async () => {
    await controller.create(userId, { title: 'Write report' });
    expect(service.create).toHaveBeenCalledWith(userId, {
      title: 'Write report',
    });
  });

  it('delegates complete to the service', async () => {
    await controller.complete(userId, task.id);
    expect(service.complete).toHaveBeenCalledWith(userId, task.id);
  });

  it('delegates reopen to the service', async () => {
    await controller.reopen(userId, task.id);
    expect(service.reopen).toHaveBeenCalledWith(userId, task.id);
  });

  it('delegates remove to the service', async () => {
    await controller.remove(userId, task.id);
    expect(service.remove).toHaveBeenCalledWith(userId, task.id);
  });
});
