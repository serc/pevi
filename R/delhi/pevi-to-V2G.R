"%notin%" <- function(x, table) match(x, table, nomatch = 0) == 0

###################################################################
# REQUIRED LOGS:
# Charging, Trip, Pain
###################################################################

# SHIFT OUTPUTS BACK 6 HOURS UNTIL ITINERARY FIX COMES THROUGH

# This script will convert pevi's charging logs into the format needed for V2G

# Step 1: Load up the charging log as a data table
charge.log <- data.table(read.csv('~/Dropbox/serc/pevi/outputs/charging-out.csv'))

# V2GSIM files are organized by driver, not time. 
setkey(charge.log,driver,time)

#V2GSIM columns go: Vehicle ID, State, Start Time (hour), End Time (hour), Distance (km), Drive Cycle, P_max (W), Location. Sam also wants vehicle type; we'll add that column after driver

charge.log[,':='(VehicleID=driver,VehicleType=vehicle.type,State='Charging',StartTime=time,EndTime=as.numeric(levels(time))[time]+as.numeric(levels(duration))[duration],Distance=0,DriveCycle=-1,Pmax=charger.level,Location=location,time=NULL,charger.id=NULL,charger.level=NULL,location=NULL,driver=NULL,vehicle.type=NULL,duration=NULL,energy=NULL,begin.soc=NULL,end.soc=NULL,after.end.charge=NULL,charging.on.whim=NULL,time.until.depart=NULL)]

# Adjust the Pmax column so it gives the power, not the charger level
# We can do this with file-read if we think the charger power is gonna change,
# but for now I am assuming that charger power will not change.

charge.log[Pmax==0,Pmax:=6600]
charge.log[Pmax==1,Pmax:=1500]
charge.log[Pmax==2,Pmax:=6600]
charge.log[Pmax==3,Pmax:=50000]

# charge.log covers the charging events. Now we need to go into the trip log and format that data as well.

# First off, we load up the data again.
trip.log <- data.table(read.csv('~/Dropbox/serc/pevi/outputs/trip-out.csv'))

setkey(trip.log,driver,time)

# Trips will give driving events, but not parking events. Our strategy will be to convert the driving log to V2G format,
# combine trip.log with charge.log, and then fill in the time gap with parking events.

trip.log[,':='(VehicleID=driver,VehicleType=vehicle.type,State='Driving',StartTime=time,EndTime=end.time,Distance=distance,DriveCycle=-1,Pmax=-1,Location=origin,time=NULL,driver=NULL,vehicle.type=NULL,origin=NULL,destination=NULL,distance=NULL,scheduled=NULL,begin.soc=NULL,end.soc=NULL,elec.used=NULL,gas.used=NULL,end.time=NULL)]
#setnames(trip.log,c('VehicleID','VehicleType','State','StartTime','EndTime','Distance','DriveCycle','Pmax','Location'),c('Vehicle ID','Vehicle Type','State','Start time (hour)','End time (hour)','Distance (km)','Drive cycle','P_max (W)','Location'))

# Set mutual keys to the data tables
setkey(charge.log,'VehicleID','StartTime')
setkey(trip.log,'VehicleID','StartTime')

# Now combine the two data frames
v2g.log <- rbindlist(list(charge.log,trip.log))
setkey(v2g.log,'VehicleID','StartTime')

v2g.log[,StartTime:=as.numeric(levels(StartTime))[StartTime]]
v2g.log[,EndTime:=as.numeric(levels(EndTime))[EndTime]]
v2g.log[,Distance:=as.numeric(levels(Distance))[Distance]]
setkey(v2g.log,'VehicleID','StartTime')

# Here's the tricky part: finding the time chunks when they are neither driving nor charging, and park them.

# We're looking for rows where the start time is greater than the end time of the previous row.
# Create a "TimeLapse" ro to hold this value; set to -1 if first row in driver subset
v2g.log[,TimeLapse:=as.vector(c(-1,tail(StartTime,-1)-head(EndTime,-1))),by=VehicleID]

# "TimeLapse" values of -1 get re-set to StartTime
v2g.log[TimeLapse==-1,TimeLapse:=StartTime]

# Now we create a separate data table for the parking events, which we build using the start times and time lapses from v2g.log

parking.log = copy(v2g.log)
parking.log[TimeLapse>0.0001,':='(State='Parked',StartTime=StartTime-TimeLapse,EndTime=StartTime,Distance=0,DriveCycle=-1,Pmax=-1)]
parking.log = parking.log[State=='Parked',]

# We will then combine parking.log and v2g.log, and the magic of keys will organize it.
v2g.log <- rbindlist(list(v2g.log,parking.log))
setkey(v2g.log,'VehicleID','StartTime')

# Remove extraneous rows and re-name
v2g.log[,TimeLapse:=NULL]

# Remove drivers who were stranded. We will need to get this info from the "pain" output file.
pain.log <- data.table(read.csv('~/Dropbox/serc/pevi/outputs/pain-out.csv'))
setkey(pain.log,driver)
stranded.drivers <- pain.log[pain.type=='stranded',driver]
v2g.log <- v2g.log[VehicleID%notin%stranded.drivers,]

# Now we do a similar action to bring all drivers up to 54 hours. First, create a new data table consisting of the last end times.
end.day.log <- v2g.log[,max(EndTime),by=VehicleID]
setnames(end.day.log,'V1','StartTime')

# Add the location and vehicle type
end.location.log <- v2g.log[,tail(Location,1),by=VehicleID]
setnames(end.location.log,'V1','Location')
vehicle.type.log <- v2g.log[,tail(VehicleType,1),by=VehicleID]
setkey(vehicle.type.log,VehicleID)
setnames(vehicle.type.log,'V1','VehicleType')

# Combine these mini-tbles and add variables where needed.
vehicle.type.log[,State:='Parked']
vehicle.type.log <- vehicle.type.log[end.day.log]
vehicle.type.log[,':='(EndTime=ceiling(max(v2g.log[,EndTime])),Distance=0,DriveCycle=-1,Pmax=-1)]
vehicle.type.log <- vehicle.type.log[end.location.log]

v2g.log <- rbindlist(list(v2g.log,vehicle.type.log))
setkey(v2g.log,'VehicleID','StartTime')
setnames(v2g.log,c('VehicleID','VehicleType','State','StartTime','EndTime','Distance','DriveCycle','Pmax','Location'),c('Vehicle ID','Vehicle Type','State','Start time (hour)','End time (hour)','Distance (km)','Drive cycle','P_max (W)','Location'))
write.table(v2g.log,file=pp(pevi.shared,'data/outputs/V2G/BaseCase_2percent.csv'),sep=',',row.names=FALSE)

# Finding (possibly) stranded drivers
# problem.drivers <- subset(new.trip[,list(end=tail(end.time,1)),by='driver'],end<30)
