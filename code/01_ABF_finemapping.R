library(BuenColors)
library(data.table)
library(GenomicRanges)
library(reshape2)
library(ComplexHeatmap)
library(matrixStats)
library(SummarizedExperiment)
library(Matrix)
library(preprocessCore)
library(tidyverse)
library(qvalue)
library(gtools)
library(gtx)

effective_n <- function(cases,controls){
  return(4*cases*controls/(cases+controls))
}

ukbb_n <- effective_n(cases=1086,controls=407155)
hinds_n <- effective_n(cases=1223,controls=252140)
finngen_n <- effective_n(cases=640,controls=176259)

towrite <- TRUE

# Perform ABF fine-mapping ----------------------------------------------------
trait <- "MPN_arraycovar_meta_finngen_r4"
p_thresh <- "1e-6"
# From GCTA COJO sentinels, accounting for nearby conditional variants
all_cojo <- fread(cmd=paste0("zcat < ../data/abf_finemap/COJO_zscores/",trait,".",p_thresh,".allregions.annotated.txt.gz")) %>%
  arrange(region,desc(abs(logodds)))

# Wakefield formula: abf.Wakefield
# Split into different dataframes
z_scores <- lapply(seq(1,length(unique(all_cojo$region))), function(y){
  temp <- all_cojo %>% dplyr::filter(region == y)
  return(temp)
})

# Calculate BFs
for (i in 1:length(z_scores)){
  z_scores[[i]]$abf <- abf.Wakefield(z_scores[[i]]$logodds,z_scores[[i]]$stderr,
                                     priorsd = sqrt(w))

  # Add label for region
  z_scores[[i]]$region <- i
}

# Calculate PPs
for (i in 1:length(z_scores)){
  # Remove rows with NA entry in logodds
  z_scores[[i]] <- z_scores[[i]][complete.cases(z_scores[[i]]$logodds),]
  
  z_scores[[i]]$PP <- sapply(z_scores[[i]]$abf,function(y){
    round(y / sum(z_scores[[i]]$abf),4)
  })
  
  z_scores[[i]] <- z_scores[[i]] %>% arrange(desc(PP)) %>% as_tibble()
}

# Collapse into 1 file suitable for being read as Granges object, filtering on PP>0.001
CS.abf.df <- rbindlist(z_scores,fill=TRUE) %>% 
  dplyr::arrange(chr, pos) %>%
  dplyr::rename(start=pos) %>%
  mutate(start=as.numeric(start),end=start+1,seqnames=paste0("chr",chr)) %>%
  dplyr::select(seqnames,start,end,PP,region,var,rsid) %>%
  dplyr::filter(PP>0.001) %>% 
  arrange(region,desc(PP))

if (towrite){
  write.table(CS.abf.df,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_PP0.001.bed"),
              quote = FALSE, sep = "\t", col.names = F, row.names = F)
  write.table(CS.abf.df,file=paste0("../data/abf_finemap/",trait,"_duplicate_abf_cojo_PP0.001.bed"),
              quote = FALSE, sep = "\t", col.names = F, row.names = F)
}

# All
CS.abf.df <- rbindlist(z_scores,fill=TRUE) %>% 
  dplyr::arrange(chr, pos) %>%
  dplyr::rename(start=pos) %>%
  mutate(start=as.numeric(start),end=start+1,seqnames=paste0("chr",chr)) %>%
  dplyr::select(seqnames,start,end,PP,region,var,rsid) %>% 
  arrange(region,desc(PP))

if (towrite){
  write.table(CS.abf.df,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_all.bed"),
              quote = FALSE, sep = "\t", col.names = T, row.names = F)
}
