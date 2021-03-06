#This script will read in ASV tables, and their associated taxonomy, to generate
#sample groups for co-occurrence network generation.

rm(list = ls())
wd <- "~/Desktop/SCCWRP/Metagenomics"
#On the cluster wd <- "/home/cmb-07/sn1/alsimons/SCCWRP/Metagenomics"
setwd(wd)

#Get all taxonomic file names.
ASVFiles <- Sys.glob("*TableWithTaxonomy.txt")
#Get all ASV tables.
TaxonomyFiles <- Sys.glob("*Taxonomy.tsv")

#Read in ASV tables and taxonomy data.
TaxonomyRaw <- read.table(TaxonomyFiles[1], quote="", header=TRUE, sep="\t",as.is=T,skip=0,fill=TRUE,check.names=FALSE, encoding = "UTF-8")
ASVRaw <-read.table(ASVFiles[1], quote="", header=TRUE, sep="\t",as.is=T,skip=0,fill=TRUE,check.names=FALSE, encoding = "UTF-8")

#Fiter taxonomy data by confidence levels.
Taxonomy <- subset(TaxonomyRaw,confidence==1)
ASV <- subset(ASVRaw,ASVRaw$`OTU ID` %in% Taxonomy$OTUID)

