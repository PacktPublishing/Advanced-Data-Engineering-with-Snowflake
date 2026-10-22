"""S3 sensor that launches the TechFlow asset graph when scores land.

A sensor runs outside any run, polls on its own cadence, and requests one run
per new file, so no worker slot is spent waiting. Each request names the
partition parsed from the file's own name, so the graph materializes for that
day rather than for whatever "now" happens to be.

Importing this module defines the sensor but starts no polling. Sensors ship
stopped: turn this one on in the UI, and run the Dagster daemon, or nothing
evaluates.
"""

import dagster as dg
from dagster_aws.s3.sensor import get_objects

from techflow_orchestration.partitions import partition_key_from_object_key

SCORES_BUCKET = "techflow-ml"
SCORES_PREFIX = "scores/"


def _object_identity(obj: dict) -> str:
    """Identify an object by name plus content version.

    Keying a run on the object name alone misses a same-name overwrite: the
    fraud team correcting a day's scores would reuse the file name, and the
    rerun would be suppressed as a duplicate. The ETag changes when the content
    does, so name plus ETag distinguishes a correction from a replay.
    """
    version = obj.get("VersionId") or obj.get("ETag", "").strip('"')
    return f'{obj["Key"]}:{version}' if version else obj["Key"]


@dg.sensor(target=dg.AssetSelection.all(), minimum_interval_seconds=60)
def scores_sensor(context: dg.SensorEvaluationContext):
    """Request one partitioned run per new scores file.

    The cursor records the last key seen so a re-evaluated tick does not
    re-request the same files. Two edge cases are worth knowing: on the first
    evaluation the cursor is empty, so every file already under the prefix
    fires a run, and ``get_objects`` raises if the cursored key has since been
    deleted from the bucket, so clear the cursor after pruning old files.
    """
    objects = get_objects(
        SCORES_BUCKET,
        prefix=SCORES_PREFIX,
        since_key=context.cursor or None,
    )
    if not objects:
        return dg.SkipReason("no new scores file")

    requests = []
    skipped = []
    for obj in objects:
        partition_key = partition_key_from_object_key(obj["Key"])
        if partition_key is None:
            # A file the sensor cannot place on the calendar is reported, not
            # guessed at: materializing the wrong partition is worse than
            # materializing none.
            skipped.append(obj["Key"])
            continue
        requests.append(
            dg.RunRequest(
                run_key=_object_identity(obj),
                partition_key=partition_key,
            )
        )

    context.update_cursor(objects[-1]["Key"])

    if skipped:
        context.log.warning(
            "skipped %d object(s) with no partition date in the name: %s",
            len(skipped),
            ", ".join(skipped),
        )
    if not requests:
        return dg.SkipReason("new objects carried no parseable partition date")
    return requests
