#Plug-in Electric Vehicle Infrastructure Model Description

####Version 2.1.1

####Authors: Colin Sheppard, Andy Harris
####Contributors: Allison Campbell, Jim Zoellick, Charles Chamberlin

####Schatz Energy Research Center

# 1. Purpose
The purpose of this model is to simulate the interaction between a regional fleet of plug-in electric vehicle drivers with public and private charging infrastructure over any time frame.  The model accepts as input the location, quantity, and type of electric vehicle support equipment (EVSE) throughout the study region.  Drivers and their vehicles are described by inputs that specify driver activity (a departure time and destination for every trip), the distribution of vehicle types, and parameters controlling driver behavior.  PEVI then simulates the drivers as they attempt to follow their trip itinerary and interact with the EVSE throughout the region.  The experience of drivers (individually or in aggregate) and the usage of the EVSE can be summarized at the end of a model run.  The model is intended to be used as tool for analyzing the impacts of alternative EVSE infrastructure scenarios in addition to PEV adoption rates, technology advances, market trends, and driver behaviors.

PEVI is a stochastic model, meaning that a variety of processes and decisions within the model are based on random chance.  The primary purpose of including stochastic processes in PEVI is to avoid reaching conclusions that are overly customized to suit one particular set of circumstances.  Instead, the model should be run many times with the same set of initial conditions and performance metrics should be averaged over those runs.

### Key Assumptions
1. All chargers are assumed to have a constant charging rate based on their power specifications. Charging algorithms -- such as trickle charging near the end of the session -- are not simulated.
2. Charging stations are assumed to be networked and their state (in-use vs. available) is known to all drivers via wireless communications.
3. Drivers can choose to make a mid-trip stop for charging, though the choice must be made before they begin their trip.
4. After arrival to a destination, drivers only seek available chargers in their current location.  They search for available chargers in neighboring or enroute TAZs if their next departure is imminent and they lack sufficient charge to make the trip.
5. Battery electric vehicles (BEVs) do not attempt to travel unless they have the minimum acceptable charge for their next trip plus a factor of safety.
6. A fraction of drivers will attempt to charge their vehicle even when a charge is not needed to get to their next destination.
7. Drive times between TAZ pairs are supplied as input and are applied to all vehicles equally, thus all vehicles are assumed to drive at the same speed for a given trip.

# 2. Entities, State Variables, and Scales
## 2.1 Traffic Analysis Zones (TAZs)
The TAZs are entities that describe the atomic geographic regions of the environment. All TAZs are interconnected, so a vehicle in one TAZ may travel to any other.  While they represent spatially explicit regions, the PEVI model does not store or track spatial data (polygons, lines, etc.) for each TAZ.  Instead, the spatial relationships between TAZs are encoded as a table (see “Environment – Origin Destination Table” below) describing the distances and travel times between all combinations of TAZs. In this document, TAZs are also referred to as “nodes.”  The TAZ agents are described by following variables:

````
Table 1: Traffic Analysis Zone Agent Variables
````

Category          | Variable     				 | Description
------------------|-----------------------------|-------------
Identity (static) | ID            				 | Integer identification code 												   specified in the input data 												   supplied to the model. ***A negative ID signifies a TAZ external to the region of interest, but which drivers may still access.***
Contents          | ~~chargersInTAZ (static)~~  | ~~A list of chargers 												   contained in the TAZ.~~
                  | ~~homeCharger~~   			 | ~~Every TAZ has a Level II 												   charger which is only 												   available to drivers in 												   their home TAZ.~~
                  | ***chargersByType***        | ***A master list of all chargers in the TAZ***
                  | ***availableChargersByType***     | ***A real-time, stack-type list of chargers in the TAZ that are not currently in use. ***
                  | ~~driversInTAZ (dynamic)~~  | ~~A list of drivers 												   currently in the TAZ.~~
                  | nLevels       				 | A 5-value list containing 												   the number of chargers of 												   each level (0 [home 												   charging], 1, 2, 3, ***or 4 (battery-swapping).***)

## 2.2 Environment
The environment is the entity where all the agents live and interact. In this model it is the geographic region described by the input data. The environment is defined by several global state variables and parameters which are available to all agents in the model for reference or use. 

````
Table 2: Environment Variables
````

Category | Variable      | Description
-------- | ------------- | ------------
Global   | time          | Numeric variable containing the decimal hour of the day, where 0 is midnight, 12 is noon, and 1.5 is 1:30am.
         | schedule      | A compound variable containing the active list of scheduled events (see section Process Overview and Scheduling below).
         | odTable (Origin-Destination Table)| Distance and time between any two TAZs.  The table has the following columns:
         | | - *odFrom:* Origin TAZ
         | | - *odTo:* Destination TAZ
         | | - *odDist:* Travel distance in miles
         | | - *odTime:* Travel time in decimal hours
         | | - *odEnroute:* List of the TAZs along the route between the origin and destination, used for seeking level 3 charging.
         | parameters    | A table of parameter values indexed by their name.  See Table 11 for a listing of parameters along with their default values.
         
## 2.3 Drivers
Driver agents are used in the model to simulate individual driver and vehicle characteristics combined. These entities are described in the model by the following state variables:

````
Table 3: Driver Agent Variables
````

Category | Variable | Description
---------|----------|------------
Vehicle (static)|thisVehicleType|String variable containing the name of the vehicle model upon which the other variables of this category are based (e.g. “Leaf” or “Volt”).
|isBEV? | A boolean flag indicating whether the vehicle is a BEV, if not, vehicle is assumed to be a PHEV (conventional vehicles are not modeled).
| chargingOnAWhim? | A boolean flag indicating whether the vehicle is seeking a charger because they actually need to charge or for some other, less critical reason.
| batteryCapacity (kWh) | The default quantity of stored energy by the battery bank when fully charged.  If the vehicle is a PHEV, then the battery capacity indicates the amount of energy available to drive the vehicle in charge depleting mode.
| electricFuelConsumption (kWh / mile)|The default amount of battery electricity required to travel 1 mile.
| hybridFuelConsumption (gallon / mile) | The default fuel amount of gasoline required to travel 1 mile for a PHEV in charge sustaining mode.  (N/A for BEVs).
| ***chargerPermissions*** | ***An array of lists for each TAZ that contain any chargers the driver has privileged access to (i.e. home charging, multi-unit charging, or workplace charging restricted from the public.)***
Demography (static) | homeTAZ | The home TAZ of the driver. This is not necessarily where the driver begins the day, nor will all drivers have a home TAZ (to account for corridor travel originating outside target region.) ~~but rather is inferred based upon the trip type column in the drivers itinerary (see below).~~ 
| probabilityOfUnneededCharge | The probability that the driver will choose to attempt to charge their vehicle despite not actually needing the charge.
| ***externalDistance (miles)*** | ***The driving distance from TAZ external to the region of interest to a gateway TAZ within the region of interest. The result of a random draw from an externally supplied distribution function.***  
| ***externalTime (hours)*** | ***The driving time from TAZ external to the region of interest to a gateway TAZ within the region of interest. The result of a random draw from an externally supplied distribution function.***  
Operation (dynamic) | state | A discrete integer value that represents the current state of a driver (Traveling, Not Charging, Charging), and used to decide which procedures to execute.
| currentTAZ | The TAZ where the driver is currently located, set to “nobody” while in transit.
| stateOfCharge | The fraction of useable energy remaining in the vehicle’s battery.  A value of 1 indicates a fully charged battery and a value of 0 indicates the battery is effectively empty.  Note, if the vehicle is a PHEV, then 0 indicates charge sustaining mode which does not imply the battery is fully depleted.
| currentCharger | The charger with which the driver is currently charging.  Set to ‘nobody’ if the driver is not charging.
| itinerary, currentItinRow | A compound variable containing the intended itinerary of the driver for one day.  Each row of the itinerary represents a single trip and includes the following columns: 
| | - *itinFrom:* origin TAZ
| | - *itinTo:* destintion TAZ
| | - *itinDepart:* departure time (decimal hour of the day)
| | ~~- *itinTripType:* type of trip (e.g. HW for home to work, WO for work to other, etc.)~~
| | - *itinChangeFlag:* (“none”, “delay”, “reroute”)
| | - *itinDelayAmount:* The cumulative time a driver has been delayed from their original itinerary.
| | The variable currentItinRow is used to keep track of the next trip in the driver’s itinerary (or the current trip if the driver state is “traveling”).  ~~This model description uses the following variable names to describe specific cells in the itinerary table:~~
| | ~~- *itinNextDepartTime:* the departure time associated with the next trip in the itinerary~~
| willingToRoam? | Boolean value that indicates whether the driver would consider traveling to a neighboring or en-route TAZ to charge.
Tracking (dynamic) | numDenials | The number of occurrences when the driver wanted/needed to charge but was unable due to a lack of available chargers.

## 2.4 Chargers
Charging agents represent the electric vehicle supply equipment installed at a given TAZ.  Charging stations can either be level 0, 1, 2, 3 ***or 4***.  Level 0 charging indicates home charging, which operates at the capacity of a level 2 charger. ***Home charging will either be limited to single drivers (single-unit homes) or give permission to multiple drivers (for multi-unit homes). Level 4 charging represents battery-swapping stations.***  In practice, most level 2 chargers will also have level 1 capability, however in this model they are represented as two separate chargers.  The charger agents are currently described by the following state variables: 

````
Table 4: Charger Agent Variables
````

Category | Variable | Description
---------|----------|------------
Infrastructure (static) | chargerType | Integer variable indicating whether the station is a level 0, 1, 2, 3, ***or 4***.
| location | A variable referencing the TAZ where the charger is located.
| chargeRate (kWh / hr) | The rate at which the charger delivers energy to the vehicle. ***For level 4 chargers, chargeRate is set to approximately replicate the time spent at the swap station.***
| energyPrice ($/kWh) | The price of energy for charging at this charger
Operation (dynamic) | current-driver | The driver currently being served by the charger.  If “nobody” then the charger is considered available for beginning a new charging session.  ~~If the charger is a ***level 0*** home charger, then this variable will always have a value of “nobody” to indicate that any driver in their home TAZ can charge at their home. ***Level -1 chargers are only available to multi-unit-home cars in their home TAZ, but not every driver can have access at the same time.***~~
Tracking (dynamic) | energyDelivered (kWh) | The cumulative amount of energy delivered by the charger up to the current moment.
| numSessions | Integer count of the number of discrete charging sessions with drivers. **(currently unused)**
    
Scales **(What?)** are used to describe changes in the model’s entities temporally and spatially. The PEVI model has a temporal extent of one 24-hour day.  Time is modeled using discrete event simulation (see section Process Overview and Scheduling below).  The spatial extent of the model is defined by the TAZs.  ~~For the Humboldt County implementation, the region is discretized into 52 TAZs.~~

# 3. Process Overview and Scheduling
In the PEVI model, time and actions are managed using discrete event simulation (DES).  Model processes are maintained as an ordered schedule of events.  An event consists of a time, an agent, and an action.  After initialization, the first event on the schedule is dispatched, at which point the specified agent performs the specified action; then the next event on the schedule is dispatched, and so on.  Events can be created during initialization or dynamically generated during model execution. 

In PEVI, events are principally associated with drivers.  Figure 1 presents a flow chart of the driver decision logic.  The chart contains a representation of the different states that a driver can have (red rectangles), the event schedulers that determine when a driver executes an event (yellow triangles), the events that control process flow (arrows labeled with green rectangles), and the decisions that are evaluated to inform the process flow (blue diamonds).  Descriptions of the states, event schedulers, events, and decisions are listed in Table 5.

In Figure 1 event schedulers are depicted as attached to states on the upstream side of the process flow.  This placement is intentional and closely tied to the management of PEVI as a DES.  At any time, drivers have complete knowledge about the state of their vehicle (state of charge, fuel consumption, etc.) and their itinerary.  This means, that as drivers enter any state, they can determine the time at which they will exit that state and perform an event.  For example, when the Traveling state is entered, the driver knows where they are going (by virtue of their itinerary) and based on the global origin-destination table, they can determine when they will arrive.  The PEVI model takes advantage of this foresight and model scheduling is structured so that drivers schedule events as they enter a new state. 

```	
(Flow chart image here)
	
Figure 1: This flow chart illustrates the three driver states (red rectangles), the events that control transitions between states (arrows labeled with green rectangles), the decision logic used to inform transitions (blue diamonds) and the event schedulers that dictate events are executed (orange triangles). See Table 5 for a description of the key elements in the flow chart. 
```
```
Table 5: Overview of driver states, event schedulers, events, and decisions.
```

Type | Name | Description | Results
-----|------|-------------|--------
State|Not Charging| This state describes a driver that is parked but not charging.  The driver could be at home or any other TAZ in the model. | N/A
State|Traveling|Drivers in the *Traveling* state are on their way from one TAZ to another.  The model does not track drivers along their path, instead they “appear” at their destination when the *Arrive* event is executed.|N/A
State|Charging|Drivers in the *Charging* state are parked and engaged in a charging session.|N/A
Event Scheduler|Itinerary|As drivers enter the *Not Charging* state through this path, they schedule the *Depart* event based on the *Itinerary* submodel (Section Itinerary). If the next trip on their itinerary was supposed to occur in the past, the driver executes the *Depart* event immediately. |Depart Event Scheduled
Event Scheduler|Wait Time|As drivers enter the *Not Charging* state through this path, they schedule the *Depart* or *Retry Seek* event based on the *Wait Time* submodel (Section Wait Time)|Depart or Retry Seek Event Scheduled
Event Scheduler|Travel Time|As drivers enter the *Traveling* state, they schedule the *Arrive* event based on the *Travel Time* submodel (Section Travel Time).|Arrive Event Scheduled
Event Scheduler|Charge Time|As drivers enter the *Charging* state, they schedule two events to occur based on the *Charge Time* submodel (Section Charge Time).  Either the *End Charge* and *Retry Seek* event are schedule (the latter to immediately follow the former) or the *End Charge* and *Depart *events are schedule.|End Charge and either Retry Seek or Depart Event Scheduled
Event|Depart|The driver executes the *Need to Charge* decision and either transitions to the *Traveling* state or executes the *Seek Charger* decision.|Transition to Traveling or Not Charging
Event|Retry Seek|The driver immediately executes the *Seek Charger* decision.|Transition to Charging, Not Charging, or Traveling
Event|Arrive|The driver executes the *Need to Charge?* decision and transitions to a new state accordingly.  If the driver is at home and has finished their itinerary, then they transition to *Charging* and schedule the *End Charge* event, after which they stop.|Transition to Charging or Not Charging
Event|End Charge|The driver SoC variable is updated to reflect the charging session, then driver transitions to *Not Charging*.|Transition to Not Charging
Decision|Need to Charge?|The driver estimates whether they have sufficient charge for their next trip according to the *Need to Charge?* submodel (Section Need to Charge).|Report Yes or No
Decision|Seek Charger|The driver seeks an available charger according to the *Seek Charger* submodel (Section Seek Charger) and responds accordingly by transitioning to any of the possible states.|Transition to Charging, Not Charging, or Traveling

# 4. Design Concepts
## 4.1 Emergence
## 4.2 Objectives
## 4.3 Adaption
## 4.4 Sensing
Driver agents can sense the availability and distance to a charger node. This information aids decision making about where to seek out available chargers if one is not available at a driver’s current destination.
## 4.5 Interaction
Interaction between vehicles and chargers is incorporated. The vehicle agents directly interact with a charger agent by querying to find out if charging is available. If charging is available the vehicle changes their state to charging and the charger’s state changes to occupied.  Vehicles interact with other vehicles indirectly by competing for a charging resource. When a vehicle interacts with a charger, that charger becomes unavailable for all other vehicles.  
## 4.6 Stochasticity
Several pseudorandom processes are used to introduce variability in the model.  ~~The incorporated drive times between zones are represented as the mean of a normal distribution (wish list item).~~  Battery capacity and energy efficiency are normally distributed. ~~anxiety proneness are also normally distributed~~  If multiple vehicles are waiting for a charger when one becomes available, a vehicle is selected randomly.  For simple decisions that a driver must make over the course of a day, a Bernoulli random variable is used.  
## 4.7 Initialization
The input to the PEVI model consists of five data sets, summarized in Table 6:

````
Table 6: PEVI Inputs
````

Input | Description
----- | -----------
OD Data |  Distance and drive times between each TAZ; used to calculate SoC reduction for each trip.
Itinerary | Provides vehicles with schedules throughout the day.
Chargers | Number and type of charging stations at each TAZ.
Charger Type | The charging rate, energy price, and installation price for each level charger.
***Starting SoC*** | ***Provides points of a function mapping random draws to the starting SoC for each vehicle; these are used to interpolate starting vehicle SoC during runtime.***
***External TAZs*** | ***Provides points of a function mapping random draws for the distance from an external TAZ outside the area of interest to a gateway TAZ within the area of interest***
***privileged access*** | ***Determines which non-public chargers, if any, a driver has access to.***
Vehicle Type | The electric fuel consumption, hybrid fuel consumption, and fraction of total PEVs represented by each vehicle type (e.g. Leaf or Volt)

~~The first set includes the distances and drive times between each TAZ, used to calculate the reduction in SoC that occurs when vehicles travel to a new zone.  The second data set is the schedule file which provides vehicles with trip scheduling throughout the day.  The third data set identifies the number and type of charging stations located at each TAZ.~~ 
Three driver agent characteristics are set at the start of each modeling day:  schedule, state of charge and satisfaction. The driver schedule establishes the nodes the driver will travel to, along with the departure and arrival times corresponding to each node in their schedule. Based on the assumption that not all drivers will charge at night, the starting state of charge is based on a Bernoulli random draw. ~~drivers charge their vehicle at night, state of charge is initialized at 100%. Each driver starts the day with a satisfaction of one, which may be reduced as complications arise during the day.~~
## 4.8 Observation
The model output important for evaluating alternative designs is driver inconvenience and charger station duty factors. The model will output a "pain" score based upon the sum of inconveniences observed by all drivers (from delays, unavailable chargers, unscheduled trips to charge, and stranded vehicles). ~~mean value of all vehicle agents’ mean driver satisfaction over the day.~~ The model will also output a mean value of all charging agents’ duty factor. ~~Additional output used to compare infrastructure alternatives are plots of mean driver satisfaction over time and mean duty factor over time. Overall driver satisfaction is calculated by averaging the end of day driver satisfaction.~~ Additional output used to troubleshoot and understand model operations include:

1. Table output for characteristics of driver inconvenience
2. Table output for driver travel info at every arrival
3. Table output for driver waiting and inactivity
4. Table output for charging events and time spent at a charger
5. Table output for when and where drivers need to charge
6. Table output for drivers selecting chargers
7. Table output for when and where drivers break up trips
8. Table output summarizing rivers, TAZs, chargers, and trips.

# 5. Submodel Details
The following sections provide detailed descriptions of the PEVI submodels.

## 5.1 Itinerary
***Describe how demand model + travel survey data are combined to produce the itinerary for all drivers.***

## 5.2 Wait Time
The wait time submodel is an event scheduler.  It is executed after a driver has performed the Seek Charger decision and found none that are available.  The submodel decides whether the driver will attempt to retry finding a charger or, if sufficient charge is available, abandon the charging attempt and schedule a departure.  
To make this determination, four values are estimated: 

- remainingRange: the number of miles remaining (set to a very large number if isBEV? is false),

	![equation](http://latex.codecogs.com/gif.latex?%5Cfrac%7B%5Ctextup%7BstateOfCharge%7D%20*%20%5Ctextup%7BbatteryCapacity%7D%7D%7B%5Ctextup%7BelectricFuelConsumption%7D%7D)<!---markdown_formula--->
	<!---$\frac{\textup{stateOfCharge} * \textup{batteryCapacity}}{\textup{electricFuelConsumption}}$---><!---pandoc_formula--->

- tripDistance: the number of miles to complete the next trip in the driver’s itinerary
- journeyDistance: the number of miles to complete all of the remaining trips in the driver’s itinerary
- timeUntilDepart: the time in hours remaining before the vehicle is due to depart on its next trip

The following table details how either the decision is made and at what time the corresponding event is to be scheduled:

````
Table 7: Wait Time Algorithm
````

If | Then
---|----- 
remainingRange / chargeSafetyFactor < tripDistance | Schedule *Retry Seek* event to occur after a random amount of time based on an exponential distribution with mean of waitTimeMean.
tripDistance <= remainingRange / chargeSafetyFactor < journeyDistance | If timeUntilDepart > willingToRoamTimeThreshold, schedule *Retry Seek* event to occur after a random amount of time based on an exponential distribution with mean of waitTimeMean and a maximum allowed value of (timeUntilDepart – willingToRoamTimeThreshold); If timeUntilDepart <= willingToRoamTimeThreshold, schedule *Depart* event to occur after timeUntilDepart hours.
remainingRange / chargeSafetyFactor >= journeyDistance| Schedule *Depart* event to occur after timeUntilDepart hours.

## 5.3 Travel Time
**Describe how this is based on OD Table and how that table is created using GIS road network data. Andy will update this with information on how the google API was used.**

## 5.4 Charge Time
The charge time submodel is an event scheduler.  It is executed after a driver has performed the *Seek Charge*r decision, selected an available charger, and optionally traveled to that charger.  The submodel decides whether the driver will attempt to retry finding a charger later in the day (necessary to allow drivers to make temporary use of lower level chargers when higher levels are currently unavailable) or to schedule the *End Charge* event.
To make this determination, the following values are estimated:
 
- chargerInOriginOrDestination: this Boolean describes whether the charger is located in a TAZ that’s a part of the driver’s itinerary vs. a neighboring TAZ or an en-route TAZ.
- timeUntilDepart: the amount of time before the next trip in the driver’s itinerary.
- tripDistance: the number of miles to complete the next trip in the driver’s itinerary
- tripChargeTimeNeed: the amount of charging time needed to complete the next trip in the itinerary, if isBev is FALSE then set this to 0 to indicate that there is no need for charge to complete the trip, otherwise use the following formula: 

````
Equation 1:
````
![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BtripChargeTimeNeed%7D%20%3D%20%5C%5C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5C%7B%200%2C%5Cfrac%7B%5Ctextup%7BtripDistance%7D%20*%20%5Ctextup%7BchargeSafetyFactor%7D%20*%20%5Ctextup%7BelectricFuelConsumption%7D%20-%20%5Ctextup%7BstateOfCharge%7D%20*%20%5Ctextup%7BbatteryCapacity%7D%7D%7B%5Ctextup%7BchargeRate%7D%7D%20%5Cright%20%5C%7D)<!---markdown_formula--->
<!---$\textup{tripChargeTimeNeed} = \\\\\textup{max}\left \{ 0,\frac{\textup{tripDistance} * \textup{chargeSafetyFactor} * \textup{electricFuelConsumption} - \textup{stateOfCharge} * \textup{batteryCapacity}}{\textup{chargeRate}} \right \}$---><!---pandoc_formula--->

- journeyDistance: the number of miles to complete all of the remaining trips in the driver’s itinerary
- journeyChargeTimeNeed: the amount of charging time needed to complete the remaining trips in the itinerary:

````
Equation 2:
````

![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BjourneyChargeTimeNeed%7D%20%3D%20%5C%5C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5C%7B%200%2C%5Cfrac%7B%5Ctextup%7BjourneyDistance%7D%20*%20%5Ctextup%7BchargeSafetyFactor%7D%20*%20%5Ctextup%7BelectricFuelConsumption%7D%20-%20%5Ctextup%7BstateOfCharge%7D%20*%20%5Ctextup%7BbatteryCapacity%7D%7D%7B%5Ctextup%7BchargeRate%7D%7D%20%5Cright%20%5C%7D)<!---markdown_formula--->
<!---$\textup{journeyChargeTimeNeed} = \\\\\textup{max}\left \{ 0,\frac{\textup{journeyDistance} * \textup{chargeSafetyFactor} * \textup{electricFuelConsumption} - \textup{stateOfCharge} * \textup{batteryCapacity}}{\textup{chargeRate}} \right \}$---><!---pandoc_formula--->
 
- fullChargeTimeNeed: the amount of charging time to complete a full charge,

````
 Equation 3:
````

![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7Bif%20chargerType%20%3D%203%2C%20then%20fullChargeTimeNeed%20%3D%7D%5C%5C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5C%7B%200%2C%5Cfrac%7B%5Cleft%20%280.8-%5Ctextup%7BstateOfCharge%7D%20%5Cright%20%29%20*%20%5Ctextup%7BbatteryCapacity%7D%7D%7B%5Ctextup%7BchargeRate%7D%7D%20%5Cright%20%5C%7D%5C%5C%5C%5C%5Ctextup%7Botherwise%2C%20fullChargeTimeNeed%20%3D%7D%5C%5C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5C%7B%200%2C%5Cfrac%7B%5Cleft%20%28%201%20-%20%5Ctextup%7BstateOfCharge%7D%20%5Cright%20%29%20*%20%5Ctextup%7BbatteryCapacity%7D%7D%7B%5Ctextup%7BchargeRate%7D%7D%20%5Cright%20%5C%7D)<!---markdown_formula--->
<!---$\textup{if chargerType = 3, then fullChargeTimeNeed =}\\\\\textup{max}\left \{ 0,\frac{\left (0.8-\textup{stateOfCharge}  \right ) * \textup{batteryCapacity}}{\textup{chargeRate}} \right \}\\\\\textup{otherwise, fullChargeTimeNeed =}\\\\\textup{max}\left \{ 0,\frac{\left ( 1 - \textup{stateOfCharge} \right ) * \textup{batteryCapacity}}{\textup{chargeRate}} \right \}$---><!---pandoc_formula--->
- timeUntilEndCharge: the anticipated time in hours remaining before the driver chooses to end charging or the vehicle is fully charged.  The following table describes how this value is calculated:

````
Table 8: Calculation for timeUntilEndCharge
````


If|Then timeUntilEndCharge = | Additional Actions
--|--------------------------|-------------------
fullChargeTimeNeed <= tripChargeTimeNeed | fullChargeTimeNeed |
timeUntilDepart < tripChargeTimeNeed | tripChargeTimeNeed | Delay itinerary with next trip occurring tripChargeTimeNeed hours from the present moment.
chargerInOriginOrDestination | min(timeUntilDepart, fullChargeTimeNeed) | 
chargerType= 3 | min(timeUntilDepart, fullChargeTimeNeed, journeyChargeTimeNeed) |
otherwise | min(timeUntilDepart, tripChargeTimeNeed) |

The following table details how the decision is made and at what time the corresponding event is to be scheduled:

````
Table 9: Charge Time Event Scheduling
````

If | Then
---|-----
*chargingOnAWhim? = FALSE* ***(originally isBEV?=TRUE, now matches code)*** AND 0 < timeUntilEndCharge < fullChargeTimeNeed AND chargerType < 3 AND (timeUntilEndCharge > timeUntilDepart OR timeUntilEndCharge < journeyChargeTimeNeed) AND timeUntilDepart > willingToRoamTimeThreshold | Schedule *Retry Seek* event to occur after a random amount of time based on an exponential distribution with mean of waitTimeMean and a maximum allowed value of (timeUntilDepart –willingToRoamTimeThreshold).
otherwise | Schedule *End Charge* event to occur after timeUntilEndCharge hours.

## 5.5 Need to Charge?
First estimate the following values:

- tripDistance: the number of miles to complete the next trip in the driver’s itinerary
- journeyDistance: the number of miles to complete all of the remaining trips in the driver’s itinerary
- remainingRange: the number of miles remaining, see Equation 1

Now base the decision on the following table, where chargingOnAWhim? is initialized to false:

````
Table 10: Need to Charge Decision Algorithm
````

If | Then
:---:|:-----:
calling event is “Arrive” AND remainingRange / chargeSafetyFactor < journeyDistance | Report yes.
Else If	| Then
calling event is “Depart” AND remainingRange / chargeSafetyFactor < tripDistance | Report yes.
Else If | Then
calling event is “Arrive” AND timeUntilDepart >= willingToRoamTimeThreshold AND randomDrawFromUniformDist < probabilityOfUnneededCharge | Report yes and set *chargingOnAWhim?* to true.
Otherwise | Report no.

## 5.6 Seek Charger
This submodel is based on an economic model that compares the total cost of charging (including the opportunity cost of a driver’s time) from all relevant charging alternatives, selecting the least cost option.
The submodel consists of the following actions:

1. Set willingToRoam? to *true* if isBEV is *true* AND timeUntilDepart is less than the parameter willingToRoamTimeThreshold AND chargingOnAWhim? is *false*, otherwise set to *false*.

2. Find the number of available chargers by type and location within range of the driver.  If willingToRoam? is set to false, then only consider charges in currentTAZ.  Otherwise, include any chargers in currentTAZ, neighboring TAZs (all TAZs within a driving distance set by chargerSearchDistance), and en-route TAZs between the current TAZ and the next destination TAZ in the driver’s itinerary.  The index ‘i’ will be used below to reference each combination of TAZ and charger type with at least one available charger.  Note that some of the variables with the prefix “extra” will be zero for chargers in the current TAZ or en-route as they only apply to travel that’s additional to the driver’s itinerary.  The one exception to this is extraTimeForCharging, which will be non-zero for en-route TAZs because the time spent is an opportunity cost to the driver. If no available chargers are found, then increment the driver variable numDenials, transition to the state *Not Charging* and stop this action.

***3. If the driver has access to any special-permission chargers within driving range, determine if the alt-energy-price of the special-permission charger is less than the public charger of the ams TAZ and charger level. If the alt-energy-price is cheaper (or if no public chargers are available), use the special-permission chargers (and the alt energy price) in the following calculations.***

4. Calculate the following values: 
	a. level3AndTooFull? This boolean value is true if the charger under consideration is level 3 and the driver’s state of charge is >= 0.8 or, for enroute chargers, will be >= 0.8 when the vehicle reaches the intermediate destination.  If this parameter is true, then the alternative is not considered.
	b. level3TimePenalty  Set this to a large value if the distance to the destination (in the case of enroute charging, from the intermediate TAZ) is greater than vehicle can go on a full level 3 charge (80% state of charge). Otherwise set to 0.  This penalizes level 3 charging when a level 1 or 2 charge might get the driver there without an additional stop or another charging session.
	c. tripOrJourneyEnergyNeed.  This value depends on the amount of time before the next departure in the driver’s itinerary as well as the current state of charge and the charger type. If timeUntilDepart < willingToRoamThreshold, then only the energy needed for the next trip is considered, otherwise the energy needed for the journey is used. If the energy needed for the trip or journey is greater than the energy needed to fill the battery (or in the case of level 3, achieved 80% state of charger) then tripOrJourneyEnergyNeed is set to the battery limiting value. As a formula, the value is calculated as:
	![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7Bif%20timeUntilDepart%7D%20%3C%20%5Ctextup%7BwillingToRoamThreshold%3A%7D%5C%5C%5Ctextup%7Bdistance%20%3D%20tripDistance%7D%5C%5C%5Ctextup%7Botherwise%3A%7D%5C%5C%5Ctextup%7Bdistance%20%3D%20journeyDistance%7D%5C%5C%5C%5C%5Ctextup%7Bif%20level%20%3D%203%3A%7D%5C%5C%5Ctextup%7BtripOrJourneyEnergyNeed%7D%20%3D%20%5Ctextup%7Bminimum%20of%7D%5C%5C%20%5Ctextup%7Bmax%7D%5Cleft%20%5B%200%2C%5Ctextup%7Bdistance%7D%20*%20%5Ctextup%7BchargeSafetyFactor%7D%20*%20%5Ctextup%7BelectricFuelConsumption%7D%20-%20%5Ctextup%7BstateOfCharge%7D%20*%20%5Ctextup%7BbatteryCapacity%7D%20%5Cright%20%5D%2C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5B%200%2C%20%5Cleft%20%28%200.8%20-%20%5Ctextup%7BstateOfCharge%7D%20%5Cright%20%29%20*%20%5Ctextup%7BbatteryCapacity%7D%20%5Cright%20%5D%5C%5C%5C%5C%5Ctextup%7Botherwise%3A%7D%5C%5C%5Ctextup%7BtripOrJourneyEnergyNeed%20%3D%20minimum%20of%7D%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5B%200%2C%5Ctextup%7Bdistance%7D%20*%20%5Ctextup%7BchargeSafetyFactor%7D%20*%20%5Ctextup%7BelectricFuelConsumption%7D%20-%20%5Ctextup%7BstateOfCharge%7D%20*%20%5Ctextup%7BbatteryCapacity%7D%20%5Cright%20%5D%2C%5C%5C%5Ctextup%7Bmax%7D%5Cleft%20%5B%200%2C%20%5Cleft%20%28%201%20-%20%5Ctextup%7BstateOfCharge%7D%20%5Cright%20%29%20*%20%5Ctextup%7BbatteryCapacity%7D%20%5Cright%20%5D) <!---markdown_formula--->
	<!---$\textup{if timeUntilDepart} < \textup{willingToRoamThreshold:}\\\textup{distance = tripDistance}\\\textup{otherwise:}\\\textup{distance = journeyDistance}\\\\\textup{if level = 3:}\\\textup{tripOrJourneyEnergyNeed} = \textup{minimum of}\\ \textup{max}\left [ 0,\textup{distance} * \textup{chargeSafetyFactor} * \textup{electricFuelConsumption} - \textup{stateOfCharge} * \textup{batteryCapacity} \right ],\\\textup{max}\left [ 0, \left ( 0.8 - \textup{stateOfCharge} \right ) * \textup{batteryCapacity} \right ]\\\\\textup{otherwise:}\\\textup{tripOrJourneyEnergyNeed = minimum of}\\\textup{max}\left [ 0,\textup{distance} * \textup{chargeSafetyFactor} * \textup{electricFuelConsumption} - \textup{stateOfCharge} * \textup{batteryCapacity} \right ],\\\textup{max}\left [ 0, \left ( 1 - \textup{stateOfCharge} \right ) * \textup{batteryCapacity} \right ]$---><!---pandoc_formula--->
	d. extraTimeForTravel(i), extraDistanceForTravel(i): the additional travel time and distance needed to accommodate the detour, equal to the difference between first traveling to the intermediate TAZ, then to the destination TAZ vs. traveling straight to the destination TAZ.
	e. extraEnergyForTravel(i): the energy needed to accommodate the extra travel, calculated by: 
	![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BextraDistanceForTravel%7D_%7Bi%7D%20*%20%5Ctextup%7BelectricFuelConsumption%7D%20*%20%5Ctextup%7BchargeSafetyFactor%7D) <!---markdown_formula--->
	<!---$\textup{extraDistanceForTravel}_{i} * \textup{electricFuelConsumption}  * \textup{chargeSafetyFactor}$---><!---pandoc_formula--->
	f. extraTimeUntilEndCharge(i): if chargerInOriginOrDestination(i) is true, then this value is set to the amount of delay in the driver’s itinerary that would be necessary to use the charging alternative. Calculate as:
	![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BCharger%20in%20origin%3F%7D%5C%5C%20%5Ctextup%7BextraTimeUntilEndCharge%7D_%7Bi%7D%20%3D%20%5Ctextup%7Bmax%7D%5Cleft%20%5C%7B%200%2C%20%5Ctextup%7BtripChargeTimeNeed%20-%20timeUntilDepart%7D%20%5Cright%20%5C%7D%5C%5C%20%5Ctextup%7BOtherwise%2C%7D%5C%5C%20%5Ctextup%7BextraTimeUntilEndCharge%20%3D%200%7D)<!---markdown_formula--->
	<!---$\textup{Charger in origin?}\\\textup{extraTimeUntilEndCharge}_{i} = \textup{max}\left \{ 0, \textup{tripChargeTimeNeed - timeUntilDepart}\right\}\\\textup{Otherwise,}\\\textup{extraTimeUntilEndCharge = 0}$---><!---pandoc_formula--->
***(ADD IN TO THE "OTHERWISE" STATEMENT THAT THIS MEANS THE CHARGER IS IN THE DESTINATION. IT'S NOT CLEAR RIGHT NOW.)***
If chargerInOriginOrDestination(i) is false, then the value is an estimate of the extra time a driver would spend charging, equal to the value of timeUntilEndCharge as calculated by the Charge Time submodel (Section Charge Time) with the following modifications:
		f.i. timeUntilDepart is decreased by the time of travel from the origin TAZ to TAZ(i)
		f.ii. stateOfCharge is decreased by  where tripDistancei is the distance in miles from the origin TAZ to TAZ(i)
		f.iii. tripDistance and journeyDistance are assumed to begin at TAZ(i)
5. Estimate the cost of the alternative,
````	
Equation 4:
````
	![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BCost%7D_%7Bi%7D%20%3D%20%5Ctextup%7BtimeOpportunityCost%7D%20*%20%5Cleft%20%5B%20%5Ctextup%7BextraTimeUntilEndCharge%7D_%7Bi%7D%20&plus;%20%5Ctextup%7BextraTimeForTravel%7D_%7Bi%7D%20&plus;%20%5Ctextup%7Blevel3TimePenalty%7D_%7Bi%7D%20%5Cright%20%5D%5C%5C%20&plus;%20%5Ctextup%7BenergyPrice%7D_%7Bi%7D%20*%20%5Cleft%20%5B%20%5Ctextup%7BtripOrJourneyEnergyNeed%7D%20&plus;%20%5Ctextup%7BextraEnergyForTravel%7D_%7Bi%7D%20%5Cright%20%5D)<!---markdown_formula--->
	<!---$\textup{Cost}_{i} = \textup{timeOpportunityCost} * \left [ \textup{extraTimeUntilEndCharge}_{i} + \textup{extraTimeForTravel}_{i} + \textup{level3TimePenalty}_{i} \right ]\\ + \textup{energyPrice}_{i} * \left [ \textup{tripOrJourneyEnergyNeed} + \textup{extraEnergyForTravel}_{i} \right ]$---><!---pandoc_formula--->
6. Chose the alternative with the minimum cost.  If TAZ(i)  is the current TAZ, call the *ChargeTime* event scheduler.   Otherwise update the driver’s itinerary to include the new destination TAZ (unless TAZ(i) is the destination TAZ) with a depart time equal to now and call the *TravelTime* event scheduler.

## 5.7 Break Up Trip
- If a driver has a full battery and cannot make the next trip (or if the stateOfCharge >= 0.8 and the currentTAZ only has level 3 chargers available), then they attempt to break the trip into smaller trips with intermediate stops for charging.
- The driver only considers en-route TAZs that are reachable given their range.
- The search is first restricted to reachable en-route TAZs that would allow the driver to reach the ultimate destination in one trip after recharging (note that this must be based on a stateOfCharge of 0.8 if only level 3 chargers are available in the candidate TAZ).  If no such TAZs can be found, or all of these TAZs have a score of 0, then all reachable en-route TAZs are considered.
- Each reachable en-route TAZ is assigned a score equal to the number of available chargers or a certain level times the level number (E.g. if two level 3 and one level 2 chargers are available then the score would be 2 * 3 + 1 * 2 = 8).  If the TAZ is the driver’s home, then 8 is added to the score for that TAZ (in other words, a home charger is as valuable as 4 level 2 chargers but not as valuable as 3 level 3 chargers).  **Do we want to judge multi-unit chargers more harshly? How much?**
- The TAZ with the highest score is selected (ties are broken by selecting the furthest TAZ from the current location).  If no en-route TAZs have any available chargers (i.e. if they all have a score of 0), then the driver selects the most distance reachable TAZ.

## 5.8 Distance From To / Time From To
***The distance-from-to and time-from-to submodels is called for each driver during setup to set that driver's externalDistance and externalTime agent variables. Both submodels require an external file that contains the external distance / external time values pegged to a random draw boundary. ***

***1. When each driver agent is created, perform a random draw.***

***2. Iterate through sequential pairs of random draw boundaries until the pair that bounds the random draw.***

***3. Interpolate the external time or external distance boundary value corresponding to the random draw between the boundaries.***

## 5.9 Interpolate From Draw
***This reporter sub model is used in the distance-from-to/time-from-to subroutines (5.8) and to establish each driver's starting state of charge. It requires as inputs a list of value bounds, the values associated with each bound, and the random draw result.***

1. Starting with the lowest bound, check each combination bound(i) and bound(i+1) to see if the random draw result is greater than or equal to bound(i) but less than bound(i+1)
2. With value(i) and value(i+1) corresponding to bound(i) and bound(i+1) respectively, calculate the  reporter value using 
````
Equation 4:
````
![equation](http://latex.codecogs.com/gif.latex?%5Ctextup%7BReporter%7D%20%3D%20%5Cfrac%7Bvalue_%7Bi&plus;1%7D-value_%7Bi%7D%7D%7Bbound_%7Bi&plus;1%7D-bound_%7Bi%7D%7D%5Cast%20%5Cleft%20%28%20random.draw%20-%20bound_%7Bi%7D%20%5Cright%20%29)


# 6. Parameters

````
Table 11: Model Parameters
````

Name | Description | Default Value
-----|-------------|:--------------:
chargeSafetyFactor | Multiplier used to approximate the safety factor drivers assume necessary to ensure a trip can be made.|1.1
chargerSearchDistance | The distance in miles used to define what TAZs are considered “neighbors” for the purpose of finding a charger. |5
willingToRoamTimeThreshold | The amount of time in hours at which point a driver will consider traveling to neighboring or en-route TAZs in order to charge vs. only considering TAZs in their current location. | 1
timeOpportunityCost | The value of a driver’s time to his or herself in units of $ / hour. | 12.50
fracPHEV | The fractions of PEV vehicles that are PHEV vs BEV. | 0.5
probabilityOfUnneededCharge | The probability that a driver will choose to charge despite not actually needing it. | 0.1
electricFuelConsumptionSD | Standard deviation of the truncated normal distribution used to distribute electric fuel consumption amongst the drivers.  In units of kWh/mile. | 0.02
electricFuelConsumptionRange | Range of the truncated normal distribution used to distribute electric fuel consumption amongst the drivers.  In units of kWh/mile. | 0.1

