import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { CalendarService } from '../calendar/calendar.service';
import { CalendarEvent } from '../calendar/interfaces/calendar-event.interface';
import { TasksService } from '../tasks/tasks.service';
import { Task } from '../tasks/interfaces/task.interface';
import { RemindersRepository, ReminderWriteData } from './reminders.repository';
import { CreateReminderDto } from './dto/create-reminder.dto';
import { UpdateReminderDto } from './dto/update-reminder.dto';
import { Reminder } from './interfaces/reminder.interface';

@Injectable()
export class RemindersService {
  constructor(
    private readonly remindersRepository: RemindersRepository,
    private readonly tasksService: TasksService,
    private readonly calendarService: CalendarService,
  ) {}

  findAll(userId: string): Promise<Reminder[]> {
    return this.remindersRepository.findAll(userId);
  }

  async findOne(userId: string, id: string): Promise<Reminder> {
    const reminder = await this.remindersRepository.findById(userId, id);

    if (!reminder) {
      throw new NotFoundException(`Reminder ${id} not found`);
    }

    return reminder;
  }

  async create(userId: string, dto: CreateReminderDto): Promise<Reminder> {
    const data = await this.buildWriteData(userId, dto, undefined);
    return this.remindersRepository.create(userId, data);
  }

  async update(
    userId: string,
    id: string,
    dto: UpdateReminderDto,
  ): Promise<Reminder> {
    const existing = await this.findOne(userId, id);

    if (existing.status !== 'pending') {
      throw new BadRequestException(
        `Cannot edit a reminder with status "${existing.status}"; only pending reminders can be edited`,
      );
    }

    const data = await this.buildWriteData(userId, dto, existing);
    return this.remindersRepository.update(userId, id, data);
  }

  async remove(userId: string, id: string): Promise<void> {
    await this.findOne(userId, id);
    await this.remindersRepository.delete(userId, id);
  }

  async cancel(userId: string, id: string): Promise<Reminder> {
    const reminder = await this.findOne(userId, id);

    if (reminder.status === 'cancelled') {
      return reminder;
    }

    if (reminder.status === 'triggered') {
      throw new BadRequestException(
        'Cannot cancel a reminder that has already triggered',
      );
    }

    return this.remindersRepository.setStatus(userId, id, 'cancelled');
  }

  /**
   * Reactivates a cancelled reminder back to `pending`.
   *
   * - Already `pending`: returned as-is (idempotent), matching the existing
   *   `cancel()`/Tasks complete-reopen convention -- no write.
   * - `triggered`: rejected; a triggered reminder can never go back to
   *   `pending`.
   * - `cancelled`, absolute: reactivated only if its existing `remindAt` is
   *   still in the future; otherwise rejected -- the caller must edit or
   *   recreate it rather than have the backend silently pick a new time.
   * - `cancelled`, relative Calendar: `remindAt` is recalculated from the
   *   *current* linked Calendar event's `startAt` (never the stale stored
   *   value), then reactivated only if that recalculated instant is still
   *   in the future.
   * - `cancelled`, relative Task: remains unsupported -- reuses
   *   {@link calculateRemindAtFromTask}, which always throws
   *   `UnprocessableEntityException`, the same as create/update.
   */
  async reactivate(userId: string, id: string): Promise<Reminder> {
    const reminder = await this.findOne(userId, id);

    if (reminder.status === 'pending') {
      return reminder;
    }

    if (reminder.status === 'triggered') {
      throw new BadRequestException(
        'Cannot reactivate a reminder that has already triggered',
      );
    }

    const remindAt =
      reminder.triggerType === 'absolute'
        ? reminder.remindAt
        : await this.recalculateRelativeRemindAt(userId, reminder);

    if (new Date(remindAt).getTime() <= Date.now()) {
      throw new BadRequestException(
        'Cannot reactivate: remindAt is in the past. Edit or create a new reminder instead.',
      );
    }

    return this.remindersRepository.reactivate(userId, id, remindAt);
  }

  private async recalculateRelativeRemindAt(
    userId: string,
    reminder: Reminder,
  ): Promise<string> {
    if (reminder.calendarEventId) {
      const calendarEvent = await this.calendarService.findOne(
        userId,
        reminder.calendarEventId,
      );
      return this.calculateRemindAtFromCalendarEvent(
        calendarEvent,
        reminder.offsetMinutes!,
      );
    }

    const task = await this.tasksService.findOne(userId, reminder.taskId!);
    return this.calculateRemindAtFromTask(task);
  }

  /**
   * Resolves the effective merged state for a create or update, validates
   * it, and (for relative reminders) authoritatively (re)calculates
   * `remindAt` server-side -- the client-supplied value is never trusted
   * for relative reminders.
   */
  private async buildWriteData(
    userId: string,
    dto: CreateReminderDto | UpdateReminderDto,
    existing: Reminder | undefined,
  ): Promise<ReminderWriteData> {
    const title = dto.title ?? existing?.title;
    const triggerType = dto.triggerType ?? existing?.triggerType;
    const taskId =
      dto.taskId !== undefined ? dto.taskId : (existing?.taskId ?? null);
    const calendarEventId =
      dto.calendarEventId !== undefined
        ? dto.calendarEventId
        : (existing?.calendarEventId ?? null);
    const offsetMinutes =
      dto.offsetMinutes !== undefined
        ? dto.offsetMinutes
        : (existing?.offsetMinutes ?? null);

    if (!title || !triggerType) {
      // Unreachable in practice: CreateReminderDto requires both, and an
      // update always has `existing` as a fallback. Narrows types below.
      throw new BadRequestException('title and triggerType are required');
    }

    if (taskId && calendarEventId) {
      throw new BadRequestException(
        'A reminder cannot be linked to both a task and a calendar event',
      );
    }

    // Ownership is checked for any linked task/calendar event, regardless
    // of trigger type -- and the fetched objects are reused below for the
    // relative-reminder calculation, avoiding a second fetch.
    const task = taskId
      ? await this.tasksService.findOne(userId, taskId)
      : null;
    const calendarEvent = calendarEventId
      ? await this.calendarService.findOne(userId, calendarEventId)
      : null;

    let remindAt: string;

    if (triggerType === 'absolute') {
      if (offsetMinutes !== null) {
        throw new BadRequestException(
          'offsetMinutes must not be set for an absolute reminder',
        );
      }

      const provided = dto.remindAt ?? existing?.remindAt;
      if (!provided) {
        throw new BadRequestException('remindAt is required');
      }
      remindAt = provided;
    } else {
      if (offsetMinutes === null) {
        throw new BadRequestException(
          'offsetMinutes is required for a relative reminder',
        );
      }
      if (!taskId && !calendarEventId) {
        throw new BadRequestException(
          'A relative reminder must be linked to a task or a calendar event',
        );
      }

      remindAt = calendarEvent
        ? this.calculateRemindAtFromCalendarEvent(calendarEvent, offsetMinutes)
        : this.calculateRemindAtFromTask(task!);
    }

    if (new Date(remindAt).getTime() <= Date.now()) {
      throw new BadRequestException('remindAt must be in the future');
    }

    return {
      title,
      taskId,
      calendarEventId,
      triggerType,
      offsetMinutes,
      remindAt,
    };
  }

  private calculateRemindAtFromCalendarEvent(
    event: CalendarEvent,
    offsetMinutes: number,
  ): string {
    const startAt = new Date(event.startAt).getTime();
    return new Date(startAt + offsetMinutes * 60_000).toISOString();
  }

  private calculateRemindAtFromTask(task: Task): string {
    if (!task.dueDate || !task.dueTime) {
      throw new BadRequestException(
        'A task-relative reminder requires the task to have both a due date and a due time',
      );
    }

    // ARCHITECTURE NOTE: Task.dueDate/dueTime are stored as plain
    // (timezone-less) `date`/`time` values -- see
    // modules/tasks/interfaces/task.interface.ts and the `tasks` table
    // schema -- and the Tasks backend never combines them into an instant
    // anywhere today, so there is no existing assumption to reuse here.
    // There is also no user-timezone source available to this backend yet
    // (the `profiles.timezone` column exists in the database, but no
    // Profiles module/service exposes it). Guessing a timezone (e.g. UTC)
    // to compute `remindAt = deadline + offsetMinutes` could silently fire
    // a reminder at the wrong real-world time, so per this slice's
    // architecture note we stop and report rather than invent that
    // assumption. See the implementation report for suggested follow-ups.
    throw new UnprocessableEntityException(
      'Cannot calculate a task-relative reminder yet: the task due date/time ' +
        'has no associated timezone and the backend has no user-timezone ' +
        'source. This is a known limitation -- see ReminderService.calculateRemindAtFromTask.',
    );
  }
}
