/***
* Name: roadtraffic
* Author: evage
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model confluence

/* Insert your model definition here */
global{
	//list<list<float>> heat_map <- [[30,146,254],[86,149,242],[144,201,254],[180,231,252],[223,255,216],[254,255,113],[248,209,69],[243,129,40],[235,46,26],[109,23,8]];
	file shape_file_buildings <- file("../includes/Bati_reclass_CC46.shp");
	file shape_file_roads <- file("../includes/ROUTESCC46.shp");
	geometry shape <- envelope(shape_file_buildings);
	
	float step_max <- 40 #mn;
	float step_min <- 8 #s;
	
	float step <- step_min;
	
	int nb_people <- 800;
	float current_hour <- 0.0;
	int min_work_start <- 8;
	int max_work_start <- 12;
	int min_work_end <- 16; 
	int max_work_end <- 18; 
	
	float ref_speed <- 2.0 #km / #h;
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
				//color <- #white;
				color <- #grey;
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
			or ((current_hour > max_work_start + 2) and (current_hour < min_work_end - 2))
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
		if(current_hour > 24)
		{
			current_hour <- 0.0;
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
	//rgb color <- #grey;
	rgb color <- #black;
	
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
		do updatePollutionMap;
		
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
		} else {
			
			
		}
		
		do goto target: the_target on: the_graph;
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
			list<gridHeatmaps> tmp <- gridHeatmaps overlapping(current_path.shape);
		
			if(tmp != nil and tmp != []){
				
				ask tmp {
					pollution_level <- pollution_level + 10;
				}
			}	
		}
	}
}

grid gridHeatmaps height: 50 width: 50 {
	int pollution_level <- 0 ;
	rgb pollution_color <- rgb(255-pollution_level*10,255-pollution_level*10,255-pollution_level*10) update:rgb(255-pollution_level*10,255-pollution_level*10,255-pollution_level*10);
	
	aspect pollution{
		draw shape color:pollution_color;
	}
}

/*
grid cell width: 100 height: 50 {
	float level <- 0.0;
	list neighbours of: cell <- (self neighbors_at 1) of_species cell;  
	rgb color <- rgb(rnd(255),rnd(255),rnd(255));   
	
	reflex update_color when:heatmap{
		float level2 <-(min([1,max([0,level/25])]))^(0.5);
		float tmp <- level2*(length(heat_map)-1);
		color <- rgb(heat_map[int(tmp)]);
	}
	
	aspect default{
		if(heatmap){
		  draw shape color:color;	
		}
	}
}
 */

experiment life type: gui {
	float minimum_cycle_duration <- 1/30;
	
	parameter "Car speed" var: ref_speed category: "Runtime settings" min: 5 #km/#h max: 1000 #km/#h;
	parameter "Step working/resting hour" var: step_max category: "Runtime settings" min: 1#mn max: 20#mn;
	parameter "Step moving hour" var: step_min category: "Runtime settings";
	
	parameter "Shapefile for the buildings" var: shape_file_buildings category: "GIS";
	parameter "Shapefile for the roads" var: shape_file_roads category: "GIS";

	parameter "Number of people agents" var: nb_people category: "People";
	
	parameter "Earliest hour to start work" var: min_work_start category: "People" min: 2 max: 8;
	parameter "Latest hour to start work" var: max_work_start category: "People" min: 8 max: 12;
	parameter "Earliest hour to end work" var: min_work_end category: "People" min: 12 max: 16;
	parameter "Latest hour to end work" var: max_work_end category: "People" min: 16 max: 23;
	
	
	parameter "Value of destruction when a people agent takes a road" var: destroy category: "Road" ;
	parameter "Number of steps between two road repairs" var: repair_time category: "Road" ;
	
	output{
		display city_display type: opengl background:rgb(cycle mod 256, cycle mod 256, cycle mod 256) synchronized:true 
			camera_pos: {1473.4207,1609.8385,2114.0265} camera_look_pos: {1409.429,1572.8928,-0.883} camera_up_vector: {-0.8655,0.4997,0.0349}
		{
			species gridHeatmaps aspect:pollution;
			species building aspect: base refresh: false;
			species road aspect: base refresh: false;
			species people aspect: base;
			//species cell transparency: 0.5;// lines: #white 
			
		}
	}
}