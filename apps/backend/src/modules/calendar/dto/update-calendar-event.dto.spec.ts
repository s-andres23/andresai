import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { UpdateCalendarEventDto } from './update-calendar-event.dto';

function validateDto(payload: Record<string, unknown>) {
  const dto = plainToInstance(UpdateCalendarEventDto, payload);
  return validate(dto);
}

describe('UpdateCalendarEventDto', () => {
  it('accepts an empty payload (all fields optional)', async () => {
    const errors = await validateDto({});
    expect(errors).toHaveLength(0);
  });

  it('accepts a partial payload with only title', async () => {
    const errors = await validateDto({ title: 'Updated title' });
    expect(errors).toHaveLength(0);
  });

  it('accepts a partial payload with only startAt', async () => {
    const errors = await validateDto({
      startAt: '2026-08-20T09:15:00.000Z',
    });
    expect(errors).toHaveLength(0);
  });

  it('rejects an empty title when provided', async () => {
    const errors = await validateDto({ title: '' });
    expect(errors.some((e) => e.property === 'title')).toBe(true);
  });

  it('rejects a non-ISO-8601 startAt when provided', async () => {
    const errors = await validateDto({ startAt: 'not-a-date' });
    expect(errors.some((e) => e.property === 'startAt')).toBe(true);
  });

  it('rejects a non-ISO-8601 endAt when provided', async () => {
    const errors = await validateDto({ endAt: 'not-a-date' });
    expect(errors.some((e) => e.property === 'endAt')).toBe(true);
  });
});
