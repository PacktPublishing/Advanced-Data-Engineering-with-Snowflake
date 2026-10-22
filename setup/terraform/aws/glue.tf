# ---------------------------------------------------------------------------
# AWS Glue catalog — for Chapter 2, Sections 2.5, 2.6, 3.4
# ---------------------------------------------------------------------------

resource "aws_glue_catalog_database" "clinical_research" {
  name = "clinical_research"
}

resource "aws_glue_catalog_table" "genomic_variants" {
  name          = "genomic_variants"
  database_name = aws_glue_catalog_database.clinical_research.name

  table_type = "EXTERNAL_TABLE"

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = "2"
    }
  }

  storage_descriptor {
    location = "s3://${aws_s3_bucket.medcore_lakehouse.id}/iceberg/clinical_research/genomic_variants/"

    columns {
      name = "variant_id"
      type = "string"
    }
    columns {
      name = "gene_name"
      type = "string"
    }
    columns {
      name = "chromosome"
      type = "string"
    }
    columns {
      name = "position"
      type = "bigint"
    }
    columns {
      name = "ref_allele"
      type = "string"
    }
    columns {
      name = "alt_allele"
      type = "string"
    }
    columns {
      name = "clinical_significance"
      type = "string"
    }
    columns {
      name = "review_status"
      type = "string"
    }
  }
}
