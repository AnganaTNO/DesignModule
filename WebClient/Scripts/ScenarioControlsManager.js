﻿var ScenarioControlsManager = {
    activeScenarioControls: {},
    allControls: {},
    controlChanges: {},

    handleMessage: function (payload) {
        if (typeof payload.allControls !== "undefined")
            this.allControls = payload.allControls;
        if (typeof payload.scenarioControls !== "undefined")
            this.activeScenarioControls = payload.scenarioControls;
    },

    showScenarios: function (options) {
        createRequestDialog("Scenarios", "control statuses for all scenarios", "controls", this.buildScenariosTableCallback);
    },

    buildScenariosTableCallback: function (div, data) {
        var table = div.appendChild(document.createElement('table'));
        table.id = "scenarioControlsTable";

        var head = table.appendChild(document.createElement('thead'));
        var tr = head.appendChild(document.createElement('tr'));

        var th = tr.appendChild(document.createElement('th'));

        for (var key in data.scenarios) {
            var scenario = data.scenarios[key];
            th = tr.appendChild(document.createElement('th'));
            th.id = "scenarioTableHeader" + i;
            th.className = "clickableHeader";
            th.scenario = scenario;
            //if (this.scenarios[i].id == this.activeScenarioId)
            //    th.className = "thActive";
            var thText = th.appendChild(document.createElement('span'));
            thText.innerHTML = scenario.name;
            th.addEventListener("click", function (e) {
                this.activeScenarioId = e.currentTarget.scenario.id;
                modalDialogClose();
            }.bind(this));
        }

        var body = table.appendChild(document.createElement('tbody'));
        for (key in data.controls) {
            var control = data.controls[key];
            tr = body.appendChild(document.createElement('tr'));
            td = tr.appendChild(document.createElement('td'));
            td.className = "scenarioTableControlText";
            var tdText = td.appendChild(document.createElement('span'));
            tdText.innerHTML = control.name;
            var j = 0; //index
            for (s in data.scenarios) {
                var scenario = data.scenarios[s];
                td = tr.appendChild(document.createElement('td'));
                td.headers = "scenarioTableHeader" + j;
                j++;
                var input = td.appendChild(document.createElement('input'));
                input.setAttribute("type", "checkbox");
                input.className = "scenarioTableInput";
                input.checked = typeof scenario.controls[key] !== "undefined" && scenario.controls[key].active == 1; //todo: make it so undefined = not availale, false = not checked and true is checked!
                input.control = control;
                input.scenario = scenario;
                input.disabled = true;
            }
        }
    },

    showScenario: function (id) {
        var div = modalDialogCreate('Scenario Management', 'Planning');
        div.style.width = '800px';
        div.style.margin = '5% auto';

        this.controlChanges = {};

        this.buildScenarioTable(div, this.activeScenarioControls);

        var mddb = div.appendChild(document.createElement('div'));
        mddb.className = 'modalDialogDevideButtons';
        var _this = this;
        modelDialogAddButton(mddb, 'Close', modalDialogClose); //maybe add popup for unsaved changes in the future?
        modelDialogAddButton(mddb, 'Apply', (function () {
            this.applyControlsChanges();
            modalDialogClose();
        }).bind(this));
    },

    applyControlsChanges: function () {
        if (this.controlChanges.length == 0)
            return; //no changes

        var payload = [];
        for (var key in this.controlChanges)
            if (this.activeScenarioControls[key] !== "undefined" && this.activeScenarioControls.active != this.controlChanges[key].active)
            {
                this.activeScenarioControls[key].active = this.controlChanges[key].active;
            }

        for (var key in this.activeScenarioControls)
        {
            payload.push({ id: key, active: this.activeScenarioControls[key].active });
        }
        var message = { type: "scenarioControlsChanges", payload: payload };
        wsSend(message);
    },

    buildScenarioTable: function (div, controls) {
        var table = div.appendChild(document.createElement('table'));
        table.id = "scenarioControlsTable";

        var head = table.appendChild(document.createElement('thead'));
        var tr = head.appendChild(document.createElement('tr'));

        var th = tr.appendChild(document.createElement('th'));

        th = tr.appendChild(document.createElement('th'));
        th.scenario = scenario;
        //if (this.scenarios[i].id == this.activeScenarioId)
        //    th.className = "thActive";
        var thText = th.appendChild(document.createElement('span'));
        thText.innerHTML = "Active";

        var body = table.appendChild(document.createElement('tbody'));
        for (key in controls) {
            var control = controls[key];
            tr = body.appendChild(document.createElement('tr'));
            td = tr.appendChild(document.createElement('td'));
            td.className = "scenarioTableControlText";
            var tdText = td.appendChild(document.createElement('span'));
            tdText.innerHTML = typeof this.allControls[key] === "undefined" ? "" : this.allControls[key].name;
            td = tr.appendChild(document.createElement('td'));
            var input = td.appendChild(document.createElement('input'));
            input.setAttribute("type", "checkbox");
            input.className = "scenarioTableInput";
            input.checked = control.active == 1;
            input.control = control;
            input.id = key;
            var controlChanges = this.controlChanges;
            input.addEventListener("click", function (e) {
                var input = e.currentTarget;
                if (input.checked) {
                    controlChanges[input.id] = { active: 1};
                }
                else {
                    controlChanges[input.id] = { active: 0};
                }
            });
        }
    }


};