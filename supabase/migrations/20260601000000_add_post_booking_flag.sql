-- Adds a flag to booking_events that distinguishes notes created after a booking
-- has already been submitted from events recorded during the booking flow itself.
-- The NotificationService only emits post_booking_note notifications for rows
-- where this column is TRUE.
--
-- All pre-existing rows default to FALSE (no retroactive notifications).
-- New comments added via BookingActivityPanel must set this to TRUE explicitly.

ALTER TABLE booking_events
  ADD COLUMN IF NOT EXISTS added_post_booking BOOLEAN NOT NULL DEFAULT FALSE;
