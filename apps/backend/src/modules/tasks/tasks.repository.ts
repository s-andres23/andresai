import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../../common/supabase/supabase.service';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { Task, TaskStatus } from './interfaces/task.interface';

const TASK_COLUMNS =
  'id, user_id, title, description, status, priority, due_date, due_time, created_at, updated_at, completed_at';

interface TaskRow {
  id: string;
  user_id: string;
  title: string;
  description: string | null;
  status: TaskStatus;
  priority: Task['priority'];
  due_date: string | null;
  due_time: string | null;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
}

function mapTaskRow(row: TaskRow): Task {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title,
    description: row.description,
    status: row.status,
    priority: row.priority,
    dueDate: row.due_date,
    dueTime: row.due_time,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
  };
}

@Injectable()
export class TasksRepository {
  constructor(private readonly supabaseService: SupabaseService) {}

  private get client() {
    return this.supabaseService.client;
  }

  async findAll(userId: string): Promise<Task[]> {
    const { data, error } = await this.client
      .from('tasks')
      .select(TASK_COLUMNS)
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      throw error;
    }

    return (data as unknown as TaskRow[]).map(mapTaskRow);
  }

  async findById(userId: string, id: string): Promise<Task | null> {
    const { data, error } = await this.client
      .from('tasks')
      .select(TASK_COLUMNS)
      .eq('user_id', userId)
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw error;
    }

    return data ? mapTaskRow(data) : null;
  }

  async create(userId: string, dto: CreateTaskDto): Promise<Task> {
    const { data, error } = await this.client
      .from('tasks')
      .insert({
        user_id: userId,
        title: dto.title,
        description: dto.description ?? null,
        priority: dto.priority ?? 'normal',
        due_date: dto.dueDate ?? null,
        due_time: dto.dueTime ?? null,
      })
      .select(TASK_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapTaskRow(data);
  }

  async update(userId: string, id: string, dto: UpdateTaskDto): Promise<Task> {
    const updates: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };

    if (dto.title !== undefined) updates.title = dto.title;
    if (dto.description !== undefined) updates.description = dto.description;
    if (dto.priority !== undefined) updates.priority = dto.priority;
    if (dto.dueDate !== undefined) updates.due_date = dto.dueDate;
    if (dto.dueTime !== undefined) updates.due_time = dto.dueTime;

    const { data, error } = await this.client
      .from('tasks')
      .update(updates)
      .eq('user_id', userId)
      .eq('id', id)
      .select(TASK_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapTaskRow(data);
  }

  async delete(userId: string, id: string): Promise<void> {
    const { error } = await this.client
      .from('tasks')
      .delete()
      .eq('user_id', userId)
      .eq('id', id);

    if (error) {
      throw error;
    }
  }

  async setStatus(
    userId: string,
    id: string,
    status: TaskStatus,
  ): Promise<Task> {
    const { data, error } = await this.client
      .from('tasks')
      .update({
        status,
        completed_at: status === 'completed' ? new Date().toISOString() : null,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('id', id)
      .select(TASK_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapTaskRow(data);
  }
}
