import { Injectable, Logger } from '@nestjs/common';
import { RemindersRepository } from './reminders.repository';

/**
 * Keeps relative Calendar reminders in sync with their linked event's
 * `startAt`.
 *
 * Deliberately depends only on {@link RemindersRepository}, not
 * `RemindersService` or `CalendarService` -- so `CalendarService` can call
 * this directly (`CalendarService -> ReminderSyncService ->
 * RemindersRepository`) without creating a circular dependency between the
 * Calendar and Reminders modules.
 */
@Injectable()
export class ReminderSyncService {
  private readonly logger = new Logger(ReminderSyncService.name);

  constructor(private readonly remindersRepository: RemindersRepository) {}

  /**
   * Recalculates `remindAt` for every pending, relative reminder linked to
   * [calendarEventId], after that event's `startAt` changed to
   * [newStartAt].
   *
   * Only pending relative reminders move with the event -- absolute,
   * triggered, and cancelled reminders are excluded by the repository
   * query, and reminders are always scoped to [userId]. Safe to call when
   * no reminders are linked (no-op).
   *
   * A moved event can legitimately push a reminder's recalculated
   * `remindAt` into the past (e.g. the event moved earlier than the
   * offset now allows). This slice preserves the calculated
   * start-plus-offset relationship rather than inventing new status
   * behavior for it; deciding how to handle an already-past pending
   * reminder is left to the future scheduler/notification layer.
   */
  async syncCalendarEventReminders(
    userId: string,
    calendarEventId: string,
    newStartAt: string,
  ): Promise<void> {
    const reminders =
      await this.remindersRepository.findPendingRelativeByCalendarEvent(
        userId,
        calendarEventId,
      );

    if (reminders.length === 0) {
      return;
    }

    const newStartAtMs = new Date(newStartAt).getTime();

    for (const reminder of reminders) {
      if (
        typeof reminder.offsetMinutes !== 'number' ||
        !Number.isFinite(reminder.offsetMinutes)
      ) {
        // The DB's `reminders_trigger_configuration_valid` constraint
        // requires relative reminders to have offset_minutes set, so this
        // should be unreachable -- but malformed data must not crash the
        // rest of the sync batch.
        this.logger.warn(
          `Reminder ${reminder.id} is relative but has no usable offsetMinutes; skipping sync`,
        );
        continue;
      }

      const newRemindAt = new Date(
        newStartAtMs + reminder.offsetMinutes * 60_000,
      ).toISOString();

      await this.remindersRepository.updateRemindAt(
        userId,
        reminder.id,
        newRemindAt,
      );
    }
  }
}
