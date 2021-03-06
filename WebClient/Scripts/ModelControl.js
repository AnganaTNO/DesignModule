﻿L.Control.ModelControl = L.Control.extend({
    options: {
        collapsed: true,
        position: 'bottomright',
        autoZIndex: true
    },

    initialize: function (options) {
        L.setOptions(this, options);
        this.rightMargin = '75px';
        this.bottomMargin = '75px';
        this._modelControl = { Div: null };
        this._models = {};
        this._first = true;
        this._showing = false;
        this._lastRefresh = 0;
        this._enabled = false;
    },

    onAdd: function (map) {
        this._initLayout();
        this._map = map;
        this._enabled = true;
        return this._container;
    },

    onRemove: function (map) {
        this._enabled = false;
    },

    _initLayout: function () {
        var className = 'leaflet-control-model',
            container = this._container = L.DomUtil.create('div', className);

        // makes this work on IE touch devices by stopping it from firing a mouseout event when the touch is released
        container.setAttribute('aria-haspopup', true);

        L.DomEvent.disableClickPropagation(container);
        if (!L.Browser.touch) {
            L.DomEvent.disableScrollPropagation(container);
        }

        container.addEventListener("click", this.clickModelControl.bind(this));
        container.addEventListener("touchstart", this.clickModelControl.bind(this));

        var link = this._categoriesLink = L.DomUtil.create('a', className + '-toggle', container);
        link.href = '#';
        link.title = 'Show model control information';
    },

    clickModelControl: function () {
        if (this._showing)
            this.hideModelControl();
        else
            this.showModelControl();
    },

    hideModelControl: function () {
        if (this._modelControl.Div != null)
        {
            this._modelControl.Div.style.display = 'none';
            //reset positioning
            L.DomUtil.setPosition(this._modelControl.Div, 0, 0);
        }
        this._showing = false;
    },

    showModelControl: function () {
        if (!this._enabled)
            return;
        if (this._modelControl.Div == null) {
            var modelDiv = this._modelControl.Div = document.body.appendChild(document.createElement("div"));
            modelDiv.className = 'modelControlDiv';
            modelDiv.style.display = 'block';
            modelDiv.style.right = this.rightMargin;
            modelDiv.style.bottom = this.bottomMargin;
            this._draggable = new L.Draggable(modelDiv);
            this._draggable.enable();
        }
        else {
            if (this._modelControl.Div.style.display == 'none') {
                this._modelControl.Div.style.display = "block";
            }
        }
        this.FillModelControl();
        this._showing = true;
    },


    GetTableRow: function (name, status, progress, id) {
        var tr = document.createElement('tr');
        tr.className = 'modelControlTR';
        tr.id = 'mcTR' + id;

        this.AddTableCell(tr, 'name', name);
        this.AddTableCell(tr, 'status', status);
        this.AddTableCell(tr, 'progress', progress);

        return tr;
    },

    FillModelControl: function () {
        if (!this._modelControl.Div)
            return;
        var modelDiv = this._modelControl.Div;
        modelDiv.innerHTML = ''; //clear all contents

        var div = modelDiv.appendChild(document.createElement('div'));
        div.className = 'modalDialog-close';
        div.innerHTML = '&#x2715;';
        div.onclick = this.ClickCloseCross.bind(this);

        var titleDiv = modelDiv.appendChild(document.createElement('div'));
        titleDiv.style.textAlign = 'center';
        titleDiv.innerHTML = "<strong>ModelControl Info:</strong>";
        titleDiv.className = "mcTitleDiv";
        titleDiv.addEventListener('contextmenu', (function (e) {
            e.preventDefault();
            e.stopPropagation();
            if (performance.now() - 1000 > this._lastRefresh)
            {
                this._lastRefresh = performance.now();
                // todo: NEW MESSAGE FORMAT
                wsSend({ modelControl: {refresh: true}});
            }
        }).bind(this));

        var table = this._modelControl.Table = modelDiv.appendChild(document.createElement('table'));
        table.className = 'modelControlTable';

        this.DisplaySection("Session Models", table);
        var empty = true;
        for (var v1 in this._models) {
            if (this._models[v1].status.toLowerCase() != "idle") {
                empty = false;
                this.DisplayModel(this._models[v1], table);
            }
        }
        if (empty)
            this.DisplayEmpty("-No session models-", table);

        this.DisplaySection("Idle Models", table);
        empty = true;
        for (var v2 in this._models) {
            if (this._models[v2].status.toLowerCase() == "idle") {
                empty = false;
                this.DisplayModel(this._models[v2], table);
            }
        }
        if (empty)
            this.DisplayEmpty("-No idle models-", table);
    },

    AddTableCell: function (row, type, text) {
        var cell = row.appendChild(document.createElement('td'));
        cell.className = 'modelControlTD modelControlTD' + type;

        cell.appendChild(document.createTextNode(text));
    },

    ClickCloseCross: function (e) {
        this._modelControl.Div.style.display = 'none';
        this._showing = false;
    },

    AddModel: function (model) {
        if (typeof this._models[model.id] !== "undefined") {
            this.UpdateModel(model);
        }
        else if (model.status.toLowerCase() != "idle" || true) {
            this._models[model.id] = model;
            this.FillModelControl();
            if (this._first) {
                this._first = false;
                this.showModelControl();
            }
        }
    },

    DisplayModel: function (model, table) {
        if (this._modelControl) {
            model.htmlRow = this.GetTableRow(model.name, model.status, model.progress, model.id);
            table.appendChild(model.htmlRow);
        }
    },

    DisplaySection: function (section, table) {
        if (this._modelControl) {
            var tr = table.appendChild(document.createElement("tr"));
            tr.className = "modelControlTR modelControlSectionTR";
            var td = tr.appendChild(document.createElement("td"));
            td.className = "modelControlTD modelControlSectionTD";
            td.colSpan = 4;
            td.appendChild(document.createTextNode(section));
        }
    },

    DisplayEmpty: function (empty, table) {
        if (this._modelControl) {
            var tr = table.appendChild(document.createElement("tr"));
            tr.className = "modelControlTR modelControlEmptyTR";
            var td = tr.appendChild(document.createElement("td"));
            td.className = "modelControlTD modelControlEmptyTD";
            td.colSpan = 4;
            td.appendChild(document.createTextNode(empty));
        }
    },

    RemoveModel: function (modelid) {
        if (typeof this._models[modelid] === 'undefined')
            return;

        delete this._models[modelid];

        this.FillModelControl();
    },

    HandleMessages: function (payload) {
        if (typeof payload.status !== "undefined") {
            for (var i = 0; i < payload.status.length; i++) {
                if (typeof payload.status[i].new !== "undefined")
                    this.AddModel(payload.status[i].new);
                else if (typeof payload.status[i].change !== "undefined")
                    this.UpdateModel(payload.status[i].change);
                else if (typeof payload.status[i].delete !== "undefined")
                    this.RemoveModel(payload.status[i].delete.id);
                else if (typeof payload.status[i].reset !== "undefined")
                    this.ClearModelControl();
            }
            if (payload.status.length > 0)
                this.FillModelControl();
        }
    },

    UpdateModel: function (payload) {
        if (typeof this._models[payload.id] !== 'undefined') {
            var model = this._models[payload.id];

            if (typeof payload.name !== 'undefined') {
                model.name = payload.name;
                if (model.htmlRow) {
                    model.htmlRow.children[0].innerText = model.name;
                }
            }

            if (typeof payload.status !== "undefined") {
                model.status = payload.status;
                if (model.htmlRow)
                    model.htmlRow.children[1].innerText = model.status;
            }

            if (typeof payload.progress !== "undefined") {
                model.progress = payload.progress;
                if (model.htmlRow)
                    model.htmlRow.children[2].innerText = model.progress;
            }
        }
    },

    ClearModelControl: function () {
        this._models = {};
    },
});

L.control.ModelControl = function (categories, options) {
    return new L.Control.ModelControl(categories, options);
};