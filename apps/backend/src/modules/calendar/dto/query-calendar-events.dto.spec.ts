import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { QueryCalendarEventsDto } from './query-calendar-events.dto';

function validateDto(payload: Record<string, unknown>) {
  const dto = plainToInstance(QueryCalendarEventsDto, payload);
  return validate(dto);
}

describe('QueryCalendarEventsDto', () => {
  it('accepts an empty query', async () => {
    const errors = await validateDto({});
    expect(errors).toHaveLength(0);
  });

  it('accepts valid from/to ISO-8601 timestamps', async () => {
    const errors = await validateDto({
      from: '2026-08-20T00:00:00.000Z',
      to: '2026-08-21T00:00:00.000Z',
    });
    expect(errors).toHaveLength(0);
  });

  it('accepts only from', async () => {
    const errors = await validateDto({ from: '2026-08-20T00:00:00.000Z' });
    expect(errors).toHaveLength(0);
  });

  it('rejects a non-ISO-8601 from', async () => {
    const errors = await validateDto({ from: 'not-a-date' });
    expect(errors.some((e) => e.property === 'from')).toBe(true);
  });

  it('rejects a non-ISO-8601 to', async () => {
    const errors = await validateDto({ to: 'not-a-date' });
    expect(errors.some((e) => e.property === 'to')).toBe(true);
  });

  // The `to < from` ordering check itself is enforced in CalendarService,
  // not the DTO -- see calendar.service.spec.ts.
});
