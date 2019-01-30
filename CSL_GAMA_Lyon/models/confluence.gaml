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
	
	float step <- 2 #mn;
	
	int nb_car <- 1000;
	int current_hour update: (time / #hour) mod 24;
	
	int min_work_start <- 6;
	int max_work_start <- 9;
	int min_work_end <- 16; 
	int max_work_end <- 20; 
	float min_speed <- 20.0 #km / #h;
	float max_speed <- 50.0 #km / #h; 
	graph the_graph;
	
	float destroy <- 0.02;
	int repair_time <- 2;
	

	init{
		create building from: shape_file_buildings with: [type::string(read ("Type"))]{
			if type="commerce" or  type="Musee"{
				color <- #steelblue;
			}
			if type="habitat" {
				color <- #white;
			}
		}

		create road from: shape_file_roads;
		map<road,float> weights_map <- road as_map (each:: (each.destruction_coeff * each.shape.perimeter));
      	the_graph <- as_edge_graph(road) with_weights weights_map;
		
		list<building> residential_buildings <- building where (each.type="habitat");
      	list<building>  industrial_buildings <- building  where (each.type="commerce" or each.type="Musee") ;
		
		create car number: nb_car{
			speed <- min_speed + rnd (max_speed - min_speed) ;
      		start_work <- min_work_start + rnd (max_work_start - min_work_start) ;
          	end_work <- min_work_end + rnd (max_work_end - min_work_end) ;
          	living_place <- one_of(residential_buildings) ;
          	working_place <- one_of(industrial_buildings) ;
          	objective <- "resting";
          	location <- any_location_in (living_place);
		}
		
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

species car skills: [moving]{
	//rgb color <- #goldenrod;
	rgb color <- #red;
	building living_place <- nil;
	building working_place <- nil;
	int start_work;
	int end_work;
	
	string objective;
	point the_target <- nil;
	
	aspect base{
		draw circle(5) color: color;
	}
	
	reflex time_to_work when: current_hour = start_work and objective = "resting"{
   		objective <- "working";
   		the_target <- any_location_in (working_place);
  	}
      
	reflex time_to_go_home when: current_hour = end_work and objective = "working"{
		objective <- "resting";
		the_target <- any_location_in (living_place);
	}
	
	reflex move when: the_target != nil{
		path path_followed <- self goto [target::the_target, on::the_graph, return_path:: true];
		list<geometry> segments <- path_followed.segments;
		loop line over: segments{
			float dist <- line.perimeter;
			ask road(path_followed agent_from_geometry line){
				destruction_coeff <- destruction_coeff + (destroy * dist/ shape.perimeter);
			}
		}
		if the_target = location{
			the_target <- nil;
		}
		
		do goto target: the_target on: the_graph;
		if the_target = location{
			the_target <- nil;
		} else {
			//do updatePollutionMap;				
		}
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

experiment road_traffic type: gui{
	parameter "Shapefile for the buildings" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads" var: shape_file_roads category: "GIS";

	parameter "Number of car agents" var: nb_car category: "Car";
	
	parameter "Earliest hour to start work" var: min_work_start category: "Car" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "Car" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "Car" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "Car" min: 16 max: 23;
	parameter "Minimal speed" var: min_speed category: "Car" min: 0.1 #km/#h ;
	parameter "Maximal speed" var: max_speed category: "Car" max: 50 #km/#h;
	
	parameter "Value of destruction when a people agent takes a road" var: destroy category: "Road" ;
	parameter "Number of steps between two road repairs" var: repair_time category: "Road" ;
	
	output{
		display city_display type: opengl background:#black refresh: every(1#s){
			species building aspect: base;
			species road aspect: base;
			species car aspect: base;
			//species gridHeatmaps aspect:pollution;
		}
		
		display chart_display { //every(10 #cycle)
			chart "Road Status" type: series size: {1, 0.5} position: {0, 0}{
				data "Mean road destruction" value: mean (road collect each.destruction_coeff) style: line color: #green;
				data "Max road destruction" value: road max_of each.destruction_coeff color: #red;
			}
			
			chart "People Objectif" type: pie style: exploded size: {1, 0.5} position: {0, 0.5} {
				data "Working" value: car count (each.objective = "working") color: #magenta;
				data "Resting" value: car count (each.objective = "resting") color: #blue;
			}
		}
	}
}