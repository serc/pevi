extensions [time profiler structs table]
__includes["setup.nls" "reporters.nls"]

globals [    
  seed-list
  seed-list-index
  
  taz-table
  od-from
  od-to
  od-dist
  od-time
  od-enroute
  od-performance  ;; not yet in use
  
  small-num
  
  n-tazs
  n-charger-types
  
  soc-cumulative-fraction
  start-soc
  ext-taz-cumulative-fraction
  external-time-bound
  external-dist-bound
  
  batch-setup?
  
;; FILE PATHS
  model-directory
  param-file-base  ;; Set externally, leads to pev-shared. Makes param files more accessible between machines.
  parameter-file
  charger-input-file
  charger-type-input-file
  driver-input-file
  od-input-file
  vehicle-type-input-file
  outputs-directory
  starting-soc-file
  ext-dist-time-file
  charger-permission-file
  
;; PARAMETERS
  charge-safety-factor
  wait-time-mean
  batt-cap-mean
  batt-cap-stdv
  batt-cap-range
  fuel-economy-stdv
  fuel-economy-range
  charger-search-distance
  time-opportunity-cost
  willing-to-roam-time-threshold
  frac-phev
  probability-of-unneeded-charge
  electric-fuel-consumption-sd
  electric-fuel-consumption-range
  stranded-delay-threshold
  soft-strand-penalty
  hard-strand-penalty
  charger-lifetime
  weekend-factor
  discount
  assign-phevs-to-extreme-drivers
  num-simulation-days
  
  ;; Objective Function Params needed to optimize the model
  reference-charger-cost
  reference-delay-cost
  
  ;; globals needed for testing
  test-driver
  seek-charger-index
]

breed [drivers driver]
breed [vehicle-types vehicle-type]
breed [chargers charger]
breed [tazs taz]
breed [charger-types charger-type]

drivers-own [
;; VEHICLE
  this-vehicle-type              ; e.g. 'leaf' or 'volt'
  is-bev?
  permission-list
  battery-capacity          ; kwh
  electric-fuel-consumption ; kwh / mile
  hybrid-fuel-consumption   ; gallon / mile, for phev charge sustaining mode
  
;; DEMOGRAPHY  
  home-taz
  id

;; OPERATION
  state                     ; discrete string value: not-charging, traveling, charging
  current-taz               ; nobody if traveling
  destination-taz
  state-of-charge
  current-charger           ; nobody if not charging
  
  itin-from 
  itin-to
  itin-depart
  itin-change-flag
  itin-delay-amount
  max-trip-distance
  max-dwell-time
  current-itin-row          ; index of current location in the itinerary (referring to next trip or current trip if traveling)
  current-od-index
  external-time             ; The time it takes to get from an external TAZ to a gateway TAZ
  external-dist             ; The distance between an external TAZ to a gateway TAZ
  wait-threshold            ; How long a driver is willing to wait before they are considered soft-stranded.

;; CONVENIENCE VARIABLES
  journey-distance
  trip-distance
  remaining-range
  departure-time
  charger-in-origin-or-destination
  time-until-depart
  trip-charge-time-need
  journey-charge-time-need
  full-charge-time-need
  time-until-end-charge
  trip-time
  itin-complete?  
  type-assignment-code

  willing-to-roam?
  charging-on-a-whim?

;; TRACKING
  energy-used
  expenses
  gasoline-used
  miles-driven
  num-denials
  
;; CANDIDATE ADDITIONS TO MODEL DESCRIPTION
  energy-received ; a count of how much energy each driver has charged

;; BATCH MODE
  master-state-of-charge
  master-electric-fuel-consumption
  master-journey-distance
  master-itin-from          
  master-itin-to             
  master-itin-depart        
]

chargers-own[
  location         ; TAZ # for each charger
  current-driver   ; driver currenlty being serviced, nobody indicates charger is available
  this-charger-type     ; 0, 1, 2, 3, or 4 ***address name later?
  num-sessions     ; count of charging sessions
  energy-delivered ; kWh
  alt-energy-price ; Used for special permissions chargers
 ]

tazs-own[
  id              ; TAZ id
  chargers-by-type ; list of lists of chargers organized by type, e.g. [ [level-0] [level-1-a level-1-b ....] [level-2-a level-2-b ....] [level-3-a ....] ]
  available-chargers-by-type ; List of stacks for available chargers
  
  neighbor-tazs   ; list of tazs within charger-search-distance of this taz
  
  n-levels        ; list containing the number of chargers for levels 0,1,2,3,4 at index 0,1,2,3,4 where 0=home and 4=battery swap
]

charger-types-own[
  level            ; 0,1,2,3,4 where 0=home, 4=battery swap
  charge-rate      ; kWh / hr  
  energy-price     ; $0.14/kWh
  installed-cost   ; $
]

vehicle-types-own[
  name
  electric-fuel-consumption
  hybrid-fuel-consumption
  battery-capacity
  frac-of-pevs
  num-vehicles
  is-bev?
]

to setup-from-gui
    clear-all-and-initialize
    set batch-setup? false
    if parameter-file = 0 [ set parameter-file "params.txt" ]
    if model-directory = 0 [ set model-directory "./" ]
    read-parameter-file
    print "setting up...."
    setup
    print "setup complete"
end

to setup-and-fix-seed
    clear-all-and-initialize
    set batch-setup? false
    ;let seed new-seed
    ;print seed
    random-seed 1;
    if parameter-file = 0 [ set parameter-file "params.txt" ]
    if model-directory = 0 [ set model-directory "./" ]
    read-parameter-file
    print "setting up...."
    setup
    print "setup complete"
end

to clear-all-and-initialize
  ;print "clear all"
  clear-all
  time:clear-schedule
  create-turtles 1 [ setxy 0 0 set color black] ;This invisible turtle makes sure we start at taz 1 not taz 0. Tutrle eventually changed to taz 0, for homeless drivers.
  reset-ticks
end

;;;;;;;;;;;;;;;;;;
;; RUN & PROFILE
;;;;;;;;;;;;;;;;;;
to run-with-profiler
  print "Profiler activated"
  profiler:start
  setup-and-fix-seed
  go-until
  profiler:stop
  print profiler:report
  profiler:reset
  ;Stuff
end


;;;;;;;;;;;;;;;;;;;;
;; SETUP 
;;;;;;;;;;;;;;;;;;;;
to setup
  set small-num 1e-6
  print "setup-od-data"
  setup-od-data
  print "setup-tazs"
  setup-tazs
  convert-enroute-ids
  print "setup-drivers"
  setup-drivers
  print "initialize-drivers"
  initialize-drivers
  print "setup-chargers"
  setup-charger-types
  setup-chargers
  reset-logfile "drivers" ;;;LOG
  reset-logfile "charging" ;;;LOG
  log-data "charging" (sentence "time" "charger.id" "charger.level" "location" "driver" "vehicle.type" "duration" "energy" "begin.soc" "end.soc" "after.end.charge" "charging.on.whim" "time.until.depart") ;;;LOG
  reset-logfile "pain" ;;;LOG
  log-data "pain" (sentence "time" "driver" "location" "vehicle.type" "pain.type" "pain.value" "state.of.charge") ;;;LOG
  reset-logfile "trip" ;;;LOG
  log-data "trip" (sentence "time" "driver" "vehicle.type" "origin" "destination" "distance" "scheduled" "begin.soc" "end.soc" "elec.used" "gas.used" "end.time") ;;;LOG
  reset-logfile "tazs" ;;;LOG
  log-data "tazs" (sentence "time" "taz" "num-bevs" "num-phevs" "num-L0" "num-L1" "num-L2" "num-L3" "num-avail-L0"  "num-avail-L1" "num-avail-L2" "num-avail-L3") ;;;LOG
  if log-tazs [ ;;;LOG
    time:schedule-repeating-event tazs task log-taz-data 0.0 (log-taz-time-interval / 60) ;;;LOG
  ] ;;;LOG
  if log-summary [ ;;;LOG
     time:schedule-event one-of drivers task summarize go-until-time - 0.01 ;;;LOG
  ] ;;;LOG
  reset-logfile "wait-time" ;;;LOG
  log-data "wait-time" (sentence "time" "driver" "vehicle.type" "soc" "trip.distance" "journey.distance" "time.until.depart" "result.action" "time.from.now" "electric.fuel.consumption") ;;;LOG
  reset-logfile "charge-time" ;;;LOG
  log-data "charge-time" (sentence "time" "driver" "charger.in.origin.dest" "level" "soc" "trip.distance" "journey.distance" "time.until.depart" "result.action" "time.from.now") ;;;LOG
  reset-logfile "need-to-charge" ;;;LOG
  log-data "need-to-charge" (sentence "time" "driver" "vehicle.type" "soc" "electric.fuel.consumption" "trip.distance" "journey.distance" "time.until.depart" "calling.event" "remaining.range" "charging.on.a.whim?" "need.to.charge?") ;;;LOG
  reset-logfile "trip-journey-timeuntildepart" ;;;LOG
  log-data "trip-journey-timeuntildepart" (sentence "time" "departure.time" "driver" "vehicle.type" "soc" "from.taz" "to.taz" "trip.distance" "journey.distance" "time.until.depart" "next.event" "remaining.range" "delay.sum") ;;;LOG
  reset-logfile "seek-charger" ;;;LOG
  log-data "seek-charger" (sentence "time" "seek-charger-index" "current.taz" "charger.taz" "driver" "vehicle.type" "electric.fuel.consumption" "is.BEV" "charger.in.origin.dest" "level" "soc" "trip.or.journey.energy.need" "distance.o.to.c" "distance.c.to.d" "time.o.to.c" "time.c.to.d" "trip.time" "trip.distance" "journey.distance" "charging.on.a.whim." "time.until.depart" "trip.charge.time.need" "cost" "extra.time.until.end.charge" "full.charge.time.need" "trip.charge.time.need" "mid.journey.charge.time.need" "mid.state.of.charge") ;;;LOG
  reset-logfile "seek-charger-result" ;;;LOG
  log-data "seek-charger-result" (sentence "time" "seek.charger.index" "driver" "chosen.taz" "charger.in.origin.dest" "chosen.level" "cost") ;;;LOG
  set seek-charger-index 0 ;;;LOG
  reset-logfile "break-up-trip" ;;;LOG
  log-data "break-up-trip" (sentence "time" "driver" "state.of.charge" "current.taz" "destination.taz" "remaining.range" "charging.on.a.whim?" "result.action") ;;;LOG
  reset-logfile "break-up-trip-choice" ;;;LOG
  log-data "break-up-trip-choice" (sentence "time" "driver" "current.taz" "destination.taz" "result.action" "new.destination" "max.score.or.distance") ;;;LOG
  reset-logfile "available-chargers" ;;;LOG
  log-data "available-chargers" (sentence "time" "driver" "current.taz" "home.taz" "taz" "level" "num.available.chargers") ;;;LOG
  reset-logfile "charge-limiting-factor" ;;;LOG
  log-data "charge-limiting-factor" (sentence "time" "driver" "vehicle.type" "state.of.charge" "result.action" "full-charge-time-need" "trip-charge-time-need" "journey-charge-time-need" "time-until-depart" "charger-in-origin-or-destination" "this-charger-type") ;;;LOG
end 

to setup-in-batch-mode-from-gui
  clear-all-and-initialize
  set starting-seed 21
  set fix-seed TRUE
  set param-file-base "/Users/critter/Dropbox/serc/pev-colin/pev-shared/"
  set parameter-file "/Users/critter/Dropbox/serc/pev-colin/pevi/netlogo/params.txt"
  read-parameter-file
  set reference-charger-cost 0
  set reference-delay-cost 0
  setup-in-batch-mode
end

to setup-in-batch-mode
  ifelse count turtles = 1 [
    ; expecting that clear-all-and-initialize has been run
    if fix-seed [random-seed starting-seed]
    ; Can we combine this with the code existing in setup?
    set small-num 1e-6
    set batch-setup? false
    set seed-list (sentence random 2147483647 random 2147483647 random 2147483647)
    set seed-list-index -1
    ; read-parameter-file ;We want to control parameter file settings externally
    print "setting up...." ;;;LOG
    setup-od-data
    print "setup-tazs" ;;;LOG
    setup-tazs
    convert-enroute-ids
    print "setup-drivers" ;;;LOG
    setup-drivers
    random-seed next-seed
    print "initialize-drivers" ;;;LOG
    initialize-drivers
    print "setup-chargers" ;;;LOG
    setup-charger-types
    setup-chargers
    initialize-logfile
    random-seed next-seed
  ][
    print "batch mode reset" ;;;LOG
    set batch-setup? true
    set seed-list-index -1
    ask chargers [
      set current-driver nobody
      set energy-delivered 0
      set num-sessions 0
    ]
    ask drivers [
      set itin-delay-amount n-values length itin-depart [0]
    ]
    initialize-available-chargers
    time:clear-schedule
    reset-ticks
    
    random-seed next-seed
    initialize-drivers
    initialize-logfile
    random-seed next-seed
  ]
end

to initialize-logfile
  reset-logfile "drivers" ;;;LOG
  reset-logfile "charging" ;;;LOG
  log-data "charging" (sentence "time" "charger.id" "charger.level" "location" "driver" "vehicle.type" "duration" "energy" "begin.soc" "end.soc" "after.end.charge" "charging.on.whim" "time.until.depart") ;;;LOG
  reset-logfile "pain" ;;;LOG
  log-data "pain" (sentence "time" "driver" "location" "vehicle.type" "pain.type" "pain.value" "state.of.charge") ;;;LOG
  reset-logfile "trip" ;;;LOG
  log-data "trip" (sentence "time" "driver" "vehicle.type" "origin" "destination" "distance" "scheduled" "begin.soc" "end.soc" "elec.used" "gas.used" "end.time") ;;;LOG
  reset-logfile "tazs" ;;;LOG
  log-data "tazs" (sentence "time" "taz" "num-bevs" "num-phevs" "num-L0" "num-L1" "num-L2" "num-L3" "num-avail-L0"  "num-avail-L1" "num-avail-L2" "num-avail-L3") ;;;LOG
  if log-tazs [ ;;;LOG
    time:schedule-repeating-event tazs task log-taz-data 0.0 (log-taz-time-interval / 60) ;;;LOG
  ] ;;;LOG
  if log-summary [ ;;;LOG
     time:schedule-event one-of drivers task summarize go-until-time - 0.01 ;;;LOG
  ] ;;;LOG
  reset-logfile "wait-time" ;;;LOG
  log-data "wait-time" (sentence "time" "driver" "vehicle.type" "soc" "trip.distance" "journey.distance" "time.until.depart" "result.action" "time.from.now" "electric.fuel.consumption") ;;;LOG
  reset-logfile "charge-time" ;;;LOG
  log-data "charge-time" (sentence "time" "driver" "charger.in.origin.dest" "level" "soc" "trip.distance" "journey.distance" "time.until.depart" "result.action" "time.from.now") ;;;LOG
  reset-logfile "need-to-charge" ;;;LOG
  log-data "need-to-charge" (sentence "time" "driver" "vehicle.type" "soc" "electric.fuel.consumption" "trip.distance" "journey.distance" "time.until.depart" "calling.event" "remaining.range" "charging.on.a.whim?" "need.to.charge?") ;;;LOG
  reset-logfile "trip-journey-timeuntildepart" ;;;LOG
  log-data "trip-journey-timeuntildepart" (sentence "time" "departure.time" "driver" "vehicle.type" "soc" "from.taz" "to.taz" "trip.distance" "journey.distance" "time.until.depart" "next.event" "remaining.range" "delay.sum") ;;;LOG
  reset-logfile "seek-charger" ;;;LOG
  log-data "seek-charger" (sentence "time" "seek-charger-index" "current.taz" "charger.taz" "driver" "vehicle.type" "electric.fuel.consumption" "is.BEV" "charger.in.origin.dest" "level" "soc" "trip.or.journey.energy.need" "distance.o.to.c" "distance.c.to.d" "time.o.to.c" "time.c.to.d" "trip.time" "trip.distance" "journey.distance" "charging.on.a.whim." "time.until.depart" "trip.charge.time.need" "cost" "extra.time.until.end.charge" "full.charge.time.need" "trip.charge.time.need" "mid.journey.charge.time.need" "mid.state.of.charge") ;;;LOG
  reset-logfile "seek-charger-result" ;;;LOG
  log-data "seek-charger-result" (sentence "time" "seek.charger.index" "driver" "chosen.taz" "charger.in.origin.dest" "chosen.level" "cost" "alt.price?") ;;;LOG
  set seek-charger-index 0 ;;;LOG
  reset-logfile "break-up-trip" ;;;LOG
  log-data "break-up-trip" (sentence "time" "driver" "state.of.charge" "current.taz" "destination.taz" "remaining.range" "charging.on.a.whim?" "result.action") ;;;LOG
  reset-logfile "break-up-trip-choice" ;;;LOG
  log-data "break-up-trip-choice" (sentence "time" "driver" "current.taz" "destination.taz" "result.action" "new.destination" "max.score.or.distance") ;;;LOG
  reset-logfile "available-chargers" ;;;LOG
  log-data "available-chargers" (sentence "time" "driver" "current.taz" "home.taz" "taz" "level" "num.available.chargers") ;;;LOG
  reset-logfile "charge-limiting-factor" ;;;LOG
  log-data "charge-limiting-factor" (sentence "time" "driver" "vehicle.type" "state.of.charge" "result.action" "full-charge-time-need" "trip-charge-time-need" "journey-charge-time-need" "time-until-depart" "charger-in-origin-or-destination" "this-charger-type") ;;;LOG

end

to-report next-seed
  set seed-list-index seed-list-index + 1
  report item seed-list-index seed-list
end

to go
  time:go
end
to go-until
  time:go-until go-until-time
end

to log-taz-data ;;;LOG
  let #num-0 count drivers with [home-taz = myself] ;;;LOG
  log-data "tazs" (sentence ticks id (count drivers with [current-taz = myself and is-bev?]) (count drivers with [current-taz = myself and not is-bev?]) #num-0 (count item 1 chargers-by-type) (count item 2 chargers-by-type) (count item 3 chargers-by-type) (#num-0 - count drivers with [current-taz = myself and current-charger = (one-of item 0 [chargers-by-type] of myself)]) (count (item 1 chargers-by-type) with [current-driver = nobody]) (count (item 2 chargers-by-type) with [current-driver = nobody]) (count (item 3 chargers-by-type) with [current-driver = nobody]) ) ;;;LOG
end ;;;LOG

to add-permission-charger [ taz-id charger-level #alt-energy-price permissioned-drivers buildout-increment ]
  ; Build a permission-charger. Permissioned-drivers must be input as a list, i.e. (list 43 45 47)
   let build-charger-type one-of charger-types with [level = charger-level]
    create-chargers buildout-increment [
      set this-charger-type build-charger-type
      set location table:get taz-table taz-id
      set shape "Circle 2"
      set color red
      set size 1
      set current-driver nobody
      set energy-delivered 0
      set alt-energy-price #alt-energy-price
      foreach permissioned-drivers [
        ask drivers with [id = ?] [
          set permission-list lput myself permission-list
        ]
      ]
    ]
end

to add-charger [ taz-id charger-level buildout-increment ]
  let build-charger-type one-of charger-types with [level = charger-level]
  create-chargers buildout-increment [
    set this-charger-type build-charger-type
    set location table:get taz-table taz-id
    set shape "Circle 2"
    set color red
    set size 1
    set current-driver nobody
    set energy-delivered 0
    ask table:get taz-table taz-id [
      structs:stack-push item charger-level available-chargers-by-type myself
      set chargers-by-type replace-item charger-level chargers-by-type chargers with [(this-charger-type = build-charger-type) and (location = myself)]
      set n-levels replace-item charger-level n-levels (item charger-level n-levels + 1)
    ]
  ]
end

to remove-charger [taz-id charger-level buildout-increment]  
  ifelse num-available-chargers table:get taz-table taz-id charger-level >= buildout-increment [
    let build-charger-type one-of charger-types with [level = charger-level]
    let death-count 0
    ask table:get taz-table taz-id [
      while [death-count < buildout-increment] [
        let #dying-charger structs:stack-pop item charger-level available-chargers-by-type
        ask #dying-charger [die]
        set death-count death-count + 1
      ]
      set chargers-by-type replace-item charger-level chargers-by-type chargers with [(this-charger-type = build-charger-type) and (location = myself)]
      set n-levels replace-item charger-level n-levels (item charger-level n-levels - buildout-increment)
    ]
  ][print (sentence "TAZ" taz-id "doesn't have a level" charger-level "charger.")] 
end
;;;;;;;;;;;;;;;;;;;;
;; NEED TO CHARGE
;;;;;;;;;;;;;;;;;;;;
to-report need-to-charge [calling-event]
  set charging-on-a-whim? false
  ;set trip-distance item current-od-index od-dist ; drivers hould already have trip-distance calculated
  set time-until-depart departure-time - ticks
  set departure-time item current-itin-row itin-depart
  ifelse is-bev? [
    set remaining-range (state-of-charge * battery-capacity / electric-fuel-consumption ) + small-num
  ][
    set remaining-range 9999999
  ]
  ifelse ( (calling-event = "arrive" and remaining-range < journey-distance * charge-safety-factor) or 
           (calling-event = "depart" and remaining-range < trip-distance * charge-safety-factor) )[
    log-data "need-to-charge" (sentence ticks id [name] of this-vehicle-type state-of-charge electric-fuel-consumption trip-distance journey-distance (departure-time - ticks) calling-event remaining-range charging-on-a-whim? "true") ;;;LOG
    report true
  ][
    ifelse (calling-event = "arrive" and state-of-charge < 1 - small-num) [  ;; drivers only consider unneeded charge if they just arrived and the vehicle does not have a full state of charge
      ifelse time-until-depart >= willing-to-roam-time-threshold and (random-float 1) < probability-of-unneeded-charge * (1 / (1 + exp(-5 + 10 * state-of-charge))) [
        set charging-on-a-whim? true
        log-data "need-to-charge" (sentence ticks id [name] of this-vehicle-type state-of-charge electric-fuel-consumption trip-distance journey-distance (departure-time - ticks) calling-event remaining-range charging-on-a-whim? "true") ;;;LOG
        report true
      ][
        log-data "need-to-charge" (sentence ticks id [name] of this-vehicle-type state-of-charge electric-fuel-consumption trip-distance journey-distance (departure-time - ticks) calling-event remaining-range charging-on-a-whim? "false") ;;;LOG
        report false
      ]
    ][
      log-data "need-to-charge" (sentence ticks id [name] of this-vehicle-type state-of-charge electric-fuel-consumption trip-distance journey-distance (departure-time - ticks) calling-event remaining-range charging-on-a-whim? "false") ;;;LOG
      report false
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;
;; RETRY SEEK 
;;;;;;;;;;;;;;;;;;;;
to retry-seek
  ;print (word precision ticks 3 " " self " retry-seek ")
  if item current-itin-row itin-depart < ticks [
    change-depart-time ticks
  ]  
  ifelse is-bev? [
    set remaining-range (state-of-charge * battery-capacity / electric-fuel-consumption ) + small-num
  ][
    set remaining-range 9999999
  ]
  seek-charger
end

;;;;;;;;;;;;;;;;;;;;
;; SEEK CHARGER
;;;;;;;;;;;;;;;;;;;;
;; remaining-charge set by retry-seek
;; trip-distance set by update-itinerary
;;;;;;;;;;;;;;;;;;;;
to seek-charger
  set seek-charger-index seek-charger-index + 1
  set time-until-depart departure-time - ticks
  let #extra-time-until-end-charge 0
  let #extra-time-for-travel 0
  let #extra-distance-for-travel 0
  let #extra-energy-for-travel 0
  let #charger-in-origin-or-destination true
  let #min-cost 1e99
  let #min-taz -99
  let #min-charger-type -99
  let #use-permissioned-charger false
  let #min-priviledged-charger nobody
  let #trip-charge-time-need-by-type n-values count charger-types [-99]
  let #trip-or-journey-energy-need-by-type n-values count charger-types [-99]
  let #level-3-and-too-full false
  let #full-charge-time-need 0
  let #trip-charge-time-need 0
  let #mid-journey-charge-time-need 0
  let #mid-state-of-charge 0
  let #level-3-time-penalty 0
  let #level-3-time-penalty-for-origin-or-destination 0
  let #charger-exists-but-unavailable false
  
  if trip-distance * charge-safety-factor > 0.8 * battery-capacity / electric-fuel-consumption [
    set #level-3-time-penalty-for-origin-or-destination 999
  ]
  
  ifelse not charging-on-a-whim? and is-bev? and time-until-depart < willing-to-roam-time-threshold [  
    set willing-to-roam? true  
  ][
    set willing-to-roam? false 
  ]
  let #taz-list n-values 0 [?]
  ifelse willing-to-roam? [
    set #taz-list remove-duplicates (sentence current-taz destination-taz [neighbor-tazs] of current-taz item current-od-index od-enroute)
  ][  
    set #taz-list (sentence current-taz)
  ]
  let #trip-energy-need  max (sentence 0 (trip-distance * charge-safety-factor * electric-fuel-consumption - state-of-charge * battery-capacity))
  let #journey-energy-need  max (sentence 0 (journey-distance * charge-safety-factor * electric-fuel-consumption - state-of-charge * battery-capacity))

  foreach [sentence level charge-rate] of charger-types [
    let #trip-energy-need-limited #trip-energy-need
    let #journey-energy-need-limited #journey-energy-need
    ifelse item 0 ? != 3 [
      set #trip-energy-need-limited min (sentence ((1 - state-of-charge) * battery-capacity) #trip-energy-need-limited)
      set #journey-energy-need-limited min (sentence ((1 - state-of-charge) * battery-capacity) #journey-energy-need-limited)
    ][
      set #trip-energy-need-limited min (sentence max (sentence 0 ((0.8 - state-of-charge) * battery-capacity)) #trip-energy-need-limited)
      set #journey-energy-need-limited min (sentence max (sentence 0 ((0.8 - state-of-charge) * battery-capacity)) #journey-energy-need-limited)
    ]
    set #trip-charge-time-need-by-type replace-item (item 0 ?) #trip-charge-time-need-by-type (#trip-energy-need-limited / (item 1 ?))
    ifelse time-until-depart < willing-to-roam-time-threshold [
      set #trip-or-journey-energy-need-by-type replace-item (item 0 ?) #trip-or-journey-energy-need-by-type #trip-energy-need-limited
    ][
      set #trip-or-journey-energy-need-by-type replace-item (item 0 ?) #trip-or-journey-energy-need-by-type #journey-energy-need-limited
    ]
  ]
  foreach #taz-list [
    if current-taz = ? or (distance-from-to [id] of current-taz [id] of ? <= remaining-range / charge-safety-factor) [
      let #this-taz ?
      set #charger-in-origin-or-destination (#this-taz = current-taz or #this-taz = destination-taz)
      ifelse #charger-in-origin-or-destination [
        set #extra-time-for-travel 0
        set #extra-distance-for-travel 0
      ][
        set #extra-time-for-travel (time-from-to [id] of current-taz [id] of #this-taz + time-from-to [id] of #this-taz [id] of destination-taz - trip-time)
        set #extra-distance-for-travel (distance-from-to [id] of current-taz [id] of #this-taz + distance-from-to [id] of #this-taz [id] of destination-taz - trip-distance)
      ]
      set #extra-energy-for-travel #extra-distance-for-travel * electric-fuel-consumption * charge-safety-factor

      foreach [level] of charger-types [
        let #level ?
        ; check to see if any charger on priviledged lists are available
        let #min-priviledged-cost 99
        foreach permission-list [
          if [location] of ? = current-taz and [current-driver] of ? = nobody and [level] of [this-charger-type] of ? = #level [
            if [alt-energy-price] of ? < #min-priviledged-cost [
              set #min-priviledged-charger ?
              set #min-priviledged-cost [alt-energy-price] of ?
            ]
          ]
        ] ; end permission-list loop
       
        ifelse (num-available-chargers #this-taz #level > 0) and ((#level > 0) or ((#this-taz = home-taz) and #level = 0)) or (#min-priviledged-charger != nobody) [ 
          let #this-charger-type one-of charger-types with [ level = #level ]
          let #this-charge-rate [charge-rate] of #this-charger-type
          ifelse #charger-in-origin-or-destination [
            ifelse #this-taz = current-taz [
              set #extra-time-until-end-charge max (sentence 0 (item #level #trip-charge-time-need-by-type - time-until-depart))
            ][
              set #extra-time-until-end-charge 0
            ]
            set #level-3-and-too-full #level = 3 and state-of-charge >= 0.8 - small-num
            ifelse #level = 3 [
              set #level-3-time-penalty #level-3-time-penalty-for-origin-or-destination 
            ][
              set #level-3-time-penalty 0
            ]
          ][
            let #leg-one-trip-distance distance-from-to [id] of current-taz [id] of #this-taz
            let #leg-two-trip-distance distance-from-to [id] of #this-taz [id] of destination-taz
            let #mid-journey-distance journey-distance - #leg-one-trip-distance
            set #mid-state-of-charge state-of-charge - #leg-one-trip-distance * electric-fuel-consumption / battery-capacity
            set #level-3-and-too-full #level = 3 and #mid-state-of-charge >= 0.8 - small-num
            set #trip-charge-time-need max sentence 0 ((#leg-two-trip-distance * charge-safety-factor * electric-fuel-consumption - #mid-state-of-charge * battery-capacity) / #this-charge-rate)
            set #mid-journey-charge-time-need max sentence 0 ((#mid-journey-distance * charge-safety-factor * electric-fuel-consumption - #mid-state-of-charge * battery-capacity) / #this-charge-rate)
            set #full-charge-time-need 0
            ifelse #level = 3[
              set #full-charge-time-need (0.8 - #mid-state-of-charge) * battery-capacity / #this-charge-rate
              ifelse #leg-two-trip-distance * charge-safety-factor > 0.8 * battery-capacity / electric-fuel-consumption [
                  set #level-3-time-penalty 999
              ][
                set #level-3-time-penalty 0
              ]
            ][
              set #full-charge-time-need (1 - #mid-state-of-charge) * battery-capacity / #this-charge-rate
              set #level-3-time-penalty 0
            ]
            set #extra-time-until-end-charge calc-time-until-end-charge #full-charge-time-need 
                                                                        #trip-charge-time-need 
                                                                        #mid-journey-charge-time-need 
                                                                        (time-until-depart - time-from-to [id] of current-taz [id] of #this-taz)
                                                                        #charger-in-origin-or-destination
                                                                        #this-charger-type                                                    
          ]
          if not #level-3-and-too-full [
            ; self is currently the driver
            
            ifelse (#min-priviledged-cost < [energy-price] of #this-charger-type or num-available-chargers #this-taz #level = 0) and #this-taz = [location] of #min-priviledged-charger [ ;If the priviledged charger is cheaper, or the only charger 
              let #this-cost (time-opportunity-cost * (#extra-time-for-travel + #extra-time-until-end-charge) + #level-3-time-penalty +
              (#min-priviledged-cost) * (item #level #trip-or-journey-energy-need-by-type + #extra-energy-for-travel))
              if #this-cost < #min-cost or (#this-cost = #min-cost and [level] of #this-charger-type > [level] of #min-charger-type) [
                set #min-cost #this-cost
                set #min-taz #this-taz
                set #min-charger-type #this-charger-type 
                set #use-permissioned-charger true 
                log-data "seek-charger" (sentence ticks seek-charger-index ([id] of current-taz) ([id] of #this-taz) id ([name] of this-vehicle-type) electric-fuel-consumption is-BEV?       ;;;LOG
                  #charger-in-origin-or-destination #level state-of-charge (item #level #trip-or-journey-energy-need-by-type) (distance-from-to [id] of current-taz [id] of #this-taz)        ;;;LOG
                  (distance-from-to [id] of #this-taz [id] of destination-taz) (time-from-to [id] of current-taz [id] of #this-taz) (time-from-to [id] of #this-taz [id] of destination-taz)  ;;;LOG
                  trip-time trip-distance journey-distance charging-on-a-whim? time-until-depart (item #level #trip-charge-time-need-by-type) #this-cost #extra-time-until-end-charge         ;;;LOG
                  #full-charge-time-need #trip-charge-time-need #mid-journey-charge-time-need #mid-state-of-charge #use-permissioned-charger)  ;;;LOG

              ]
            ][
              let #this-cost (time-opportunity-cost * (#extra-time-for-travel + #extra-time-until-end-charge) + #level-3-time-penalty +
              ([energy-price] of #this-charger-type) * (item #level #trip-or-journey-energy-need-by-type + #extra-energy-for-travel))
              if #this-cost < #min-cost or (#this-cost = #min-cost and [level] of #this-charger-type > [level] of #min-charger-type) [
                set #min-cost #this-cost
                set #min-taz #this-taz
                set #min-charger-type #this-charger-type 
                set #use-permissioned-charger false
                log-data "seek-charger" (sentence ticks seek-charger-index ([id] of current-taz) ([id] of #this-taz) id ([name] of this-vehicle-type) electric-fuel-consumption is-BEV?       ;;;LOG
                #charger-in-origin-or-destination #level state-of-charge (item #level #trip-or-journey-energy-need-by-type) (distance-from-to [id] of current-taz [id] of #this-taz)        ;;;LOG
                (distance-from-to [id] of #this-taz [id] of destination-taz) (time-from-to [id] of current-taz [id] of #this-taz) (time-from-to [id] of #this-taz [id] of destination-taz)  ;;;LOG
                trip-time trip-distance journey-distance charging-on-a-whim? time-until-depart (item #level #trip-charge-time-need-by-type) #this-cost #extra-time-until-end-charge         ;;;LOG
                #full-charge-time-need #trip-charge-time-need #mid-journey-charge-time-need #mid-state-of-charge #use-permissioned-charger)  ;;;LOG

              ]
            ]
          ]
        ][ ; end if (available chargers of level in TAZ > 0), switch to the "else" where we check if there are ANY chargers.
          if (count item #level [chargers-by-type] of #this-taz > 0 and #level != 0 and not #charger-exists-but-unavailable) [
            set #charger-exists-but-unavailable true ; If no available chargers are found, we have a soft instead of hard stranding.
          ]
        ]  ; end else
      ] ; end foreach level of charger-types
    ]
  ] ; end foreach taz-list
  ifelse #min-taz = -99 [
    ifelse #charger-exists-but-unavailable or charging-on-a-whim? [ 
      ; Either they don't really need to charge, or chargers are out there but in use. The latter may result in a soft strand.
      log-data "seek-charger-result" (sentence ticks seek-charger-index id -1 "" -1 -1)  ;;;LOG
      log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "denial" (num-denials + 1) state-of-charge) ;;;LOG
      set num-denials (num-denials + 1)
      wait-time-event-scheduler
    ][
      set state "stranded"
      set itin-delay-amount replace-item current-itin-row itin-delay-amount (item current-itin-row itin-delay-amount + hard-strand-penalty)
      log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "stranded" "" state-of-charge) ;;;LOG
    ]
  ][
    log-data "seek-charger-result" (sentence ticks seek-charger-index id ([id] of #min-taz) (#min-taz = current-taz or #min-taz = destination-taz) ([level] of #min-charger-type) #min-cost)  ;;;LOG
    ifelse #min-taz = current-taz [
      ifelse #use-permissioned-charger [
        set current-charger #min-priviledged-charger
      ][
        set current-charger selected-charger current-taz [level] of #min-charger-type
      ]
      if [level] of #min-charger-type > 0 [
        ask current-charger[
          set current-driver myself
        ]
      ]
      set charger-in-origin-or-destination (#min-taz = current-taz or #min-taz = destination-taz)
      charge-time-event-scheduler
    ][
      ifelse #min-taz = destination-taz [
        change-depart-time ticks
      ][
        add-trip-to-itinerary #min-taz
        travel-time-event-scheduler
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; WAIT TIME EVENT SCHEDULER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; wait-time-mean set in params.txt
;; remaining-range set in need-to-charge and retry-seek
;; time-until-depart set in seek-charger
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to wait-time-event-scheduler
  set state "not charging"
  ifelse remaining-range / charge-safety-factor < trip-distance [
    ifelse sum [itin-delay-amount] of self > wait-threshold [
      set state "stranded" ;soft stranding
      set itin-delay-amount replace-item current-itin-row itin-delay-amount (item current-itin-row itin-delay-amount + soft-strand-penalty)
      log-data "wait-time" (sentence ticks id [name] of this-vehicle-type state-of-charge trip-distance journey-distance time-until-depart "stranded" -1 electric-fuel-consumption) ;;;LOG
      log-data "trip-journey-timeuntildepart" (sentence ticks departure-time id [name] of this-vehicle-type state-of-charge [id] of current-taz [id] of destination-taz true false (departure-time - ticks) "stranded" remaining-range sum map weight-delay itin-delay-amount) ;;;LOG
      log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "stranded" "" state-of-charge) ;;;LOG
    ][
      let event-time-from-now random-exponential wait-time-mean
      time:schedule-event self task retry-seek ticks + event-time-from-now
      log-data "wait-time" (sentence ticks id [name] of this-vehicle-type state-of-charge trip-distance journey-distance time-until-depart "retry-seek" event-time-from-now electric-fuel-consumption) ;;;LOG
    ]
  ][
    ifelse remaining-range / charge-safety-factor >= journey-distance or time-until-depart <= willing-to-roam-time-threshold [
      time:schedule-event self task depart departure-time
      log-data "wait-time" (sentence ticks id [name] of this-vehicle-type state-of-charge trip-distance journey-distance time-until-depart "depart" departure-time electric-fuel-consumption) ;;;LOG
    ][
      let event-time-from-now min(sentence (random-exponential wait-time-mean) (time-until-depart - willing-to-roam-time-threshold))
      if event-time-from-now < 0 [ set event-time-from-now 0 ]
      time:schedule-event self task retry-seek ticks + event-time-from-now
      log-data "wait-time" (sentence ticks id [name] of this-vehicle-type state-of-charge trip-distance journey-distance time-until-depart "retry-seek" event-time-from-now electric-fuel-consumption) ;;;LOG
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHARGE TIME EVENT SCHEDULER   
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; time-until-depart set in SEEK CHARGER = departure-time - ticks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to charge-time-event-scheduler
  set state "charging"
  if state-of-charge >= 1 - small-num [
     itinerary-event-scheduler
     stop
  ]
  ifelse is-bev?[
    set trip-charge-time-need max sentence 0 ((trip-distance * charge-safety-factor * electric-fuel-consumption - state-of-charge * battery-capacity) / charge-rate-of current-charger)
  ][
    set trip-charge-time-need 0
  ]
  set journey-charge-time-need max sentence 0 ((journey-distance * charge-safety-factor * electric-fuel-consumption - state-of-charge * battery-capacity) / charge-rate-of current-charger)
  let after-end-charge "retry-seek"
  ifelse level-of current-charger = 3 [
    set full-charge-time-need max (sentence 0 ((0.8 - state-of-charge) * battery-capacity / charge-rate-of current-charger))
  ][
    set full-charge-time-need (1 - state-of-charge) * battery-capacity / charge-rate-of current-charger
  ]
  set time-until-end-charge (calc-time-until-end-charge full-charge-time-need 
                                                    trip-charge-time-need 
                                                    journey-charge-time-need 
                                                    time-until-depart 
                                                    charger-in-origin-or-destination 
                                                    [this-charger-type] of current-charger)
  let next-event-scheduled-at 0 
  ifelse (not charging-on-a-whim?) and (time-until-end-charge > 0) and (time-until-end-charge < full-charge-time-need) and   
         (level-of current-charger < 3) and ;I think we can leave this unchanged with level 4 charging
         ( time-until-end-charge > time-until-depart or 
           ( (time-until-end-charge < journey-charge-time-need) and (time-until-depart > willing-to-roam-time-threshold) )
         ) [
    ifelse time-until-end-charge > time-until-depart [
      set next-event-scheduled-at ticks + random-exponential wait-time-mean
    ][
      set next-event-scheduled-at ticks + min (sentence (random-exponential wait-time-mean) (time-until-depart - willing-to-roam-time-threshold))
    ]
    time:schedule-event self task end-charge-then-retry next-event-scheduled-at
  ][
    set next-event-scheduled-at ticks + time-until-end-charge
    time:schedule-event self task end-charge-then-itin next-event-scheduled-at
    set after-end-charge "depart"
  ]
  log-data "charge-time" (sentence ticks id charger-in-origin-or-destination (level-of current-charger) state-of-charge trip-distance journey-distance time-until-depart after-end-charge (next-event-scheduled-at - ticks)) ;;;LOG
  log-data "charging" (sentence ticks [who] of current-charger level-of current-charger [id] of current-taz [id] of self [name] of this-vehicle-type (next-event-scheduled-at - ticks) ((next-event-scheduled-at - ticks) * charge-rate-of current-charger) state-of-charge (state-of-charge + ((next-event-scheduled-at - ticks) * charge-rate-of current-charger) / battery-capacity ) after-end-charge charging-on-a-whim? (departure-time - ticks)) ;;;LOG
  if next-event-scheduled-at > departure-time[
    change-depart-time next-event-scheduled-at
  ]
  set time-until-end-charge (next-event-scheduled-at - ticks)
end

to-report calc-time-until-end-charge-with-logging [#full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination #this-charger-type] ;;;LOG
  ifelse #full-charge-time-need <= #trip-charge-time-need [  ;; if sufficent time to charge to full ;;;LOG
    log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "full-charge-less-than-trip-need" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
    report #full-charge-time-need ;;;LOG
  ][ ;;;LOG                                                      
    ifelse #time-until-depart < #trip-charge-time-need [ ;;;LOG
      log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "not-enough-time-for-trip-need" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
      ;; NOT SUFFICIENT TIME FOR NEXT TRIP - will cause delay in schedule
      report #trip-charge-time-need ;;;LOG    
    ][ ;;;LOG                                                    
      ;; SUFFICIENT TIME - 
      ifelse #charger-in-origin-or-destination [ ;;;LOG
        ifelse #time-until-depart < #full-charge-time-need [ ;;;LOG
          log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "in-od-depart-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
        ][ ;;;LOG
          log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "in-od-full-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
        ] ;;;LOG
        ;; charge to full if enough time @ home/work
        report min sentence #time-until-depart #full-charge-time-need ;;;LOG 
      ][ ;;;LOG                                                  
        ifelse [level] of #this-charger-type = 3 [ ;;;LOG
          ifelse min (sentence #time-until-depart #journey-charge-time-need #full-charge-time-need) = #time-until-depart [ ;;;LOG
            log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "enroute-level3-depart-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
          ][ ;;;LOG
            ifelse min (sentence #time-until-depart #journey-charge-time-need #full-charge-time-need) = #journey-charge-time-need [ ;;;LOG
              log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "enroute-level3-journey-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
            ][ ;;;LOG
              log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "enroute-level3-full-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
            ] ;;;LOG
          ] ;;;LOG
          ;; charge until departure or journey charge time, whichever comes first 
          report min (sentence #time-until-depart #journey-charge-time-need #full-charge-time-need) ;;;LOG
        ][ ;;;LOG
          ifelse #time-until-depart < #trip-charge-time-need [ ;;;LOG
            log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "enroute-level1-2-depart-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
          ][ ;;;LOG
            log-data "charge-limiting-factor" (sentence ticks id [name] of this-vehicle-type state-of-charge "enroute-level1-2-trip-limiting" #full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination [level] of #this-charger-type) ;;;LOG
          ] ;;;LOG
          ;; charge until departure or trip charge time, whichever comes first
          report min sentence #time-until-depart #trip-charge-time-need ;;;LOG
        ] ;;;LOG
      ] ;;;LOG
    ] ;;;LOG
  ] ;;;LOG
end ;;;LOG

to-report calc-time-until-end-charge [#full-charge-time-need #trip-charge-time-need #journey-charge-time-need #time-until-depart #charger-in-origin-or-destination #this-charger-type]
  ifelse #full-charge-time-need <= #trip-charge-time-need [  ;; if sufficent time to charge to full
    report #full-charge-time-need
  ][                                                      
    ifelse #time-until-depart < #trip-charge-time-need [   
      ;; NOT SUFFICIENT TIME FOR NEXT TRIP - will cause delay in schedule
      report #trip-charge-time-need    
    ][                                                    
      ;; SUFFICIENT TIME - 
      ifelse #charger-in-origin-or-destination [
        ;; charge to full if enough time @ home/work
        report min sentence #time-until-depart #full-charge-time-need 
      ][                                                  
        ifelse [level] of #this-charger-type = 3 [  
          ;; charge until departure or journey charge time, whichever comes first 
          report min (sentence #time-until-depart #journey-charge-time-need #full-charge-time-need)
        ][
          ;; charge until departure or trip charge time, whichever comes first
          report min sentence #time-until-depart #trip-charge-time-need
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHANGE DEPARTURE TIME
;;;;;;;;;;;;;;;;;;;;;;;;;

to change-depart-time [new-depart-time]
  let #delay-duration new-depart-time - item current-itin-row itin-depart
  if #delay-duration > small-num [ ; unfortunately need this due to the roundoff issue mentioned in charge-time-event-scheduler
    set itin-delay-amount replace-item current-itin-row itin-delay-amount (item current-itin-row itin-delay-amount + #delay-duration)
  ]
  set itin-depart replace-item current-itin-row itin-depart new-depart-time
  ;print (word precision ticks 3 " " self " new-depart-time: " new-depart-time " for row: " current-itin-row " new itin-depart: " itin-depart)      
  if current-itin-row < (length itin-depart - 1)[
    foreach n-values (length itin-depart - current-itin-row - 1) [current-itin-row + ? + 1] [ change-depart-time-row ?  ]
  ]
  set departure-time new-depart-time
  log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "delay" #delay-duration state-of-charge) ;;;LOG
end

to change-depart-time-row [row-num]
  if item row-num itin-depart < item (row-num - 1) itin-depart[
    let #prev-depart-time item row-num itin-depart
    set itin-depart replace-item row-num itin-depart (0.5 + item (row-num - 1) itin-depart) ;; TODO make sub-model about how itin is adjusted when multiple trips are impacted
    let #delay-duration item row-num itin-depart - #prev-depart-time
    if #delay-duration > small-num [ ; unfortunately need this due to the roundoff issue mentioned in charge-time-event-scheduler
      set itin-delay-amount replace-item row-num itin-delay-amount (item row-num itin-delay-amount + #delay-duration)
    ]
  ]
end

to add-trip-to-itinerary [new-destination-taz]
  ; print (word precision ticks 3 " " self " new-taz: " new-destination-taz " for row: " current-itin-row " itin-depart: " itin-depart " itin-from: " itin-from " itin-to: " itin-to)
  
  ; start from the end and work backwards to the current-itin-row
  let last-row (length itin-depart - 1)
  set itin-depart lput (item last-row itin-depart) itin-depart
  set itin-to lput (item last-row itin-to) itin-to
  set itin-from lput (item last-row itin-from) itin-from
  set itin-delay-amount lput (item last-row itin-delay-amount) itin-delay-amount
  set itin-change-flag lput 0 itin-change-flag
    
  ; update all subsequent trips, including their departure time if necessary
  foreach n-values (last-row - current-itin-row) [last-row - ?] [
    set itin-depart replace-item ? itin-depart item (? - 1) itin-depart
    set itin-to replace-item ? itin-to item (? - 1) itin-to
    set itin-from replace-item ? itin-from item (? - 1) itin-from
    set itin-delay-amount replace-item ? itin-delay-amount item (? - 1) itin-delay-amount
  ]
  ; change the current destination to the new one and set depart time to now, and delay to 0
  set itin-to replace-item current-itin-row itin-to [who] of new-destination-taz
  set itin-from replace-item (current-itin-row + 1) itin-from [who] of new-destination-taz
  set itin-depart replace-item current-itin-row itin-depart ticks
  set itin-delay-amount replace-item current-itin-row itin-delay-amount 0
  set itin-change-flag replace-item current-itin-row itin-change-flag 1
  
  ; note that any inconsistent departure times will get resolved later through calls to change-departure-time
  
  ; rewind current-itin-row by one and use update-itinerary to take care of setting state var's
  set current-itin-row current-itin-row - 1

  update-itinerary

  ; update-itinerary does not update journey-distance, do so here by adding the difference between the previous trip and the current trip)
  let #added-journey-distance (distance-from-to (item current-itin-row itin-from) (item current-itin-row itin-to) + 
    distance-from-to (item (current-itin-row + 1) itin-from) (item (current-itin-row + 1) itin-to) - 
    distance-from-to (item current-itin-row itin-from) (item (current-itin-row + 1) itin-to) )
  set journey-distance journey-distance + #added-journey-distance
  
  log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "unscheduled-trip" #added-journey-distance state-of-charge) ;;;LOG
;  file-print (word precision ticks 3 " " self " add-trip-to-itinerary new-taz: " new-destination-taz " for row: " current-itin-row " itin-depart: " itin-depart " itin-from: " itin-from " itin-to: " itin-to)      
end

;;;;;;;;;;;;;;;;;;;;
;; END CHARGE
;;;;;;;;;;;;;;;;;;;;

to end-charge-then-itin
  end-charge
  itinerary-event-scheduler
end

to end-charge-then-retry
  end-charge
  retry-seek
end

to end-charge
  let energy-charged time-until-end-charge * charge-rate-of current-charger ;????????????????????????????????????????????
  set energy-received energy-received + energy-charged
  set expenses expenses + energy-charged * energy-price-of current-charger
  set state-of-charge min (sentence 1 (state-of-charge + energy-charged / battery-capacity))
  log-driver "end charge" ;;;LOG
  ask current-charger [ 
    set energy-delivered energy-delivered + energy-charged
    set current-driver nobody 
  ]
  return-charger current-taz [level] of [this-charger-type] of current-charger current-charger
  set current-charger nobody
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ITINERARY EVENT SCHEDULER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to itinerary-event-scheduler
  set state "not-charging"
  time:schedule-event self task depart departure-time
end

;;;;;;;;;;;;;;;;;;;;
;; DEPART 
;;;;;;;;;;;;;;;;;;;;
to depart
;  log-data "drivers" (sentence precision ticks 3 [id] of self "departing" state-of-charge)
  ifelse need-to-charge "depart" [  
    ifelse state-of-charge >= 1 - small-num or (( num-existing-chargers current-taz 1 = 0) and ( num-existing-chargers current-taz 2  = 0) and (num-existing-chargers current-taz 4 = 0) and state-of-charge >= 0.8 - small-num)[
      log-data "break-up-trip" (sentence ticks id state-of-charge ([id] of current-taz) ([id] of destination-taz) remaining-range charging-on-a-whim? "break-up-trip") ;;;LOG
      break-up-trip
    ][
      log-data "break-up-trip" (sentence ticks id state-of-charge ([id] of current-taz) ([id] of destination-taz) remaining-range charging-on-a-whim? "seek-charger") ;;;LOG
      seek-charger
    ]
  ][  
    travel-time-event-scheduler
  ]
end

;;;;;;;;;;;;;;;;;;;;
;; BREAK UP TRIP
;;;;;;;;;;;;;;;;;;;;
to break-up-trip
  let #cand-taz-list (remove current-taz (remove destination-taz (item current-od-index od-enroute)))
  let #this-taz 0
  let #max-score 0
  let #max-taz 0
  let #max-dist 0
  let #max-dist-only 0
  let #max-dist-taz 0
  let #result-action "-from-subset"
  foreach #cand-taz-list [
    set #this-taz ?
    let #this-score 0
    let #this-dist distance-from-to [id] of current-taz [id] of #this-taz
    let #only-level-3 (num-existing-chargers #this-taz 1  = 0) and (num-existing-chargers #this-taz 2 = 0) and (num-existing-chargers #this-taz 4 = 0)
    if #this-dist <= remaining-range / charge-safety-factor and 
      ( (#only-level-3 and distance-from-to [id] of #this-taz [id] of destination-taz <= 0.8 * battery-capacity / electric-fuel-consumption / charge-safety-factor)
        or (not #only-level-3 and distance-from-to [id] of #this-taz [id] of destination-taz <= battery-capacity / electric-fuel-consumption / charge-safety-factor) ) [
      foreach [level] of charger-types [
        let #level ?
        if (num-available-chargers #this-taz #level > 0) [
          ifelse #level = 0 [
            if #this-taz = home-taz [ set #this-score #this-score + 8 ]
          ][
            set #this-score #this-score + #level * num-available-chargers #this-taz #level
          ]  
        ]
      ]
    ]
    if #this-score > #max-score or (#this-score = #max-score and #this-dist > #max-dist) [ 
      set #max-score #this-score
      set #max-taz #this-taz
      set #max-dist #this-dist
    ]
  ]
  ; log available chargers for verification
  if log-break-up-trip-choice[ ;;;LOG
      foreach #cand-taz-list [ ;;;LOG
        set #this-taz ? ;;;LOG
        foreach [level] of charger-types [ ;;;LOG
          log-data "available-chargers" (sentence ticks id [id] of current-taz [id] of home-taz [id] of #this-taz ? num-available-chargers #this-taz ?) ;;;LOG
        ] ;;;LOG
      ] ;;;LOG
  ] ;;;LOG
  if #max-score = 0 [  ; do it again but don't restrict to taz's that get us there on the second trip and count all chargers (not just available chargers) in making the score
    set #result-action "-from-all"
    set #max-taz 0
    set #max-dist 0
    set #max-dist-taz 0
    foreach #cand-taz-list [
      set #this-taz ?
      let #this-score 0
      let #this-dist distance-from-to [id] of current-taz [id] of #this-taz
      if #this-dist <= remaining-range / charge-safety-factor [
        foreach [level] of charger-types [
          let #level ?
          let #total-num-chargers num-existing-chargers #this-taz #level
          if (#total-num-chargers > 0) [
            ifelse #level = 0 [ 
              if #this-taz = home-taz [ set #this-score #this-score + 8 ]
            ][
              let #num-available num-available-chargers #this-taz #level
              set #this-score #this-score + #level * #num-available + #level * (#total-num-chargers - #num-available) * 0.25
            ]  
          ]
        ]
      ]
      if #this-score > #max-score or (#this-score = #max-score and #this-dist > #max-dist) [ 
        set #max-score #this-score
        set #max-taz #this-taz
        set #max-dist #this-dist
      ]
      if #this-dist > #max-dist-only [ 
        set #max-dist-only #this-dist
        set #max-dist-taz #this-taz
      ]
    ]
  ]
  ifelse #max-score = 0 [
    ifelse #max-dist-taz = 0 [
      log-data "break-up-trip-choice" (sentence ticks id ([id] of current-taz) ([id] of destination-taz) "none-found" 0 0) ;;;LOG
      ;; Nothing found, this driver is hard-stranded
      set state "stranded"
      set itin-delay-amount replace-item current-itin-row itin-delay-amount (item current-itin-row itin-delay-amount + hard-strand-penalty)
      log-data "pain" (sentence ticks id [id] of current-taz [name] of this-vehicle-type "stranded" "" state-of-charge) ;;;LOG      
    ][ 
      ; choose the furthest along and hope
      log-data "break-up-trip-choice" (sentence ticks id ([id] of current-taz) ([id] of destination-taz) "max-distance" ([id] of #max-dist-taz) #max-dist-only) ;;;LOG
      add-trip-to-itinerary #max-dist-taz
    ]
  ][
    log-data "break-up-trip-choice" (sentence ticks id ([id] of current-taz) ([id] of destination-taz) (word "max-score" #result-action) ([id] of #max-taz) #max-score) ;;;LOG
    add-trip-to-itinerary #max-taz
  ]
  travel-time-event-scheduler
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TRAVEL TIME EVENT SCHEDULER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to travel-time-event-scheduler
  set state "traveling"
  set trip-time item current-od-index od-time
  time:schedule-event self task arrive (ticks + trip-time)
end

;;;;;;;;;;;;;;;;;;;;
;; ARRIVE
;;;;;;;;;;;;;;;;;;;;
to arrive
  ; for logging trip
  let #is-scheduled true ;;;LOG
  if item current-itin-row itin-change-flag = 1 [ set #is-scheduled false ] ;;;LOG
  
  ; account for energy / gas used in the trip
  let #charge-used trip-distance * electric-fuel-consumption / battery-capacity
  set miles-driven miles-driven + trip-distance
  ifelse not is-bev? and state-of-charge - #charge-used < 0 [
    log-data "trip" (sentence (ticks - trip-time) id ([name] of this-vehicle-type) ([id] of current-taz) ([id] of destination-taz) (distance-from-to [id] of current-taz [id] of destination-taz) #is-scheduled state-of-charge 0 (state-of-charge * battery-capacity) ((#charge-used - state-of-charge) * battery-capacity / electric-fuel-consumption * hybrid-fuel-consumption) ticks) ;;;LOG
    set energy-used energy-used + state-of-charge * battery-capacity
    set gasoline-used gasoline-used + (#charge-used - state-of-charge) * battery-capacity / electric-fuel-consumption * hybrid-fuel-consumption
    set state-of-charge 0
  ][
    log-data "trip" (sentence (ticks - trip-time) id ([name] of this-vehicle-type) ([id] of current-taz) ([id] of destination-taz) (distance-from-to [id] of current-taz [id] of destination-taz) #is-scheduled state-of-charge (max (sentence 0 (state-of-charge - #charge-used))) (#charge-used * battery-capacity) 0 ticks) ;;;LOG
    set state-of-charge max (sentence 0 (state-of-charge - #charge-used))
    set energy-used energy-used + #charge-used * battery-capacity
  ]
  
  let #completed-journey journey-distance  ;;;LOG
  let #completed-trip trip-distance        ;;;LOG
  let #from-taz [id] of current-taz        ;;;LOG
  set journey-distance journey-distance - trip-distance
  log-driver "arriving" ;;;LOG
  update-itinerary 
  let #to-taz [id] of current-taz
  ifelse not itin-complete? [
    ifelse need-to-charge "arrive" [
      seek-charger   
      log-data "trip-journey-timeuntildepart" (sentence ticks departure-time id [name] of this-vehicle-type state-of-charge #from-taz #to-taz #completed-trip #completed-journey (departure-time - ticks) "seeking-charger" remaining-range sum map weight-delay itin-delay-amount) ;;;LOG
    ][
      itinerary-event-scheduler  
      log-data "trip-journey-timeuntildepart" (sentence ticks departure-time id [name] of this-vehicle-type state-of-charge #from-taz #to-taz #completed-trip #completed-journey (departure-time - ticks) "scheduling-itinerary" remaining-range sum map weight-delay itin-delay-amount) ;;;LOG
    ]
  ][
    ;; itin is complete and at home? Perform random draw to see if they plug-in immediately and charge till full. If multi-unit, charger may not be available.
    ifelse current-taz = home-taz [
      if (random-float 1) < (1 / (1 + exp(-5 + 6 * state-of-charge))) [
        set current-charger (one-of item 0 [chargers-by-type] of current-taz)
        set full-charge-time-need (1 - state-of-charge) * battery-capacity / charge-rate-of current-charger
        time:schedule-event self task end-charge ticks + full-charge-time-need 
        set time-until-end-charge full-charge-time-need
        log-data "charging" (sentence ticks [who] of current-charger level-of current-charger [id] of current-taz [id] of self [name] of this-vehicle-type full-charge-time-need (full-charge-time-need * charge-rate-of current-charger) state-of-charge (state-of-charge + (full-charge-time-need * charge-rate-of current-charger) / battery-capacity ) "stop" false) ;;;LOG
      ]
      log-data "trip-journey-timeuntildepart" (sentence ticks ticks id [name] of this-vehicle-type state-of-charge #from-taz #to-taz #completed-trip #completed-journey 0 "home" remaining-range sum map weight-delay itin-delay-amount) ;;;LOG
    ][
      log-data "trip-journey-timeuntildepart" (sentence ticks ticks id [name] of this-vehicle-type state-of-charge #from-taz #to-taz #completed-trip #completed-journey 0 "journey-complete" remaining-range sum map weight-delay itin-delay-amount) ;;;LOG
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;
;; UPDATE ITINERARY
;;;;;;;;;;;;;;;;;;;;
to update-itinerary
  ifelse (current-itin-row + 1 < length itin-from) [
    set current-itin-row current-itin-row + 1
    let #itin-from item current-itin-row itin-from
    let #itin-to item current-itin-row itin-to
    set current-taz table:get taz-table #itin-from ;one-of tazs with [id = #itin-from]
    set destination-taz table:get taz-table #itin-to ;one-of tazs with [id = #itin-to]
    update-od-index
    ifelse ((item current-itin-row itin-depart) < ticks)[     
      change-depart-time ticks
    ][
      set departure-time item current-itin-row itin-depart
    ]
    ifelse ([id] of destination-taz >= 0 and [id] of current-taz >= 0) [
      set trip-distance item current-od-index od-dist
      set trip-time item current-od-index od-time
    ][
      set trip-distance item current-od-index od-dist + [external-dist] of self
      set trip-time item current-od-index od-time + [external-time] of self
    ]
  ][
    set current-taz destination-taz  ;; ac 12.20
    set itin-complete? true
  ]
end

to initialize-available-chargers
  ask tazs [
    foreach chargers-by-type [
      ask-concurrent ? [
        return-charger myself [level] of this-charger-type self
      ]
    ]
  ]
end

to return-charger [#taz #level #charger]
  if ([alt-energy-price] of #charger = 0) [
    ask #taz [
      if not structs:stack-contains item #level available-chargers-by-type #charger [
      structs:stack-push item #level available-chargers-by-type #charger
      ]
    ]
  ]  
end

to-report num-available-chargers [#taz #level]
  let #found-chargers 0
  ask #taz[
    set #found-chargers (structs:stack-count item #level available-chargers-by-type) ; I think this needs the actual chargers, not just how many.
  ]
  report #found-chargers
end

to-report selected-charger [#taz #level]
  let #selected-charger 0
  ask #taz[
    set #selected-charger structs:stack-pop item #level available-chargers-by-type
  ]
  report #selected-charger
end

to-report num-existing-chargers [#taz #level]
  let #found-chargers 0
  ask #taz[
    set #found-chargers count (item #level chargers-by-type)
  ]
  report #found-chargers
end

to-report charge-rate-of [#charger]
  report [charge-rate] of ([this-charger-type] of #charger)
end

to-report energy-price-of [#charger]
  report [energy-price] of ([this-charger-type] of #charger)
end
to-report level-of [#charger]
  report [level] of ([this-charger-type] of #charger)
end
to-report distance-from-to [from-taz to-taz]
  let reporter-distance 0
  ifelse ((from-taz >= 0) and (to-taz >= 0)) [
    set reporter-distance item ((from-taz - 1) * n-tazs + to-taz - 1 ) od-dist
  ][ ; determine distance from gateway to destination, add extra distance
    let #gateway-distance item ((abs(from-taz) - 1) * n-tazs + abs(to-taz) - 1 ) od-dist
    set reporter-distance #gateway-distance + [external-dist] of self
  ]
  report reporter-distance
end
to-report time-from-to [from-taz to-taz]
  let reporter-time 0
  ifelse ((from-taz >= 0) and (to-taz >= 0)) [
    set reporter-time item ((from-taz - 1) * n-tazs + to-taz - 1 ) od-time
  ][ ; determine distance from gateway to destination, add extra distance
    let #gateway-time item ((abs(from-taz) - 1) * n-tazs + (abs(to-taz) - 1) ) od-time
    set reporter-time #gateway-time + [external-time] of self
  ]
  report reporter-time
end
to-report od-index [destination source]
  report ((abs(destination) - 1) * n-tazs + abs(source) - 1)
end

to update-od-index
  set current-od-index ((abs([id] of current-taz) - 1) * n-tazs + abs([id] of destination-taz) - 1)
end

to-report driver-soc [the-driver]
  report [state-of-charge] of the-driver
end

to-report weight-delay [delay]
  ifelse delay >= 0 [report delay][report -0.5 * delay]
end

to-report interpolate-from-draw [#rand-draw cumulative-fraction variable-bounds]
  
  ; Input the random-draw, the cumulative-fraction draw-bounds list, and the variable-bounds list.
  
  foreach cumulative-fraction [
    let current-index position ? cumulative-fraction
    let next-index position ? cumulative-fraction + 1
    if #rand-draw > ? and #rand-draw <= item next-index cumulative-fraction [
      report (#rand-draw - item current-index cumulative-fraction)*(item next-index variable-bounds - item current-index variable-bounds)/(item next-index cumulative-fraction - item current-index cumulative-fraction) + item current-index variable-bounds
    ]
  ]
  report 1
end

to summarize ;;;LOG
  reset-logfile "driver-summary" ;;;LOG
  log-data "driver-summary" (sentence "metric" "vehicle-type" "home" "value") ;;;LOG
  foreach sort remove-duplicates [home-taz] of drivers [ ;;;LOG
    let #home-taz ? ;;;LOG
    ask vehicle-types [ ;;;LOG
      let subset drivers with [home-taz = #home-taz and this-vehicle-type = myself] ;;;LOG
      log-data "driver-summary" (sentence "num.drivers" name [id] of #home-taz (count subset)) ;;;LOG
      log-data "driver-summary" (sentence "num.trips" name [id] of #home-taz (sum [ length itin-change-flag - sum itin-change-flag ] of subset)) ;;;LOG
      log-data "driver-summary" (sentence "total.delay" name [id] of #home-taz sum [ sum map weight-delay itin-delay-amount  ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "num.delayed" name [id] of #home-taz count subset with [ sum map weight-delay itin-delay-amount > 0 ]) ;;;LOG
      log-data "driver-summary" (sentence "num.unscheduled.trips" name [id] of #home-taz sum [ sum itin-change-flag ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "energy.charged" name [id] of #home-taz sum [ energy-received ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "driver.expenses" name [id] of #home-taz sum [ expenses ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "gasoline.used" name [id] of #home-taz sum [ gasoline-used ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "miles.driven" name [id] of #home-taz sum [ miles-driven ] of subset) ;;;LOG
      log-data "driver-summary" (sentence "num.denials" name [id] of #home-taz sum [ num-denials ] of subset) ;;;LOG
    ] ;;;LOG
  ] ;;;LOG

  reset-logfile "summary"  ;;;LOG
  log-data "summary" (sentence "metric" "value") ;;;LOG
  log-data "summary" (sentence "num.drivers" count drivers) ;;;LOG
  log-data "summary" (sentence "num.bevs" count drivers with [is-bev?])  ;;;LOG
  log-data "summary" (sentence "num.trips" sum [ length itin-change-flag - sum itin-change-flag ] of drivers) ;;;LOG
  log-data "summary" (sentence "total.delay" sum [ sum map weight-delay itin-delay-amount  ] of drivers) ;;;LOG
  log-data "summary" (sentence "mean.delay" mean [ sum map weight-delay itin-delay-amount  ] of drivers) ;;;LOG
  log-data "summary" (sentence "frac.drivers.delayed" (count drivers with [ sum map weight-delay itin-delay-amount > 0 ] / count drivers)) ;;;LOG
  log-data "summary" (sentence "frac.stranded.by.delay" (num-stranded-by-delay / count drivers)) ;;;LOG
  log-data "summary" (sentence "num.unscheduled.trips" sum [ sum itin-change-flag ] of drivers) ;;;LOG
  log-data "summary" (sentence "energy.charged" sum [ energy-received ] of drivers) ;;;LOG
  log-data "summary" (sentence "driver.expenses" sum [ expenses ] of drivers) ;;;LOG
  log-data "summary" (sentence "infrastructure.cost" sum [ [installed-cost] of this-charger-type ] of chargers) ;;;LOG
  log-data "summary" (sentence "gasoline.used" sum [ gasoline-used ] of drivers) ;;;LOG
  log-data "summary" (sentence "miles.driven" sum [ miles-driven ] of drivers) ;;;LOG
  log-data "summary" (sentence "num.denials" sum [ num-denials ] of drivers) ;;;LOG
  log-data "summary" (sentence "frac.denied" (count drivers with [num-denials > 0] / count drivers)) ;;;LOG
  file-flush ;;;LOG
end ;;;LOG
@#$#@#$#@
GRAPHICS-WINDOW
195
14
440
232
-1
-1
7.5
1
10
1
1
1
0
0
0
1
0
25
0
24
1
1
1
ticks
30.0

BUTTON
9
10
138
43
NIL
setup-from-gui
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
9
47
72
80
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
473
10
645
43
go-until-time
go-until-time
0
100
100
0.5
1
NIL
HORIZONTAL

BUTTON
10
93
110
126
NIL
summarize
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
476
143
617
176
log-wait-time
log-wait-time
1
1
-1000

SWITCH
476
189
615
222
log-charging
log-charging
1
1
-1000

SWITCH
476
235
635
268
log-charge-time
log-charge-time
1
1
-1000

SWITCH
476
280
658
313
log-need-to-charge
log-need-to-charge
1
1
-1000

SWITCH
475
97
736
130
log-trip-journey-timeuntildepart
log-trip-journey-timeuntildepart
1
1
-1000

SWITCH
476
326
642
359
log-seek-charger
log-seek-charger
0
1
-1000

SWITCH
474
410
644
443
log-break-up-trip
log-break-up-trip
1
1
-1000

SWITCH
475
456
692
489
log-break-up-trip-choice
log-break-up-trip-choice
1
1
-1000

SWITCH
474
499
697
532
log-charge-limiting-factor
log-charge-limiting-factor
1
1
-1000

SWITCH
475
367
684
400
log-seek-charger-result
log-seek-charger-result
1
1
-1000

BUTTON
9
276
164
309
NIL
setup-and-fix-seed
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
10
319
92
352
NIL
go-until
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
476
541
603
574
log-drivers
log-drivers
1
1
-1000

SWITCH
477
59
587
92
log-pain
log-pain
1
1
-1000

SWITCH
474
587
583
620
log-tazs
log-tazs
1
1
-1000

SLIDER
611
588
840
621
log-taz-time-interval
log-taz-time-interval
0
60
60
1
1
minutes
HORIZONTAL

SWITCH
674
61
779
94
log-trip
log-trip
1
1
-1000

SWITCH
682
147
833
180
log-summary
log-summary
1
1
-1000

BUTTON
12
176
151
209
run-with-profiler
run-with-profiler
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
11
136
242
169
NIL
setup-in-batch-mode-from-gui
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
677
193
832
253
starting-seed
21
1
0
Number

SWITCH
678
264
787
297
fix-seed
fix-seed
0
1
-1000

@#$#@#$#@
## ## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## ## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## ## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## ## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## ## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## ## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## ## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## ## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## ## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.0.4
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Alt5_batt-cap-std" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>total-satisfaction</metric>
    <metric>average-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>total-wait</metric>
    <steppedValueSet variable="batt-cap-stdv" first="0" step="0.5" last="4"/>
    <enumeratedValueSet variable="min-batt-cap">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-batt-cap">
      <value value="27"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-mean">
      <value value="0.34"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-fuel-economy">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alternative">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-mean">
      <value value="24"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p2r1.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p4r1.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Alt5_bat_cap_range" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>total-satisfaction</metric>
    <metric>average-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>total-wait</metric>
    <steppedValueSet variable="batt-cap-range" first="1" step="1" last="10"/>
    <enumeratedValueSet variable="alternative">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-mean">
      <value value="24"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-fuel-economy">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-stdv">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p2r1.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p4r1.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-mean">
      <value value="0.34"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Alt5_batt-cap-mean" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>total-satisfaction</metric>
    <metric>average-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>total-wait</metric>
    <enumeratedValueSet variable="alternative">
      <value value="5"/>
    </enumeratedValueSet>
    <steppedValueSet variable="batt-cap-mean" first="24" step="6" last="48"/>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="max-fuel-economy">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-stdv">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-range">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p1r2.txt&quot;"/>
      <value value="&quot;p1r3.txt&quot;"/>
      <value value="&quot;p1r4.txt&quot;"/>
      <value value="&quot;p1r5.txt&quot;"/>
      <value value="&quot;p2r1.txt&quot;"/>
      <value value="&quot;p2r2.txt&quot;"/>
      <value value="&quot;p2r3.txt&quot;"/>
      <value value="&quot;p2r4.txt&quot;"/>
      <value value="&quot;p2r5.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p3r2.txt&quot;"/>
      <value value="&quot;p3r3.txt&quot;"/>
      <value value="&quot;p3r4.txt&quot;"/>
      <value value="&quot;p3r5.txt&quot;"/>
      <value value="&quot;p4r1.txt&quot;"/>
      <value value="&quot;p4r2.txt&quot;"/>
      <value value="&quot;p4r3.txt&quot;"/>
      <value value="&quot;p4r4.txt&quot;"/>
      <value value="&quot;p4r5.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
      <value value="&quot;p5r2.txt&quot;"/>
      <value value="&quot;p5r3.txt&quot;"/>
      <value value="&quot;p5r4.txt&quot;"/>
      <value value="&quot;p5r5.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="min-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-mean">
      <value value="0.34"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Alt5_batt-cap-stdv-2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>total-satisfaction</metric>
    <metric>average-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>total-wait</metric>
    <enumeratedValueSet variable="alternative">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-range">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-mean">
      <value value="24"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="batt-cap-stdv" first="0" step="1" last="4"/>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-range">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p1r2.txt&quot;"/>
      <value value="&quot;p1r3.txt&quot;"/>
      <value value="&quot;p1r4.txt&quot;"/>
      <value value="&quot;p1r5.txt&quot;"/>
      <value value="&quot;p2r1.txt&quot;"/>
      <value value="&quot;p2r2.txt&quot;"/>
      <value value="&quot;p2r3.txt&quot;"/>
      <value value="&quot;p2r4.txt&quot;"/>
      <value value="&quot;p2r5.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p3r2.txt&quot;"/>
      <value value="&quot;p3r3.txt&quot;"/>
      <value value="&quot;p3r4.txt&quot;"/>
      <value value="&quot;p3r5.txt&quot;"/>
      <value value="&quot;p4r1.txt&quot;"/>
      <value value="&quot;p4r2.txt&quot;"/>
      <value value="&quot;p4r3.txt&quot;"/>
      <value value="&quot;p4r4.txt&quot;"/>
      <value value="&quot;p4r5.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
      <value value="&quot;p5r2.txt&quot;"/>
      <value value="&quot;p5r3.txt&quot;"/>
      <value value="&quot;p5r4.txt&quot;"/>
      <value value="&quot;p5r5.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-mean">
      <value value="0.34"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Alt5_fuel-econ-mean" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>total-satisfaction</metric>
    <metric>average-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>total-wait</metric>
    <enumeratedValueSet variable="alternative">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-range">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-mean">
      <value value="24"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-stdv">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-range">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p1r2.txt&quot;"/>
      <value value="&quot;p1r3.txt&quot;"/>
      <value value="&quot;p1r4.txt&quot;"/>
      <value value="&quot;p1r5.txt&quot;"/>
      <value value="&quot;p2r1.txt&quot;"/>
      <value value="&quot;p2r2.txt&quot;"/>
      <value value="&quot;p2r3.txt&quot;"/>
      <value value="&quot;p2r4.txt&quot;"/>
      <value value="&quot;p2r5.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p3r2.txt&quot;"/>
      <value value="&quot;p3r3.txt&quot;"/>
      <value value="&quot;p3r4.txt&quot;"/>
      <value value="&quot;p3r5.txt&quot;"/>
      <value value="&quot;p4r1.txt&quot;"/>
      <value value="&quot;p4r2.txt&quot;"/>
      <value value="&quot;p4r3.txt&quot;"/>
      <value value="&quot;p4r4.txt&quot;"/>
      <value value="&quot;p4r5.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
      <value value="&quot;p5r2.txt&quot;"/>
      <value value="&quot;p5r3.txt&quot;"/>
      <value value="&quot;p5r4.txt&quot;"/>
      <value value="&quot;p5r5.txt&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="fuel-economy-mean" first="0.26" step="0.04" last="0.43"/>
  </experiment>
  <experiment name="pev135_alt135_Power" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>count drivers</metric>
    <metric>count drivers with [phev? = true]</metric>
    <metric>count drivers with [status = "Stranded"]</metric>
    <metric>count drivers with [status = "Traveling"]</metric>
    <metric>count drivers with [status = "Waiting"]</metric>
    <metric>count drivers with [status = "Staging"]</metric>
    <metric>count drivers with [status = "Charging"]</metric>
    <metric>count drivers with [status = "Home"]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.1 and driver-satisfaction &gt; 0]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.4 and driver-satisfaction &gt;= 0.1]</metric>
    <metric>count drivers with [driver-satisfaction &lt; 0.7 and driver-satisfaction &gt;= 0.4]</metric>
    <metric>count drivers with [driver-satisfaction &lt;= 1 and driver-satisfaction &gt;= 0.7]</metric>
    <metric>sum [kWh-received] of drivers</metric>
    <metric>average-duty-factor</metric>
    <metric>level1-duty-factor</metric>
    <metric>level2-duty-factor</metric>
    <metric>average-charger-service</metric>
    <metric>mean [charger-service] of chargers with [charger-level = 1]</metric>
    <metric>mean [charger-service] of chargers with [charger-level = 2]</metric>
    <metric>count chargers with [available = true and charger-level = 1]</metric>
    <metric>count chargers with [available = true and charger-level = 2]</metric>
    <metric>sum [kWh-charged] of chargers</metric>
    <metric>total-wait</metric>
    <metric>total-satisfaction</metric>
    <metric>kw</metric>
    <enumeratedValueSet variable="driver-input-file">
      <value value="&quot;p1r1.txt&quot;"/>
      <value value="&quot;p1r2.txt&quot;"/>
      <value value="&quot;p1r3.txt&quot;"/>
      <value value="&quot;p1r4.txt&quot;"/>
      <value value="&quot;p1r5.txt&quot;"/>
      <value value="&quot;p3r1.txt&quot;"/>
      <value value="&quot;p3r2.txt&quot;"/>
      <value value="&quot;p3r3.txt&quot;"/>
      <value value="&quot;p3r4.txt&quot;"/>
      <value value="&quot;p3r5.txt&quot;"/>
      <value value="&quot;p5r1.txt&quot;"/>
      <value value="&quot;p5r2.txt&quot;"/>
      <value value="&quot;p5r3.txt&quot;"/>
      <value value="&quot;p5r4.txt&quot;"/>
      <value value="&quot;p5r5.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-range">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-mean">
      <value value="0.34"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-range">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="bev-charge-anyway">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alternative">
      <value value="1"/>
      <value value="3"/>
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-step-size">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="n-nodes">
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debug?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-batt-cap">
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-fuel-economy">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="safety-factor">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fuel-economy-stdv">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-mean">
      <value value="24"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="phev-charge">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="batt-cap-stdv">
      <value value="1"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 1.0 0.0
0.0 1 1.0 0.0
0.2 0 1.0 0.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
