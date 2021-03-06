create.schedule <- function(pev.penetration,scale.dist.thresh=1,frac.end.at.home=0.922){
  environment(pick.driver) <- sys.frame(sys.nframe())
  environment(find.consistent.journey) <- sys.frame(sys.nframe())
   #for testing
   #pev.penetration <- 0.005
   #scale.dist.thresh <- 1
   #frac.end.at.home <- 0.922
   #set.seed(1)

  od.counts <- od.agg.simp
  od.counts[,':='(hw.mean=hw*pev.penetration,ho.mean=ho*pev.penetration,ow.mean=ow*pev.penetration)]
  # explode the od.counts frame to be on an hourly basis scaled by the epdfs
  od.counts <- data.frame(from    = rep(od.counts$from,each=24),
                          to      = rep(od.counts$to,each=24),
                          hour    = rep(6:29,nrow(od.counts)),
                          hw.mean = rep(od.counts$hw.mean,each=24)*rep(epdfs$hw,nrow(od.counts)),
                          ho.mean = rep(od.counts$ho.mean,each=24)*rep(epdfs$ho,nrow(od.counts)),
                          ow.mean = rep(od.counts$ow.mean,each=24)*rep(epdfs$ow,nrow(od.counts)))

  # do the random draws to convert the mean trips to discrete numbers
  od.counts[,c('hw','ho','ow')] <- t(apply(od.counts[,c('hw.mean','ho.mean','ow.mean')],1,function(row){ apply(as.matrix(row,byrow=T),1,rpois,n=1) }))

  # now sort by hour and shuffle otherwise
  od.counts[,c('hw.orig','ho.orig','ow.orig')] <- od.counts[,c('hw','ho','ow')]
  tazs <- sort(unique(od.counts$from))
  num.tazs <- length(tazs)

  # now convert into data table 
  od.counts <- data.table(od.counts,key=c('to'))
  
  # start the data structure to store a list of drivers available to be redispatched
  # the structure is nested lists indexed by [from.taz]][[count | drivers]]
  # and will then contain a data frame with 2 columns, driver.id and at.home 
  available.drivers <- list()
  for(taz.i in tazs){
    num.counts <- sum(od.counts[J(taz.i),hw+ho+ow]$V1)
    if(num.counts < 1)num.counts <- 1
    available.drivers[[as.character(taz.i)]][['drivers']] <- data.frame(driver.id=rep(NA,num.counts),at.home=NA,hour=NA)
    available.drivers[[as.character(taz.i)]][['count']] <- 0
  }
  expected.num.drivers <- pev.penetration * sum(pops.2020) * 0.84 # 0.84 is average # vehicle per capita in California

  home.drivers <- list()
  driver.count <- 0
  for(taz.i in tazs){
    c.taz <- as.character(taz.i)
    home.drivers[[c.taz]] <- list()
    if(length(home.dist$frac.home[home.dist$agg.id==taz.i])>0){
      n.drivers <- rpois(1,home.dist$frac.home[home.dist$agg.id==taz.i] * expected.num.drivers)
      home.drivers[[c.taz]] <- list(driver=c(),count=0)
      if(n.drivers>0){
        for(i in 1:n.drivers){
          driver.count <- driver.count + 1
          home.drivers[[c.taz]][['driver']] <- c(home.drivers[[c.taz]][['driver']],driver.count)
          home.drivers[[c.taz]][['count']] <- home.drivers[[c.taz]][['count']] + 1
        }
      }
    }
  }
  tot.drivers <- sum(unlist(sapply(home.drivers,function(x){x[['count']]})))
  num.home.drivers <- tot.drivers
  print(paste("num.drivers",num.home.drivers,"num.trips",sum(od.counts[,hw+ho+ow]),"trips.per.driver",sum(od.counts[,hw+ho+ow])/num.home.drivers))

  setkey(time.distance,'from','to')

  #Rprof(pp(pevi.nondrop,'profile5.txt'))
  # make the schedule
  od.counts[,':='(hw=hw.orig,ho=ho.orig,ow=ow.orig)]
  od.m <- melt(od.counts[,list(from,to,hour,hw,ho,ow)],id.vars=c('from','to','hour'),measure.vars=c('hw','ho','ow'))
  od.m <- data.table(ddply(od.m,.(hour),function(df){df[sample(1:nrow(df)),]}))
  od.m[,':='(purp=variable,variable=NULL)]
  od.m[,od.row:=1:nrow(od.m)]
  setkey(od.m,'purp','from','to','hour')
  od.m[,od.i:=1:nrow(od.m)]
  od.row.i.lookup <- data.table(od.m[,list(od.i,od.row)],key='od.row')
  
  dist.thresh <- data.frame(under=c(3,seq(5,40,by=5),seq(50,100,by=25),seq(150,300,by=50)),
                            miles=c(3,rep(5,8),10,rep(25,2),rep(50,4))) # miles
  dist.thresh$miles <- dist.thresh$miles * scale.dist.thresh
  depart.thresh <- 3 # hours
  max.journey.len <- 15 # max(ddply(rur.tours,.(journey.id),nrow)$V1) # takes a long time to run
  schedule <- data.frame(driver=rep(NA,sum(od.m$value)))
  schedule$from   <- NA
  schedule$to     <- NA
  schedule$depart <- NA
  schedule$arrive <- NA
  schedule$type   <- NA
  schedule$purp <- NA
  schedule$home <- NA
  
  cand.schedule <- schedule[1:max.journey.len,]
  num.trips <- 1
  recycle.drivers.thresh <- 0.0
  max.length.remaining <- max(rur.tours$tours.left.in.journey)

  for(od.row in 1:nrow(od.m)){
    od.i <- od.row.i.lookup[od.row,od.i]
    if(od.row%%5000 == 0){
      print(paste("pev ",pev.penetration," rep ",replicate," progress: ",roundC(od.row/nrow(od.m)*100,1),"%",sep=''))
      system('sleep 0.05')
    }
    if(od.m[od.i,value]<=0)next
    to.i <- od.m$to[od.i]
    from.i <- od.m$from[od.i]
    type <- od.m$purp[od.i]
    hour <- od.m$hour[od.i]
    # we increase the working threshold at the boundaries (near hour 0 and 24) to account for the fact that we can't go off the edges
    # and for the fact that demand is lower at night so the pool get's small quickly
    if(hour - 6 < depart.thresh){
      depart.thresh.modified <- 2*depart.thresh - (hour-6)
    }else if(hour > 29 - depart.thresh){
      depart.thresh.modified <- 2*depart.thresh - (29-hour)
    }else{
      depart.thresh.modified <- depart.thresh
    }
    hours.to.search <- (hour-depart.thresh.modified):(hour+depart.thresh.modified)
    # deal with loop around from 24 to 0
    hours.to.search[hours.to.search>23] <- hours.to.search[hours.to.search>23]-24
    dists <- time.distance[J(from.i,to.i),]
    dist.thresh.to.use <- dist.thresh$miles[findInterval(dists$miles,dist.thresh$under)+1]
    dists.to.search <- (dists$miles.int-dist.thresh.to.use):(dists$miles.int+dist.thresh.to.use)
    # grab the indices of the tours that are close in time and distance, and in the case of home-based travel, starting from home
    if(type=='ow'){
      cands <- na.omit(rur.by.type[[type]][['non.home.start']][J(hours.to.search,dists.to.search),index]$index)
      if(length(cands)==0)cands <- na.omit(rur.by.type[[type]][['home.start']][J(hours.to.search,dists.to.search),index]$index)
      if(length(cands)==0){
        print(paste('Warning: no candidate tours found for ',dists$miles,' miles at ',hour,' hour for type ',type,' and od.row ',od.row,' taking random cand',sep=''))
        cands <- sample(rur.by.type[[type]][['non.home.start']]$index,1)
      }
    }else{
      cands <- na.omit(rur.by.type[[type]][['home.start']][J(hours.to.search,dists.to.search),index]$index)
      if(length(cands)==0)cands <- na.omit(rur.by.type[[type]][['non.home.start']][J(hours.to.search,dists.to.search),index]$index)
      if(length(cands)==0){
        print(paste('Warning: no candidate tours found for ',dists$miles,' miles at ',hour,' hour for type ',type,' and od.row ',od.row,' taking random cand',sep=''))
        cands <- sample(rur.by.type[[type]][['home.start']]$index,1)
      }
    }
    if(length(cands)==1){
      shuffled.cands <- cands
    }else{
      shuffled.cands <- sample(cands)
    }
    for(pick.i in 1:50){
      driver <- pick.driver(type,from.i,to.i,hour)
      driver.i <- driver$driver.i
      driver.home <- driver$driver.home
      driver.home.ch <- as.character(driver$driver.home)
      if(!is.na(driver.home))break
    }
    if(is.na(driver.home))stop('driver home still NA after 50 attempts')
    #print(paste(driver.i,driver.home))
    
    # loop through the cands in random order until enough consistent journeys are found to satisfy the demand for drivers 
    for(cand in shuffled.cands){
      use.cand <- T
      cand.schedule[,] <- NA 
      journey <- rur.tours[cand:(cand+rur.tours$tours.left.in.journey[cand])]
      depart <- hour+runif(1)
      arrive <- depart + dists$hours
      #if(arrive >= 24){
        #arrive <- arrive - 24
      #}
      #print(pp(driver.i,from.i,to.i,depart,arrive,journey$TOURTYPE[1],as.character(journey$purp[1]),driver.home,sep="  "))
      cand.schedule[1,] <- data.frame(driver.i,from.i,to.i,depart,arrive,journey$TOURTYPE[1],as.character(journey$purp[1]),driver.home,stringsAsFactors=F)
      if(arrive >= depart & nrow(journey) > 1){
        new.cand.schedule <- find.consistent.journey(2,cand.schedule,journey,dists,dist.thresh)
        if(is.logical(new.cand.schedule)){
          use.cand <- F
        }else{
          cand.schedule <- new.cand.schedule
        }
      }
      if(use.cand){
        if(!any(is.na(driver$to.erase.inds))){
          schedule <- rbind(schedule[-driver$to.erase.inds,],schedule[10000001:(10000000+length(driver$to.erase.inds)),])
        }
        if(driver.i > tot.drivers) tot.drivers <- driver.i
        n.cand.trips <- length(na.omit(cand.schedule$driver))
        schedule[num.trips:(num.trips+n.cand.trips-1),] <- cand.schedule[1:n.cand.trips,]
        if(any(is.na(cand.schedule$home[1:n.cand.trips])))stop(paste('na in home',num.trips,(num.trips+n.cand.trips-1)))
        num.trips <- num.trips + n.cand.trips
        for(row.i in 1:n.cand.trips){
          if(row.i==1){
            od.i.check <- od.m[J(type,cand.schedule$from[row.i],cand.schedule$to[row.i],as.integer(cand.schedule$depart[row.i]))]$od.i
            if(od.i.check != od.i)stop('stop, somehow the driver schedule does not start in the place we expected based on od.i')
          }
          od.m[od.i,value:=value - 1L]
        }
        if(driver.i %in% home.drivers[[driver.home.ch]]$driver){
          home.drivers[[driver.home.ch]]$driver <- home.drivers[[driver.home.ch]]$driver[-which(home.drivers[[driver.home.ch]]$driver==driver.i)]
          home.drivers[[driver.home.ch]]$count <- home.drivers[[driver.home.ch]]$count - 1
          num.home.drivers <- num.home.drivers - 1 
        }
        # is the driver already listed in available drivers?  if so remove before adding again to the appropriate place
        already.there.taz <- as.character(tazs[which(sapply(available.drivers,function(x){ any(x[['drivers']]$driver.id==driver.i) }))])
        if(length(already.there.taz)>0){
          available.drivers[[already.there.taz]][['count']] <- available.drivers[[already.there.taz]][['count']] - 1
          available.driver.i <- which(available.drivers[[already.there.taz]][['drivers']]$driver.id == driver.i)
          if(available.driver.i < nrow(available.drivers[[already.there.taz]][['drivers']])){
            available.drivers[[already.there.taz]][['drivers']][available.driver.i:(nrow(available.drivers[[already.there.taz]][['drivers']])-1),] <- available.drivers[[already.there.taz]][['drivers']][(available.driver.i+1):nrow(available.drivers[[already.there.taz]][['drivers']]),]
          }
          available.drivers[[already.there.taz]][['drivers']][nrow(available.drivers[[already.there.taz]][['drivers']]),] <- NA
        }
        available.drivers[[as.character(cand.schedule$to[n.cand.trips])]][['count']] <- available.drivers[[as.character(cand.schedule$to[n.cand.trips])]][['count']] + 1
        available.drivers[[as.character(cand.schedule$to[n.cand.trips])]][['drivers']][available.drivers[[as.character(cand.schedule$to[n.cand.trips])]][['count']],] <- data.frame(driver.id=driver.i,
                                                                                      at.home=cand.schedule$to[n.cand.trips]==driver.home,
                                                                                      hour=ceiling(cand.schedule$arrive[n.cand.trips]))
        if(od.m[od.i,value] <= 0)break
        for(pick.i in 1:50){
          driver <- pick.driver(type,from.i,to.i,hour)
          driver.i <- driver$driver.i
          driver.home <- driver$driver.home
          driver.home.ch <- as.character(driver.home)
          if(!is.na(driver.home))break
        }
        if(is.na(driver.home))stop('driver home still NA after 50 attempts')
        #print(paste(driver.i,driver.home))
      }
    }
    if(od.m[od.i,value]>0){
      print(paste('no consistent journeys: giving up on ',od.m[od.i,value],' trips'))
      #stop()
    }
  } # end foreach row in od
  #summaryRprof(pp(pevi.nondrop,'profile5.txt'))
  #Rprof(NULL)
  schedule$type <- as.factor(schedule$type)
  levels(schedule$type) <- levels(rur.tours$TOURTYPE)
  schedule <- na.omit(ddply(schedule[order(schedule$driver),],.(driver),function(df){ df[order(df$depart),] }))

  # now force drivers to go home instead of somewhere else, prioritize drivers whose final trip of the day is close in length to a 
  # trip home instead
  final.trip.by.driver <- ddply(schedule,.(driver),function(df){ data.frame(from=df$from[nrow(df)], to=df$to[nrow(df)], trip.miles=time.distance[J(df$from[nrow(df)],df$to[nrow(df)]),miles]$miles, home=df$home[1], home.miles = time.distance[J(df$from[nrow(df)],df$home[1]),miles]$miles ) })
  final.trip.by.driver <- final.trip.by.driver[order(abs(final.trip.by.driver$trip.miles - final.trip.by.driver$home.miles)),]
  n.to.change <- round(nrow(final.trip.by.driver) * (frac.end.at.home - sum(final.trip.by.driver$to==final.trip.by.driver$home)/nrow(final.trip.by.driver)))
  if(n.to.change > 0){
    final.trip.by.driver <- subset(final.trip.by.driver,to != home)
    final.trip.by.driver$trip.diff <- abs(final.trip.by.driver$trip.miles - final.trip.by.driver$home.miles)
    final.trip.by.driver <- final.trip.by.driver[order(final.trip.by.driver$trip.diff),][1:n.to.change,]
    schedule <- ddply(schedule,.(driver),function(df){ 
      if(df$driver[1] %in% final.trip.by.driver$driver){
        df$to[nrow(df)] <- df$home[1]
      }
      df
    })
  }
  return(schedule)
}

#cand.schedule[2:nrow(cand.schedule),] <- NA

# vars in this function which must be altered on the global environment: journey, time.distance, dists, od.m, dist.thresh
find.consistent.journey <- function(journey.i,cand.schedule,journey,dists,dist.thresh){
  #print(paste(journey.i, paste(na.omit(cand.schedule$from),na.omit(cand.schedule$to),collapse="---",sep=",")))
  if(journey.i > nrow(journey))return(cand.schedule)
  
  # first see if the dwell time puts us into tomorrow, if so we're done
  depart <- cand.schedule$arrive[journey.i-1] + journey$TOT_DWEL4[journey.i-1]/60
  if(depart >= 30)return(cand.schedule)

  # now find a new TAZ within dist.thresh of the NHTS schedule 
  new.hour <- as.integer(depart)
  new.from <- cand.schedule$to[journey.i-1]
  new.type <- journey$purp[journey.i] 
  # if the journey tourtype is to home (and not the last trip of the journey), we restrict the search to going to the home taz
  if(journey$home.end[journey.i] & journey.i < nrow(journey)){
    new.to.distance <- time.distance[J(new.from,driver.home)]$miles
    new.to.cands <- ifelse( abs(new.to.distance - journey$TOT_MILS[journey.i]) < dist.thresh$miles[findInterval(journey$TOT_MILS[journey.i],dist.thresh$under)+1], driver.home, NA)
  }else{
    # otherwise, look for any TAZ that is near enough
    new.to.cands <- time.distance[J(new.from)]
    new.to.cands <- subset(new.to.cands,abs(miles - journey$TOT_MILS[journey.i]) < dist.thresh$miles[findInterval(journey$TOT_MILS[journey.i],dist.thresh$under)+1])$to
  }
  if(length(new.to.cands)==0)return(F)
  if(length(new.to.cands)==1){
    if(is.na(new.to.cands))return(F)
  }
  new.to.cands <- subset(od.m[J(new.type,new.from,new.to.cands,new.hour)],value>0)$to
  if(length(new.to.cands)==0)return(F)
  if(length(new.to.cands)>1)new.to.cands <- sample(new.to.cands) # shuffle if needed
  for(new.to in new.to.cands){
    arrive <- depart + time.distance[J(new.from,new.to)]$hours
    #if(arrive >= 24){
      #arrive <- arrive - 24
    #}
    #print(pp(driver.i,new.from,new.to,depart,arrive,journey$TOURTYPE[journey.i],new.type,driver.home,collapse="  "))
    cand.schedule[journey.i,] <- data.frame(driver.i,new.from,new.to,depart,arrive,journey$TOURTYPE[journey.i],new.type,driver.home,stringsAsFactors=F)
    new.cand.schedule <- find.consistent.journey(journey.i+1,cand.schedule,journey,dists,dist.thresh)
    if(!is.logical(new.cand.schedule))return(new.cand.schedule)
  }
  return(F)
}

pick.driver <- function(type,from.i,to.i,hour){
  driver.i <- NA
  driver.home <- NA
  to.erase.inds <- NA
  if(num.home.drivers > 0){
    if(type == 'ow'){
      cand.homes <- as.character(taz.10[[as.character(from.i)]])
      cand.home.counts <- sapply(cand.homes,function(x){ home.drivers[[x]]$count })
      if(sum(cand.home.counts)>0){
        #print("home driver other")
        driver.home.ch <- sample.one(cand.homes[cand.home.counts>0])
        driver.home <- as.numeric(driver.home.ch)
        driver.i <- sample.one(home.drivers[[driver.home.ch]]$driver)
      }
    }else{
      if(home.drivers[[as.character(from.i)]]$count > 0){
        #print("home driver home-based")
        driver.home <- from.i
        driver.i <- sample.one(home.drivers[[as.character(driver.home)]]$driver)
      }
    }
  }
  if(is.na(driver.i)){
    # are there any available drivers, if yes, are any of them available at this time and 
    from.i.ch <- as.character(from.i)
    if(available.drivers[[from.i.ch]][['count']] > 0 & any( available.drivers[[from.i.ch]][['drivers']]$hour <= hour & (!available.drivers[[from.i.ch]][['drivers']]$at.home | type!='ow'), na.rm=T)){
      #print("available driver used")
      available.driver.i <- sample.one(which(available.drivers[[from.i.ch]][['drivers']]$hour <= hour & (!available.drivers[[from.i.ch]][['drivers']]$at.home | type!='ow')))
      driver.i <- available.drivers[[from.i.ch]][['drivers']]$driver.id[available.driver.i]
      driver.home <- as.numeric(subset(schedule,driver==driver.i)$home[1])
    }else{
      # can we canibalize the schedule, throw away a couple of trips of a driver that's otherwise consistent
      if(type == 'ow'){
        cand.trips <- which(schedule$to == from.i & schedule$arrive < hour & schedule$home != from.i)
      }else{
        cand.trips <- which(schedule$to == from.i & schedule$arrive < hour & schedule$home == from.i)
      }
      if(length(cand.trips)>0){
        #print(paste('found a trip to cannibalize',type,from.i,to.i,hour))
        prev.trip <- sample.one(cand.trips)
        driver.i <- schedule$driver[prev.trip]
        driver.home <- as.numeric(schedule$home[prev.trip])
        to.erase.inds <- which(schedule$driver == schedule$driver[prev.trip] & schedule$arrive > schedule$arrive[prev.trip])
        if(length(to.erase.inds)==0){ to.erase.inds <- NA }
      }else{
        #print(paste("no available drivers, creating one"))
        driver.i <- tot.drivers + 1
        if(type == 'ow'){
          driver.home <- sample(taz.10[[as.character(from.i)]],1)
        }else{
          driver.home <- from.i
        }
      }
    }
  }
  return( list(driver.i=driver.i,driver.home=driver.home, to.erase.inds=to.erase.inds) )
}

sample.one <- function(x){
  ifelse(length(x)==1,x,sample(x,1))
}


## debugging stuff
if(F){
  
  order.sched <- na.omit(schedule[order(schedule$driver),])

  find.problem <- function(df){ 
    if(nrow(df)==1){ 
      return(F) 
    }else{
      return(any(df$to[1:(nrow(df)-1)] != df$from[2:nrow(df)]))
    }
  }

  inconsist.drivers <- ddply(order.sched,.(driver),find.problem)

}
