# Legacy migration reference

This directory preserves the earlier schemachange example for review history.
It is not part of the current Chapter 10 exercise and is not called by CI.
Do not run it alongside the native stream script or add it back to the pipeline.

The old migration creates the Chapter 9 audit table and shared stream. Chapter 9
already supplies the audit table, and the current Chapter 10 workflow uses
`native/streams.sql` for the stream. A new account must complete Chapter 9 first.
The example remains here to avoid rewriting an applied migration or losing old
review references; use a separate migration project if studying that approach.
