import { Module } from '@nestjs/common';
import { ReminderSyncService } from './reminder-sync.service';
import { RemindersRepository } from './reminders.repository';

/**
 * A small leaf module holding only what's needed to sync reminders from
 * elsewhere (currently: Calendar), kept separate from `RemindersModule` so
 * `CalendarModule` can depend on `ReminderSyncService` without importing
 * `RemindersModule` -- which would create a circular module dependency,
 * since `RemindersModule` already imports `CalendarModule`.
 *
 * `RemindersModule` also imports this module, so `RemindersService` and
 * `ReminderSyncService` share the same `RemindersRepository` instance
 * rather than each module providing its own.
 */
@Module({
  providers: [ReminderSyncService, RemindersRepository],
  exports: [ReminderSyncService, RemindersRepository],
})
export class ReminderSyncModule {}
