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
	
	float step_max <- 5 #mn;
	float step_min <- 300 #ms;
	float step <- step_min;
	
	int nb_people <- 500;
	float current_hour <- 0.0;
	int min_work_start <- 7;
	int max_work_start <- 8;
	int min_work_end <- 17; 
	int max_work_end <- 18; 
	float ref_speed <- 200.0 #km / #h;
	graph the_graph;
	
	float destroy <- 0.02;
	int repair_time <- 2;
	

	init{
		create building from: shape_file_buildings with: [type::string(read ("Type"))]{
			if type="commerce"{
				color <- #steelblue;
			}
			if type="gare" or  type="Musee"{
				color <- #goldenrod;
			}
			if type="habitat" {
				color <- #white;
			}
		}

		create road from: shape_file_roads;
		map<road,float> weights_map <- road as_map (each:: (each.destruction_coeff * each.shape.perimeter));
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
		bool time_to_stay <- (current_hour < min_work_start 
			or ((current_hour > max_work_start) and (current_hour < min_work_end))
			or current_hour > max_work_start );
		if(time_to_stay)
		{
			step <- step_max;
		}else {
			step <- step_min;
		}
	}
	
	reflex update_current_hour{
		current_hour <- time / #hour;
	}
	
	reflex update_graph{
		map<road, float> weights_map <- road as_map (each:: (each.destruction_coeff * each.shape.perimeter));
		the_graph <- the_graph with_weights weights_map;
	}
	
	reflex repair_road when: every(repair_time #hour / step){
		road the_road_to_repair <- road with_max_of(each.destruction_coeff);
		ask the_road_to_repair{
			destruction_coeff <- 1.0;
		}
	}
}

species building{
	string type;
	rgb color <- #grey;
	
	aspect base {
		draw shape color: color;
	}
}

species road {
	float destruction_coeff <- 1.0;
	int colorValue <- int(255*(destruction_coeff - 1)) update: int (255 * (destruction_coeff - 1));
	rgb color <- rgb(min([255, colorValue]), max ([0,255 - colorValue]), 0) update: rgb(min([255, colorValue]), max ([0,255 - colorValue]), 0);
	
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
		draw circle(8) color: color;
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
		if(the_target != nil){
			path path_followed <- self goto [target::the_target, on::the_graph, return_path:: true];
			/* 
			list<geometry> segments <- path_followed.segments;
			loop line over: segments{
				float dist <- line.perimeter;
				ask road(path_followed agent_from_geometry line){
					destruction_coeff <- destruction_coeff + (destroy * dist/ shape.perimeter);
				}
			}
			* */
			
			if the_target = location{
				the_target <- nil;
			} else {
				//do updatePollutionMap;
				
			}
			
			do goto target: the_target on: the_graph;
			if the_target = location{
				the_target <- nil;
			}
		}
	}
	
	reflex update_speed{
		speed <- ref_speed;
	}

	
	action updatePollutionMap{
		ask gridHeatmaps overlapping(current_path.shape) {
			pollution_level <- pollution_level + 1;
		}
	}	
}

grid gridHeatmaps height: 50 width: 50 {
	int pollution_level <- 0 ;
	rgb pollution_color <- rgb(255-pollution_level*10,255-pollution_level*10,255-pollution_level*10) update:rgb(255-pollution_level*10,255-pollution_level*10,255-pollution_level*10);
	
	aspect pollution{
		draw shape color:pollution_color;
	}
	/** 	
	reflex raz when: every(24#hour) {
		pollution_level <- 0;
	}
	* 
	*/
}

experiment life type: gui {
	float minimum_cycle_duration <- 1/30;
	parameter "Shapefile for the buildings" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads" var: shape_file_roads category: "GIS";

	parameter "Number of people agents" var: nb_people category: "People";
	
	parameter "Earliest hour to start work" var: min_work_start category: "People" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "People" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "People" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "People" min: 16 max: 23;
	parameter "Car speed" var: ref_speed category: "People" min: 5 #km/#h max: 1000 #km/#h;
	
	parameter "Value of destruction when a people agent takes a road" var: destroy category: "Road" ;
	parameter "Number of steps between two road repairs" var: repair_time category: "Road" ;
	
	output{
		display city_display type: opengl background:#black synchronized:true { //
			species building aspect: base refresh: false;
			species road aspect: base refresh: false;
			species people aspect: base;
			//species gridHeatmaps aspect:pollution;
		}
		
		/** 
		display chart_display { //every(10 #cycle)
			chart "Road Status" type: series size: {1, 0.5} position: {0, 0}{
				data "Mean road destruction" value: mean (road collect each.destruction_coeff) style: line color: #green;
				data "Max road destruction" value: road max_of each.destruction_coeff color: #red;
			}
			
			chart "People Objectif" type: pie style: exploded size: {1, 0.5} position: {0, 0.5} {
				data "Working" value: people count (each.objective = "working") color: #magenta;
				data "Resting" value: people count (each.objective = "resting") color: #blue;
			}
		}
		* */
	}
}