library(tidyverse)
library(data.table)
library(BuenColors)
library(cowplot)
library(GenomicRanges)
"%ni%" <- Negate("%in%")

towrite <- T
trait <- "MPN_arraycovar_meta_finngen_r4"

# Read in all fine-mapped SNPs
abf_all.df <- fread(paste0("../data/abf_finemap/",trait,"_abf_cojo_all.bed"))
names(abf_all.df) <- c("seqnames","start","end","PP","region","var","rsid")

# Merge with summary statistic p-values
sumstats <- "file path to MPN summary statistics"
metal <- fread(sumstats)
colnames(metal) <- tolower(colnames(metal))
abf.merged <- merge(abf_all.df, metal, by="rsid") 
abf.merged <- abf.merged %>% dplyr::select(-markername) %>% 
  dplyr::select(seqnames,start,end,PP,var,rsid,everything()) %>% arrange(region, desc(PP))

# Look at variants in more than 1 region
abf_all.df %>% filter(PP>0.01) %>%
  group_by(var) %>% filter(n() > 1) %>% arrange(seqnames,start,region)

# Write table of fine-mapped variants merged with summary statistics
if (towrite){
  write.table(abf.merged,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_all.sumstats.tsv"),
              quote = FALSE, sep = "\t", col.names = T, row.names = F)
}

# Create n% credible sets
threshold = 0.95
lapply(unique(abf.merged$region),function(i){
  region <- abf.merged %>% filter(region== i,PP>0)  %>% arrange(desc(PP)) %>% 
    mutate(region_rank = row_number())
  # If the first SNP has PP>0.95, then return just that SNP
  if (region[1,]$PP >= threshold){
    return(region[1,])
  } else{
    ix <- max(which(cumsum(region$PP) <= threshold))
    max_idx <- ifelse(ix == nrow(region),ix,ix+1)
    return(region[1:max_idx,])
  }
}) %>% rbindlist() -> CS.df

# Read in sentinels 
sentinels <- fread("../data/meta-gwas/sentinels/MPN_arraycovar_meta_finngen_r4_gcta_cojo_combined.1e-6.txt") %>%
  dplyr::select(Chr,SNP,bp,refA,freq,b,se,p)
# Merge sentinel list with CS sizes
sentinels$CS <- as.integer(table(CS.df$region))

# Median size of CS
summary(sentinels$CS)

# Add sentinel column to CS
CS.df <- CS.df %>% mutate(sentinel = ifelse(rsid %in% sentinels$SNP,"yes","no"))
abf.merged <- abf.merged %>% mutate(sentinel = ifelse(rsid %in% sentinels$SNP,"yes","no"))

# Add columns to PP001 list
PP001 <- fread(paste0("../data/abf_finemap/",trait,"_abf_cojo_PP0.001.bed")) %>% 
  setNames(.,c("seqnames","start","end","PP","region","var","rsid"))
abf.merged <- abf.merged %>% filter(PP>0) %>% group_by(region) %>% arrange(desc(PP)) %>% 
  mutate(region_rank = row_number()) %>% ungroup() %>% arrange(region,region_rank)

PP001.merged <- merge(PP001,abf.merged %>% dplyr::select(var,region,effect,stderr,pvalue,maf,region_rank,sentinel),by=c("var","region"))

if (towrite){
  # Write PP001 with sumstats
  write.table(PP001.merged,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_PP0.001_annotated.bed"),
              quote = FALSE, sep = "\t", col.names = T, row.names = F)
  
  # Write table of CS variants
  write.table(CS.df,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_",100*threshold,"CS.bed"),
              quote = FALSE, sep = "\t", col.names = T, row.names = F)
  
  # Write CS RSIDs
  write.table(CS.df$rsid,file=paste0("../data/abf_finemap/",trait,"_abf_cojo_",100*threshold,"CS_snps.txt"),
              quote = FALSE, sep = "\t", col.names = F, row.names = F)
  
  # Write sentinel file with CS
  write.table(sentinels,file=paste0("../data/meta-gwas/sentinels/",trait,".cojo.suggestive_loci.withsentinels.tsv"),
              quote = FALSE, sep = "\t", col.names = TRUE, row.names = F)
}
