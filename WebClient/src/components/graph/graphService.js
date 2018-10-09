/**
 * Graph service. Provides graph models to the application.
 * Responsible for retrieving graphs from server side and 
 * maintaining them in sync with the server.
 */

/* globals L, d3 */

import './graphModel';
import ModelCollection from '../../core/modelCollection';
import GraphModel from './graphModel';

function convertChartToGraphModel(chart) {
    if (!chart) throw new Error('chart is not provided');
    if (!chart.data) throw new Error('chart.data is not provided');
    if (!Array.isArray(chart.data.columns)) throw new Error('chart.data.columns is not an array');

	var color = d3.scaleOrdinal(d3.schemeCategory10);

	var axes = {
		yLeft: {
			formatSpecifier: ',.1f'
		},
		xBottom: {
			title: chart.data.x || ''
		}
	};
	
	var columns = chart.data.columns;
	
	var categories = columns[0].slice(1).map(function(category) {
		return {
			id: '' + category,
			title: '' + category
		};
	});
	
	var series = columns.slice(1).map(function(row) {
        if (!Array.isArray(row)) return null;

		var data = row.slice(1).map(function(item, i) {
			return {
				categoryId: categories[i].id,
				y: item,
				axisId: 'yLeft'			
			};
		});
		var rowName = row[0];
		
		return {
			type: chart.type,
			id: rowName,
			title: rowName,
			color: color(rowName),
			data: data
		};
    });	
    series = series.filter(function (item) { return !!item; });
	
	return new GraphModel({
		type: 'category',
		id: chart.id,
		title: chart.title,
		axes: axes,
		categories: categories,
		series: series,
	});
}

var GraphService = L.Evented.extend({

    initialize: function () {
        this._graphsModel = new ModelCollection();
        
        Object.defineProperty(this, 'graphsModel', {
            get: function () { return this._graphsModel; }
        });
    },

    setGraphs: function (graphs) {
        if (!graphs) return;

        var originalGraphs = Array.isArray(graphs) ? graphs : [graphs];

        try {
            var graphModels = originalGraphs.map(convertChartToGraphModel);
            this.graphsModel.set(graphModels);
        } catch (error) {
            console.error('Failed to set graphs because graphs data is incorrect.', error);
        }
    },

    updateGraphs: function (graphs) {
        if (!graphs) return;
        
        var originalGraphs = Array.isArray(graphs) ? graphs : [graphs];
        var graphsModel = this.graphsModel;

        try {
            var graphModels = originalGraphs.map(convertChartToGraphModel);
            graphModels.forEach(function (newGraphModel) {
                var graphModel = graphsModel.getById(newGraphModel.id);
                if (!graphModel) return;

                graphModel.title = newGraphModel.title;
                graphModel.axes = newGraphModel.axes;
                graphModel.categories = newGraphModel.categories;
                graphModel.series = newGraphModel.series;
            });
        } catch (error) {
            console.error('Failed to update graphs because graphs data is incorrect.', error);
        }
    }

});

export default GraphService;
