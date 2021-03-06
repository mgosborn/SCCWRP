library("plyr")
library(dplyr)
library("ggplot2")
library(lubridate)
library("ape")
library("vegan")
library("microbiome")
library(data.table)
library(tidyr)

setwd("~/Desktop/SCCWRP")
#Read in site data containing biological and land usage
#values.  If this file is not yet generated then proceed with the following commands
#to generate it in the first place.
GISBioData <- read.table("GISBioData.csv", header=TRUE, sep=",",as.is=T,skip=0,fill=TRUE,check.names=FALSE)

#Get number of unique samples.
sitesNum <- length(unique(GISBioData$UniqueID))
#Enter number of divisions for subsampling.
divisionNum = 3
#Enter the percent land coverage band size.
divisionSize = 5

for(i in 1:divisionNum){
  GISBioData <- read.table("GISBioData.csv", header=TRUE, sep=",",as.is=T,skip=0,fill=TRUE,check.names=FALSE)
  if(i==1){
    GISBioDataSubset <- subset(GISBioData,LU_2011_5K<divisionSize*i)
  }
  if(i==2){
    GISBioDataSubset <- subset(GISBioData,LU_2011_5K<3*divisionSize*i & LU_2011_5K>=divisionSize*i)
  }
  if(i==divisionNum){
    GISBioDataSubset <- subset(GISBioData,LU_2011_5K>=3*divisionSize*i)
  }
  #Determine the average land usage (5km buffer) per subsample of sites.
  meanLU = mean(na.omit(GISBioDataSubset$LU_2011_5K))
  #Initialize a data frame where the rows are all of the unique measurements for a given
  #subset of the data.
  #Order the data frame by measurement name.
  selected <- arrange(GISBioDataSubset,Year,UniqueID)
  eLSAInput <- as.data.frame(unique(selected$FinalID))
  colnames(eLSAInput)<-c("FinalID")
  eLSAInput <- as.data.frame(eLSAInput[order(as.character(eLSAInput$FinalID)),])
  colnames(eLSAInput)<-c("FinalID")
  
  #Add the relative taxa abundances by column to a new dataframe.
  #The rows are the unique taxa in a given subset of data.
  selected <- selected[order(selected$Year,selected$UniqueID,selected$FinalID),]
  for(ID in unique(selected$UniqueID)){
    tmp <- filter(selected, UniqueID == ID)[,c("FinalID","Measurement","UniqueID")]
    tmp <- as.data.frame(tmp[order(tmp$FinalID),])
    tmp <- tmp[-c(3)] #Remove UniqueID from temporary dataframe.
    colnames(tmp)<-c("FinalID",paste("Measurement",ID,sep=" "))
    eLSAInput <- join(eLSAInput,tmp,by="FinalID")
    eLSAInput$FinalID=as.character(eLSAInput$FinalID)
    eLSAInput <- eLSAInput %>% group_by(FinalID) %>% summarise_if(is.numeric,mean,na.rm=TRUE)
    #print(ID)
  }
  
  eLSAInput[is.na(eLSAInput)] <- "NA"
  
  #Determine the number of time points in the eLSA input file.
  spotNum = length(unique(selected$Year))
  #Determine the number of replicates per time point in the eLSA input file.
  #In order to ensure a uniform number of replicates per year this needs to
  #be the maximum number of replicates for all of the years available.
  repMax = 0
  for(year in unique(selected$Year)){
    tmp <- filter(selected, Year == year)[,c(6,7)]
    repNum = length(unique(tmp$UniqueID))
    if(repNum >= repMax){repMax = repNum}
    #print (paste(repMax,repNum,year,sep=" "))
  }
  repNum = repMax
  
  #Now insert the replicates with actual data in between the "NA" dummy columns
  #which ensure that the final eLSA input file has an even number of replicates
  #per year regardless of the variations in the actual number of sites (replicates)
  #sampled per year.
  eLSAtmp <- eLSAInput[,1]
  j=1
  k=1
  nulCol <- data.frame(matrix(ncol=repNum*spotNum,nrow=length(unique(selected$FinalID))))
  nulCol[,1] <- eLSAInput[,1]
  for(year in unique(selected$Year)){
    tmp <- filter(selected, Year == year)
    rep = length(unique(tmp$UniqueID))
    for(i in 1:repNum){
      if(i <= rep){
        repLabel = paste(year,"DoneRep",i,sep="")
        j=j+1
        k=k+1
        eLSAtmp[,k] <- eLSAInput[,j]
      }
      else{
        repLabel = as.character(paste(year,"Rep",i,sep=""))
        k=k+1
        eLSAtmp[,k] <- "NA"
        #print(paste(k,repLabel,sep=" "))
      }
    }
  }
  
  eLSAInput <- eLSAtmp
  
  #Designate a unique filename.
  #N is the number of samples in the subsample group.
  #S is the number of spots, or years represented in the subsample group.
  #R is the number of replicates per year.  Many of the years will have null replicates, but a uniform number is needed for eLSA.
  #M is the mean land usage score, at a 5km clip from 2011 data, per subsample group.
  sampleNum <- length(unique(GISBioDataSubset$UniqueID))
  filename = paste("LUSweep3BandsN",sampleNum,"S",spotNum,"R",repNum,"M",meanLU,sep="")
  
  #Output file for use in eLSA.
  write.table(eLSAInput,paste(filename,".txt",sep=""),quote=FALSE,sep="\t",row.names = FALSE)
  print(filename)
}

#Read in eLSA output.
#Compute network statistics of the likeliest association networks between taxa.
library(igraph)
library(network)
library(stringr)
#Read in site data.
GISBioData <- read.table("GISBioData.csv", header=TRUE, sep=",",as.is=T,skip=0,fill=TRUE,check.names=FALSE)
#Get unique identifiers for algal, invertebrate, and chemical measurement types.
algae <- subset(GISBioData,GISBioData$MeasurementType=="Benthic algal relative abundance" | GISBioData$MeasurementType=="Soft-bodied algal relative abundance")
algaeID <- unique(algae$FinalID)
insect <-subset(GISBioData,GISBioData$MeasurementType=="Invertebrate relative abundances" | GISBioData$MeasurementType=="Invertebrate relative abundance")
insectID <- unique(insect$FinalID)
networkfiles <- Sys.glob("eLSALUSweep3BandsN*.txt")
networkAnalysis <- data.frame()
#Define a 'not in' function.
'%!in%' <- function(x,y)!('%in%'(x,y))
for(networkFile in networkfiles){
  print(networkFile)
  networkdata <- read.delim(networkFile,header=TRUE, sep="\t",as.is=T,check.names=FALSE)
  #Filter out association network data based on P and Q scores, for the local similarity
  #between two factors, with values less than 0.01.
  networkdata <- filter(networkdata, P <= 0.01)
  networkdata <- filter(networkdata, Q <= 0.01)
  names(networkdata)[names(networkdata)=="LS"]<-"weight"
  meanLU <- as.numeric(str_match(networkFile,"M(.*?).txt")[2])
  #Generate network graph and begin calculating network parameters.
  networkgraph=graph.data.frame(networkdata,directed=FALSE)
  if(ecount(networkgraph)>0){
    #Get the full weighted adjacency matrix.
    networkmatrix <- as.matrix(get.adjacency(networkgraph,attr='weight'))
    #Get the eigenvalues of the full weighted adjacency matrix.
    lambda_network <- eigen(networkmatrix)
    #Get the real component first eigenvalue.
    lambda_network_1 <- Re(lambda_network$values[1])
    #Generate randomized version of full weighted adjacency matrix.
    set.seed(1)
    randnetworkmatrix <- matrix(sample(as.vector((networkmatrix))),nrow=nrow(networkmatrix),ncol=ncol(networkmatrix))
    #Get the eigenvalues of the full weighted adjacency matrix.
    lambda_rand <- eigen(randnetworkmatrix)
    #Get the real component of the first eigenvalue.
    lambda_rand_1 <- Re(lambda_rand$values[1])
    #Calculate stability parameter.
    gamma <- lambda_network_1/lambda_rand_1
    #Calculate the degree heterogeneity of the adjacency matrix.
    networkmatrix <- as.matrix(get.adjacency(networkgraph,attr='weight'))
    networkmatrix[upper.tri(networkmatrix)] <- 0
    networkmatrix[which(networkmatrix != 0)] <- 1
    zeta <- mean(colSums(networkmatrix)^2)/mean(colSums(networkmatrix))^2
    #Calculate whole network modularity.
    M <- modularity(cluster_edge_betweenness(networkgraph, weights=NULL,directed=FALSE))
    print(paste(mean(colSums(networkmatrix)^2),mean(colSums(networkmatrix))^2,zeta))
  }
  #Filter contravariant network data based on local similarity scores.
  networkdataCon <- subset(networkdata,networkdata$weight<0)
  #Generate network graph and begin calculating network parameters.
  networkgraphCon=graph.data.frame(networkdataCon,directed=FALSE)
  if(ecount(networkgraphCon)>0){
    # Generate adjacency matrix of relative taxa abundance correlations
    adj= as.network(get.adjacency(networkgraphCon,attr='weight',sparse=FALSE),directed=FALSE,loops=FALSE,matrix.type="adjacency")
    # Get the number of unique network edges
    networkEdgecount <- network.edgecount(adj)
    # Get the number of nodes
    networkNodecount <- network.size(adj)
    # Get the average degree per node.
    k <- (2*networkEdgecount)/networkNodecount
    # Get the random characteristic path length.
    networkRandLength <- 0.5+((log(networkNodecount)-0.5772156649)/log(k))
    # Get the random clustering coefficient.
    networkRandClustering <- k/networkNodecount
    # Get the network density.
    networkDensity <- network.density(adj)
    con_C <- networkDensity
    # Calculate the modularity of the network.
    networkModularity <- modularity(cluster_edge_betweenness(networkgraphCon, weights=NULL,directed=FALSE))
    con_M <- networkModularity
    # Calculate the number of groups related to the modularity value.
    networkModGroups <- length(cluster_edge_betweenness(networkgraphCon, weights=NULL,directed=FALSE))
    # Calculate the average network path length
    networkLength <- mean_distance(networkgraphCon,directed=FALSE)
    con_L <- networkLength
    # Calculate the clustering coefficient
    networkClustering <- transitivity(networkgraphCon,type="globalundirected",isolate="zero")
    con_Cl <- networkClustering
    # Calcuate the log ratio of clustering coefficients.
    l_con_rCl <- log(networkClustering/networkRandClustering)
    # Calculate the modularity of the random network.
    networkRandModularity <- (1-(2/sqrt(networkNodecount)))*(2/k)^(2/3)
    # Calculate the log ratio of the modularities.
    l_con_rM <- log(networkModularity/networkRandModularity)
    # Get log ratio of characteristic path lengths.
    l_con_rL <- log(networkLength/networkRandLength)
  }
  #Filter covariant network data based on local similarity scores.
  networkdataCov <- subset(networkdata,networkdata$weight>0)
  #Generate network graph and begin calculating network parameters.
  networkgraphCov=graph.data.frame(networkdataCov,directed=FALSE)
  if(ecount(networkgraph)>0){
    # Generate adjacency matrix of relative taxa abundance correlations
    adj= as.network(get.adjacency(networkgraphCov,attr='weight',sparse=FALSE),directed=FALSE,loops=FALSE,matrix.type="adjacency")
    # Get the number of unique network edges
    networkEdgecount <- network.edgecount(adj)
    # Get the number of nodes
    networkNodecount <- network.size(adj)
    # Get the average degree per node.
    k <- (2*networkEdgecount)/networkNodecount
    # Get the random characteristic path length.
    networkRandLength <- 0.5+((log(networkNodecount)-0.5772156649)/log(k))
    # Get the random clustering coefficient.
    networkRandClustering <- k/networkNodecount
    # Get the network density.
    networkDensity <- network.density(adj)
    cov_C <- networkDensity
    # Calculate the modularity of the network.
    networkModularity <- modularity(cluster_edge_betweenness(networkgraphCov, weights=NULL,directed=FALSE))
    cov_M <- networkModularity
    # Calculate the number of groups related to the modularity value.
    networkModGroups <- length(cluster_edge_betweenness(networkgraphCov, weights=NULL,directed=FALSE))
    # Calculate the average network path length
    networkLength <- mean_distance(networkgraphCov,directed=FALSE)
    cov_L <- networkLength
    # Calculate the clustering coefficient
    networkClustering <- transitivity(networkgraphCov,type="globalundirected",isolate="zero")
    cov_Cl <- networkClustering
    # Calcuate the log ratio of clustering coefficients.
    l_cov_rCl <- log(networkClustering/networkRandClustering)
    # Calculate the modularity of the random network.
    networkRandModularity <- (1-(2/sqrt(networkNodecount)))*(2/k)^(2/3)
    # Calculate the log ratio of the modularities.
    l_cov_rM <- log(networkModularity/networkRandModularity)
    # Get log ratio of characteristic path lengths.
    l_cov_rL <- log(networkLength/networkRandLength)
  }
  dat <- data.frame()
  dat[1,1] <- networkFile
  dat[1,2] <- meanLU
  dat[1,3] <- l_con_rL
  dat[1,4] <- l_con_rCl
  dat[1,5] <- l_con_rM
  dat[1,6] <- l_cov_rL
  dat[1,7] <- l_cov_rCl
  dat[1,8] <- l_cov_rM
  dat[1,9] <- gamma
  dat[1,10] <- con_L
  dat[1,11] <- con_Cl
  dat[1,12] <- con_M
  dat[1,13] <- cov_L
  dat[1,14] <- cov_Cl
  dat[1,15] <- cov_M
  dat[1,16] <- zeta
  dat[1,17] <- con_C
  dat[1,18] <- cov_C
  dat[1,19] <- M
  networkAnalysis <- rbind(networkAnalysis,dat)
  print(paste(networkFile,meanLU,l_con_rL,l_con_rCl,l_con_rM,l_cov_rL,l_cov_rCl,l_cov_rM,gamma,con_L,con_Cl,con_M,cov_L,cov_Cl,cov_M,zeta,con_C,cov_C,M))
}
colnames(networkAnalysis) <- c("filename","meanLU","l_con_rL","l_con_rCl","l_con_rM","l_cov_rL","l_cov_rCl","l_cov_rM","gamma","con_L","con_Cl","con_M","cov_L","cov_Cl","cov_M","zeta","con_C","cov_C","M")
networkAnalysis[networkAnalysis=="-Inf"] <- NA
networkAnalysis[networkAnalysis=="Inf"] <- NA
networkAnalysis <- arrange(networkAnalysis,meanLU)

#Logistic regression between network parameters
library(PerformanceAnalytics)
library(aod)
library(glmm)
library(rcompanion)
model.vars <- names(networkAnalysis)[c(3:19)]
model.list <- lapply(model.vars, function(x){
  summary(glm(substitute(meanLU ~ i, list(i=as.name(x))),data=networkAnalysis))$coefficients[,c(1:4)]
})
model.list
