import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CalendarRepository } from './calendar.repository';
import { CreateCalendarEventDto } from './dto/create-calendar-event.dto';
import { QueryCalendarEventsDto } from './dto/query-calendar-events.dto';
import { UpdateCalendarEventDto } from './dto/update-calendar-event.dto';
import { CalendarEvent } from './interfaces/calendar-event.interface';
import { ReminderSyncService } from '../reminders/reminder-sync.service';

@Injectable()
export class CalendarService {
  constructor(
    private readonly calendarRepository: CalendarRepository,
    private readonly reminderSyncService: ReminderSyncService,
  ) {}

  async findAll(
    userId: string,
    query: QueryCalendarEventsDto,
  ): Promise<CalendarEvent[]> {
    this.validateRange(query.from, query.to);
    return this.calendarRepository.findAll(userId, query.from, query.to);
  }

  async findOne(userId: string, id: string): Promise<CalendarEvent> {
    const event = await this.calendarRepository.findById(userId, id);

    if (!event) {
      throw new NotFoundException(`Calendar event ${id} not found`);
    }

    return event;
  }

  async create(
    userId: string,
    dto: CreateCalendarEventDto,
  ): Promise<CalendarEvent> {
    this.validateInterval(dto.startAt, dto.endAt);
    return this.calendarRepository.create(userId, dto);
  }

  async update(
    userId: string,
    id: string,
    dto: UpdateCalendarEventDto,
  ): Promise<CalendarEvent> {
    const existing = await this.findOne(userId, id);

    // Validate the *effective* interval, merging any partial update with the
    // event's current values, so changing only one of startAt/endAt is still
    // checked against the resulting interval rather than the raw DTO.
    const effectiveStartAt = dto.startAt ?? existing.startAt;
    const effectiveEndAt = dto.endAt ?? existing.endAt;
    this.validateInterval(effectiveStartAt, effectiveEndAt);

    const updated = await this.calendarRepository.update(userId, id, dto);

    // Only sync once the update has actually persisted, and only when
    // startAt effectively changed. Comparing the persisted instants (not
    // raw strings) avoids false positives from timestamp formatting
    // differences between reads.
    const startAtChanged =
      new Date(updated.startAt).getTime() !==
      new Date(existing.startAt).getTime();
    if (startAtChanged) {
      await this.reminderSyncService.syncCalendarEventReminders(
        userId,
        id,
        updated.startAt,
      );
    }

    return updated;
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.findOne(userId, id);
    await this.calendarRepository.delete(userId, id);
  }

  private validateInterval(startAt: string, endAt: string): void {
    if (new Date(endAt).getTime() < new Date(startAt).getTime()) {
      throw new BadRequestException('endAt must not be before startAt');
    }
  }

  private validateRange(from?: string, to?: string): void {
    if (from && to && new Date(to).getTime() < new Date(from).getTime()) {
      throw new BadRequestException('to must not be before from');
    }
  }
}
