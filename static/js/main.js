makeGraph("oneyear");
makeGraph("fiveyear");
makeGraph("tenyear");
makeGraph("max");

function makeGraph(graphName){
	var width = 500;
	var height = 380;
	var padding = 30;
	var margin = {top: 20, right: 30, bottom: 30, left: 25};
	var filename = "./csv/" + graphName + ".csv";
	var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

	d3.csv(filename, function(d) {
		return {
			date: new Date(d.date + " 00:00:00"),
			value: +d.value
		};
	}).then(function(data) {
		var options = {year:'numeric', month:'long', day:'numeric'};
		var lastdate = data[data.length - 1].date.toLocaleDateString("en-US", options);
		var lastvalue = (data[data.length - 1].value).toFixed(2);
		var weekday = data[data.length - 1].date.getDay();

		var update = "On " + days[weekday] + " " + lastdate + " the MS Index was at " + lastvalue;
		d3.select("#currentindex").text(update)

		x = d3.scaleUtc()
			.domain(d3.extent(data, d => d.date))
			.range([margin.left, width - margin.right])

		y = d3.scaleLinear()
			.domain([0, d3.max(data, d => d.value)]).nice()
			.range([height - margin.bottom, margin.top])

		xAxis = g => g
			.attr("transform", `translate(0,${height - margin.bottom})`)
			.call(d3.axisBottom(x).ticks(width / 90).tickSizeOuter(0))


		yAxis = g => g
		.attr("transform", `translate(${margin.left},0)`)
		.call(d3.axisLeft(y))
		.call(g => g.select(".domain").remove())
		.call(g => g.select(".tick:last-of-type text").clone()
			.text(data.y))

		line = d3.line()
			.x(function(d) { return x(d.date); })
			.y(function(d) { return y(d.value); });

		var graphId = "#".concat(graphName);
		var svg = d3.select(graphId)
			.append("svg")
			.attr("viewBox", [0, 0, width, height])
			.attr("id", "chart");

		svg.append("g")
		  .call(xAxis);

		svg.append("g")
		  .call(yAxis);


		svg.append("path")
		  .datum(data)
		  .attr("fill", "none")
		  .attr("stroke", "steelblue")
		  .attr("stroke-width", 1.5)
		  .attr("stroke-linejoin", "round")
		  .attr("stroke-linecap", "round")
		  .attr("d", line);

		const points = Array.from(data, x => x.value);
		const asc = arr => arr.sort((a, b) => a - b);
		const sum = arr => arr.reduce((a, b) => a + b, 0);
		const mean = arr => sum(arr) / arr.length;
		const quantile = (arr, q) => {
		    const sorted = asc(arr);
		    const pos = (sorted.length - 1) * q;
		    const base = Math.floor(pos);
		    const rest = pos - base;
		    if (sorted[base + 1] !== undefined) {
			return sorted[base] + rest * (sorted[base + 1] - sorted[base]);
		    } else {
			return sorted[base];
		    }
		};

		const q25 = arr => quantile(arr, .25);
		const q50 = arr => quantile(arr, .50);
		const q75 = arr => quantile(arr, .75);
		const quartiles = [q25(points), q50(points), q75(points)]
		quartiles.forEach(function (x, index) {
		    svg.append("line")
		      .style("stroke", "grey")
		      .style("display", "none")
		      .attr("class", "quartile")
		      .attr("x1", 30)
		      .attr("y1", y(x))
		      .attr("x2", 475)
		      .attr("y2", y(x));
		});

  });
}

function openGraph(evt, graphName, quartiles = false) {
  // Declare all variables
  var i, tabcontent, tablinks;

  // Get all elements with class="tabcontent" and hide them
  tabcontent = document.getElementsByClassName("tabcontent");
  for (i = 0; i < tabcontent.length; i++) {
    tabcontent[i].style.display = "none";
  }

  // Get all elements with class="tablinks" and remove the class "active"
  tablinks = document.getElementsByClassName("tablinks");
  for (i = 0; i < tablinks.length; i++) {
    tablinks[i].className = tablinks[i].className.replace(" active", "");
  }

  // Show the current tab, and add an "active" class to the button that opened the tab
  document.getElementById(graphName).style.display = "block";

  const all_quartiles = document.getElementById(graphName).getElementsByClassName("quartile");
  for (let i = 0; i < all_quartiles.length; i++){
    all_quartiles[i].style.display = "none";
  }
  if (quartiles) {
    const all_quartiles = document.getElementById(graphName).getElementsByClassName("quartile");
    if (all_quartiles[0].style.display === "none") {
      for (let i = 0; i < all_quartiles.length; i++){
        all_quartiles[i].style.display = "block";
      }
    }
  }
  evt.currentTarget.className += " active";
}
