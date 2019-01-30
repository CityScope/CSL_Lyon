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
	geometry shape <- envelope(shape_file_buildings);
	
	float step_max <- 6 #mn;
	float step_min <- 6 #s; // 10sec of disp == 1h of sim (at 60 fps)
	
	float step <- step_min;
	bool heatmap <- true;
	bool heatmap_clean <- false;
	
	list<list<float>> heatmap_color <- [[30,146,254],[86,149,242],[144,201,254],[180,231,252],[223,255,216],[254,255,113],[248,209,69],[243,129,40],[235,46,26],[109,23,8]];
	int nb_people <- 600;
	
	float current_hour <- 0.0;
	
	int min_work_start <- 6;
	int max_work_start <- 8;
	int min_work_end <- 16; 
	int max_work_end <- 18; 
	
	float ref_speed <- 10.0 #km / #h;
	graph the_graph;
	
	int pollution_max_level <- 25;
	

	init{
		create building from: shape_file_buildings with: [type::string(read ("Type"))]{
			if type="commerce"{
				color <- #steelblue;
			}
			if type="gare" or  type="Musee"{
				color <- #goldenrod;
			}
			if type="habitat" {
				//color <- #white;
				color <- #grey;
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
		}
		map<road,float> weights_map <- road as_map (each:: (each.weight * each.shape.perimeter));
      	the_graph <- as_edge_graph(road) with_weights weights_map;
		
		list<building> residential_buildings <- building where (each.type="habitat");
      	list<building>  interesting_buildings <- building  where (each.type="commerce" or each.type="Musee" or each.type="gare") ;
		
		create people number: nb_people{
			speed <- ref_speed;
      		start_work <- min_work_start + (max_work_start - min_work_start) * rnd(0,100)/100.0;
          	end_work <- min_work_end + (max_work_end - min_work_end) * rnd(0,100)/100.0 ;
          	living_place <- one_of(residential_buildings) ;
          	working_place <- one_of(interesting_buildings) ;
          	objective <- "resting";
          	location <- any_location_in (living_place);
		}		
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
	
}

species building{
	string type;
	//rgb color <- #grey;
	rgb color <- #black;
	
	aspect base {
		draw shape color: color;
	}
}

species road {
	string classe;
	float weight <- 1.0;
	rgb color <- rgb(0, 255, 0);
	
	aspect base {
		draw shape color: color;
	}
}

species people skills: [moving]{
	//rgb color <- #goldenrod;
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
					pollution_level <- pollution_level +1;
					if(pollution_level > pollution_max_level)
					{
						pollution_level <- pollution_max_level;
					}
				}
			}	
		}
	}
}

grid cell height: 100 width: 100 neighbors: 8{
	
	int pollution_level <- 0 ;
	list neighbours of: cell <- (self neighbors_at 1) of_species cell;  

	rgb pollution_color <- rgb(255,255,255);
	float transparency <- 1.0;

	reflex update_color when:heatmap{
		float level2 <-(min([1,max([0,pollution_level/25])]))^(0.5);
		float tmp <- level2*(length(heatmap_color)-1);
		pollution_color <- rgb(heatmap_color[int(tmp)]);
	}
	
	reflex update_transparency when:heatmap {
		transparency <- 1.0 - float(pollution_level) / pollution_max_level;
	}
	
	action raz {
		pollution_level <- 0;
	}
	
	aspect pollution{
		if(heatmap)
		{
			draw shape color:pollution_color;
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
			species building aspect: base refresh: false;
			species road aspect: base refresh: false;
			species cell aspect:pollution transparency: 0.75;
			species people aspect: base;
			
			graphics "time" {
				draw string(current_date.hour) + "h" + string(current_date.minute) +"m" color: # white font: font("Helvetica", 30, #italic) at: {world.shape.width*0.43,world.shape.height*0.93};
			}
			
			event ['h'] action: {heatmap <- !heatmap;}; //heatmap display
			event ['c'] action: {if(heatmap){ask cell{do raz;}}}; // clean heatmap (if heatmap)
		}
	}
}