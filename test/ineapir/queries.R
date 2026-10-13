# Queries run with the official ineapir R package. Their results are compared
# with the ones of Inex by test/ineapir/cross_check_test.exs.
#
# Usage (from the project root):
#
#   docker build -t inex-ineapir test/ineapir
#   docker run --rm -v "$PWD/test/ineapir:/work" inex-ineapir Rscript queries.R output
#
# Every query writes a JSON file (one object per data frame row) in the output dir.

library(ineapir)
library(jsonlite)

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) > 0) args[[1]] else "output"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

save <- function(name, df) {
  write_json(df, file.path(out, paste0(name, ".json")),
             dataframe = "rows", na = "null", null = "null",
             auto_unbox = TRUE, digits = NA, pretty = TRUE)
  cat(sprintf("%-28s %6d rows\n", name, if (is.null(nrow(df))) length(df) else nrow(df)))
}

px_table <- "t20/e245/p08/l0/01001.px"

# Data ------------------------------------------------------------------------

save("series_ipc290750",
     get_data_series(codSeries = "IPC290750", nlast = 24, tip = "A", unnest = TRUE, validate = FALSE))

save("series_epa452434_range",
     get_data_series(codSeries = "EPA452434", dateStart = "2020/01/01", dateEnd = "2024/12/31",
                     tip = "A", unnest = TRUE, validate = FALSE))

save("series_cntr6654_dates",
     get_data_series(codSeries = "CNTR6654", dateStart = c("2019/01/01", "2023/01/01"),
                     dateEnd = c("2019/12/31", "2023/12/31"), tip = "A", unnest = TRUE, validate = FALSE))

save("table_76136",
     get_data_table(idTable = 76136, filter = list("3" = "74", "762" = "304092", "70" = ""),
                    nlast = 3, tip = "AM", unnest = TRUE, metanames = TRUE, validate = FALSE))

save("table_px",
     get_data_table(idTable = px_table,
                    filter = list(sexo = "", espanolesextranjeros = "espanoles", edad3gruposdeedad = "totaledades"),
                    nlast = 3, tip = "A", unnest = TRUE, validate = FALSE))

save("table_tpx",
     get_data_table(idTable = 33387, filter = list(tipodematerial = c("1biomasa", "2mineralesmetalicosmineralenbruto")),
                    nlast = 2, tip = "A", unnest = TRUE, validate = FALSE))

save("series_filter_ipc",
     get_data_series_filter(operation = "IPC", filter = list("115" = "", "3" = "74", "762" = "304092"),
                            periodicity = 1, nlast = 2, tip = "A", unnest = TRUE, validate = FALSE))

# Metadata --------------------------------------------------------------------

save("operations", get_metadata_operations(validate = FALSE))
save("operation_ipc", get_metadata_operations(operation = "IPC", validate = FALSE))
save("variables_ipc", get_metadata_variables(operation = "IPC", validate = FALSE))
save("values_ipc_762", get_metadata_values(operation = "IPC", variable = 762, validate = FALSE))
save("values_115", get_metadata_values(variable = 115, validate = FALSE))
save("children_70_9008", get_metadata_values(variable = 70, value = 9008, validate = FALSE))
save("tables_ipc", get_metadata_tables_operation(operation = "IPC", validate = FALSE))
save("table_groups_76136", get_metadata_table_groups(idTable = 76136, validate = FALSE))
save("table_varval_76136", get_metadata_table_varval(idTable = 76136, validate = FALSE))
save("table_varval_px", get_metadata_table_varval(idTable = px_table, validate = FALSE))
save("series_table_76136", get_metadata_series_table(idTable = 76136, validate = FALSE))
save("series_ipc290750_meta", get_metadata_series(codSeries = "IPC290750", validate = FALSE))
save("series_values_ipc290750", get_metadata_series_values(codSeries = "IPC290750", validate = FALSE))
save("series_filter_meta_ipc",
     get_metadata_series_filter(operation = "IPC", filter = list("115" = "", "3" = "74", "762" = "304092"),
                                periodicity = 1, validate = FALSE))
save("publications_ipc", get_metadata_publications(operation = "IPC", validate = FALSE))
save("publication_dates_8", get_metadata_publication_dates(publication = 8, validate = FALSE))
save("periodicities", get_metadata_periodicity(validate = FALSE))
save("periodicities_ipc", get_metadata_periodicity(operation = "IPC", validate = FALSE))
save("classifications", get_metadata_classifications(validate = FALSE))
save("classifications_ipc", get_metadata_classifications(operation = "IPC", validate = FALSE))
save("operation_table_76136", get_metadata_operation_table(idTable = 76136, validate = FALSE))
