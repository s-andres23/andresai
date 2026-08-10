import { NotFoundException } from '@nestjs/common';
import { TasksService } from './tasks.service';
import { TasksRepository } from './tasks.repository';
import { Task } from './interfaces/task.interface';

describe('TasksService', () => {
  let service: TasksService;
  let repository: jest.Mocked<TasksRepository>;

  const userId = 'user-1';
  const baseTask: Task = {
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

  beforeEach(() => {
    repository = {
      findAll: jest.fn(),
      findById: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      setStatus: jest.fn(),
    } as unknown as jest.Mocked<TasksRepository>;

    service = new TasksService(repository);
  });

  it('returns all tasks for a user', async () => {
    repository.findAll.mockResolvedValue([baseTask]);

    await expect(service.findAll(userId)).resolves.toEqual([baseTask]);
    expect(repository.findAll).toHaveBeenCalledWith(userId);
  });

  it('throws NotFoundException when a task does not belong to the user', async () => {
    repository.findById.mockResolvedValue(null);

    await expect(service.findOne(userId, 'missing')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('creates a task via the repository', async () => {
    repository.create.mockResolvedValue(baseTask);

    await expect(
      service.create(userId, { title: 'Write report' }),
    ).resolves.toEqual(baseTask);
    expect(repository.create).toHaveBeenCalledWith(userId, {
      title: 'Write report',
    });
  });

  it('updates a task after confirming ownership', async () => {
    repository.findById.mockResolvedValue(baseTask);
    repository.update.mockResolvedValue({ ...baseTask, title: 'Updated' });

    await expect(
      service.update(userId, baseTask.id, { title: 'Updated' }),
    ).resolves.toEqual({ ...baseTask, title: 'Updated' });
  });

  it('removes a task after confirming ownership', async () => {
    repository.findById.mockResolvedValue(baseTask);

    await service.remove(userId, baseTask.id);

    expect(repository.delete).toHaveBeenCalledWith(userId, baseTask.id);
  });

  it('marks an open task as completed', async () => {
    repository.findById.mockResolvedValue(baseTask);
    repository.setStatus.mockResolvedValue({
      ...baseTask,
      status: 'completed',
      completedAt: '2026-08-10T01:00:00.000Z',
    });

    const result = await service.complete(userId, baseTask.id);

    expect(repository.setStatus).toHaveBeenCalledWith(
      userId,
      baseTask.id,
      'completed',
    );
    expect(result.status).toBe('completed');
  });

  it('is idempotent when completing an already-completed task', async () => {
    const completedTask: Task = { ...baseTask, status: 'completed' };
    repository.findById.mockResolvedValue(completedTask);

    const result = await service.complete(userId, baseTask.id);

    expect(repository.setStatus).not.toHaveBeenCalled();
    expect(result).toEqual(completedTask);
  });

  it('reopens a completed task', async () => {
    const completedTask: Task = { ...baseTask, status: 'completed' };
    repository.findById.mockResolvedValue(completedTask);
    repository.setStatus.mockResolvedValue(baseTask);

    const result = await service.reopen(userId, baseTask.id);

    expect(repository.setStatus).toHaveBeenCalledWith(
      userId,
      baseTask.id,
      'open',
    );
    expect(result.status).toBe('open');
  });
});
