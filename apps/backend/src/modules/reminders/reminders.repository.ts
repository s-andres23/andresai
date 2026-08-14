import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../../common/supabase/supabase.service';
import {
  Reminder,
  ReminderStatus,
  ReminderTriggerType,
} from './interfaces/reminder.interface';

const REMINDER_COLUMNS =
  'id, user_id, task_id, calendar_event_id, title, trigger_type, offset_minutes, remind_at, status, created_at, updated_at';

interface ReminderRow {
  id: string;
  user_id: string;
  task_id: string | null;
  calendar_event_id: string | null;
  title: string;
  trigger_type: ReminderTriggerType;
  offset_minutes: number | null;
  remind_at: string;
  status: ReminderStatus;
  created_at: string;
  updated_at: string;
}

function mapReminderRow(row: ReminderRow): Reminder {
  return {
    id: row.id,
    userId: row.user_id,
    taskId: row.task_id,
    calendarEventId: row.calendar_event_id,
    title: row.title,
    triggerType: row.trigger_type,
    offsetMinutes: row.offset_minutes,
    remindAt: row.remind_at,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * The fully-resolved fields needed to persist a reminder, as computed by
 * {@link RemindersService} (ownership already checked, `remindAt` already
 * calculated for relative reminders). Shared by create and update since
 * both write the same "definition" fields.
 */
export interface ReminderWriteData {
  title: string;
  taskId: string | null;
  calendarEventId: string | null;
  triggerType: ReminderTriggerType;
  offsetMinutes: number | null;
  remindAt: string;
}

@Injectable()
export class RemindersRepository {
  constructor(private readonly supabaseService: SupabaseService) {}

  private get client() {
    return this.supabaseService.client;
  }

  async findAll(userId: string): Promise<Reminder[]> {
    const { data, error } = await this.client
      .from('reminders')
      .select(REMINDER_COLUMNS)
      .eq('user_id', userId)
      .order('remind_at', { ascending: true });

    if (error) {
      throw error;
    }

    return (data as unknown as ReminderRow[]).map(mapReminderRow);
  }

  async findById(userId: string, id: string): Promise<Reminder | null> {
    const { data, error } = await this.client
      .from('reminders')
      .select(REMINDER_COLUMNS)
      .eq('user_id', userId)
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw error;
    }

    return data ? mapReminderRow(data) : null;
  }

  async create(userId: string, data: ReminderWriteData): Promise<Reminder> {
    const { data: row, error } = await this.client
      .from('reminders')
      .insert({
        user_id: userId,
        title: data.title,
        task_id: data.taskId,
        calendar_event_id: data.calendarEventId,
        trigger_type: data.triggerType,
        offset_minutes: data.offsetMinutes,
        remind_at: data.remindAt,
      })
      .select(REMINDER_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapReminderRow(row);
  }

  async update(
    userId: string,
    id: string,
    data: ReminderWriteData,
  ): Promise<Reminder> {
    const { data: row, error } = await this.client
      .from('reminders')
      .update({
        title: data.title,
        task_id: data.taskId,
        calendar_event_id: data.calendarEventId,
        trigger_type: data.triggerType,
        offset_minutes: data.offsetMinutes,
        remind_at: data.remindAt,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('id', id)
      .select(REMINDER_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapReminderRow(row);
  }

  async delete(userId: string, id: string): Promise<void> {
    const { error } = await this.client
      .from('reminders')
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
    status: ReminderStatus,
  ): Promise<Reminder> {
    const { data, error } = await this.client
      .from('reminders')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('id', id)
      .select(REMINDER_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapReminderRow(data);
  }

  /**
   * Finds the pending, relative reminders linked to a calendar event, for
   * {@link ReminderSyncService} to recalculate after the event's `startAt`
   * changes. Absolute, triggered, and cancelled reminders are excluded by
   * the query itself, not by the caller.
   */
  async findPendingRelativeByCalendarEvent(
    userId: string,
    calendarEventId: string,
  ): Promise<Reminder[]> {
    const { data, error } = await this.client
      .from('reminders')
      .select(REMINDER_COLUMNS)
      .eq('user_id', userId)
      .eq('calendar_event_id', calendarEventId)
      .eq('trigger_type', 'relative')
      .eq('status', 'pending');

    if (error) {
      throw error;
    }

    return (data as unknown as ReminderRow[]).map(mapReminderRow);
  }

  /** Updates only `remind_at` (plus `updated_at`), scoped to the user. */
  async updateRemindAt(
    userId: string,
    id: string,
    remindAt: string,
  ): Promise<Reminder> {
    const { data, error } = await this.client
      .from('reminders')
      .update({ remind_at: remindAt, updated_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('id', id)
      .select(REMINDER_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapReminderRow(data);
  }
}
