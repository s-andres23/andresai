export const REMINDER_TRIGGER_TYPES = ['absolute', 'relative'] as const;
export type ReminderTriggerType = (typeof REMINDER_TRIGGER_TYPES)[number];

export const REMINDER_STATUSES = ['pending', 'triggered', 'cancelled'] as const;
export type ReminderStatus = (typeof REMINDER_STATUSES)[number];

export interface Reminder {
  id: string;
  userId: string;
  taskId: string | null;
  calendarEventId: string | null;
  title: string;
  triggerType: ReminderTriggerType;
  offsetMinutes: number | null;
  remindAt: string;
  status: ReminderStatus;
  createdAt: string;
  updatedAt: string;
}
