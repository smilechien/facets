library(shiny)
library(DT)
library(ggplot2)
library(igraph)
library(scales)

# ------------------------------
# Helpers
# ------------------------------
clean_judge_names <- function(x) {
  x <- trimws(x)
  x <- sub('^[0-9]+\\s+', '', x)
  x
}

prepare_input <- function(df) {
  if (ncol(df) < 2) stop('The uploaded CSV must contain one ID column and at least two judge columns.')
  perf_id <- as.character(df[[1]])
  judge_df <- df[-1]
  names(judge_df) <- clean_judge_names(names(judge_df))
  judge_df[] <- lapply(judge_df, function(z) as.numeric(as.character(z)))
  judge_df <- judge_df[, colSums(!is.na(judge_df)) > 0, drop = FALSE]
  if (ncol(judge_df) < 2) stop('Need at least two numeric judge columns.')

  # Recode to 0-based categories while preserving ordinal spacing
  vals <- sort(unique(unlist(judge_df)))
  vals <- vals[!is.na(vals)]
  map <- setNames(seq_along(vals) - 1, vals)
  recoded <- as.data.frame(lapply(judge_df, function(z) unname(map[as.character(z)])))

  list(perf_id = perf_id, raw = judge_df, recoded = recoded, map = map)
}

compute_std_residuals <- function(resp_df) {
  X <- as.matrix(resp_df)
  rownames(X) <- rownames(resp_df)
  colnames(X) <- colnames(resp_df)

  # Package-free Rasch-style approximation:
  # expected = grand mean + performance effect + judge effect
  grand <- mean(X, na.rm = TRUE)
  row_eff <- rowMeans(X, na.rm = TRUE) - grand
  col_eff <- colMeans(X, na.rm = TRUE) - grand
  E <- outer(row_eff, col_eff, FUN = '+') + grand

  # keep expected values inside observed category range
  min_x <- min(X, na.rm = TRUE)
  max_x <- max(X, na.rm = TRUE)
  E <- pmax(min_x, pmin(max_x, E))

  R <- X - E
  sd_r <- stats::sd(as.vector(R), na.rm = TRUE)
  if (!is.finite(sd_r) || sd_r == 0) sd_r <- 1
  Z <- R / sd_r

  list(expected = E, residual = R, std_residual = Z)
}

compute_sh_from_stdres <- function(stdres_mat) {
  cor_mat <- suppressWarnings(cor(stdres_mat, use = 'pairwise.complete.obs', method = 'pearson'))
  W <- abs(cor_mat)
  diag(W) <- 0
  W[is.na(W)] <- 0
  rs <- rowSums(W)
  rs[rs == 0] <- 1
  P <- W / rs
  C <- (P + P %*% P)^2
  SH <- rowSums(C)
  sh_table <- data.frame(judge = rownames(W), SH = as.numeric(SH), row.names = NULL)
  sh_table <- sh_table[order(sh_table$SH, decreasing = TRUE), ]
  list(cor_mat = cor_mat, W = W, P = P, C = C, SH = SH, sh_table = sh_table)
}

bubble_plot_obj <- function(sh_table) {
  sh_table$judge <- factor(sh_table$judge, levels = sh_table$judge)
  ggplot(sh_table, aes(x = judge, y = 1, size = SH, label = sprintf('%.2f', SH))) +
    geom_point(shape = 21, fill = 'skyblue2', color = 'black') +
    geom_text(vjust = -1, color = 'red4', size = 4) +
    scale_size_continuous(range = c(8, 24)) +
    labs(title = 'Structural Holes (SH) Bubble Plot', x = 'Judge', y = NULL) +
    theme_minimal(base_size = 14) +
    theme(axis.text.y = element_blank(),
          axis.ticks.y = element_blank(),
          panel.grid.major.y = element_blank())
}

network_plot_base <- function(Cmat, SHvec, cor_mat, threshold = NULL, show_edge_labels = TRUE, color_mode = c('raw_correlation_sign', 'sh_strength')) {
  color_mode <- match.arg(color_mode)
  Cmat <- as.matrix(Cmat)
  cor_mat <- as.matrix(cor_mat)
  diag(Cmat) <- 0
  diag(cor_mat) <- 0
  if (is.null(threshold)) {
    nz <- Cmat[Cmat > 0]
    threshold <- if (length(nz)) stats::quantile(nz, 0.75, na.rm = TRUE) else 0
  }
  A <- Cmat
  A[A < threshold] <- 0
  g <- graph_from_adjacency_matrix(A, mode = 'directed', weighted = TRUE, diag = FALSE)
  if (ecount(g) == 0) {
    plot.new()
    title('SH Network Plot')
    text(0.5, 0.5, 'No edges above threshold', cex = 1.3)
    return(invisible(NULL))
  }

  V(g)$label <- V(g)$name
  sh_named <- SHvec[V(g)$name]
  sh_named[is.na(sh_named)] <- 0
  V(g)$size <- 18 + 28 * sqrt(sh_named) / max(sqrt(sh_named) + 1e-9)
  E(g)$width <- 1 + 8 * E(g)$weight / max(E(g)$weight)

  ed <- as_edgelist(g, names = TRUE)
  raw_vals <- vapply(seq_len(nrow(ed)), function(k) cor_mat[ed[k, 1], ed[k, 2]], numeric(1))
  raw_vals[!is.finite(raw_vals)] <- 0
  sh_vals <- E(g)$weight

  if (color_mode == 'raw_correlation_sign') {
    # blue = positive residual correlation, red = negative residual correlation
    edge_cols <- ifelse(raw_vals >= 0,
                        alpha('steelblue4', 0.65 + 0.25 * pmin(abs(raw_vals), 1)),
                        alpha('firebrick3', 0.65 + 0.25 * pmin(abs(raw_vals), 1)))
  } else {
    pal_fun <- colorRampPalette(c('grey80', 'orange', 'darkorange3'))
    pal <- pal_fun(100)
    idx <- pmax(1, pmin(100, round(rescale(sh_vals, to = c(1, 100)))))
    edge_cols <- alpha(pal[idx], 0.8)
  }
  E(g)$color <- edge_cols
  if (show_edge_labels) {
    E(g)$label <- sprintf('%.2f', sh_vals)
    E(g)$label.color <- 'black'
    E(g)$label.cex <- 0.9
  } else {
    E(g)$label <- NA
  }

  lay <- layout_in_circle(g)
  plot(g,
       layout = lay,
       vertex.color = 'gold',
       vertex.frame.color = 'black',
       vertex.label.color = 'blue4',
       edge.arrow.size = 0.5,
       main = sprintf('SH Network Plot (threshold = %.3f)', threshold))

  legend('topleft', bty = 'n', cex = 0.9,
         legend = if (color_mode == 'raw_correlation_sign') c('Positive raw residual correlation', 'Negative raw residual correlation', 'Edge label = Cij') else c('Low SH-cell strength', 'High SH-cell strength', 'Edge label = Cij'),
         col = if (color_mode == 'raw_correlation_sign') c('steelblue4', 'firebrick3', 'black') else c('grey70', 'darkorange3', 'black'),
         lwd = c(3, 3, 0), pch = c(NA, NA, NA))
}

sample_path <- '/mnt/data/2002judgeSH.csv'

ui <- fluidPage(
  titlePanel('Judge SH App (No mirt / No SimDesign)'),
  tags$p('Upload a CSV with one performance ID column and judge-score columns. This app uses a package-free Rasch-style standardized residual approximation, then computes judge-level SH values. In the network plot, edge labels show Cij values. Edge colors can represent either raw residual-correlation sign or SH-cell strength.'),
  sidebarLayout(
    sidebarPanel(
      fileInput('file', 'Upload input CSV', accept = c('.csv')),
      checkboxInput('use_sample', 'Use bundled sample file (2002judgeSH.csv) when no upload', TRUE),
      sliderInput('edge_q', 'Network edge threshold quantile', min = 0, max = 1, value = 0.75, step = 0.05),
      checkboxInput('show_edge_labels', 'Show edge labels (Cij)', TRUE),
      radioButtons('edge_color_mode', 'Edge color meaning',
                   choices = c('Raw residual correlation sign' = 'raw_correlation_sign',
                               'SH-cell strength' = 'sh_strength'),
                   selected = 'raw_correlation_sign'),
      actionButton('run', 'Run analysis', class = 'btn-primary'),
      hr(),
      downloadButton('dl_sh', 'Download SH table'),
      downloadButton('dl_resid', 'Download standardized residuals'),
      downloadButton('dl_cor', 'Download judge residual correlation'),
      downloadButton('dl_cij', 'Download Cij matrix')
    ),
    mainPanel(
      tabsetPanel(
        tabPanel('SH table', br(), DTOutput('sh_table')),
        tabPanel('Bubble plot', br(), plotOutput('bubble_plot', height = '520px')),
        tabPanel('Network plot', br(), plotOutput('network_plot', height = '720px')),
        tabPanel('Residual correlation', br(), DTOutput('cor_table')),
        tabPanel('Residuals', br(), DTOutput('resid_table'))
      )
    )
  )
)

server <- function(input, output, session) {
  analysis <- eventReactive(input$run, {
    path <- NULL
    if (!is.null(input$file)) {
      path <- input$file$datapath
    } else if (isTRUE(input$use_sample) && file.exists(sample_path)) {
      path <- sample_path
    } else {
      stop('Please upload a CSV file or enable the bundled sample file option.')
    }

    df <- read.csv(path, check.names = FALSE)
    prep <- prepare_input(df)
    rownames(prep$recoded) <- prep$perf_id
    res <- compute_std_residuals(prep$recoded)
    sh <- compute_sh_from_stdres(res$std_residual)

    list(
      perf_id = prep$perf_id,
      raw = prep$raw,
      recoded = prep$recoded,
      expected = res$expected,
      std_residual = res$std_residual,
      sh = sh
    )
  })

  output$sh_table <- renderDT({
    datatable(analysis()$sh$sh_table, rownames = FALSE, options = list(pageLength = 15))
  })

  output$cor_table <- renderDT({
    cm <- round(analysis()$sh$cor_mat, 4)
    datatable(data.frame(judge = rownames(cm), cm, check.names = FALSE), rownames = FALSE,
              options = list(pageLength = 12, scrollX = TRUE))
  })

  output$resid_table <- renderDT({
    Z <- round(analysis()$std_residual, 4)
    datatable(data.frame(performance = rownames(Z), Z, check.names = FALSE), rownames = FALSE,
              options = list(pageLength = 12, scrollX = TRUE))
  })

  output$bubble_plot <- renderPlot({
    bubble_plot_obj(analysis()$sh$sh_table)
  })

  output$network_plot <- renderPlot({
    sh <- analysis()$sh
    nz <- sh$C[sh$C > 0]
    thr <- if (length(nz)) as.numeric(stats::quantile(nz, input$edge_q, na.rm = TRUE)) else 0
    network_plot_base(sh$C, sh$SH, sh$cor_mat, threshold = thr, show_edge_labels = input$show_edge_labels, color_mode = input$edge_color_mode)
  })

  output$dl_sh <- downloadHandler(
    filename = function() 'judge_SH_table.csv',
    content = function(file) write.csv(analysis()$sh$sh_table, file, row.names = FALSE)
  )

  output$dl_resid <- downloadHandler(
    filename = function() 'judge_std_residuals.csv',
    content = function(file) {
      Z <- analysis()$std_residual
      write.csv(data.frame(performance = rownames(Z), Z, check.names = FALSE), file, row.names = FALSE)
    }
  )

  output$dl_cor <- downloadHandler(
    filename = function() 'judge_std_residual_cor.csv',
    content = function(file) write.csv(round(analysis()$sh$cor_mat, 6), file)
  )

  output$dl_cij <- downloadHandler(
    filename = function() 'judge_Cij_matrix.csv',
    content = function(file) write.csv(round(analysis()$sh$C, 6), file)
  )
}

shinyApp(ui, server)
