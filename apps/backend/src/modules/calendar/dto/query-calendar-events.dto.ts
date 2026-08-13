import { IsISO8601, IsOptional } from 'class-validator';

/**
 * `from`/`to` are independently optional and only format-validated here;
 * the `to < from` ordering check depends on both values together and is
 * enforced in {@link CalendarService} instead.
 */
export class QueryCalendarEventsDto {
  @IsOptional()
  @IsISO8601()
  from?: string;

  @IsOptional()
  @IsISO8601()
  to?: string;
}
