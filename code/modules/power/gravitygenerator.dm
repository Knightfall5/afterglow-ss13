
//
// Gravity Generator
//

GLOBAL_LIST_EMPTY(gravity_generators) // We will keep track of this by adding new gravity generators to the list, and keying it with the z level.

#define POWER_IDLE 0
#define POWER_UP 1
#define POWER_DOWN 2

#define GRAV_NEEDS_SCREWDRIVER 0
#define GRAV_NEEDS_WELDING 1
#define GRAV_NEEDS_PLASTEEL 2
#define GRAV_NEEDS_WRENCH 3

//
// Abstract Generator
//

/obj/machinery/gravity_generator
	name = "gravitational generator"
	desc = "A device which produces a gravaton field when set up."
	icon = 'icons/obj/machines/gravity_generator.dmi'
	anchored = 1
	density = 1
	use_power = 0
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	var/sprite_number = 0

/obj/machinery/gravity_generator/throw_at()
	return FALSE

/obj/machinery/gravity_generator/ex_act(severity, target)
	if(severity == 1) // Very sturdy.
		set_broken()

/obj/machinery/gravity_generator/blob_act(obj/structure/blob/B)
	if(prob(20))
		set_broken()

/obj/machinery/gravity_generator/tesla_act(power, explosive)
	..()
	if(explosive)
		qdel(src)//like the singulo, tesla deletes it. stops it from exploding over and over

/obj/machinery/gravity_generator/update_icon()
	..()
	icon_state = "[get_status()]_[sprite_number]"

//prevents shuttles attempting to rotate this since it messes up sprites
/obj/machinery/gravity_generator/shuttleRotate()
	return

/obj/machinery/gravity_generator/proc/get_status()
	return "off"

// You aren't allowed to move.
/obj/machinery/gravity_generator/Move()
	..()
	qdel(src)

/obj/machinery/gravity_generator/proc/set_broken()
	stat |= BROKEN

/obj/machinery/gravity_generator/proc/set_fix()
	stat &= ~BROKEN

/obj/machinery/gravity_generator/part/Destroy()
	if(main_part)
		qdel(main_part)
	set_broken()
	return ..()

//
// Part generator which is mostly there for looks
//

/obj/machinery/gravity_generator/part
	var/obj/machinery/gravity_generator/main/main_part = null

/obj/machinery/gravity_generator/part/attackby(obj/item/I, mob/user, params)
	return main_part.attackby(I, user)

/obj/machinery/gravity_generator/part/get_status()
	return main_part.get_status()

/obj/machinery/gravity_generator/part/attack_hand(mob/user)
	return main_part.attack_hand(user)

/obj/machinery/gravity_generator/part/set_broken()
	..()
	if(main_part && !(main_part.stat & BROKEN))
		main_part.set_broken()

//
// Generator which spawns with the station.
//

/obj/machinery/gravity_generator/main/station/Initialize()
	. = ..()
	setup_parts()
	middle.add_overlay("activated")
	update_list()

//
// Generator an admin can spawn
//
/obj/machinery/gravity_generator/main/station/admin
	use_power = 0

//
// Main Generator with the main code
//

/obj/machinery/gravity_generator/main
	icon_state = "on_8"
	idle_power_usage = 0
	active_power_usage = 3000
	power_channel = ENVIRON
	sprite_number = 8
	use_power = 1
	interact_offline = 1
	var/on = 1
	var/breaker = 1
	var/list/parts = list()
	var/obj/middle = null
	var/charging_state = POWER_IDLE
	var/charge_count = 100
	var/current_overlay = null
	var/broken_state = 0

/obj/machinery/gravity_generator/main/Destroy() // If we somehow get deleted, remove all of our other parts.
	investigate_log("was destroyed!", "gravity")
	on = 0
	update_list()
	for(var/obj/machinery/gravity_generator/part/O in parts)
		O.main_part = null
		if(!QDESTROYING(O))
			qdel(O)
	return ..()

/obj/machinery/gravity_generator/main/proc/setup_parts()
	var/turf/our_turf = get_turf(src)
	// 9x9 block obtained from the bottom middle of the block
	var/list/spawn_turfs = block(locate(our_turf.x - 1, our_turf.y + 2, our_turf.z), locate(our_turf.x + 1, our_turf.y, our_turf.z))
	var/count = 10
	for(var/turf/T in spawn_turfs)
		count--
		if(T == our_turf) // Skip our turf.
			continue
		var/obj/machinery/gravity_generator/part/part = new(T)
		if(count == 5) // Middle
			middle = part
		if(count <= 3) // Their sprite is the top part of the generator
			part.density = 0
			part.layer = WALL_OBJ_LAYER
		part.sprite_number = count
		part.main_part = src
		parts += part
		part.update_icon()

/obj/machinery/gravity_generator/main/proc/connected_parts()
	return parts.len == 8

/obj/machinery/gravity_generator/main/set_broken()
	..()
	for(var/obj/machinery/gravity_generator/M in parts)
		if(!(M.stat & BROKEN))
			M.set_broken()
	middle.cut_overlays()
	charge_count = 0
	breaker = 0
	set_power()
	set_state(0)
	investigate_log("has broken down.", "gravity")

/obj/machinery/gravity_generator/main/set_fix()
	..()
	for(var/obj/machinery/gravity_generator/M in parts)
		if(M.stat & BROKEN)
			M.set_fix()
	broken_state = 0
	update_icon()
	set_power()

// Interaction

// Fixing the gravity generator.
/obj/machinery/gravity_generator/main/attackby(obj/item/I, mob/user, params)
	switch(broken_state)
		if(GRAV_NEEDS_SCREWDRIVER)
			if(istype(I, /obj/item/weapon/screwdriver))
				to_chat(user, "<span class='notice'>You secure the screws of the framework.</span>")
				playsound(src.loc, I.usesound, 50, 1)
				broken_state++
				update_icon()
				return
		if(GRAV_NEEDS_WELDING)
			if(istype(I, /obj/item/weapon/weldingtool))
				var/obj/item/weapon/weldingtool/WT = I
				if(WT.remove_fuel(1, user))
					to_chat(user, "<span class='notice'>You mend the damaged framework.</span>")
					playsound(src.loc, 'sound/items/Welder2.ogg', 50, 1)
					broken_state++
					update_icon()
				else if(WT.isOn())
					to_chat(user, "<span class='warning'>You don't have enough fuel to mend the damaged framework!</span>")
				return
		if(GRAV_NEEDS_PLASTEEL)
			if(istype(I, /obj/item/stack/sheet/plasteel))
				var/obj/item/stack/sheet/plasteel/PS = I
				if(PS.get_amount() >= 10)
					PS.use(10)
					to_chat(user, "<span class='notice'>You add the plating to the framework.</span>")
					playsound(src.loc, 'sound/machines/click.ogg', 75, 1)
					broken_state++
					update_icon()
				else
					to_chat(user, "<span class='warning'>You need 10 sheets of plasteel!</span>")
				return
		if(GRAV_NEEDS_WRENCH)
			if(istype(I, /obj/item/weapon/wrench))
				to_chat(user, "<span class='notice'>You secure the plating to the framework.</span>")
				playsound(src.loc, I.usesound, 75, 1)
				set_fix()
				return
	return ..()


/obj/machinery/gravity_generator/main/attack_hand(mob/user)
	if(!..())
		return interact(user)

/obj/machinery/gravity_generator/main/interact(mob/user)
	if(stat & BROKEN)
		return
	var/dat = "Gravity Generator Breaker: "
	if(breaker)
		dat += "<span class='linkOn'>ON</span> <A href='?src=\ref[src];gentoggle=1'>OFF</A>"
	else
		dat += "<A href='?src=\ref[src];gentoggle=1'>ON</A> <span class='linkOn'>OFF</span> "

	dat += "<br>Generator Status:<br><div class='statusDisplay'>"
	if(charging_state != POWER_IDLE)
		dat += "<font class='bad'>WARNING</font> Radiation Detected. <br>[charging_state == POWER_UP ? "Charging..." : "Discharging..."]"
	else if(on)
		dat += "Powered."
	else
		dat += "Unpowered."

	dat += "<br>Gravity Charge: [charge_count]%</div>"

	var/datum/browser/popup = new(user, "gravgen", name)
	popup.set_content(dat)
	popup.open()


/obj/machinery/gravity_generator/main/Topic(href, href_list)

	if(..())
		return

	if(href_list["gentoggle"])
		breaker = !breaker
		investigate_log("was toggled [breaker ? "<font color='green'>ON</font>" : "<font color='red'>OFF</font>"] by [usr.key].", "gravity")
		set_power()
		src.updateUsrDialog()

// Power and Icon States

/obj/machinery/gravity_generator/main/power_change()
	..()
	investigate_log("has [stat & NOPOWER ? "lost" : "regained"] power.", "gravity")
	set_power()

/obj/machinery/gravity_generator/main/get_status()
	if(stat & BROKEN)
		return "fix[min(broken_state, 3)]"
	return on || charging_state != POWER_IDLE ? "on" : "off"

/obj/machinery/gravity_generator/main/update_icon()
	..()
	for(var/obj/O in parts)
		O.update_icon()

// Set the charging state based on power/breaker.
/obj/machinery/gravity_generator/main/proc/set_power()
	var/new_state = 0
	if(stat & (NOPOWER|BROKEN) || !breaker)
		new_state = 0
	else if(breaker)
		new_state = 1

	charging_state = new_state ? POWER_UP : POWER_DOWN // Startup sequence animation.
	investigate_log("is now [charging_state == POWER_UP ? "charging" : "discharging"].", "gravity")
	update_icon()

// Set the state of the gravity.
/obj/machinery/gravity_generator/main/proc/set_state(new_state)
	charging_state = POWER_IDLE
	on = new_state
	use_power = on ? 2 : 1
	// Sound the alert if gravity was just enabled or disabled.
	var/alert = 0
	var/area/A = get_area(src)
	if(on && SSticker && SSticker.current_state == GAME_STATE_PLAYING) // If we turned on and the game is live.
		if(gravity_in_level() == 0)
			alert = 1
			investigate_log("was brought online and is now producing gravity for this level.", "gravity")
			message_admins("The gravity generator was brought online [A][ADMIN_COORDJMP(src)]")
	else
		if(gravity_in_level() == 1)
			alert = 1
			investigate_log("was brought offline and there is now no gravity for this level.", "gravity")
			message_admins("The gravity generator was brought offline with no backup generator. [A][ADMIN_COORDJMP(src)]")

	update_icon()
	update_list()
	src.updateUsrDialog()
	if(alert)
		shake_everyone()

// Charge/Discharge and turn on/off gravity when you reach 0/100 percent.
// Also emit radiation and handle the overlays.
/obj/machinery/gravity_generator/main/process()
	if(stat & BROKEN)
		return
	if(charging_state != POWER_IDLE)
		if(charging_state == POWER_UP && charge_count >= 100)
			set_state(1)
		else if(charging_state == POWER_DOWN && charge_count <= 0)
			set_state(0)
		else
			if(charging_state == POWER_UP)
				charge_count += 2
			else if(charging_state == POWER_DOWN)
				charge_count -= 2

			if(charge_count % 4 == 0 && prob(75)) // Let them know it is charging/discharging.
				playsound(src.loc, 'sound/effects/EMPulse.ogg', 100, 1)

			updateDialog()
			if(prob(25)) // To help stop "Your clothes feel warm." spam.
				pulse_radiation()

			var/overlay_state = null
			switch(charge_count)
				if(0 to 20)
					overlay_state = null
				if(21 to 40)
					overlay_state = "startup"
				if(41 to 60)
					overlay_state = "idle"
				if(61 to 80)
					overlay_state = "activating"
				if(81 to 100)
					overlay_state = "activated"

			if(overlay_state != current_overlay)
				if(middle)
					middle.cut_overlays()
					if(overlay_state)
						middle.add_overlay(overlay_state)
					current_overlay = overlay_state


/obj/machinery/gravity_generator/main/proc/pulse_radiation()
	radiation_pulse(get_turf(src), 3, 7, 20)

// Shake everyone on the z level to let them know that gravity was enagaged/disenagaged.
/obj/machinery/gravity_generator/main/proc/shake_everyone()
	var/turf/T = get_turf(src)
	for(var/mob/M in GLOB.mob_list)
		if(M.z != z)
			continue
		M.update_gravity(M.mob_has_gravity())
		if(M.client)
			shake_camera(M, 15, 1)
			M.playsound_local(T, 'sound/effects/alert.ogg', 100, 1, 0.5)

/obj/machinery/gravity_generator/main/proc/gravity_in_level()
	var/turf/T = get_turf(src)
	if(!T)
		return 0
	if(GLOB.gravity_generators["[T.z]"])
		return length(GLOB.gravity_generators["[T.z]"])
	return 0

/obj/machinery/gravity_generator/main/proc/update_list()
	var/turf/T = get_turf(src.loc)
	if(T)
		if(!GLOB.gravity_generators["[T.z]"])
			GLOB.gravity_generators["[T.z]"] = list()
		if(on)
			GLOB.gravity_generators["[T.z]"] |= src
		else
			GLOB.gravity_generators["[T.z]"] -= src

// Misc

/obj/item/weapon/paper/gravity_gen
	name = "paper- 'Generate your own gravity!'"
	info = {"<h1>Gravity Generator Instructions For Dummies</h1>
	<p>Surprisingly, gravity isn't that hard to make! All you have to do is inject deadly radioactive minerals into a ball of
	energy and you have yourself gravity! You can turn the machine on or off when required but you must remember that the generator
	will EMIT RADIATION when charging or discharging, you can tell it is charging or discharging by the noise it makes, so please WEAR PROTECTIVE CLOTHING.</p>
	<br>
	<h3>It blew up!</h3>
	<p>Don't panic! The gravity generator was designed to be easily repaired. If, somehow, the sturdy framework did not survive then
	please proceed to panic; otherwise follow these steps.</p><ol>
	<li>Secure the screws of the framework with a screwdriver.</li>
	<li>Mend the damaged framework with a welding tool.</li>
	<li>Add additional plasteel plating.</li>
	<li>Secure the additional plating with a wrench.</li></ol>"}
