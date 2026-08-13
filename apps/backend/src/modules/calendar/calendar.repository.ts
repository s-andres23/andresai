import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../../common/supabase/supabase.service';
import { CreateCalendarEventDto } from './dto/create-calendar-event.dto';
import { UpdateCalendarEventDto } from './dto/update-calendar-event.dto';
import { CalendarEvent } from './interfaces/calendar-event.interface';

const CALENDAR_EVENT_COLUMNS =
  'id, user_id, title, description, start_at, end_at, all_day, location, created_at, updated_at';

interface CalendarEventRow {
  id: string;
  user_id: string;
  title: string;
  description: string | null;
  start_at: string;
  end_at: string;
  all_day: boolean;
  location: string | null;
  created_at: string;
  updated_at: string;
}

function mapCalendarEventRow(row: CalendarEventRow): CalendarEvent {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title,
    description: row.description,
    startAt: row.start_at,
    endAt: row.end_at,
    allDay: row.all_day,
    location: row.location,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

@Injectable()
export class CalendarRepository {
  constructor(private readonly supabaseService: SupabaseService) {}

  private get client() {
    return this.supabaseService.client;
  }

  /**
   * Lists a user's events, always scoped to `userId`.
   *
   * When `from`/`to` are provided, returns events overlapping
   * `[from, to]` using the standard interval-overlap test
   * `event.start_at <= to AND event.end_at >= from`. Each bound is applied
   * independently, so a range with only one side supplied is treated as
   * open-ended on the other: `from` alone excludes events that already
   * ended before it, `to` alone excludes events that start after it.
   */
  async findAll(
    userId: string,
    from?: string,
    to?: string,
  ): Promise<CalendarEvent[]> {
    let query = this.client
      .from('calendar_events')
      .select(CALENDAR_EVENT_COLUMNS)
      .eq('user_id', userId);

    if (from) {
      query = query.gte('end_at', from);
    }
    if (to) {
      query = query.lte('start_at', to);
    }

    const { data, error } = await query.order('start_at', {
      ascending: true,
    });

    if (error) {
      throw error;
    }

    return (data as unknown as CalendarEventRow[]).map(mapCalendarEventRow);
  }

  async findById(userId: string, id: string): Promise<CalendarEvent | null> {
    const { data, error } = await this.client
      .from('calendar_events')
      .select(CALENDAR_EVENT_COLUMNS)
      .eq('user_id', userId)
      .eq('id', id)
      .maybeSingle();

    if (error) {
      throw error;
    }

    return data ? mapCalendarEventRow(data) : null;
  }

  async create(
    userId: string,
    dto: CreateCalendarEventDto,
  ): Promise<CalendarEvent> {
    const { data, error } = await this.client
      .from('calendar_events')
      .insert({
        user_id: userId,
        title: dto.title,
        description: dto.description ?? null,
        start_at: dto.startAt,
        end_at: dto.endAt,
        all_day: dto.allDay ?? false,
        location: dto.location ?? null,
      })
      .select(CALENDAR_EVENT_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapCalendarEventRow(data);
  }

  async update(
    userId: string,
    id: string,
    dto: UpdateCalendarEventDto,
  ): Promise<CalendarEvent> {
    const updates: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };

    if (dto.title !== undefined) updates.title = dto.title;
    if (dto.description !== undefined) updates.description = dto.description;
    if (dto.startAt !== undefined) updates.start_at = dto.startAt;
    if (dto.endAt !== undefined) updates.end_at = dto.endAt;
    if (dto.allDay !== undefined) updates.all_day = dto.allDay;
    if (dto.location !== undefined) updates.location = dto.location;

    const { data, error } = await this.client
      .from('calendar_events')
      .update(updates)
      .eq('user_id', userId)
      .eq('id', id)
      .select(CALENDAR_EVENT_COLUMNS)
      .single();

    if (error) {
      throw error;
    }

    return mapCalendarEventRow(data);
  }

  async delete(userId: string, id: string): Promise<void> {
    const { error } = await this.client
      .from('calendar_events')
      .delete()
      .eq('user_id', userId)
      .eq('id', id);

    if (error) {
      throw error;
    }
  }
}
