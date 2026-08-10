import { Injectable, NotFoundException } from '@nestjs/common';
import { TasksRepository } from './tasks.repository';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { Task } from './interfaces/task.interface';

@Injectable()
export class TasksService {
  constructor(private readonly tasksRepository: TasksRepository) {}

  findAll(userId: string): Promise<Task[]> {
    return this.tasksRepository.findAll(userId);
  }

  async findOne(userId: string, id: string): Promise<Task> {
    const task = await this.tasksRepository.findById(userId, id);

    if (!task) {
      throw new NotFoundException(`Task ${id} not found`);
    }

    return task;
  }

  create(userId: string, dto: CreateTaskDto): Promise<Task> {
    return this.tasksRepository.create(userId, dto);
  }

  async update(userId: string, id: string, dto: UpdateTaskDto): Promise<Task> {
    await this.findOne(userId, id);
    return this.tasksRepository.update(userId, id, dto);
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.findOne(userId, id);
    await this.tasksRepository.delete(userId, id);
  }

  async complete(userId: string, id: string): Promise<Task> {
    const task = await this.findOne(userId, id);

    if (task.status === 'completed') {
      return task;
    }

    return this.tasksRepository.setStatus(userId, id, 'completed');
  }

  async reopen(userId: string, id: string): Promise<Task> {
    const task = await this.findOne(userId, id);

    if (task.status === 'open') {
      return task;
    }

    return this.tasksRepository.setStatus(userId, id, 'open');
  }
}
