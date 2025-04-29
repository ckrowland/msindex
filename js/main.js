var maxQButton = document.getElementById('maxQButton');
var maxButton = document.getElementById('maxButton');
var tenYearButton = document.getElementById('tenYearButton');
var fiveYearButton = document.getElementById('fiveYearButton');
var oneYearButton = document.getElementById('oneYearButton');

makeGraph("oneYear");
makeGraph("fiveYear");
makeGraph("tenYear");
makeGraph("max", true);
makeGraph("max");

maxQButton.addEventListener('click', openGraph);
maxButton.addEventListener('click', openGraph);
tenYearButton.addEventListener('click', openGraph);
fiveYearButton.addEventListener('click', openGraph);
oneYearButton.addEventListener('click', openGraph);

document.getElementById("maxButton").click();

function openGraph(evt) {
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
  let name = evt.currentTarget.id;
  let chartName = name.substring(0, name.length - 6);

  document.getElementById(chartName).style.display = "block";
}

function makeGraph(graphName, quartiles = false){
	var width = 500;
	var height = 380;
	var padding = 30;
	var margin = {top: 20, right: 30, bottom: 30, left: 25};
	var filename = "./json/" + graphName + ".json";
	var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

	d3.json(filename).then(function(rawData) {
        const data = rawData.map(({ date, ...object }) => ({
            ...object,
            date: new Date(date + " 00:00:00"),
        }));
		var options = {year:'numeric', month:'long', day:'numeric'};
        var lastDate = data[data.length - 1].date;
		var lastDateStr = lastDate.toLocaleDateString("en-US", options);
		var lastvalue = (data[data.length - 1].index).toFixed(2);
		var weekday = lastDate.getDay();

		var update = "On " + days[weekday] + " " + lastDateStr + " the MS Index was at " + lastvalue;
		d3.select("#currentindex").text(update)

		var x = d3.scaleUtc()
			.domain(d3.extent(data, d => d.date))
			.range([margin.left, width - margin.right])

		var y = d3.scaleLinear()
			.domain([0, d3.max(data, d => d.index)]).nice()
			.range([height - margin.bottom, margin.top])

		var xAxis = g => g
			.attr("transform", `translate(0,${height - margin.bottom})`)
			.call(d3.axisBottom(x).ticks(width / 90).tickSizeOuter(0))


		var yAxis = g => g
		.attr("transform", `translate(${margin.left},0)`)
		.call(d3.axisLeft(y))
		.call(g => g.select(".domain").remove())
		.call(g => g.select(".tick:last-of-type text").clone()
			.text(data.y))

		var line = d3.line()
			.x(function(d) { return x(d.date); })
			.y(function(d) { return y(d.index); });

		var graphId = "#".concat(graphName);
        if (quartiles) {
            graphId = graphId.concat("Q");
        }
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

        if (quartiles) {
		    const points = Array.from(data, x => x.index);
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
		          .attr("class", "quartile")
		          .attr("x1", 30)
		          .attr("y1", y(x))
		          .attr("x2", 475)
		          .attr("y2", y(x));
		    });
        }
  });
}

