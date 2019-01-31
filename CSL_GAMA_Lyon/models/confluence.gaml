/***
* Name: roadtraffic
* Author: evage
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model confluence

/* Insert your model definition here */
global{
	
	file shape_file_buildings <- file("../includes/Bati_reclass_CC46.shp");
	file shape_file_roads <- file("../includes/ROUTESCC46.shp");
	file shape_file_trains <- file("../includes/voiesferres_ligneunique_CC46.shp");
	geometry shape <- envelope(shape_file_buildings);
	
	float step_max <- 6 #mn;
	float step_min <- 6 #s; // 10sec of disp == 1h of sim (at 60 fps)
	
	float step <- step_min;
	bool heatmap <- true;
	bool heatmap_clean <- false;
	bool road_display <- true;
	bool building_display <- true;
	bool add_bridges_flag <- false;
	bool ns_wind <- false;
	
	int nb_people <- 600;
	int nb_extra_people <- 20;
	int nb_train <- 5;
	
	float current_hour <- 0.0;
	
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16; 
	int max_work_end <- 18; 
	
	float ref_speed <- 10.0 #km / #h;
	graph the_graph;
	graph train_line_graph;
	
	float pollution_max_level <- 100.0;
	int spread_factor <- 10;
	

	init{
		create building from: shape_file_buildings with: [type::string(read ("Type"))]{
			if type="commerce"{
				color <- #goldenrod;
			}
			if type="gare" or  type="Musee"{
				color <- #yellow;
			}
			if type="habitat" or type="culte"{
				color <- #white;
			}
			if type="spawn1" or type="spawn2" or type="spawn3" or type="spawn4" or type="spawn5" {
				color <- rgb(#grey, 0.0);
			}
		}

		create road from: shape_file_roads with: [classe::string(read("CLASSE"))]{
			if classe="Route"{
				weight <- 1.0;
			}
			if classe="Départementale"{
				weight <- 0.6;
			}
			if classe="Autoroute"{
				weight <- 0.2;
			}
			if classe="pont"{
				weight <- 0.2;
				color <- rgb(#grey, 0.0);
			}
		}
		
		create train_line from: shape_file_trains with: [classe::string(read("CLASSE"))]{
		}
		
		map<road,float> weights_map <- road as_map (each:: (each.weight * each.shape.perimeter));
      	the_graph <- as_edge_graph(road) with_weights weights_map;
      	
      	map<train_line,float> weights_map_train <- train_line as_map (each:: (each.weight * each.shape.perimeter));
      	train_line_graph <- as_edge_graph(train_line) with_weights weights_map_train;
		
		list<building> residential_buildings <- building where (each.type="habitat");
      	list<building> activity_buildings <- building  where (each.type="commerce");
      	list<building> populated_areas <- building  where (each.type="Musee" or each.type="gare");

		create people number: nb_people{
			speed <- ref_speed;
      		start_work <- min_work_start + (max_work_start - min_work_start) * rnd(0,100)/100.0;
          	end_work <- min_work_end + (max_work_end - min_work_end) * rnd(0,100)/100.0 ;
          	living_place <- one_of(residential_buildings) ;
          	working_place <- one_of(activity_buildings) ;
          	objective <- "resting";
          	location <- any_location_in (living_place);
		}		
		
		
		create extra_people_highway number: nb_extra_people{
			spawns <- building  where (each.type="spawn1" or each.type="spawn2");
			location <- any_location_in (one_of(spawns));
		}
		
		/* TODO
		create train number: nb_train{
			spawns <- building  where (each.type="spawn3" or each.type="spawn4" or each.type="spawn5" or each.type="gare");
			location <- any_location_in (one_of(spawns));
		}
		* 
		*/
	}
	
	reflex update_step{
		bool time_to_go <- ((current_hour >= min_work_start) and (current_hour <= max_work_start + 1));
		bool time_to_come_back <- ((current_hour >= min_work_end) and (current_hour <= max_work_start + 1));
		if(time_to_go or time_to_come_back)
		{
			step <- step_min;
		}else {
			step <- step_max;
		}
	}
	
	reflex update_current_hour{
		current_hour <- current_date.hour + float(current_date.minute/60.0);	
	}
	
	reflex addBridges when: add_bridges_flag{
		ask(road)
		{
			if(classe="pont"){
				weight <- 0.6;
				color <- rgb(0,255,0);
			}
		}
		
		map<road,float> weights_map <- road as_map (each:: (each.weight * each.shape.perimeter));
		the_graph <- as_edge_graph(road) with_weights weights_map;
		
		add_bridges_flag <- false;
	}
}

species building{
	string type;
	rgb color <- #black;
	
	aspect base {
		if(building_display){
			draw shape color: color;
		}
	}
}

species road {
	string classe;
	float weight <- 1.0;
	rgb color <- rgb(0,255,0);
	
	aspect base {
		if(road_display){
			draw shape color: color;
		}
	}
}

species train_line {
	string classe;
	float weight <- 0.1;
	rgb color <- #yellow;
	
	aspect base {
		if(road_display){
			draw shape color: color;
		}
	}
}

species people skills: [moving]{
	rgb color <- #red;
	building living_place <- nil;
	building working_place <- nil;
	float start_work;
	float end_work;
	
	string objective;
	point the_target <- nil;
	
	aspect base{
		draw circle(10) color: color;
	}
	
	reflex time_to_work when: current_hour > start_work and current_hour < start_work + 1 and objective = "resting"{
   		objective <- "working";
   		the_target <- any_location_in (working_place);
  	}
      
	reflex time_to_go_home when: current_hour > end_work and current_hour < end_work + 1  and objective = "working"{
		objective <- "resting";
		the_target <- any_location_in (living_place);
	}
	
	reflex move when: the_target != nil{
		do updatePollutionMap;
		
		path path_followed <- self goto [target::the_target, on::the_graph, return_path:: true];
		
		if the_target = location{
			the_target <- nil;
		}
	}
	
	reflex update_speed{
		speed <- ref_speed;
	}
	
	action updatePollutionMap{
		if(current_path != nil)
		{
			list<cell> tmp <- cell overlapping(shape);
		
			if(tmp != []){
				ask tmp {
					pollution_level <- pollution_level + 1;
					if(pollution_level > pollution_max_level)
					{
						pollution_level <- pollution_max_level;
					}
				}
			}	
		}
	}
}

species extra_people_highway skills: [moving]{
	list<building> spawns;
	
	point the_target <- nil;
	rgb color <- #red;
	
	reflex set_target when: the_target = nil and flip(0.005){
		the_target <- any_location_in (one_of(spawns));
	}
	
	reflex move when: the_target != nil{
		do updatePollutionMap;
		
		path path_followed <- self goto [target::the_target, on::the_graph, return_path:: true];
		
		if the_target = location{
			the_target <- nil;
		}
	}
	
	action updatePollutionMap{
		if(current_path != nil)
		{
			list<cell> tmp <- cell overlapping(shape);
		
			if(tmp != []){
				ask tmp {
					pollution_level <- pollution_level + 1;
					if(pollution_level > pollution_max_level)
					{
						pollution_level <- pollution_max_level;
					}
				}
			}	
		}
	}
	
	aspect base{
		if(the_target != nil ){
			draw circle(10) color: color;
		}
	}
}

species train skills: [moving]{
	list<building> spawns;
	
	point the_target <- nil;
	rgb color <- #yellow;
	
	reflex set_target when: the_target = nil and flip(0.005){
		the_target <- any_location_in (one_of(spawns));
	}
	
	reflex move when: the_target != nil{
		path path_followed <- self goto [target::the_target, on::train_line_graph, return_path:: true];
		
		if the_target = location{
			the_target <- nil;
		}
	}
	
	
	aspect base{
		if(the_target != nil ){
			draw square(40) color: color rotate: heading;
		}
	}
}

grid cell height: 100 width: 100 neighbors: 4 {
	
	float pollution_level <- 0.0 ;
	//list neighbours of: cell <- (self neighbors_at 1) of_species cell;  

	rgb pollution_color <- rgb(255,255,255);
	float transparency <- 0.75;

	reflex update_color when:heatmap{
		pollution_color <-  rgb(transparency *30,transparency *109,transparency *255);
	}
	
	reflex update_transparency when:heatmap {
		transparency <- float(pollution_level) / pollution_max_level;
	}
	
	//TODO not working
	/* 
	reflex spread{
		if(!ns_wind){
			float tmp_pollution <- pollution_level;
			float pollution_spread <- pollution_level * spread_factor/100.0;
			
			pollution_level <- pollution_level - pollution_spread;
			pollution_spread <- pollution_spread / 8;
			
			loop n over: neighbours {
				pollution_level <- pollution_level + pollution_spread;
			}
		}else{
			//TODO
		}
	}
	* */
	
	action raz {
		pollution_level <- 0.0;
	}
	
	aspect pollution{
		if(heatmap)
		{
			draw shape color: rgb(pollution_color, transparency);
		}
	}
}

experiment life type: gui {
	float minimum_cycle_duration <- 1/60; //60fps
	
	parameter "Car speed" var: ref_speed category: "Runtime settings" min: 5 #km/#h max: 1000 #km/#h;
	parameter "Step working/resting hour" var: step_max category: "Runtime settings" min: 1#mn max: 20#mn;
	parameter "Step moving hour" var: step_min category: "Runtime settings";
	
	parameter "Number of people agents" var: nb_people category: "People";
	
	parameter "Shapefile for the buildings" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads" var: shape_file_roads category: "GIS";
	
	output{
		display city_display type: opengl 
		background:rgb(sin_rad(#pi * current_hour / 24.0) * 150, sin_rad(#pi * current_hour / 24.0) * 120, sin_rad(#pi * current_hour / 24.0) * 80) 
		synchronized:true 
		camera_pos: {1473.4207,1609.8385,2114.0265} camera_look_pos: {1409.429,1572.8928,-0.883} camera_up_vector: {-0.8655,0.4997,0.0349}
		{
			species building aspect: base; // refresh: false;
			species train_line aspect: base; 
			species road aspect: base; 
			species train aspect: base;
			species extra_people_highway aspect: base;
			species people aspect: base;
			species cell aspect:pollution; //transparency: 0.75;
			
			graphics "time" {
				draw string(current_date.hour) + "h" + string(current_date.minute) +"m" color: # white font: font("Helvetica", 30, #italic) at: {world.shape.width*0.43,world.shape.height*0.93};
			}
			
			event ['h'] action: {heatmap <- !heatmap;}; //heatmap display
			event ['c'] action: {if(heatmap){ask cell{do raz;}}}; // clean heatmap (if heatmap)
			event ['b'] action: {building_display <- !building_display;}; //building display
			event ['r'] action: {road_display <- !road_display;}; //road display
			event ['p'] action: {add_bridges_flag <- true;}; //add bridges(ponts)
			event ['w'] action: {ns_wind <- !ns_wind;}; //north-south wind activation
		}
	}
}