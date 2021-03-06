Sys.setenv(NOAWT=1)
options(java.parameters="-Xmx10g")
load.libraries(c('ggplot2','yaml','RNetLogo','plyr','reshape','stringr'))

#exp.name <- commandArgs(trailingOnly=T)[1]
exp.name <- 'delhi-smart-quasi-reopt'
exp.name <- 'delhi-roam-threshold'
exp.name <- 'delhi-test-revised'
path.to.inputs <- pp(pevi.shared,'data/inputs/compare/',exp.name,'/')

#to.log <- c('pain','charging','need-to-charge')
to.log <- c('pain','charging','tazs','trip')
#to.log <- c('pain','charging')

# load the reporters and loggers needed to summarize runs and disable logging
source(paste(pevi.home,"R/reporters-loggers.R",sep=''))

# read the parameters and values to vary in the experiment
vary <- yaml.load(readChar(paste(path.to.inputs,'vary.yaml',sep=''),file.info(paste(path.to.inputs,'vary.yaml',sep=''))$size))
#vary <- yaml.load(readChar(paste(path.to.inputs,'vary-noL1.yaml',sep=''),file.info(paste(path.to.inputs,'vary-noL1.yaml',sep=''))$size))
for(file.param in names(vary)[grep("-file",names(vary))]){
  vary[[file.param]] <- str_replace_all(str_replace_all(str_replace_all(vary[[file.param]],"pevi.home",pevi.home),"pevi.shared",pevi.shared),"pevi.nondrop",pevi.nondrop)
}
naming <- yaml.load(readChar(paste(path.to.inputs,'naming.yaml',sep=''),file.info(paste(path.to.inputs,'naming.yaml',sep=''))$size))

# setup the data frame containing all combinations of those parameter values
vary.tab <- expand.grid(vary,stringsAsFactors=F)

results <- data.frame(vary.tab)
if("driver-input-file" %in% names(vary)){
  results$penetration <- as.numeric(unlist(lapply(strsplit(as.character(results$driver.input.file),'-pen',fixed=T),function(x){ unlist(strsplit(x[2],"-rep",fixed=T)[[1]][1]) })))
  results$replicate <- as.numeric(unlist(lapply(strsplit(as.character(results$driver.input.file),'-rep',fixed=T),function(x){ unlist(strsplit(x[2],"-",fixed=T)[[1]][1]) })))
  results$itin.scenario <- unlist(lapply(strsplit(as.character(results$driver.input.file),'/driver-schedule',fixed=T),function(x){ tail(unlist(strsplit(x[1],"/",fixed=T)[[1]]),1) }))
  results$itin.scenario.named <- results$itin.scenario
  results$itin.scenario.order <- results$itin.scenario
  for(scen.i in names(naming$`driver-input-file`)){
    results$itin.scenario.named[results$itin.scenario == scen.i] <- naming$`driver-input-file`[[scen.i]][[1]]
    results$itin.scenario.order[results$itin.scenario == scen.i] <- as.numeric(naming$`driver-input-file`[[as.character(scen.i)]][[2]])
  }
}
if("charger-input-file" %in% names(vary)){
  results$infrastructure.scenario <- unlist(lapply(strsplit(as.character(results$charger.input.file),'-scen',fixed=T),function(x){ unlist(strsplit(x[2],".txt",fixed=T)) }))
  results$infrastructure.scenario.named <- results$infrastructure.scenario
  results$infrastructure.scenario.order <- results$infrastructure.scenario
  if(all(is.na(results$infrastructure.scenario))){
    for(scen.i in names(naming$`charger-input-file`)){
      results$infrastructure.scenario[grep(scen.i,as.character(results$charger.input.file))] <- scen.i
      results$infrastructure.scenario.named[results$infrastructure.scenario == scen.i] <- naming$`charger-input-file`[[scen.i]][[1]]
      results$infrastructure.scenario.order[results$infrastructure.scenario == scen.i] <- as.numeric(naming$`charger-input-file`[[scen.i]][[2]])
    }
  }else{
    for(scen.i in as.numeric(names(naming$`charger-input-file`))){
      results$infrastructure.scenario.named[results$infrastructure.scenario == scen.i] <- naming$`charger-input-file`[[as.character(scen.i)]][[1]]
      results$infrastructure.scenario.order[results$infrastructure.scenario == scen.i] <- as.numeric(naming$`charger-input-file`[[as.character(scen.i)]][[2]])
    }
  }
  results$infrastructure.scenario.named  <- reorder(factor(results$infrastructure.scenario.named),results$infrastructure.scenario.order)
}
if("vehicle-type-input-file" %in% names(vary)){
  results$vehicle.scenario <- as.numeric(unlist(lapply(strsplit(as.character(results$vehicle.type.input.file),'-scen',fixed=T),function(x){ unlist(strsplit(x[2],".txt",fixed=T)) })))
  results$vehicle.scenario.named <- results$vehicle.scenario
  results$vehicle.scenario.order <- results$vehicle.scenario
  if(all(is.na(results$vehicle.scenario))){
    for(scen.i in names(naming$`vehicle-type-input-file`)){
      results$vehicle.scenario[grep(scen.i,as.character(results$vehicle.type.input.file))] <- scen.i
      results$vehicle.scenario.named[results$vehicle.scenario == scen.i] <- naming$`vehicle-type-input-file`[[scen.i]][[1]]
      results$vehicle.scenario.order[results$vehicle.scenario == scen.i] <- as.numeric(naming$`vehicle-type-input-file`[[scen.i]][[2]])
    }
  }else{
    for(scen.i in as.numeric(names(naming$`vehicle-type-input-file`))){
      results$vehicle.scenario.named[results$vehicle.scenario == scen.i] <- naming$`vehicle-type-input-file`[[as.character(scen.i)]][[1]]
      results$vehicle.scenario.order[results$vehicle.scenario == scen.i] <- as.numeric(naming$`vehicle-type-input-file`[[as.character(scen.i)]][[2]])
    }
  }
}
if(exp.name=='delhi-animation' | exp.name=='delhi-battery-swap' | exp.name=='consistent-vs-quadrupled'){
  results <- subset(results,(penetration==0.5 & infrastructure.scenario=='delhi-final-rec-pen-0.5') | 
                    (penetration==1 & infrastructure.scenario=='delhi-final-rec-pen-1') | 
                    (penetration==2 & infrastructure.scenario=='delhi-final-rec-pen-2') |
                    (penetration==0.5 & infrastructure.scenario=='delhi-final-with-swap-pen-0.5') | 
                    (penetration==1 & infrastructure.scenario=='delhi-final-with-swap-pen-1') | 
                    (penetration==2 & infrastructure.scenario=='delhi-final-with-swap-pen-2') &
                    ((num.simulation.days==2 & itin.scenario=='consistent') |
                    (num.simulation.days==4 & itin.scenario=='quadrupled'))
                    )
}

# start NL
tryCatch(NLStart(nl.path, gui=F),error=function(err){ NA })
model.path <- paste(pevi.home,"netlogo/PEVI-v2.1.2.nlogo",sep='')
NLLoadModel(model.path)

for(cmd in paste('set log-',logfiles,' false',sep='')){ NLCommand(cmd) }
for(cmd in paste('set log-',to.log,' true',sep='')){ NLCommand(cmd) }

logs <- list()
logs[['results']] <- results
for(reporter in names(reporters)){
  logs[['results']][,reporter] <- NA
}

# for every combination of parameters, run the model and capture the summary statistics
for(results.i in 1:nrow(results)){
#results.i <- 1
  cat(paste(results.i,""))
  system('sleep 0.01')
  if(results.i%%10 == 0){
    save(logs,file=paste(path.to.inputs,'logs.Rdata',sep=''))
  }
  NLCommand('clear-all-and-initialize')
  NLCommand('random-seed 1')
  NLCommand(paste('set param-file-base "',pevi.shared,'"',sep=''))
  NLCommand(paste('set parameter-file "',path.to.inputs,'/params.txt"',sep=''))
  NLCommand(paste('set model-directory "',pevi.home,'netlogo/"',sep=''))
  NLCommand('set batch-setup? false')
  NLCommand('read-parameter-file')
  for(param in names(vary.tab)){
    param.dot <- str_replace_all(param,"-",".") 
    if(is.character(vary.tab[1,param])){
      NLCommand(paste('set ',param,' "',results[results.i,param.dot],'"',sep=''))
    }else{
      NLCommand(paste('set ',param,' ',results[results.i,param.dot],'',sep=''))
    }
  }
  if("tazs" %in% to.log)NLCommand('set log-taz-time-interval 5')
  NLCommand('set go-until-time 125')
  NLCommand('setup')

  NLCommand('time:go-until go-until-time')
  logs[['results']][results.i,names(reporters)] <- tryCatch(NLDoReport(1,"",reporter = paste("(sentence",paste(reporters,collapse=' '),")"),as.data.frame=T,df.col.names=names(reporters)),error=function(e){ NA })
  if(results.i == 1){
    outputs.dir <- NLReport('outputs-directory')
    for(logger in to.log){
      tmp <- read.csv(paste(outputs.dir,logger,"-out.csv",sep=''),stringsAsFactors=F)
      logs[[logger]] <- data.frame(results[results.i,],tmp,row.names=1:nrow(tmp))
    }
  }else{
    for(logger in to.log){
      tmp <- read.csv(paste(outputs.dir,logger,"-out.csv",sep=''),stringsAsFactors=F)
      logs[[logger]] <- rbind(logs[[logger]],data.frame(results[results.i,],tmp,row.names=1:nrow(tmp)))
    }
  }
  if(length(grep("animation",path.to.inputs))>0){
    for(logger in to.log){
      file.copy(paste(outputs.dir,logger,"-out.csv",sep=''),paste(outputs.dir,logger,"-out-",results.i,".csv",sep=''))
    }
  }
}
if(length(grep("animation",path.to.inputs))>0){
  for(logger in to.log){
    file.remove(paste(outputs.dir,logger,"-out.csv",sep=''))
  }
}
save(logs,file=paste(path.to.inputs,'logs.Rdata',sep=''))
#load(paste(path.to.inputs,'logs.Rdata',sep=''))

# ANALYZE PAIN
ggplot(logs[['pain']],aes(x=time,y=state.of.charge,colour=pain.type,shape=vehicle.type))+geom_point()+facet_grid(charge.safety.factor~replicate)
ggplot(subset(logs[['pain']],pain.type=="delay"),aes(x=time,y=state.of.charge,colour=pain.type,shape=location))+geom_point()+facet_grid(charge.safety.factor~replicate)
ggplot(subset(logs[['pain']],pain.type=="delay"),aes(x=time,y=state.of.charge,colour=pain.type,label=location))+geom_text()+facet_grid(charge.safety.factor~replicate)
ggplot(subset(logs[['pain']],pain.type=="delay"),aes(x=time,y=state.of.charge,colour=vehicle.type,shape=vehicle.type,label=location))+geom_point()+geom_text(aes(y=state.of.charge+.03))+facet_grid(charge.safety.factor~replicate)

# CHARGING
ggplot(subset(logs[['charging']],charger.level>0),aes(x=time,y=begin.soc,colour=factor(charger.level)))+geom_point()+facet_grid(charge.safety.factor~replicate)

# ANALYZE charger availability
ggplot(melt(subset(logs[['tazs']],replicate==1 & charge.safety.factor==1),id.vars=c("time","taz","replicate","charge.safety.factor"),measure.vars=c(paste("num.avail.L",1:3,sep=''))),aes(x=time,y=value,colour=variable))+geom_line()+facet_wrap(~taz)

ggplot(melt(subset(logs[['tazs']],replicate==1),id.vars=c("time","taz","replicate","charge.safety.factor"),measure.vars=c(paste("num.avail.L",1:3,sep=''))),aes(x=time,y=value,colour=variable))+
geom_line()+facet_grid(charge.safety.factor~taz)

# NEED TO CHARGE
ggplot(subset(logs[['need-to-charge']],need.to.charge.=="true"),aes(x=time,y=soc,colour=calling.event,shape=vehicle.type))+geom_point()+facet_grid(charge.safety.factor~replicate)
ddply(logs[['need-to-charge']],.(calling.event,charge.safety.factor),function(df){ data.frame(num.need.to.charge=sum(df$need.to.charge.=="true")) })

# PATTERNS
# Frac events by Charger Type
ggplot(ddply(logs[['charging']],.(vehicle.type),function(df){ 
    data.frame(charger.level=ddply(df,.(charger.level),nrow)$charger.level,
      frac.charges=ddply(df,.(charger.level),nrow)$V1/nrow(df)) 
  }),
  aes(x=1,y=frac.charges))+geom_bar(stat="identity",aes(fill=factor(charger.level)))+ xlab('') + labs(fill='Level') + facet_wrap(~vehicle.type)

ggplot(ddply(logs[['charging']],.(probability.of.unneeded.charge,vehicle.type),function(df){ 
    data.frame(charger.level=ddply(df,.(charger.level),nrow)$charger.level,
      frac.charges=ddply(df,.(charger.level),nrow)$V1/nrow(df)) 
  }),
  aes(x=1,y=frac.charges))+
  geom_bar(stat="identity",aes(fill=factor(charger.level)))+
  facet_grid(probability.of.unneeded.charge~vehicle.type)+ xlab('') + labs(fill='Level')

# Miles per day by vehicle type
ggplot(ddply(ddply(logs[['trip']],.(vehicle.type,replicate),function(df){ sum(df$distance)/length(unique(df$driver)) }),.(vehicle.type),function(df){ data.frame(miles.per.day=mean(df$V1))}),
  aes(x=1,y=miles.per.day))+geom_bar(stat="identity")+ xlab('') + labs(fill='Level') + facet_wrap(~vehicle.type)

# Miles between charging
v.trips <- subset(logs[['trip']],vehicle.type=="volt")
v.ch <- subset(logs[['charging']],vehicle.type=="volt")

miles.between.charges <- ddply(v.ch,.(driver,replicate),function(df){
  df.row <- 1
  res <- sum(subset(v.trips,driver==df$driver[1] & replicate==df$replicate[1] & time <= df$time[df.row])$distance)
  while(df.row < nrow(df)){
    df.row <- df.row + 1
    res <- c(res,sum(subset(v.trips,driver==df$driver[1] & replicate==df$replicate[1] & time <= df$time[df.row] & time > df$time[df.row-1])$distance))
  }
  data.frame(miles=res)
})
ggplot(miles.between.charges,aes(x=miles))+geom_histogram()+geom_vline(data=data.frame(v=c(mean(miles.between.charges$miles),median(miles.between.charges$miles)),c=c('green','red')),aes(xintercept=v,colour=c))

# charges per driver per day
charges.per.driver <- ddply(logs[['charging']],.(replicate),function(df){ data.frame(charges.per.driver=nrow(df)/subset(logs[['summary']],replicate==df$replicate[1] & metric=="num.drivers")$value)})
charges.per.driver$leaf <- ddply(subset(logs[['charging']],vehicle.type=='leaf'),.(replicate),function(df){ nrow(df)/subset(logs[['summary']],replicate==df$replicate[1] & metric=="num.bevs")$value})$V1
charges.per.driver$volt <- ddply(subset(logs[['charging']],vehicle.type=='volt'),.(replicate),function(df){ nrow(df)/(subset(logs[['summary']],replicate==df$replicate[1] & metric=="num.drivers")$value - subset(logs[['summary']],replicate==df$replicate[1] & metric=="num.bevs")$value)})$V1
ggplot(charges.per.driver,aes(x=charges.per.driver))+geom_histogram(binwidth=0.1)

# Volt fraction miles on electricity
v.frac.elec <- ddply(v.trips,.(driver),function(df){ 
  data.frame(frac=(1 - (sum(df$gas.used)/0.027)/sum(df$distance)))
})
ggplot(v.frac.elec,aes(x=frac))+geom_histogram()+geom_vline(data=data.frame(v=c(mean(v.frac.elec$frac),median(v.frac.elec$frac)),c=c('green','red')),aes(xintercept=v,colour=c))

# State-of-charge at start
logs[['charging']]$at.home <- logs[['charging']]$charger.level==0
logs[['charging']]$at.home[logs[['charging']]$at.home] <- "Residential"
logs[['charging']]$at.home[logs[['charging']]$at.home=="FALSE"] <- "Public"
soc.at.beg <- ddply(logs[['charging']],.(at.home,vehicle.type),function(df){ data.frame(up.to=seq(0.1,1,by=.1),percent=hist(df$begin.soc,plot=F,breaks=seq(0,1,by=0.1))$counts/nrow(df)*100) })
ggplot(soc.at.beg,aes(x=up.to,y=percent,fill=factor(at.home)))+geom_bar(stat='identity',position="dodge")+facet_wrap(~vehicle.type)+labs(fill="Charger Type")

# Home charging power demand
caps <- c(6.6,2.4,6.6,30)
demand <- ddply(logs[['tazs']],.(replicate,time),function(df){ colSums(df[,paste('num.L',0:3,sep='')] - df[,paste('num.avail.L',0:3,sep='')]) * caps })
demand <- data.frame(logs[['tazs']][,c('replicate','time','taz')],t(apply(logs[['tazs']][,paste('num.L',0:3,sep='')] - logs[['tazs']][,paste('num.avail.L',0:3,sep='')],1,function(x){ x * caps })))
names(demand) <- c('replicate','time','taz','pow.L0','pow.L1','pow.L2','pow.L3')

demand.sum <- ddply(ddply(demand,.(time,replicate),function(df){ colSums(df[,c('pow.L0','pow.L1','pow.L2','pow.L3')]) }),
                    .(time),function(df){ rbind( data.frame(level=0,min=min(df$pow.L0),max=max(df$pow.L0),median=median(df$pow.L0),mean=mean(df$pow.L0)),
                                                        data.frame(level=1,min=min(df$pow.L1),max=max(df$pow.L1),median=median(df$pow.L1),mean=mean(df$pow.L1)),
                                                        data.frame(level=2,min=min(df$pow.L2),max=max(df$pow.L2),median=median(df$pow.L2),mean=mean(df$pow.L2)),
                                                        data.frame(level=3,min=min(df$pow.L3),max=max(df$pow.L3),median=median(df$pow.L3),mean=mean(df$pow.L3))) })
ggplot(melt(subset(demand.sum,level==0),id.vars=c('time','level')),aes(x=time,y=value,colour=variable))+geom_line()+facet_wrap(~level)
ggplot(melt(subset(demand.sum,level>0),id.vars=c('time','level')),aes(x=time,y=value,colour=variable))+geom_line()+facet_wrap(~level)
demand.sum <- ddply(demand,.(time,taz),function(df){ rbind( data.frame(level=0,min=min(df$pow.L0),max=max(df$pow.L0),median=median(df$pow.L0),mean=mean(df$pow.L0)),
                                                        data.frame(level=1,min=min(df$pow.L1),max=max(df$pow.L1),median=median(df$pow.L1),mean=mean(df$pow.L1)),
                                                        data.frame(level=2,min=min(df$pow.L2),max=max(df$pow.L2),median=median(df$pow.L2),mean=mean(df$pow.L2)),
                                                        data.frame(level=3,min=min(df$pow.L3),max=max(df$pow.L3),median=median(df$pow.L3),mean=mean(df$pow.L3))) })
ggplot(melt(subset(demand.sum,level==0),id.vars=c('time','level','taz')),aes(x=time,y=value,colour=variable))+geom_line()+facet_wrap(~taz)

# Charging length and energy distributions
ggplot(logs[['charging']],aes(x=duration))+geom_histogram(binwidth=1)+facet_wrap(~public)
ggplot(logs[['charging']],aes(x=energy))+geom_histogram(binwidth=0.1)

# Duty factor by TAZ

existing.chargers <- data.frame(id=c(6,23,27,45),name=c("ARC_Plaza","EKA_Waterfront","EKA_NW101","Redway"))

logs[['charging']]$infrastructure.scenario <- NA
for(scen.i in names(naming$`charger-input-file`)){
  logs[['charging']]$infrastructure.scenario[grep(scen.i,as.character(logs[['charging']]$charger.input.file))] <- scen.i
  logs[['charging']]$infrastructure.scenario.named[logs[['charging']]$infrastructure.scenario == scen.i] <- naming$`charger-input-file`[[scen.i]][[1]]
  logs[['charging']]$infrastructure.scenario.order[logs[['charging']]$infrastructure.scenario == scen.i] <- as.numeric(naming$`charger-input-file`[[scen.i]][[2]])
}
logs[['charging']]$penetration <- as.numeric(unlist(lapply(strsplit(as.character(logs[['charging']]$driver.input.file),'-pen',fixed=T),function(x){ unlist(strsplit(x[2],"-rep",fixed=T)[[1]][1]) })))
logs[['charging']]$replicate <- as.numeric(unlist(lapply(strsplit(as.character(logs[['charging']]$driver.input.file),'-rep',fixed=T),function(x){ unlist(strsplit(x[2],"-",fixed=T)[[1]][1]) })))

num.chargers <- list()
for(charger.file in unique(as.character(logs[['charging']]$charger.input.file))){
  scen.named <- logs[['charging']]$infrastructure.scenario.named[which(logs[['charging']]$charger.input.file == charger.file)[1]]
  num.chargers[[scen.named]] <- read.table(charger.file,skip=1)
  names(num.chargers[[scen.named]]) <- c('taz','L0','L1','L2','L3','L4')
}

charge.sum <- na.omit(ddply(logs[['charging']],.(location,charger.level,penetration,infrastructure.scenario.named),function(df){
  num.reps <- length(unique(df$replicate))
  duty.factor <- sum(df$duration)/(24*num.reps*num.chargers[[df$infrastructure.scenario.named[1]]][df$location[1],pp('L',df$charger.level[1])])
  data.frame(duty.factor=ifelse(duty.factor==Inf,NA,duty.factor))
}))

taz.names <- read.csv(pp(pevi.shared,'data/google-earth/ordering-for-TAZ-table.csv'))
charge.sum$taz <- taz.names$name[match(charge.sum$location,taz.names$id)]

df <- subset(charge.sum,charger.level>0 & ! location %in% existing.chargers$id)
p <- ggplot(df,aes(x=factor(charger.level),fill=factor(penetration),y=duty.factor))+geom_bar(stat='identity',position="dodge")+facet_wrap(~taz)+labs(title=df$infrastructure.scenario.named[1],x="Charger Level",y="Duty Factor")

p <- ggplot(df,aes(x=penetration,color=factor(charger.level),y=duty.factor))+geom_point()+geom_line()+facet_wrap(~taz)+labs(title=df$infrastructure.scenario.named[1],x="Penetration",y="Duty Factor",colour="L1/L2")
ggsave(pp(pevi.shared,'maps-results/duty-factors-CEC.pdf'),p,width=11,height=8.5)

pdf(pp(pevi.shared,'maps-results/duty-factors-noL1.pdf'),width=11,height=8.5)
d_ply(subset(charge.sum,charger.level>0),.(infrastructure.scenario.named),function(df){
  p <- ggplot(df,aes(x=factor(charger.level),fill=factor(penetration),y=duty.factor))+geom_bar(stat='identity',position="dodge")+facet_wrap(~taz)+labs(title=df$infrastructure.scenario.named[1],x="Charger Level",y="Duty Factor")
  print(p)
})
dev.off()

fish <- read.csv(pp(pevi.shared,'data/chargers/fisherman-terminal-usage-2012-2013/2013-12-04 FTB EVSE Energy-vs-Time.csv'),stringsAsFactors=F)
names(fish) <- c('date','kwh','cum')
fish$date <- to.posix(fish$date,'%m/%d/%Y')
fish$dow <- as.numeric(strftime(fish$date,'%w'))
fish$is.weekday <- fish$dow>0 & fish$dow<6
fish$dow <- factor(strftime(fish$date,'%a'))
fish$dow <- factor(strftime(fish$date,'%a'),levels=levels(fish$dow)[c(2,6,7,5,1,3,4)])
fish$month <- factor(as.numeric(strftime(fish$date,'%m')))

ggplot(fish,aes(x=date,y=kwh)) + geom_point() + labs(x="Date",y="Energy Dispensed (kWh)",title="Fisherman's Terminal EVSE Utilization")
ggplot(subset(fish,kwh>0),aes(x=factor(dow),y=kwh,colour=is.weekday)) + geom_point() + geom_boxplot() + labs(x="Week Day",y="Energy Dispensed (kWh)",title="Fisherman's Terminal EVSE Utilization")
ggplot(ddply(subset(fish,kwh>0),.(dow),function(df){ data.frame(kwh=sum(df$kwh)) }),aes(x=dow,y=kwh)) + geom_bar(stat='identity') + labs(x="Week Day",y="Energy Dispensed (kWh)",title="Fisherman's Terminal EVSE Utilization")

daily.energy <- sum(subset(fish,date>to.posix('2013-02-01'))$kwh)/as.numeric(difftime(max(subset(fish,date>to.posix('2013-02-01'))$date),min(subset(fish,date>to.posix('2013-02-01'))$date),units='days'))

# what fraction of the kWh were delivered to EVs charging at 3.3kW vs 6.6kW
#(sum(fish$kwh)/316.5- 6.6)/-3.3

# so if there's an average of 3.5 kWh per day delivered and we assume drivers will charge at 6.6kW, that's a 2.2% duty factor for ~100 drivers
#0.02209596

# PEVI predicts ~40% duty factor at the waterfront with 0.5% pen or 750 driver
subset(charge.sum,taz=='EKA_Waterfront')
