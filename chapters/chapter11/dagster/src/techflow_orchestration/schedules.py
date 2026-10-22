"""Time-driven alternative to the S3 sensor.

This chapter's graph is event-driven, so ``definitions.py`` registers
``scores_sensor`` as the trigger. Swap this schedule into the same registration
slot (``schedules=[nightly_schedule]``) for a nightly cron run instead.
"""

import dagster as dg


nightly_schedule = dg.ScheduleDefinition(
    name="techflow_nightly",
    target=dg.AssetSelection.all(),
    cron_schedule="0 2 * * *",
    execution_timezone="UTC",
    description="Materializes the complete TechFlow asset graph nightly at 02:00 UTC.",
)
