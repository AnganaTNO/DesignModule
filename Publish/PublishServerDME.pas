unit PublishServerDME;

interface

uses
  Logger,
  StdIni,

  Ora,
  OraObjects,
  Data.DB,
  OraSmart,
  MyOraLib,
  MyStr,

  ODBFiles2,

  WorldDataCode,
  WorldLegends,

  IMB3NativeClient,

  imb4,
  WorldTilerConsts,
  CommandQueue,
  TimerPool,

  ModelControllerLib,

  NDWLib,

  System.JSON,
  System.SysUtils,

  PublishServerLib,
  PublishServerGIS,
  PublishServerUS,
  PublishServerMCLib;

const
  //hardcoded bounding box zones for the Park & Shuttle measure
  xMin = '119000';
  xMax = '120600';
  yMin = '482500';
  yMax = '484200';
  targetZone = '719';

type
  TUSDesignProject = class(TUSProject)
  constructor Create(aSessionModel: TSessionModel; aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
    aDBConnection: TCustomConnection; aMapView: TMapView; aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer; aStartScenario: string);
  destructor Destroy; override;
  private
    fUSIMBConnection: TIMBConnection;
  public
    procedure ReadBasicData(); override;
    procedure handleClientMessage(aClient: TClient; aScenario: TScenario; aJSONObject: TJSONObject); override;
  end;

  TUSMonitorProject = class(TUSProject)
  constructor Create(aSessionModel: TSessionModel; aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
    aDBConnection: TCustomConnection; aMapView: TMapView; aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer; aStartScenario: string{; aSourceEPSG: Integer});
  destructor Destroy; override;
  public
    procedure ReadBasicData(); override;
  end;

  TUSEvaluateProject = class(TUSProject)
  constructor Create(aSessionModel: TSessionModel; aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
    aDBConnection: TCustomConnection; aMapView: TMapView; aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer; aStartScenario: string{; aSourceEPSG: Integer});
  destructor Destroy; override;
  public
    procedure ReadBasicData(); override;
  end;

  TUSDesignScenario = class(TUSScenario)
  public
    function HandleClientSubscribe(aClient: TClient): Boolean; override;
    function HandleClientUnsubscribe(aClient: TClient): Boolean; override;
  end;

implementation

{ TUSDesignProject }

constructor TUSDesignProject.Create(aSessionModel: TSessionModel;
  aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID,
  aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
  aDBConnection: TCustomConnection; aMapView: TMapView;
  aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer; aStartScenario: string);
begin
  inherited Create(aSessionModel, aConnection, aIMB3Connection, aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource, aDBConnection, aMapView, aPreLoadScenarios, True, aMaxNearestObjectDistanceInMeters);
  fProjectCurrentScenario := ReadScenario(aStartScenario);
  fUSIMBConnection := TIMBConnection.Create(
      GetSetting('IMB3RemoteHost', 'vps17642.public.cloudvps.com'),
      GetSetting('IMB3RemotePort', 4000),
      'PublisherDME-Design', 21, '');
  EnableControl(selectControl);
  EnableControl(measuresControl);
  EnableControl(measuresHistoryControl);
  EnableControl(modelControl);
end;

destructor TUSDesignProject.Destroy;
begin
  inherited;
end;

procedure TUSDesignProject.handleClientMessage(aClient: TClient;
  aScenario: TScenario; aJSONObject: TJSONObject);
var
  oraSession: TOraSession;
  measure: TMeasureAction;
  jsonMeasures: TJSONArray;
  jsonMeasure, jsonAction: TJSONValue;
  id: string;
  objectID: Integer;
  jsonObjectIDs: TJSONArray;
  jsonObjectID: TJSONValue;
  measureFactor: Double;
  factorString, inverseString: string;
  queryText1, queryText2, table1, table2: string;
  table, queryText, value: string;
  publishEventName: string;
  publishEvent: TIMBEventEntry;
begin
  inherited;
  oraSession := fDBConnection as TOraSession;
  if Assigned(aScenario) and (aScenario is TUSScenario) then
  begin
    if aJSONObject.TryGetValue<TJSONArray>('applyMeasures', jsonMeasures) then
      for jsonMeasure in jsonMeasures do
        if jsonMeasure.TryGetValue<TJSONValue>('measure', jsonAction) then
          if jsonAction.TryGetValue<string>('id', id) then
            if FindMeasure(id, measure) then
            begin
              if measure.actionID < 0 then
              begin
                if measure.actionID >= -3 then
                begin
                  measureFactor := 1;
                  case measure.actionID of
                    -1: measureFactor := 0.98; //2%
                    -2: measureFactor := 0.95; //5%
                    -3: measureFactor := 0.90; //10%
                  end;

                  table1 := (aScenario as TUSScenario).Tableprefix + 'TRAF_OD';
                  table2 := (aScenario as TUSScenario).Tableprefix + 'TRAF_ZONE';
                  factorString := (FloatToStr(measureFactor)).Replace(',', '.');
                  inverseString := (FloatToStr(1 - measureFactor)).Replace(',', '.');

                  queryText1 := 'update ' + table1 + ' t1' +
                    ' set' +
                    ' t1.CAR_TRIPS = t1.CAR_TRIPS +' +
                    ' (' + inverseString + ' * (select coalesce (sum(CAR_TRIPS), 0) FROM' +
                    ' (select FROM_ZONE, TO_ZONE, CAR_TRIPS, X_CENTROID, Y_CENTROID FROM (' + table1 + ' t_od inner join ' + table2 + ' t_zone on t_od.TO_ZONE = t_zone.OBJECT_ID)' +
                    ' where t_od.FROM_ZONE = t1.FROM_ZONE and t_od.TO_ZONE <> '+ targetZone + ') t2' +
                    ' where (t2.X_CENTROID between ' + xMin + ' and ' + xMax + ') and (t2.Y_CENTROID between ' + yMin + ' and ' + yMax + ')' +
                    '))' +
                    ' where' +
                    ' t1.TO_ZONE = ' + targetZone;

                  queryText2 := 'update ' + table1 + ' t1' +
                    ' set' +
                    ' t1.CAR_TRIPS = t1.CAR_TRIPS * ' + factorString +
                    ' where' +
                    ' t1.FROM_ZONE <> ' + targetZone + ' and t1.TO_ZONE <> ' + targetZone + 'and t1.TO_ZONE in' +
                    ' (select TO_ZONE from ' + table1 + ' t_od inner join ' + table2 + ' t_zone on t_od.TO_ZONE = t_zone.OBJECT_ID' +
                    ' where' +
                    ' t_zone.X_CENTROID between ' + xMin + ' and ' + xMax + ' and t_zone.Y_CENTROID between ' + yMin + ' and ' + yMax + ')';

                  oraSession.StartTransaction;
                  try
                    oraSession.ExecSQL(queryText1);
                    oraSession.ExecSQL(queryText2);
                    oraSession.Commit;

                    publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.TRAF_OD';
                    publishEvent := fUSIMBConnection.publish(publishEventName, false);
                    publishEvent.SignalChangeObject(actionChange, 0, 'CAR_TRIPS'); //todo: send object id = 0 in case of everything?
                    publishEvent.UnPublish;
                  except
                    oraSession.Rollback;
                    //todo: logging transaction failed
                  end;
                end
                else if (measure.ActionID >= -12) and (measure.ActionID <= -11) then
                begin
                  table := (aScenario as TUSScenario).Tableprefix + 'GENE_ROAD';
                  case measure.ActionID of
                    -11: value := '1';
                    -12: value := '0';
                  end;
                  queryText := 'update ' + table +
                    ' set' +
                    ' STATUS_L  = ' + value + ', STATUS_R = ' + value +
                    ' where OBJECT_ID = :A';
                  if jsonMeasure.TryGetValue<TJSONArray>('selectedObjects', jsonObjectIDs) then
                  begin
                    publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.GENE_ROAD';
                    publishEvent := fUSIMBConnection.publish(publishEventName, false);
                    try
                      for jsonObjectID in jsonObjectIDs do
                      begin
                        if TryStrToInt(jsonObjectID.Value, objectID) then
                        begin
                          //check if this road exists
                          if aScenario.Layers.ContainsKey('road') and aScenario.Layers['road'].objects.ContainsKey(AnsiString(objectID.ToString)) then
                          begin
                            oraSession.ExecSQL(queryText, [objectID]);
                            oraSession.Commit;
                            publishEvent.SignalChangeObject(actionChange, objectID, 'STATUS_L');
                            publishEvent.SignalChangeObject(actionChange, objectID, 'STATUS_R');
                          end;
                        end;
                      end;
                    finally
                      publishEvent.UnPublish;
                    end;
                  end;
                end
                else if (measure.ActionID >= -22) and (measure.ActionID <= -21) then
                begin
                  table := (aScenario as TUSScenario).Tableprefix + 'GENE_ROAD';
                  case measure.ActionID of
                    -21: value := '0.5';
                    -22: value := '2';
                  end;
                  queryText := 'update ' + table +
                    ' set' +
                    ' CAPACITY_L  = CAPACITY_L * ' + value + ', CAPACITY_R = CAPACITY_R * ' + value +
                    ' where OBJECT_ID = :A';
                  if jsonMeasure.TryGetValue<TJSONArray>('selectedObjects', jsonObjectIDs) then
                  begin
                    publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.GENE_ROAD';
                    publishEvent := fUSIMBConnection.publish(publishEventName, false);
                    try
                      for jsonObjectID in jsonObjectIDs do
                      begin
                        if TryStrToInt(jsonObjectID.Value, objectID) then
                        begin
                          //check if this road exists
                          if aScenario.Layers.ContainsKey('road') and aScenario.Layers['road'].objects.ContainsKey(AnsiString(objectID.ToString)) then
                          begin
                            oraSession.ExecSQL(queryText, [objectID]);
                            oraSession.Commit;
                            publishEvent.SignalChangeObject(actionChange, objectID, 'CAPACITY_L');
                            publishEvent.SignalChangeObject(actionChange, objectID, 'CAPACITY_R');
                          end;
                        end;
                      end;
                    finally
                      publishEvent.UnPublish;
                    end;
                  end;
                end
                else if (measure.ActionID >= -35) and (measure.ActionID <= -31) then
                begin
                  table := (aScenario as TUSScenario).Tableprefix + 'GENE_ROAD';
                  case measure.ActionID of
                    -31: value := '30';
                    -32: value := '50';
                    -33: value := '80';
                    -34: value := '100';
                    -35: value := '120';
                  end;
                  queryText := 'update ' + table +
                    ' set' +
                    ' SPEED_L = (SPEED_L * 0) + ' + value + ', SPEED_R = (SPEED_R * 0) + ' + value + //preserves null values!
                    ' where OBJECT_ID = :A';
                  if jsonMeasure.TryGetValue<TJSONArray>('selectedObjects', jsonObjectIDs) then
                  begin
                    publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.GENE_ROAD';
                    publishEvent := fUSIMBConnection.publish(publishEventName, false);
                    try
                      for jsonObjectID in jsonObjectIDs do
                      begin
                        if TryStrToInt(jsonObjectID.Value, objectID) then
                        begin
                          //check if this road exists
                          if aScenario.Layers.ContainsKey('road') and aScenario.Layers['road'].objects.ContainsKey(AnsiString(objectID.ToString)) then
                          begin
                            oraSession.ExecSQL(queryText, [objectID]);
                            oraSession.Commit;
                            publishEvent.SignalChangeObject(actionChange, objectID, 'SPEED_L');
                            publishEvent.SignalChangeObject(actionChange, objectID, 'SPEED_R');
                          end;
                        end;
                      end;
                    finally
                      publishEvent.UnPublish;
                    end;
                  end;
                end
                else if (measure.ActionID >= -42) and (measure.ActionID <= -41) then
                begin
                  case measure.ActionID of
                    -41: value := '* 0.7';
                    -42: value := '/ 0.7';
                  end;
                  table := (aScenario as TUSScenario).Tableprefix + 'TRAF_OD';
                  queryText := 'update ' + table +
                    ' set' +
                    ' CAR_TRIPS = CAR_TRIPS ' + value;
                  publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.TRAF_OD';
                  publishEvent := fUSIMBConnection.publish(publishEventName, false);
                  try
                    oraSession.ExecSQL(queryText);
                    oraSession.Commit;
                    publishEvent.SignalChangeObject(actionChange, 0, 'CAR_TRIPS');
                  finally
                    publishEvent.UnPublish;
                  end;
                end
                else if (measure.ActionID >= -54) and (measure.ActionID <= -51) then
                begin
                  table := (aScenario as TUSScenario).Tableprefix + 'GENE_BUILDING';
                  case measure.ActionID of
                    -51: value := '10';
                    -52: value := '100';
                    -53: value := '1000';
                    -54: value := '10000';
                  end;
                  queryText := 'update ' + table +
                    ' set' +
                    ' INHABIT = ' + value + //preserves null values!
                    ' where OBJECT_ID = :A';
                  if jsonMeasure.TryGetValue<TJSONArray>('selectedObjects', jsonObjectIDs) then
                  begin
                    publishEventName := oraSession.Username + '#' + aClient.currentScenario.Name + '.GENE_BUILDING';
                    publishEvent := fUSIMBConnection.publish(publishEventName, false);
                    try
                      for jsonObjectID in jsonObjectIDs do
                      begin
                        if TryStrToInt(jsonObjectID.Value, objectID) then
                        begin
                          //check if this building exists
                          if aScenario.Layers.ContainsKey('building') and aScenario.Layers['building'].objects.ContainsKey(AnsiString(objectID.ToString)) then
                          begin
                            oraSession.ExecSQL(queryText, [objectID]);
                            oraSession.Commit;
                            publishEvent.SignalChangeObject(actionChange, objectID, 'INHABIT');
                          end;
                        end;
                      end;
                    finally
                      publishEvent.UnPublish;
                    end;
                  end;
                end
              end
            end;
  end;
end;

procedure TUSDesignProject.ReadBasicData;
var
  scenarioID: Integer;
  s: string;
begin
  ReadScenarios;
  ReadMeasures;
  // load current scenario and ref scenario first
  scenarioID := getUSCurrentPublishedScenarioID(OraSession, GetCurrentScenarioID(OraSession));
  fProjectCurrentScenario := ReadScenario(scenarioID.ToString);
  Log.WriteLn('current US scenario: '+fProjectCurrentScenario.ID+' ('+(fProjectCurrentScenario as TUSScenario).Tableprefix+'): "'+fProjectCurrentScenario.description+'"', llOk);
  // ref
  scenarioID := GetScenarioBaseID(OraSession, scenarioID);
  if scenarioID>=0 then
  begin
    fProjectRefScenario := ReadScenario(scenarioID.ToString);
    Log.WriteLn('reference US scenario: '+fProjectRefScenario.ID+' ('+(fProjectRefScenario as TUSScenario).Tableprefix+'): "'+fProjectRefScenario.description+'"', llOk);
  end
  else Log.WriteLn('NO reference US scenario', llWarning);
  if PreLoadScenarios then
  begin
    for s in USDBScenarios.Keys do
    begin
      if USDBScenarios[s]._published=1
        then ReadScenario(s);
    end;
  end;
end;

{ TUSMonitorProject }

constructor TUSMonitorProject.Create(aSessionModel: TSessionModel;
  aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID,
  aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
  aDBConnection: TCustomConnection; aMapView: TMapView;
  aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer;
  aStartScenario: string);
begin
  inherited Create(aSessionModel, aConnection, aIMB3Connection, aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource, aDBConnection, aMapView, aPreLoadScenarios, False, aMaxNearestObjectDistanceInMeters);
  DisableControl(selectControl);
  DisableControl(measuresControl);
  DisableControl(measuresHistoryControl);
  fProjectCurrentScenario := ReadScenario(aStartScenario);
  EnableControl(modelControl);
end;

destructor TUSMonitorProject.Destroy;
begin
  inherited;
end;

procedure TUSMonitorProject.ReadBasicData;
begin
  ReadScenarios;
end;

{ TUSEvaluateProject }

constructor TUSEvaluateProject.Create(aSessionModel: TSessionModel;
  aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID,
  aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource: string;
  aDBConnection: TCustomConnection; aMapView: TMapView;
  aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer;
  aStartScenario: string);
begin
  inherited Create(aSessionModel, aConnection, aIMB3Connection, aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL, aDataSource, aDBConnection, aMapView, aPreLoadScenarios, False, aMaxNearestObjectDistanceInMeters);
  DisableControl(selectControl);
  DisableControl(measuresControl);
  DisableControl(measuresHistoryControl);
  EnableControl(modelControl);
  fProjectCurrentScenario := ReadScenario(aStartScenario);
end;

destructor TUSEvaluateProject.Destroy;
begin

  inherited;
end;

procedure TUSEvaluateProject.ReadBasicData;
begin
end;

{ TUSDesignScenario }

function TUSDesignScenario.HandleClientSubscribe(aClient: TClient): Boolean;
var
  clientMCControlInterface: TClientMCControlInterface;
  jsonNewModels: String;
  model: TCIModelEntry2;
begin
  Result := inherited HandleClientSubscribe(aClient);

  //send the model control information
  clientMCControlInterface := (project as TMCProject).controlInterface;
  clientMCControlInterface.Lock.Acquire;
  try
    jsonNewModels := '';
    for model in clientMCControlInterface.Models do
    begin
      if model.IsThisSession(aClient.currentScenario.ID) then
      begin
        if jsonNewModels<>''
          then jsonNewModels := jsonNewModels+',';
        jsonNewModels := jsonNewModels+clientMCControlInterface.jsonModelStatusNew(model.UID.ToString, model.ModelName, model.State.ToString, model.Progress)
      end;
    end;
    aClient.signalString(clientMCControlInterface.jsonModelStatusArray(jsonNewModels));
  finally
    clientMCControlInterface.Lock.Release;
  end;
end;

function TUSDesignScenario.HandleClientUnsubscribe(aClient: TClient): Boolean;
var
  clientMCControlInterface: TClientMCControlInterface;
  jsonDeleteModels: String;
  model: TCIModelEntry2;
begin
  Result := inherited HandleClientUnsubscribe(aClient);

  //delete the models of this scenario from the ModelControlInterface
  clientMCControlInterface := (project as TMCProject).controlInterface;
  clientMCControlInterface.Lock.Acquire;
  try
    jsonDeleteModels := '';
    for model in clientMCControlInterface.Models do
    begin
      if model.IsThisSession(aClient.currentScenario.ID) then
      begin
        if jsonDeleteModels<>''
          then jsonDeleteModels := jsonDeleteModels+',';
        jsonDeleteModels := jsonDeleteModels+clientMCControlInterface.jsonModelStatusDelete(model.UID.ToString);
      end;
    end;
    aClient.signalString(clientMCControlInterface.jsonModelStatusArray(jsonDeleteModels));
  finally
    clientMCControlInterface.Lock.Release;
  end;
end;

end.
