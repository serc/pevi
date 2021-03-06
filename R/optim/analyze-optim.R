library(colinmisc)
Sys.setenv(NOAWT=1)
load.libraries(c('yaml','stringr','RNetLogo','maptools','reshape','colorRamps','ggplot2'))

#base.path <- '/Users/sheppardc/Dropbox/serc/pev-colin/'
base.path <- '/Users/critter/Dropbox/serc/pev-colin/'
path.to.pevi <- paste(base.path,'pevi/',sep='')
path.to.inputs <- paste(base.path,'pev-shared/data/inputs/optim/',sep='')
path.to.outputs <- paste(base.path,'pev-shared/data/outputs/optim/',sep='')
path.to.google <- paste(base.path,'pev-shared/data/google-earth/',sep='')
path.to.geatm <- paste(base.path,'pev-shared/data/GEATM-2020/',sep='')
nl.path <- "/Applications/NetLogo\ 5.0.3"
model.path <- paste(path.to.pevi,"netlogo/PEVI-nolog.nlogo",sep='')

#optim.code <- 'min-cost-constrained-by-frac-delayed'
#optim.code <- 'min-cost-constrained-by-frac-stranded'
#optim.code <- 'min-cost-constrained-by-frac-stranded-50-50'
#optim.code <- 'min-cost-constrained-by-num-stranded'
optim.code <- 'min-frac-stranded-constrained-by-cost-50-50'

hard.code.coords <- read.csv(paste(path.to.google,"hard-coded-coords.csv",sep=''),stringsAsFactors=F)
source(paste(path.to.pevi,'R/gis-functions.R',sep=''))
source(paste(path.to.pevi,"R/optim/optim-functions.R",sep='')) 
source(paste(path.to.pevi,"R/optim/optim-config.R",sep=''))
source(paste(path.to.pevi,"R/optim/objectives.R",sep=''))
source(paste(path.to.pevi,"R/optim/constraints.R",sep=''))
source(paste(path.to.pevi,"R/reporters-loggers.R",sep=''))

# load aggregated tazs
agg.taz <- readShapePoly(paste(path.to.google,'aggregated-taz-with-weights/aggregated-taz-with-weights',sep=''),IDvar="ID")
load(paste(path.to.google,'aggregated-taz-with-weights/aggregated-taz-with-weights-fieldnames.Rdata',sep=''))
names(agg.taz@data) <- c("SP_ID",taz.shp.fieldnames)

# load dist times
dist <- read.csv(file=paste(path.to.geatm,'taz-dist-time.csv',sep=''))
names(dist)[1] <- "from"

# save paths needed in this loop
optim.code.save <- optim.code
base.path.save <- base.path

for(pev.penetration in c(0.005,0.01,0.02,0.04)){
  #pev.penetration <- 0.02
  load(paste(path.to.outputs,optim.code,"/0saved-state-pen",pev.penetration*100,".Rdata",sep=''))
  optim.code <- optim.code.save
  path.to.outputs <- paste(base.path.save,'pev-shared/data/outputs/optim/',sep='')

  final.gen <- gen.num - 1
  ptx.m <- melt(data.frame(ptx=1:(nrow(all.ptx[,,1])),all.ptx[,1:(ncol(all.ptx[,,1])-1),final.gen]),id.vars=c("ptx"))
  ptx.m$taz <- as.numeric(unlist(lapply(strsplit(substr(as.character(ptx.m$variable),2,nchar(as.character(ptx.m$variable))-1),".",fixed=T),function(x){ x[[1]] })))
  ptx.m$level <- as.numeric(unlist(lapply(strsplit(as.character(ptx.m$variable),"L",fixed=T),function(x){ x[2] })))
  ptx.m$name <- agg.taz$name[match(ptx.m$taz,agg.taz$id)]

  tot.by.taz <- ddply(ptx.m,.(taz),function(df){
                     sum.weights <- rep(1,nrow(df))
                     sum.weights[df$level==3] <- 2
                     data.frame(charger.score=2*mean(df$value*sum.weights),L2=median(df$value[df$level==2]),L3=median(df$value[df$level==3]))})
  tot.by.taz$name <- agg.taz$name[match(tot.by.taz$taz,agg.taz$id)]
  tot.to.plot <- melt(tot.by.taz,id.vars=c('taz','name'),measure.vars=c('L2','L3'))
  tot.to.plot$order <- match(1:nrow(tot.to.plot),order(tot.by.taz$charger.score[match(tot.to.plot$taz,tot.by.taz$taz)],decreasing=T))
  tot.to.plot$name <- reorder(tot.to.plot$name,tot.to.plot$order)
  p <- ggplot(tot.to.plot,aes(x=factor(""),y=value,fill=variable))+geom_bar(stat='identity')+facet_wrap(~name)
  
  agg.taz@data$L2 <- tot.by.taz$L2[match(agg.taz$id,tot.by.taz$taz)]
  agg.taz@data$L3 <- tot.by.taz$L3[match(agg.taz$id,tot.by.taz$taz)]
  agg.taz@data$charger.score <- tot.by.taz$charger.score[match(agg.taz$id,tot.by.taz$taz)]
  agg.taz@data$weighted.demand <- roundC(agg.taz@data$weighted.demand,0)
  agg.taz@data$frac.homes <- roundC(agg.taz@data$frac.homes,3)
  c.map <- paste(map.color(agg.taz@data$charger.score,blue2red(50)),'7F',sep='')
  c.map <- paste(map.color(as.numeric(agg.taz$weighted.demand),blue2red(50)),'7F',sep='')
  chargers.to.kml(agg.taz,paste(path.to.google,'optim/',optim.code,'-pen',100*pev.penetration,'.kml',sep=''),paste('Chargers: Pen ',100*pev.penetration,'% Optimization: ',optim.code,sep=''),'Color denotes total chargers in each TAZ with L3 counting for 2 chargers (click to get actual # chargers).','red',1.5,c.map,id.col='ID',name.col='name',description.cols=c('id','name','L2','L3','weighted.demand','frac.homes'))
  demand.to.kml(agg.taz,150e3 * pev.penetration,paste(path.to.google,'optim/num-pevs-pen',100*pev.penetration,'.kml',sep=''),paste('Demand: Pen ',100*pev.penetration,'% Optimization: ',optim.code,sep=''),'Color denotes total chargers in each TAZ with L3 counting for 2 chargers (click to get actual # chargers). Icon displays the number of electric vehicles native to the TAZ. Icon image courtesy of Danilo Rizzuti / FreeDigitalPhotos.net','black',1.5,c.map,id.col='ID',name.col='name',description.cols=c('id','name','L2','L3','weighted.demand','frac.homes'))
  to.csv <- agg.taz@data[,c('id','name','L2','L3')]
  to.csv$cost <- 8 * to.csv$L2 + 50 * to.csv$L3
  to.csv$power <- 6.6 * to.csv$L2 + 30 * to.csv$L3
  write.csv(to.csv,file=paste(path.to.google,'optim/',optim.code,'-mean-of-ptx-pen',100*pev.penetration,'.csv',sep=''),row.names=F)
  agg.taz@data$L2 <- all.ptx[which.min(all.ptx[,'fitness',final.gen]),(1:52)[agg.taz$id],final.gen]
  agg.taz@data$L3 <- all.ptx[which.min(all.ptx[,'fitness',final.gen]),(53:104)[agg.taz$id],final.gen]
  to.csv <- agg.taz@data[,c('id','name','L2','L3')]
  #to.csv$cost <- 8 * to.csv$L2 + 50 * to.csv$L3
  #to.csv$power <- 6.6 * to.csv$L2 + 30 * to.csv$L3
  # min distances between chargers
  l2.l3.tazs <- agg.taz$id[which(agg.taz@data$L2>0 | agg.taz@data$L3>0)]
  for(taz.id in agg.taz$id){ 
    to.csv$min.dist.to[which(to.csv$id==taz.id)] <- min(subset(dist,from==taz.id & to%in%l2.l3.tazs[l2.l3.tazs != taz.id])$miles) 
  }
  to.csv$l2.per.trip <- agg.taz$weighted.demand*pev.penetration / agg.taz$L2
  to.csv$l3.per.trip <- agg.taz$weighted.demand*pev.penetration / agg.taz$L3
  to.csv$l2.per.trip[to.csv$l2.per.trip == Inf] <- NA
  to.csv$l3.per.trip[to.csv$l3.per.trip == Inf] <- NA

  write.csv(to.csv,file=paste(path.to.google,'optim/',optim.code,'-min-ptx-pen',100*pev.penetration,'.csv',sep=''),row.names=F)
}

agg.taz$long <- coordinates(agg.taz)[,1]
agg.taz$lat  <- coordinates(agg.taz)[,2]

