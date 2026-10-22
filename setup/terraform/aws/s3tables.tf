# ---------------------------------------------------------------------------
# AWS S3 Tables — for Chapter 2, Section 4.2
# ---------------------------------------------------------------------------

resource "aws_s3tables_table_bucket" "medcore" {
  name = "medcore-s3tables-${var.bucket_suffix}"

  lifecycle {
    ignore_changes = [encryption_configuration]
  }
}

resource "aws_s3tables_namespace" "medcore" {
  namespace        = "medcore_namespace"
  table_bucket_arn = aws_s3tables_table_bucket.medcore.arn
}

resource "aws_s3tables_table" "genomic_variants" {
  name             = "genomic_variants"
  namespace        = aws_s3tables_namespace.medcore.namespace
  table_bucket_arn = aws_s3tables_table_bucket.medcore.arn
  format           = "ICEBERG"
}
