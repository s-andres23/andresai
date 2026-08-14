import {
  IsIn,
  IsISO8601,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { REMINDER_TRIGGER_TYPES } from '../interfaces/reminder.interface';
import type { ReminderTriggerType } from '../interfaces/reminder.interface';

export class CreateReminderDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  title: string;

  @IsOptional()
  @IsUUID()
  taskId?: string;

  @IsOptional()
  @IsUUID()
  calendarEventId?: string;

  @IsIn(REMINDER_TRIGGER_TYPES)
  triggerType: ReminderTriggerType;

  @IsOptional()
  @IsInt()
  offsetMinutes?: number;

  // Required by the DTO contract. For relative reminders this value is
  // recalculated server-side from the linked task/calendar event; the
  // client-supplied value is only actually used for absolute reminders.
  @IsISO8601()
  remindAt: string;
}
